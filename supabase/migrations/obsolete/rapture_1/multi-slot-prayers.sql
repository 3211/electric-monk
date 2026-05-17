-- ============================================
-- Electric Monk - Multi-Slot Prayer System
-- Migration for: supporting multiple simultaneous active prayers
-- 
-- SCHEMA VERSION: 2.3
-- Date: 2026-05-16
--
-- CHANGES:
-- 1. Rewrite submit_prayer() — slot-aware, FIFO rotation instead of blanket deactivation
-- 2. Rewrite activate_prayer() — slot-aware, only deactivate oldest when over limit
-- 3. Update start_altruistic_prayer() — slot-aware deactivation
-- 4. Update start_intercessory_prayer() — slot-aware deactivation
--
-- ⚠️  COPY AND PASTE THIS ENTIRE SCRIPT INTO SUPABASE SQL EDITOR
-- ⚠️  Run it as a single transaction
-- ============================================

-- Drop existing functions first to avoid "cannot change return type" errors
DROP FUNCTION IF EXISTS submit_prayer(TEXT) CASCADE;
DROP FUNCTION IF EXISTS activate_prayer(UUID) CASCADE;
DROP FUNCTION IF EXISTS start_altruistic_prayer(UUID, TEXT) CASCADE;
DROP FUNCTION IF EXISTS start_intercessory_prayer(UUID, TEXT) CASCADE;

-- ============================================
-- 1. REWRITE: submit_prayer() — Slot-aware with FIFO rotation
-- ============================================
-- Instead of deactivating ALL active prayers, check against max_prayer_slots.
-- If all slots are occupied, deactivate only the OLDEST active prayer (FIFO).
-- Returns deactivated_id so client can update local state.

CREATE OR REPLACE FUNCTION submit_prayer(prayer_content TEXT)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_char_limit INT := 1500;
    v_token_ratio INT := 5;
    v_cost INT;
    v_spent INT;
    v_limit INT;
    v_new_prayer_id UUID;
    v_max_slots INT;
    v_active_count INT;
    v_deactivated_id UUID;
