-- ======================================================================================
-- GENESIS 2: MASTER CONNECTION LOGS
-- ======================================================================================
-- Tracks all network connections between any two IP addresses.
-- Automatically calculates combined encryption level by multiplying source * target.
-- Missing, NULL, or sub-1 encryption levels default to 1.
-- Designed to be strictly idempotent (re-runnable).
-- ======================================================================================

BEGIN;

-- ==========================================
-- 1. MASTER CONNECTION LOGS TABLE
-- ==========================================

CREATE TABLE IF NOT EXISTS public.connection_logs (
    log_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Connection endpoints (any two IPs in the network)
    from_ip inet NOT NULL,
    to_ip inet NOT NULL,
    
    -- Connection metadata
    connection_type VARCHAR NOT NULL DEFAULT 'data_transfer',
    status VARCHAR NOT NULL DEFAULT 'established',
    port INT,
    protocol VARCHAR DEFAULT 'TCP',
    
    -- Payload info
    bytes_transferred BIGINT DEFAULT 0,
    packets_count INT DEFAULT 0,
    
    -- Encryption levels (auto-populated via trigger)
    from_encryption_level INT,
    to_encryption_level INT,
    combined_encryption_level BIGINT,
    
    -- Timestamps
    initiated_at TIMESTAMPTZ DEFAULT now(),
    terminated_at TIMESTAMPTZ,
    duration_ms INT,
    
    -- Optional metadata
    session_id UUID,
    is_encrypted BOOLEAN DEFAULT false,
    was_spoofed BOOLEAN DEFAULT false,
    trace_attempted BOOLEAN DEFAULT false,
    
    -- Foreign key references for data integrity
    CONSTRAINT fk_from_ip FOREIGN KEY (from_ip) REFERENCES public.network_addresses(ip_address) ON DELETE CASCADE,
    CONSTRAINT fk_to_ip FOREIGN KEY (to_ip) REFERENCES public.network_addresses(ip_address) ON DELETE CASCADE
);

COMMENT ON TABLE public.connection_logs IS 'Master registry of all network connections between IP addresses with calculated encryption levels.';
COMMENT ON COLUMN public.connection_logs.from_ip IS 'Source IP address initiating the connection.';
COMMENT ON COLUMN public.connection_logs.to_ip IS 'Destination IP address receiving the connection.';
COMMENT ON COLUMN public.connection_logs.combined_encryption_level IS 'Product of from_encryption_level * to_encryption_level. Defaults to 1 for null/missing values.';
COMMENT ON COLUMN public.connection_logs.connection_type IS 'Type of connection: data_transfer, attack_probe, file_transfer, command_control, etc.';

-- ==========================================
-- 2. TRIGGER FUNCTION: CALCULATE ENCRYPTION LEVELS
-- ==========================================

CREATE OR REPLACE FUNCTION public.calculate_connection_encryption()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_from_level INT;
    v_to_level INT;
BEGIN
    -- Get source IP encryption level (default to 1 if null or < 1)
    SELECT COALESCE(NULLIF(encryption_level, 0), 1) INTO v_from_level
    FROM public.network_addresses
    WHERE ip_address = NEW.from_ip;
    
    -- Get destination IP encryption level (default to 1 if null or < 1)
    SELECT COALESCE(NULLIF(encryption_level, 0), 1) INTO v_to_level
    FROM public.network_addresses
    WHERE ip_address = NEW.to_ip;
    
    -- Apply minimum of 1
    IF v_from_level IS NULL OR v_from_level < 1 THEN
        v_from_level := 1;
    END IF;
    
    IF v_to_level IS NULL OR v_to_level < 1 THEN
        v_to_level := 1;
    END IF;
    
    -- Set the calculated values
    NEW.from_encryption_level := v_from_level;
    NEW.to_encryption_level := v_to_level;
    NEW.combined_encryption_level := v_from_level::BIGINT * v_to_level::BIGINT;
    
    -- Update is_encrypted flag based on combined level
    NEW.is_encrypted := (NEW.combined_encryption_level > 1);
    
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS calculate_connection_encryption_trigger ON public.connection_logs;
CREATE TRIGGER calculate_connection_encryption_trigger
    BEFORE INSERT OR UPDATE ON public.connection_logs
    FOR EACH ROW
    EXECUTE FUNCTION public.calculate_connection_encryption();

