-- ======================================================================================
-- GENESIS 2.0: NETWORK ACTION LOGS (REVISION)
-- ======================================================================================
-- 
-- FIELD CATEGORIES:
-- IMMUTABLE (admin/anti-cheat, never changes):
--   - log_id, creation_time, last_change, origin_actor, target_actor
--
-- SEMI-IMMUTABLE (set once, then locked):
--   - first_ip, first_target, first_details, first_log_time
--
-- MUTABLE (gameplay/hacking mechanics):
--   - source_ip, target_ip, details, log_time, log_update
--   - log_encryption, log_hidden, log_deleted
--
-- ======================================================================================

BEGIN;

-- ==========================================
-- SECTION 1: DROP OLD TABLE (CLEAN SLATE)
-- ==========================================

DROP TABLE IF EXISTS public.connection_logs CASCADE;

-- ==========================================
-- SECTION 2: MASTER ACTION LOGS TABLE
-- ==========================================

CREATE TABLE public.connection_logs (
    -- ======================================
    -- IMMUTABLE META-FIELDS (Admin/Anti-Cheat)
    -- ======================================
    log_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    creation_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_change TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    -- Origin and target can be IP addresses, sect UUIDs, 'admin', etc.
    origin_actor TEXT NOT NULL,
    target_actor TEXT,
    
    -- ======================================
    -- SEMI-IMMUTABLE FIELDS (Set Once)
    -- ======================================
    first_location TEXT,       -- Semi-immutable: Original storage location
    first_ip TEXT,           -- Original source_ip when first set
    first_target TEXT,       -- Original target_ip when first set
    first_details TEXT,      -- Original details when first set
    first_log_time TIMESTAMPTZ, -- Original log_time when first set
    -- ======================================
    -- MUTABLE FIELDS (Gameplay/Hacking)
    -- ======================================
    log_location TEXT,         -- Mutable: Where log is 'stored' in game (IP, system ID, etc.)
    source_ip TEXT,          -- Mutable source (can be spoofed/hidden)
    target_ip TEXT,          -- Mutable target (can be redirected)
    details TEXT,            -- Arbitrary blob data (can be modified)
    
    log_time TIMESTAMPTZ DEFAULT now(),    -- Mutable timestamp
    log_update TIMESTAMPTZ,                  -- Manual update tracking
    
    -- Dynamic game rule fields (no 'first' versions needed)
    log_encryption INT NOT NULL DEFAULT 0,   -- Difficulty to decipher
    log_hidden INT NOT NULL DEFAULT 0,       -- Fake deletion layers
    log_deleted INT NOT NULL DEFAULT 0,      -- Real deletion layers
    
    -- ======================================
    -- CONSTRAINTS
    -- ======================================
    CONSTRAINT chk_log_hidden_non_negative CHECK (log_hidden >= 0),
    CONSTRAINT chk_log_deleted_non_negative CHECK (log_deleted >= 0),
    CONSTRAINT chk_log_encryption_non_negative CHECK (log_encryption >= 0)
);

