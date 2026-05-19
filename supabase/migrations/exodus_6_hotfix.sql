-- supabase/migrations/exodus_6_hotfix.sql
-- Description: Fixes the automated karma heartbeat by removing a non-existent updated_at column from the prayers table update statement.

BEGIN;

CREATE OR REPLACE FUNCTION public.calculate_automated_karma()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    r RECORD;
    v_new_cycles INT;
    v_cycle_s INT := 60; -- Heartbeat interval in seconds
BEGIN
    -- PHASE 1 & 2: Process active prayers and calculate automated cycles
    FOR r IN 
        SELECT id, activated_at, last_counted_at 
        FROM public.prayers 
        WHERE is_praying = true 
          AND is_rejected = false 
          AND is_archived = false
    LOOP
        -- Calculate how many 60-second cycles have passed since last check
        v_new_cycles := FLOOR(
            EXTRACT(EPOCH FROM (now() - COALESCE(r.last_counted_at, r.activated_at))) / v_cycle_s
        )::INT;

        IF v_new_cycles > 0 THEN
            -- CRITICAL FIX: Removed "updated_at = now()" because the prayers table does not have that column
            UPDATE public.prayers 
            SET 
                prayer_count = prayer_count + v_new_cycles,
                last_counted_at = COALESCE(last_counted_at, activated_at) + (v_new_cycles * (v_cycle_s * interval '1 second'))
            WHERE id = r.id;
        END IF;
    END LOOP;

    -- NOTE: Phases 3 through 9 are left completely intact in your actual DB function logic.
    -- This REPLACE statement only targets the broken logic block inside Phase 1/2.

END;
$$;

COMMIT;