-- ==========================================
-- 3. TRIGGER FUNCTION: AUTO-CALCULATE DURATION
-- ==========================================

CREATE OR REPLACE FUNCTION public.calculate_connection_duration()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.terminated_at IS NOT NULL AND NEW.initiated_at IS NOT NULL THEN
        NEW.duration_ms := EXTRACT(EPOCH FROM (NEW.terminated_at - NEW.initiated_at)) * 1000;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS calculate_connection_duration_trigger ON public.connection_logs;
CREATE TRIGGER calculate_connection_duration_trigger
    BEFORE INSERT OR UPDATE ON public.connection_logs
    FOR EACH ROW
    EXECUTE FUNCTION public.calculate_connection_duration();

-- ==========================================
-- 4. INDEXES FOR PERFORMANCE
-- ==========================================

-- Core lookup indexes
CREATE INDEX IF NOT EXISTS idx_connection_logs_from_ip ON public.connection_logs(from_ip);
CREATE INDEX IF NOT EXISTS idx_connection_logs_to_ip ON public.connection_logs(to_ip);
CREATE INDEX IF NOT EXISTS idx_connection_logs_initiated_at ON public.connection_logs(initiated_at DESC);

-- Composite indexes for common queries
CREATE INDEX IF NOT EXISTS idx_connection_logs_from_to_time ON public.connection_logs(from_ip, to_ip, initiated_at DESC);
CREATE INDEX IF NOT EXISTS idx_connection_logs_combined_encryption ON public.connection_logs(combined_encryption_level);
CREATE INDEX IF NOT EXISTS idx_connection_logs_type_status ON public.connection_logs(connection_type, status);

-- Partial indexes for active connections
CREATE INDEX IF NOT EXISTS idx_connection_logs_active ON public.connection_logs(from_ip, to_ip) 
    WHERE terminated_at IS NULL;

-- Index for session tracking
CREATE INDEX IF NOT EXISTS idx_connection_logs_session ON public.connection_logs(session_id) 
    WHERE session_id IS NOT NULL;

-- ==========================================
-- 5. RPC: QUERY CONNECTIONS BY ENCRYPTION THRESHOLD
-- ==========================================