-- Table and column documentation
COMMENT ON TABLE public.connection_logs IS 'Network action logs with immutable audit trail and mutable gameplay fields for hacking/spoofing mechanics.';
COMMENT ON COLUMN public.connection_logs.log_id IS 'IMMUTABLE: Unique identifier, never changes';
COMMENT ON COLUMN public.connection_logs.creation_time IS 'IMMUTABLE: When log was created';
COMMENT ON COLUMN public.connection_logs.last_change IS 'AUTO: Updates whenever any mutable field changes';
COMMENT ON COLUMN public.connection_logs.origin_actor IS 'IMMUTABLE: Who/what initiated the action (IP, sect UUID, admin, etc.)';
COMMENT ON COLUMN public.connection_logs.target_actor IS 'IMMUTABLE: Who/what was targeted (IP, sect UUID, etc.)';
COMMENT ON COLUMN public.connection_logs.first_ip IS 'SEMI-IMMUTABLE: Original source_ip, set once';
COMMENT ON COLUMN public.connection_logs.first_target IS 'SEMI-IMMUTABLE: Original target_ip, set once';
COMMENT ON COLUMN public.connection_logs.first_details IS 'SEMI-IMMUTABLE: Original details, set once';
COMMENT ON COLUMN public.connection_logs.first_log_time IS 'SEMI-IMMUTABLE: Original log_time, set once';
COMMENT ON COLUMN public.connection_logs.source_ip IS 'MUTABLE: Current visible source (can be spoofed)';
COMMENT ON COLUMN public.connection_logs.target_ip IS 'MUTABLE: Current visible target (can be changed)';
COMMENT ON COLUMN public.connection_logs.details IS 'MUTABLE: Arbitrary data blob';
COMMENT ON COLUMN public.connection_logs.log_time IS 'MUTABLE: Timestamp of the logged event';
COMMENT ON COLUMN public.connection_logs.log_update IS 'MUTABLE: Manual update timestamp (RPC controlled)';
COMMENT ON COLUMN public.connection_logs.log_encryption IS 'MUTABLE: Difficulty to decrypt (0=plaintext)';
COMMENT ON COLUMN public.connection_logs.log_hidden IS 'MUTABLE: Fake deletion depth (0=visible)';
COMMENT ON COLUMN public.connection_logs.log_deleted IS 'MUTABLE: Real deletion depth (0=exists)';

-- ==========================================
-- SECTION 3: PROTECTION TRIGGERS
-- ==========================================

-- 3.1: Protect immutable fields from updates
CREATE OR REPLACE FUNCTION public.protect_immutable_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Prevent changes to immutable fields
    IF OLD.log_id IS DISTINCT FROM NEW.log_id THEN
        RAISE EXCEPTION 'log_id is immutable and cannot be modified';
    END IF;
    
    IF OLD.creation_time IS DISTINCT FROM NEW.creation_time THEN
        RAISE EXCEPTION 'creation_time is immutable and cannot be modified';
    END IF;
    
    IF OLD.origin_actor IS DISTINCT FROM NEW.origin_actor THEN
        RAISE EXCEPTION 'origin_actor is immutable and cannot be modified';
    END IF;
    
    IF OLD.target_actor IS DISTINCT FROM NEW.target_actor THEN
        RAISE EXCEPTION 'target_actor is immutable and cannot be modified';
    END IF;
    
    -- Auto-update last_change
    NEW.last_change := now();
    
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS protect_immutable_trigger ON public.connection_logs;
CREATE TRIGGER protect_immutable_trigger
    BEFORE UPDATE ON public.connection_logs
    FOR EACH ROW
    EXECUTE FUNCTION public.protect_immutable_fields();

-- 3.2: Initialize semi-immutable fields on insert
CREATE OR REPLACE FUNCTION public.init_semi_immutable_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Set first_* fields to initial values if provided
    IF NEW.source_ip IS NOT NULL THEN
        NEW.first_ip := NEW.source_ip;
    END IF;
    
    IF NEW.target_ip IS NOT NULL THEN
        NEW.first_target := NEW.target_ip;
    END IF;
    
    IF NEW.details IS NOT NULL THEN
        NEW.first_details := NEW.details;
    END IF;
    
    IF NEW.log_time IS NOT NULL THEN
        NEW.first_log_time := NEW.log_time;
    ELSE
        NEW.first_log_time := NEW.creation_time;
        NEW.log_time := NEW.creation_time;
    END IF;
    
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS init_semi_immutable_trigger ON public.connection_logs;
CREATE TRIGGER init_semi_immutable_trigger
    BEFORE INSERT ON public.connection_logs
    FOR EACH ROW
    EXECUTE FUNCTION public.init_semi_immutable_fields();

