-- Electric Monk - Automated Server-Side Karma & Prayer Counting
-- Migration Version: 4.0
-- Date: 2026-05-17
--
-- This migration moves the "Clock" for prayers from the browser to the database.
-- It uses pg_cron to run a heartbeat every minute.

-- =====================================================
-- 1. ENABLE REQUIRED EXTENSIONS
-- =====================================================
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- =====================================================
-- 2. CREATE THE HEARTBEAT FUNCTION
-- =====================================================
-- This function runs every minute and processes ALL active prayers.
-- It calculates elapsed cycles based on time passed, updates counts,
-- awards karma milestones, and checks for sinner redemption.

CREATE OR REPLACE FUNCTION public.calculate_automated_karma()
RETURNS void AS $$
DECLARE
    r RECORD;
    v_text TEXT;
    v_cycle_s INT;
    v_elapsed_s FLOAT;
    v_new_cycles INT;
    v_milestones_total INT;
    v_karma_to_award INT;
    v_sinner_redeemed BOOLEAN;
BEGIN
    -- STEP A: Process all active prayers
    FOR r IN 
        SELECT p.*
        FROM prayers p
        WHERE p.is_praying = true
    LOOP
        -- 1. Calculate Cycle Time
        -- Formula: ~200ms per char (0.2s), clamped 15s - 180s
        v_text := COALESCE(r.response_content, r.content);
        v_cycle_s := GREATEST(15, LEAST(length(v_text) * 0.2, 180))::INT;

        -- 2. Calculate Elapsed Cycles since last update
        -- We use EXTRACT(EPOCH FROM ...) to get seconds
        v_elapsed_s := EXTRACT(EPOCH FROM (now() - COALESCE(r.last_counted_at, r.activated_at)));
        v_new_cycles := floor(v_elapsed_s / v_cycle_s);

        IF v_new_cycles > 0 THEN
            -- 3. Update Prayer Count
            -- We update last_counted_at by the exact duration of the cycles processed
            -- to ensure we don't lose partial seconds in the next run.
            UPDATE prayers 
            SET prayer_count = prayer_count + v_new_cycles,
                last_counted_at = COALESCE(last_counted_at, activated_at) + (v_new_cycles * (v_cycle_s * interval '1 second')),
                updated_at = now()
            WHERE id = r.id;

            -- 4. Check & Award Karma Milestones (Every 10 prays)
            v_milestones_total := floor((r.prayer_count + v_new_cycles) / 10);
            
            IF v_milestones_total > r.karma_awarded THEN
                v_karma_to_award := (v_milestones_total - r.karma_awarded) * (
                    CASE 
                        WHEN r.prayer_type = 'altruistic' THEN 2 
                        ELSE 1 
                    END
                );

                UPDATE profiles 
                SET karma = karma + v_karma_to_award,
                    updated_at = now()
                WHERE id = r.user_id;

                UPDATE prayers 
                SET karma_awarded = v_milestones_total 
                WHERE id = r.id;
            END IF;
        END IF;

        -- 5. Handle Intercessory Redemption Check
        -- If praying for a sinner, check if they are still banned
        IF r.prayer_type = 'intercessory' AND r.source_sinner_id IS NOT NULL THEN
            SELECT (ban_until IS NULL OR ban_until <= now()) INTO v_sinner_redeemed
            FROM profiles WHERE id = r.source_sinner_id;

            IF v_sinner_redeemed THEN
                -- Sinner is free! Stop the prayer and give a "Redemption Bonus"
                UPDATE prayers 
                SET is_praying = false, 
                    last_counted_at = now(),
                    updated_at = now()
                WHERE id = r.id;
                
                UPDATE profiles 
                SET karma = karma + 10, -- 10 Karma bonus for freeing a soul
                    updated_at = now()
                WHERE id = r.user_id;
            END IF;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- 3. REFACTOR sync_prayer_count RPC TO BE READ-ONLY
-- =====================================================
-- This function no longer accepts increments; it just returns the current server state.
-- The frontend calls this to "snap" its local count to the server truth.

CREATE OR REPLACE FUNCTION public.sync_prayer_count(p_prayer_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_prayer RECORD;
    v_sinner_redeemed BOOLEAN := false;
BEGIN
    SELECT * INTO v_prayer FROM prayers WHERE id = p_prayer_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'Prayer not found'; END IF;
    IF v_prayer.user_id != auth.uid() THEN RAISE EXCEPTION 'Not authorized'; END IF;

    -- Check if it was an intercessory prayer that just finished
    IF v_prayer.prayer_type = 'intercessory' AND v_prayer.is_praying = false THEN
        v_sinner_redeemed := true;
    END IF;

    RETURN jsonb_build_object(
        'prayer_count', v_prayer.prayer_count,
        'last_counted_at', v_prayer.last_counted_at,
        'activated_at', v_prayer.activated_at,
        'is_praying', v_prayer.is_praying,
        'karma_awarded', v_prayer.karma_awarded,
        'sinner_redeemed', v_sinner_redeemed
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- 4. SCHEDULE THE CRON JOB (RUNS EVERY MINUTE)
-- =====================================================
-- Use DO block to gracefully handle first-run (job doesn't exist yet)
DO $$
BEGIN
    PERFORM cron.unschedule('prayer-heartbeat');
EXCEPTION
    WHEN OTHERS THEN NULL; -- Ignore error if job doesn't exist
END $$;

SELECT cron.schedule('prayer-heartbeat', '* * * * *', 'SELECT calculate_automated_karma()');

-- =====================================================
-- 5. GRANT PERMISSIONS
-- =====================================================
GRANT EXECUTE ON FUNCTION sync_prayer_count(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION calculate_automated_karma() TO service_role;