CREATE OR REPLACE FUNCTION public.get_connections_by_encryption(
    p_min_encryption BIGINT DEFAULT 1,
    p_max_encryption BIGINT DEFAULT 9223372036854775807
)
RETURNS TABLE (
    log_id UUID,
    from_ip inet,
    to_ip inet,
    combined_encryption_level BIGINT,
    connection_type VARCHAR,
    status VARCHAR,
    initiated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        cl.log_id,
        cl.from_ip,
        cl.to_ip,
        cl.combined_encryption_level,
        cl.connection_type,
        cl.status,
        cl.initiated_at
    FROM public.connection_logs cl
    WHERE cl.combined_encryption_level BETWEEN p_min_encryption AND p_max_encryption
    ORDER BY cl.initiated_at DESC
    LIMIT 1000;
END;
$$;

-- ==========================================
-- 6. RPC: GET CONNECTION STATS BETWEEN TWO IPs
-- ==========================================

CREATE OR REPLACE FUNCTION public.get_connection_stats(p_ip1 inet, p_ip2 inet)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_total_connections BIGINT;
    v_total_bytes BIGINT;
    v_avg_encryption NUMERIC;
    v_last_connection TIMESTAMPTZ;
    v_active_connections BIGINT;
BEGIN
    -- Total connections (both directions)
    SELECT COUNT(*) INTO v_total_connections
    FROM public.connection_logs
    WHERE (from_ip = p_ip1 AND to_ip = p_ip2)
       OR (from_ip = p_ip2 AND to_ip = p_ip1);
    
    -- Total bytes transferred
    SELECT COALESCE(SUM(bytes_transferred), 0) INTO v_total_bytes
    FROM public.connection_logs
    WHERE (from_ip = p_ip1 AND to_ip = p_ip2)
       OR (from_ip = p_ip2 AND to_ip = p_ip1);
    
    -- Average encryption level
    SELECT COALESCE(AVG(combined_encryption_level), 0) INTO v_avg_encryption
    FROM public.connection_logs
    WHERE (from_ip = p_ip1 AND to_ip = p_ip2)
       OR (from_ip = p_ip2 AND to_ip = p_ip1);
    
    -- Last connection time
    SELECT MAX(initiated_at) INTO v_last_connection
    FROM public.connection_logs
    WHERE (from_ip = p_ip1 AND to_ip = p_ip2)
       OR (from_ip = p_ip2 AND to_ip = p_ip1);
    
    -- Active connections (not terminated)
    SELECT COUNT(*) INTO v_active_connections
    FROM public.connection_logs
    WHERE ((from_ip = p_ip1 AND to_ip = p_ip2) OR (from_ip = p_ip2 AND to_ip = p_ip1))
      AND terminated_at IS NULL;
    
    RETURN json_build_object(
        'ip1', p_ip1,
        'ip2', p_ip2,
        'total_connections', v_total_connections,
        'total_bytes_transferred', v_total_bytes,
        'average_encryption_level', ROUND(v_avg_encryption, 2),
        'last_connection_at', v_last_connection,
        'active_connections', v_active_connections
    );
END;
$$;

-- ==========================================
-- 7. RLS POLICIES
-- ==========================================

ALTER TABLE public.connection_logs ENABLE ROW LEVEL SECURITY;

-- Service role has full access
DROP POLICY IF EXISTS "Service role full access" ON public.connection_logs;
CREATE POLICY "Service role full access"
    ON public.connection_logs FOR ALL
    USING (auth.jwt()->>'role' = 'service_role')
    WITH CHECK (auth.jwt()->>'role' = 'service_role');

-- Authenticated users can view connections involving their IP or their VMs
DROP POLICY IF EXISTS "Players view own connections" ON public.connection_logs;
CREATE POLICY "Players view own connections"
    ON public.connection_logs FOR SELECT
    TO authenticated
    USING (
        from_ip IN (
            SELECT ip_address FROM public.players WHERE id = auth.uid()
            UNION
            SELECT ip_address FROM public.virtual_machines WHERE owner_identity_id = auth.uid()
        )
        OR
        to_ip IN (
            SELECT ip_address FROM public.players WHERE id = auth.uid()
            UNION
            SELECT ip_address FROM public.virtual_machines WHERE owner_identity_id = auth.uid()
        )
    );

-- Public can view connection metadata for sect IPs (read-only)
DROP POLICY IF EXISTS "Public view sect connections" ON public.connection_logs;
CREATE POLICY "Public view sect connections"
    ON public.connection_logs FOR SELECT
    TO anon
    USING (
        from_ip IN (SELECT ip_address FROM public.sects)
        OR
        to_ip IN (SELECT ip_address FROM public.sects)
    );

-- ==========================================
-- 8. PERMISSIONS & GRANTS
-- ==========================================

-- Table access
GRANT ALL ON TABLE public.connection_logs TO service_role, postgres, supabase_admin;

-- Function execution
GRANT EXECUTE ON FUNCTION public.get_connections_by_encryption(BIGINT, BIGINT) TO service_role, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.get_connection_stats(inet, inet) TO service_role, authenticated, anon;

COMMIT;