-- 3.3: Protect semi-immutable fields from being cleared/modified
CREATE OR REPLACE FUNCTION public.protect_semi_immutable_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Prevent clearing or changing first_* fields once set
    IF OLD.first_location IS NOT NULL AND NEW.first_location IS NULL THEN
        RAISE EXCEPTION 'first_location cannot be cleared once set';
    END IF;
    IF OLD.first_location IS DISTINCT FROM NEW.first_location THEN
        RAISE EXCEPTION 'first_location is semi-immutable and cannot be modified';
    END IF;
    IF OLD.first_ip IS NOT NULL AND NEW.first_ip IS NULL THEN
        RAISE EXCEPTION 'first_ip cannot be cleared once set';
    END IF;
    IF OLD.first_ip IS DISTINCT FROM NEW.first_ip THEN
        RAISE EXCEPTION 'first_ip is semi-immutable and cannot be modified (was: %, attempted: %)', OLD.first_ip, NEW.first_ip;
    END IF;
    
    IF OLD.first_target IS NOT NULL AND NEW.first_target IS NULL THEN
        RAISE EXCEPTION 'first_target cannot be cleared once set';
    END IF;
    IF OLD.first_target IS DISTINCT FROM NEW.first_target THEN
        RAISE EXCEPTION 'first_target is semi-immutable and cannot be modified';
    END IF;
    
    IF OLD.first_details IS NOT NULL AND NEW.first_details IS NULL THEN
        RAISE EXCEPTION 'first_details cannot be cleared once set';
    END IF;
    IF OLD.first_details IS DISTINCT FROM NEW.first_details THEN
        RAISE EXCEPTION 'first_details is semi-immutable and cannot be modified';
    END IF;
    
    IF OLD.first_log_time IS NOT NULL AND NEW.first_log_time IS NULL THEN
        RAISE EXCEPTION 'first_log_time cannot be cleared once set';
    END IF;
    IF OLD.first_log_time IS DISTINCT FROM NEW.first_log_time THEN
        RAISE EXCEPTION 'first_log_time is semi-immutable and cannot be modified';
    END IF;
    
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS protect_semi_immutable_trigger ON public.connection_logs;
CREATE TRIGGER protect_semi_immutable_trigger
    BEFORE UPDATE ON public.connection_logs
    FOR EACH ROW
    EXECUTE FUNCTION public.protect_semi_immutable_fields();

-- ==========================================
-- SECTION 4: PERFORMANCE INDEXES
-- ==========================================

-- Core lookups
CREATE INDEX idx_logs_creation_time ON public.connection_logs(creation_time DESC);
CREATE INDEX idx_logs_last_change ON public.connection_logs(last_change DESC);

CREATE INDEX idx_logs_location ON public.connection_logs(log_location);
CREATE INDEX idx_logs_first_location ON public.connection_logs(first_location);
-- Actor lookups (truth fields)
CREATE INDEX idx_logs_origin_actor ON public.connection_logs(origin_actor);
CREATE INDEX idx_logs_target_actor ON public.connection_logs(target_actor);
CREATE INDEX idx_logs_actors_composite ON public.connection_logs(origin_actor, target_actor);

-- Mutable field lookups (what players see/interact with)
CREATE INDEX idx_logs_source_ip ON public.connection_logs(source_ip);
CREATE INDEX idx_logs_target_ip ON public.connection_logs(target_ip);
CREATE INDEX idx_logs_ip_composite ON public.connection_logs(source_ip, target_ip);

-- Game state filters
CREATE INDEX idx_logs_encryption ON public.connection_logs(log_encryption);
CREATE INDEX idx_logs_hidden ON public.connection_logs(log_hidden) WHERE log_hidden > 0;
CREATE INDEX idx_logs_deleted ON public.connection_logs(log_deleted) WHERE log_deleted > 0;
CREATE INDEX idx_logs_visible ON public.connection_logs(log_hidden, log_deleted) WHERE log_hidden = 0 AND log_deleted = 0;

-- Time-based queries
CREATE INDEX idx_logs_log_time ON public.connection_logs(log_time DESC);
CREATE INDEX idx_logs_log_update ON public.connection_logs(log_update DESC) WHERE log_update IS NOT NULL;

-- Text search on details
CREATE INDEX idx_logs_details ON public.connection_logs USING gin(to_tsvector('english', details));