BEGIN
    -- Get current stats + slot limit
    SELECT tokens_spent_today, daily_token_limit, max_prayer_slots
    INTO v_spent, v_limit, v_max_slots
    FROM profiles WHERE id = v_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Profile not found';
    END IF;

    -- Validate character count
    IF length(prayer_content) > v_char_limit THEN
        RAISE EXCEPTION 'Prayer exceeds maximum length of % characters.', v_char_limit;
    END IF;

    -- Calculate cost
    v_cost := ceil(length(prayer_content)::float / v_token_ratio);

    -- Check budget
    IF (v_spent + v_cost) > v_limit THEN
        RAISE EXCEPTION 'Insufficient Mana. This prayer costs % Mana, but you only have % remaining.', v_cost, (v_limit - v_spent);
    END IF;

    -- Count currently active prayers
    SELECT COUNT(*)::INT INTO v_active_count
    FROM prayers WHERE user_id = v_user_id AND is_praying = true;

    -- FIFO rotation: if all slots occupied, deactivate the OLDEST active prayer
    IF v_active_count >= v_max_slots THEN
        SELECT id INTO v_deactivated_id
        FROM prayers
        WHERE user_id = v_user_id AND is_praying = true
        ORDER BY activated_at ASC NULLS LAST
        LIMIT 1;

        IF v_deactivated_id IS NOT NULL THEN
            UPDATE prayers
            SET is_praying = false, activated_at = NULL
            WHERE id = v_deactivated_id;
        END IF;
    END IF;

    -- Insert new prayer as active
    INSERT INTO prayers (user_id, content, is_praying, activated_at, last_counted_at)
    VALUES (v_user_id, prayer_content, true, now(), now())
    RETURNING id INTO v_new_prayer_id;

    -- Deduct mana
    UPDATE profiles
    SET tokens_spent_today = tokens_spent_today + v_cost,
        last_prayer_date = CURRENT_DATE
    WHERE id = v_user_id;

    RETURN jsonb_build_object(
        'id', v_new_prayer_id,
        'cost', v_cost,
        'deactivated_id', v_deactivated_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 2. REWRITE: activate_prayer() — Slot-aware with FIFO rotation
-- ============================================
-- Instead of deactivating ALL active prayers, check against max_prayer_slots.
-- If activating would exceed the limit, deactivate only the OLDEST active prayer.
-- Performs final count sync on the deactivated prayer before deactivating.

CREATE OR REPLACE FUNCTION activate_prayer(p_prayer_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_max_slots INT;
    v_active_count INT;
    v_deactivated_id UUID;
    v_deactivated RECORD;
    v_new_activated RECORD;
    v_elapsed_counts INT;
    v_cycle_time_ms INT;
BEGIN
    -- Get user's max slots
    SELECT max_prayer_slots INTO v_max_slots
    FROM profiles WHERE id = v_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Profile not found';
    END IF;

    -- Count active prayers (excluding the one we're about to activate)
    SELECT COUNT(*)::INT INTO v_active_count
    FROM prayers
    WHERE user_id = v_user_id AND is_praying = true AND id != p_prayer_id;

    -- FIFO: if all slots are occupied, deactivate the OLDEST active prayer
    IF v_active_count >= v_max_slots THEN
        SELECT id, COALESCE(response_content, content) AS cycle_text,
               activated_at, last_counted_at, prayer_count
        INTO v_deactivated
        FROM prayers
        WHERE user_id = v_user_id AND is_praying = true AND id != p_prayer_id
        ORDER BY activated_at ASC NULLS LAST
        LIMIT 1;

        IF FOUND THEN
            v_deactivated_id := v_deactivated.id;

            -- Calculate elapsed counts before deactivating
            v_cycle_time_ms := GREATEST(15000, LEAST(length(v_deactivated.cycle_text) * 200, 180000));
            v_elapsed_counts := GREATEST(0, floor(
                EXTRACT(EPOCH FROM (now() - COALESCE(v_deactivated.last_counted_at, v_deactivated.activated_at)))
                * 1000.0 / v_cycle_time_ms
            ));

            UPDATE prayers
            SET prayer_count = prayer_count + v_elapsed_counts,
                last_counted_at = now(),
                is_praying = false,
                activated_at = NULL
            WHERE id = v_deactivated.id;
        END IF;
    END IF;

    -- Activate the target prayer
    UPDATE prayers
    SET is_praying = true, activated_at = now(), last_counted_at = now()
    WHERE id = p_prayer_id AND user_id = v_user_id
    RETURNING id, prayer_count, is_praying, activated_at, last_counted_at
    INTO v_new_activated;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Prayer not found or not authorized';
    END IF;

    RETURN jsonb_build_object(
        'activated', jsonb_build_object(
            'id', v_new_activated.id,
            'prayer_count', v_new_activated.prayer_count,
            'is_praying', v_new_activated.is_praying,
            'activated_at', v_new_activated.activated_at,
            'last_counted_at', v_new_activated.last_counted_at
        ),
        'deactivated_id', v_deactivated_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 3. UPDATE: start_altruistic_prayer() — Slot-aware deactivation
-- ============================================
-- Same slot-aware logic: only deactivate oldest when over limit.

CREATE OR REPLACE FUNCTION start_altruistic_prayer(
  p_target_prayer_id UUID,
  p_response_content TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_existing RECORD;
    v_new_id UUID;
    v_target RECORD;
    v_max_slots INT;
    v_active_count INT;
    v_deactivated_id UUID;
BEGIN
    -- Get user's max slots
    SELECT max_prayer_slots INTO v_max_slots
    FROM profiles WHERE id = v_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Profile not found';
    END IF;

    -- Get the target prayer's response_content if not provided
    IF p_response_content IS NULL THEN
        SELECT response_content, content INTO v_target
        FROM prayers WHERE id = p_target_prayer_id;

        IF NOT FOUND THEN RAISE EXCEPTION 'Target prayer not found'; END IF;

        p_response_content := COALESCE(v_target.response_content, v_target.content);
    END IF;

    -- Count currently active prayers
    SELECT COUNT(*)::INT INTO v_active_count
    FROM prayers WHERE user_id = v_user_id AND is_praying = true;

    -- FIFO rotation: if all slots occupied, deactivate the OLDEST active prayer
    IF v_active_count >= v_max_slots THEN
        SELECT id INTO v_deactivated_id
        FROM prayers
        WHERE user_id = v_user_id AND is_praying = true
        ORDER BY activated_at ASC NULLS LAST
        LIMIT 1;

        IF v_deactivated_id IS NOT NULL THEN
            UPDATE prayers
            SET is_praying = false, activated_at = NULL
            WHERE id = v_deactivated_id;
        END IF;
    END IF;

    -- Check if an existing altruistic prayer for this target exists
    SELECT id, prayer_count, karma_awarded INTO v_existing
    FROM prayers
    WHERE user_id = v_user_id
      AND source_prayer_id = p_target_prayer_id
      AND prayer_type = 'altruistic'
      AND is_archived = false
    LIMIT 1;

    IF FOUND THEN
        UPDATE prayers
        SET is_praying = true, activated_at = now(), last_counted_at = now()
        WHERE id = v_existing.id
        RETURNING id INTO v_new_id;
    ELSE
        INSERT INTO prayers (user_id, content, response_content, prayer_type, source_prayer_id, is_praying, activated_at, last_counted_at, status)
        VALUES (
            v_user_id,
            'Altruistic prayer for another',
            p_response_content,
            'altruistic',
            p_target_prayer_id,
            true, now(), now(), 'completed'
        )
        RETURNING id INTO v_new_id;
    END IF;

    RETURN jsonb_build_object(
        'id', v_new_id,
        'type', 'altruistic',
        'target_prayer_id', p_target_prayer_id,
        'deactivated_id', v_deactivated_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 4. UPDATE: start_intercessory_prayer() — Slot-aware deactivation
-- ============================================

CREATE OR REPLACE FUNCTION start_intercessory_prayer(
  p_target_sinner_id UUID,
  p_response_content TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_existing RECORD;
    v_new_id UUID;
    v_max_slots INT;
    v_active_count INT;
    v_deactivated_id UUID;
BEGIN
    -- Get user's max slots
    SELECT max_prayer_slots INTO v_max_slots
    FROM profiles WHERE id = v_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Profile not found';
    END IF;

    -- Count currently active prayers
    SELECT COUNT(*)::INT INTO v_active_count
    FROM prayers WHERE user_id = v_user_id AND is_praying = true;

    -- FIFO rotation: if all slots occupied, deactivate the OLDEST active prayer
    IF v_active_count >= v_max_slots THEN
        SELECT id INTO v_deactivated_id
        FROM prayers
        WHERE user_id = v_user_id AND is_praying = true
        ORDER BY activated_at ASC NULLS LAST
        LIMIT 1;

        IF v_deactivated_id IS NOT NULL THEN
            UPDATE prayers
            SET is_praying = false, activated_at = NULL
            WHERE id = v_deactivated_id;
        END IF;
    END IF;

    -- Check if an existing intercessory prayer for this sinner exists
    SELECT id, prayer_count, karma_awarded INTO v_existing
    FROM prayers
    WHERE user_id = v_user_id
      AND source_sinner_id = p_target_sinner_id
      AND prayer_type = 'intercessory'
      AND is_archived = false
    LIMIT 1;

    IF FOUND THEN
        UPDATE prayers
        SET is_praying = true, activated_at = now(), last_counted_at = now(),
            response_content = p_response_content
        WHERE id = v_existing.id
        RETURNING id INTO v_new_id;
    ELSE
        INSERT INTO prayers (user_id, content, response_content, prayer_type, source_sinner_id, is_praying, activated_at, last_counted_at, status)
        VALUES (
            v_user_id,
            'Intercessory prayer for a sinner',
            p_response_content,
            'intercessory',
            p_target_sinner_id,
            true, now(), now(), 'completed'
        )
        RETURNING id INTO v_new_id;
    END IF;

    RETURN jsonb_build_object(
        'id', v_new_id,
        'type', 'intercessory',
        'target_sinner_id', p_target_sinner_id,
        'deactivated_id', v_deactivated_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 5. GRANT PERMISSIONS
-- ============================================

GRANT EXECUTE ON FUNCTION submit_prayer(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION submit_prayer(TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION activate_prayer(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION activate_prayer(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION start_altruistic_prayer(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION start_altruistic_prayer(UUID, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION start_intercessory_prayer(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION start_intercessory_prayer(UUID, TEXT) TO service_role;

-- ============================================
-- DONE! Verify the functions were created:
-- ============================================
-- Run this query to verify:
-- SELECT proname, prosrc FROM pg_proc WHERE proname IN ('submit_prayer', 'activate_prayer', 'start_altruistic_prayer', 'start_intercessory_prayer');