-- Composite for common gameplay queries
CREATE INDEX idx_logs_gameplay_query ON public.connection_logs(source_ip, log_hidden, log_deleted, log_time DESC);

-- ==========================================
-- SECTION 5: RPC FUNCTIONS
-- ==========================================

-- 5.1: Create a new log entry
CREATE OR REPLACE FUNCTION public.create_log(
    p_origin_actor TEXT,
    p_target_actor TEXT DEFAULT NULL,
    p_source_ip TEXT DEFAULT NULL,
    p_target_ip TEXT DEFAULT NULL,
    p_details TEXT DEFAULT NULL,
    p_log_time TIMESTAMPTZ DEFAULT NULL,
    p_log_encryption INT DEFAULT 0
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_log_id UUID;
BEGIN
    INSERT INTO public.connection_logs (
        origin_actor,
        target_actor,
        source_ip,
        target_ip,
        details,
        log_time,
        log_encryption
    ) VALUES (
        p_origin_actor,
        p_target_actor,
        p_source_ip,
        p_target_ip,
        p_details,
        COALESCE(p_log_time, now()),
        p_log_encryption
    )
    RETURNING log_id INTO v_log_id;
    
    RETURN v_log_id;
END;
$$;

-- 5.2: Modify a log with optional log_update control
CREATE OR REPLACE FUNCTION public.modify_log(
    p_log_id UUID,
    p_source_ip TEXT DEFAULT NULL,
    p_target_ip TEXT DEFAULT NULL,
    p_details TEXT DEFAULT NULL,
    p_log_time TIMESTAMPTZ DEFAULT NULL,
    p_log_encryption INT DEFAULT NULL,
    p_log_hidden INT DEFAULT NULL,
    p_log_deleted INT DEFAULT NULL,
    p_update_log_update BOOLEAN DEFAULT true,  -- Whether to auto-set log_update
    p_manual_log_update TIMESTAMPTZ DEFAULT NULL  -- Manual value if not auto-updating
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_log RECORD;
    v_changes TEXT[] := '{}';
BEGIN
    SELECT * INTO v_log FROM public.connection_logs WHERE log_id = p_log_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'message', 'Log not found');
    END IF;
    
    -- Build dynamic update
    UPDATE public.connection_logs
    SET
        source_ip = COALESCE(p_source_ip, source_ip),
        target_ip = COALESCE(p_target_ip, target_ip),
        details = COALESCE(p_details, details),
        log_time = COALESCE(p_log_time, log_time),
        log_encryption = COALESCE(p_log_encryption, log_encryption),
        log_hidden = COALESCE(p_log_hidden, log_hidden),
        log_deleted = COALESCE(p_log_deleted, log_deleted),
        -- Handle log_update based on parameters
        log_update = CASE
            WHEN p_manual_log_update IS NOT NULL THEN p_manual_log_update
            WHEN p_update_log_update THEN now()
            ELSE log_update
        END
    WHERE log_id = p_log_id;
    
    -- Track what changed
    IF p_source_ip IS NOT NULL AND p_source_ip IS DISTINCT FROM v_log.source_ip THEN
        v_changes := array_append(v_changes, 'source_ip');
    END IF;
    IF p_target_ip IS NOT NULL AND p_target_ip IS DISTINCT FROM v_log.target_ip THEN
        v_changes := array_append(v_changes, 'target_ip');
    END IF;
    IF p_details IS NOT NULL AND p_details IS DISTINCT FROM v_log.details THEN
        v_changes := array_append(v_changes, 'details');
    END IF;
    IF p_log_time IS NOT NULL AND p_log_time IS DISTINCT FROM v_log.log_time THEN
        v_changes := array_append(v_changes, 'log_time');
    END IF;
    
    RETURN json_build_object(
        'success', true,
        'log_id', p_log_id,
        'changes', v_changes,
        'log_update_set', CASE
            WHEN p_manual_log_update IS NOT NULL THEN 'manual'
            WHEN p_update_log_update THEN 'auto'
            ELSE 'unchanged'
        END
    );
END;
$$;

-- 5.3: Get logs with visibility filtering
CREATE OR REPLACE FUNCTION public.get_visible_logs(
    p_viewer_actor TEXT,
    p_max_hidden INT DEFAULT 0,
    p_max_deleted INT DEFAULT 0,
    p_limit INT DEFAULT 100
)
RETURNS TABLE (
    log_id UUID,
    creation_time TIMESTAMPTZ,
    origin_actor TEXT,
    target_actor TEXT,
    source_ip TEXT,
    target_ip TEXT,
    details TEXT,
    log_time TIMESTAMPTZ,
    log_encryption INT,
    log_hidden INT,
    log_deleted INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        cl.log_id,
        cl.creation_time,
        cl.origin_actor,
        cl.target_actor,
        cl.source_ip,
        cl.target_ip,
        cl.details,
        cl.log_time,
        cl.log_encryption,
        cl.log_hidden,
        cl.log_deleted
    FROM public.connection_logs cl
    WHERE cl.log_hidden <= p_max_hidden
      AND cl.log_deleted <= p_max_deleted
      AND (
          -- Viewer is involved in the log
          cl.origin_actor = p_viewer_actor OR
          cl.target_actor = p_viewer_actor OR
          cl.source_ip = p_viewer_actor OR
          cl.target_ip = p_viewer_actor OR
          cl.first_ip = p_viewer_actor OR
          cl.first_target = p_viewer_actor
      )
    ORDER BY cl.log_time DESC
    LIMIT p_limit;
END;
$$;

-- 5.4: Attempt to decrypt/hide/delete logs (hacking mechanics)
CREATE OR REPLACE FUNCTION public.attempt_log_manipulation(
    p_log_id UUID,
    p_actor TEXT,
    p_new_encryption INT DEFAULT NULL,
    p_new_hidden INT DEFAULT NULL,
    p_new_deleted INT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_log RECORD;
    v_success BOOLEAN := false;
    v_message TEXT := '';
BEGIN
    SELECT * INTO v_log FROM public.connection_logs WHERE log_id = p_log_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'message', 'Log not found');
    END IF;
    
    -- Check if actor has rights (is origin, target, or has the IP)
    IF v_log.origin_actor != p_actor AND 
       v_log.target_actor != p_actor AND
       v_log.source_ip != p_actor AND
       v_log.target_ip != p_actor THEN
        RETURN json_build_object('success', false, 'message', 'Access denied');
    END IF;
    
    -- Apply changes
    IF p_new_encryption IS NOT NULL THEN
        UPDATE public.connection_logs SET log_encryption = p_new_encryption WHERE log_id = p_log_id;
        v_success := true;
        v_message := v_message || 'Encryption updated. ';
    END IF;
    
    IF p_new_hidden IS NOT NULL THEN
        UPDATE public.connection_logs SET log_hidden = p_new_hidden WHERE log_id = p_log_id;
        v_success := true;
        v_message := v_message || 'Hidden level updated. ';
    END IF;
    
    IF p_new_deleted IS NOT NULL THEN
        UPDATE public.connection_logs SET log_deleted = p_new_deleted WHERE log_id = p_log_id;
        v_success := true;
        v_message := v_message || 'Deleted level updated. ';
    END IF;
    
    RETURN json_build_object(
        'success', v_success,
        'message', COALESCE(NULLIF(v_message, ''), 'No changes made'),
        'log_id', p_log_id
    );
END;
$$;

-- 5.5: Get full audit trail (admin only)
CREATE OR REPLACE FUNCTION public.get_log_audit(
    p_log_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_log RECORD;
BEGIN
    SELECT * INTO v_log FROM public.connection_logs WHERE log_id = p_log_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'message', 'Log not found');
    END IF;
    
    RETURN json_build_object(
        'log_id', v_log.log_id,
        'creation_time', v_log.creation_time,
        'last_change', v_log.last_change,
        'origin_actor', v_log.origin_actor,
        'target_actor', v_log.target_actor,
        'immutable', json_build_object(
            'first_ip', v_log.first_ip,
            'first_target', v_log.first_target,
            'first_details', v_log.first_details,
            'first_log_time', v_log.first_log_time
        ),
        'current', json_build_object(
            'source_ip', v_log.source_ip,
            'target_ip', v_log.target_ip,
            'details', v_log.details,
            'log_time', v_log.log_time,
            'log_update', v_log.log_update
        ),
        'state', json_build_object(
            'encryption', v_log.log_encryption,
            'hidden', v_log.log_hidden,
            'deleted', v_log.log_deleted
        )
    );
END;
$$;
-- 5.6: Move a log to a new location (with access control)
CREATE OR REPLACE FUNCTION public.move_log_location(
    p_log_id UUID,
    p_actor TEXT,
    p_new_location TEXT,
    p_update_first_location BOOLEAN DEFAULT false  -- Admin only: change the immutable record
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_log RECORD;
    v_old_location TEXT;
BEGIN
    SELECT * INTO v_log FROM public.connection_logs WHERE log_id = p_log_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'message', 'Log not found');
    END IF;
    
    v_old_location := v_log.log_location;
    
    -- Check if actor controls current location or is the log originator
    IF v_log.log_location != p_actor AND 
       v_log.origin_actor != p_actor AND
       v_log.first_location != p_actor THEN
        RETURN json_build_object(
            'success', false, 
            'message', 'Access denied: You do not control the current location of this log'
        );
    END IF;
    
    -- Update location
    UPDATE public.connection_logs 
    SET log_location = p_new_location
    WHERE log_id = p_log_id;
    
    -- Optionally update first_location (admin/anti-cheat override)
    IF p_update_first_location THEN
        UPDATE public.connection_logs 
        SET first_location = p_new_location
        WHERE log_id = p_log_id;
    END IF;
    
    RETURN json_build_object(
        'success', true,
        'log_id', p_log_id,
        'old_location', v_old_location,
        'new_location', p_new_location,
        'first_location_updated', p_update_first_location
    );
END;
$$;

-- 5.7: Copy a log to another location (leaves original, creates duplicate at new location)
CREATE OR REPLACE FUNCTION public.copy_log_to_location(
    p_log_id UUID,
    p_actor TEXT,
    p_new_location TEXT,
    p_modify_on_copy BOOLEAN DEFAULT false,  -- If true, actor can spoof the copy
    p_new_source_ip TEXT DEFAULT NULL,
    p_new_target_ip TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_log RECORD;
    v_new_log_id UUID;
BEGIN
    SELECT * INTO v_log FROM public.connection_logs WHERE log_id = p_log_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'message', 'Log not found');
    END IF;
    
    -- Check access to read the log
    IF v_log.log_location != p_actor AND 
       v_log.origin_actor != p_actor AND
       v_log.log_encryption > 0 THEN
        RETURN json_build_object(
            'success', false, 
            'message', 'Access denied or log is encrypted'
        );
    END IF;
    
    -- Create copy at new location
    INSERT INTO public.connection_logs (
        origin_actor,
        target_actor,
        source_ip,
        target_ip,
        first_ip,
        first_target,
        details,
        first_details,
        log_time,
        first_log_time,
        log_location,
        first_location,
        log_encryption,
        log_hidden,
        log_deleted
    ) VALUES (
        v_log.origin_actor,
        v_log.target_actor,
        CASE WHEN p_modify_on_copy THEN COALESCE(p_new_source_ip, v_log.source_ip) ELSE v_log.source_ip END,
        CASE WHEN p_modify_on_copy THEN COALESCE(p_new_target_ip, v_log.target_ip) ELSE v_log.target_ip END,
        v_log.first_ip,
        v_log.first_target,
        v_log.details,
        v_log.first_details,
        v_log.log_time,
        v_log.first_log_time,
        p_new_location,
        p_new_location,  -- Copy sets its own first_location
        v_log.log_encryption,
        v_log.log_hidden,
        v_log.log_deleted
    )
    RETURNING log_id INTO v_new_log_id;
    
    RETURN json_build_object(
        'success', true,
        'original_log_id', p_log_id,
        'new_log_id', v_new_log_id,
        'copied_to_location', p_new_location,
        'modified', p_modify_on_copy
    );
END;
$$;

-- 5.8: Get all logs at a specific location
CREATE OR REPLACE FUNCTION public.get_logs_at_location(
    p_location TEXT,
    p_viewer_actor TEXT,
    p_include_hidden BOOLEAN DEFAULT false,
    p_limit INT DEFAULT 100
)
RETURNS TABLE (
    log_id UUID,
    origin_actor TEXT,
    target_actor TEXT,
    source_ip TEXT,
    target_ip TEXT,
    log_time TIMESTAMPTZ,
    log_encryption INT,
    log_hidden INT,
    log_deleted INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        cl.log_id,
        cl.origin_actor,
        cl.target_actor,
        cl.source_ip,
        cl.target_ip,
        cl.log_time,
        cl.log_encryption,
        cl.log_hidden,
        cl.log_deleted
    FROM public.connection_logs cl
    WHERE cl.log_location = p_location
      AND (p_include_hidden OR cl.log_hidden = 0)
      AND cl.log_deleted = 0
      AND (
          -- Viewer has access to this location or is in the log
          cl.log_location = p_viewer_actor OR
          cl.origin_actor = p_viewer_actor OR
          cl.target_actor = p_viewer_actor OR
          cl.source_ip = p_viewer_actor OR
          cl.target_ip = p_viewer_actor
      )
    ORDER BY cl.log_time DESC
    LIMIT p_limit;
END;
$$;

-- 5.9: Attempt to hack/steal a log (move without proper access - gameplay mechanic)
CREATE OR REPLACE FUNCTION public.attempt_log_hack(
    p_log_id UUID,
    p_actor TEXT,
    p_new_location TEXT,
    p_hacker_skill_level INT DEFAULT 1,
    p_target_encryption INT DEFAULT 0
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_log RECORD;
    v_success BOOLEAN;
    v_roll INT;
BEGIN
    SELECT * INTO v_log FROM public.connection_logs WHERE log_id = p_log_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'message', 'Log not found');
    END IF;
    
    -- Can't hack if already at this location
    IF v_log.log_location = p_new_location THEN
        RETURN json_build_object('success', false, 'message', 'Log already at this location');
    END IF;
    
    -- Hack mechanics: skill vs encryption + randomness
    v_roll := floor(random() * 20 + 1)::INT;  -- d20 roll
    
    -- Success if: roll + skill > encryption + 10 (base difficulty)
    v_success := (v_roll + p_hacker_skill_level) > (v_log.log_encryption + 10);
    
    IF v_success THEN
        UPDATE public.connection_logs 
        SET log_location = p_new_location,
            log_encryption = GREATEST(v_log.log_encryption - p_hacker_skill_level, 0)
        WHERE log_id = p_log_id;
        
        RETURN json_build_object(
            'success', true,
            'message', 'Hack successful: Log moved',
            'log_id', p_log_id,
            'new_location', p_new_location,
            'roll', v_roll,
            'encryption_reduced_to', GREATEST(v_log.log_encryption - p_hacker_skill_level, 0)
        );
    ELSE
        -- Failed hack leaves traces
        UPDATE public.connection_logs 
        SET log_hidden = LEAST(v_log.log_hidden + 1, 255),
            details = COALESCE(v_log.details || E'\n[HACK_ATTEMPT]', '[HACK_ATTEMPT]')
        WHERE log_id = p_log_id;
        
        RETURN json_build_object(
            'success', false,
            'message', 'Hack failed: Traces detected',
            'log_id', p_log_id,
            'roll', v_roll,
            'needed', v_log.log_encryption + 10 - p_hacker_skill_level,
            'traces_increased', true
        );
    END IF;
END;
$$;

-- ==========================================
-- SECTION 6: RLS POLICIES
-- ==========================================

ALTER TABLE public.connection_logs ENABLE ROW LEVEL SECURITY;

-- Service role bypass
DROP POLICY IF EXISTS "service_full_access" ON public.connection_logs;
CREATE POLICY "service_full_access"
    ON public.connection_logs FOR ALL
    USING (auth.jwt()->>'role' = 'service_role')
    WITH CHECK (auth.jwt()->>'role' = 'service_role');

-- Players can view logs where they are the actor or have the IP
DROP POLICY IF EXISTS "players_view_own_logs" ON public.connection_logs;
CREATE POLICY "players_view_own_logs"
    ON public.connection_logs FOR SELECT
    TO authenticated
    USING (
        log_hidden = 0 AND log_deleted = 0
        AND (
            origin_actor IN (
                SELECT ip_address::text FROM public.virtual_machines 
                WHERE owner_identity_id = auth.uid()
                UNION
                SELECT id::text FROM public.players WHERE id = auth.uid()
            )
            OR target_actor IN (
                SELECT ip_address::text FROM public.virtual_machines 
                WHERE owner_identity_id = auth.uid()
                UNION
                SELECT id::text FROM public.players WHERE id = auth.uid()
            )
            OR source_ip IN (
                SELECT ip_address::text FROM public.virtual_machines 
                WHERE owner_identity_id = auth.uid()
            )
            OR target_ip IN (
                SELECT ip_address::text FROM public.virtual_machines 
                WHERE owner_identity_id = auth.uid()
            )
        )
    );

-- Players can insert logs as their own actors
DROP POLICY IF EXISTS "players_insert_logs" ON public.connection_logs;
CREATE POLICY "players_insert_logs"
    ON public.connection_logs FOR INSERT
    TO authenticated
    WITH CHECK (
        origin_actor IN (
            SELECT ip_address::text FROM public.virtual_machines 
            WHERE owner_identity_id = auth.uid()
            UNION
            SELECT id::text FROM public.players WHERE id = auth.uid()
        )
    );

-- Players can modify logs they originated
DROP POLICY IF EXISTS "players_modify_own_logs" ON public.connection_logs;
CREATE POLICY "players_modify_own_logs"
    ON public.connection_logs FOR UPDATE
    TO authenticated
    USING (
        origin_actor IN (
            SELECT ip_address::text FROM public.virtual_machines 
            WHERE owner_identity_id = auth.uid()
            UNION
            SELECT id::text FROM public.players WHERE id = auth.uid()
        )
    )
    WITH CHECK (
        origin_actor IN (
            SELECT ip_address::text FROM public.virtual_machines 
            WHERE owner_identity_id = auth.uid()
            UNION
            SELECT id::text FROM public.players WHERE id = auth.uid()
        )
    );

-- ==========================================
-- SECTION 7: GRANTS
-- ==========================================

GRANT ALL ON TABLE public.connection_logs TO service_role, postgres, supabase_admin;

GRANT EXECUTE ON FUNCTION public.create_log(TEXT, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, INT) 
    TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION public.modify_log(UUID, TEXT, TEXT, TEXT, TIMESTAMPTZ, INT, INT, INT, BOOLEAN, TIMESTAMPTZ) 
    TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION public.get_visible_logs(TEXT, INT, INT, INT) 
    TO service_role, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.attempt_log_manipulation(UUID, TEXT, INT, INT, INT) 
    TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION public.get_log_audit(UUID) 
    TO service_role;
GRANT EXECUTE ON FUNCTION public.move_log_location(UUID, TEXT, TEXT, BOOLEAN) 
    TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION public.copy_log_to_location(UUID, TEXT, TEXT, BOOLEAN, TEXT, TEXT) 
    TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION public.get_logs_at_location(TEXT, TEXT, BOOLEAN, INT) 
    TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION public.attempt_log_hack(UUID, TEXT, TEXT, INT, INT) 
    TO service_role, authenticated;
COMMIT;