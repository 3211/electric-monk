-- =====================================================
-- ELECTRIC MONK - AUTOMATED SERVER-SIDE KARMA
-- Migration Version: 4.1
-- Date: 2026-05-17
--
-- Changes from v4.0:
-- - Milestone threshold changed from /10 to /50 (50 prays per milestone)
-- - Karma payout multiplied by *5 to compensate for higher threshold
-- - Added updated_at column to prayers table
-- =====================================================

-- 1. ENABLE REQUIRED EXTENSIONS & PATCH SCHEMA
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Fix: Add the missing column to the table before the function calls it
alter table public.prayers 
add column if not exists updated_at timestamp with time zone default timezone('utc'::text, now());

-- 2. CREATE THE HEARTBEAT FUNCTION
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
    FOR r IN SELECT p.* FROM prayers p WHERE p.is_praying = true LOOP
        v_text := COALESCE(r.response_content, r.content);
        v_cycle_s := GREATEST(15, LEAST(length(v_text) * 0.2, 180))::INT;

        v_elapsed_s := EXTRACT(EPOCH FROM (now() - COALESCE(r.last_counted_at, r.activated_at)));
        v_new_cycles := floor(v_elapsed_s / v_cycle_s);

        IF v_new_cycles > 0 THEN
            UPDATE prayers 
            SET prayer_count = prayer_count + v_new_cycles,
                last_counted_at = COALESCE(last_counted_at, activated_at) + (v_new_cycles * (v_cycle_s * interval '1 second')),
                updated_at = now()
            WHERE id = r.id;

            -- 1. THE THRESHOLD: Every 50 prays = 1 milestone
            v_milestones_total := floor((r.prayer_count + v_new_cycles) / 50);

            IF v_milestones_total > r.karma_awarded THEN
                -- 2. THE PAYOUT: *5 multiplier so a 50-pray milestone drops 5x more points
                v_karma_to_award := (v_milestones_total - r.karma_awarded) * 5 * (
                    CASE WHEN r.prayer_type = 'altruistic' THEN 2 ELSE 1 END
                );

                UPDATE profiles SET karma = karma + v_karma_to_award, updated_at = now() WHERE id = r.user_id;
                UPDATE prayers SET karma_awarded = v_milestones_total WHERE id = r.id;
            END IF;
        END IF;

        IF r.prayer_type = 'intercessory' AND r.source_sinner_id IS NOT NULL THEN
            SELECT (ban_until IS NULL OR ban_until <= now()) INTO v_sinner_redeemed
            FROM profiles WHERE id = r.source_sinner_id;

            IF v_sinner_redeemed THEN
                UPDATE prayers SET is_praying = false, last_counted_at = now(), updated_at = now() WHERE id = r.id;
                UPDATE profiles SET karma = karma + 10, updated_at = now() WHERE id = r.user_id;
            END IF;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. REFACTOR sync_prayer_count RPC TO BE READ-ONLY
CREATE OR REPLACE FUNCTION public.sync_prayer_count(p_prayer_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_prayer RECORD;
    v_sinner_redeemed BOOLEAN := false;
BEGIN
    SELECT * INTO v_prayer FROM prayers WHERE id = p_prayer_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Prayer not found'; END IF;
    IF v_prayer.user_id != auth.uid() THEN RAISE EXCEPTION 'Not authorized'; END IF;

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

-- 4. SCHEDULE THE CRON JOB (RUNS EVERY MINUTE)
DO $$
BEGIN
    PERFORM cron.unschedule('prayer-heartbeat');
EXCEPTION
    WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule('prayer-heartbeat', '* * * * *', 'SELECT calculate_automated_karma()');

-- 5. GRANT PERMISSIONS
GRANT EXECUTE ON FUNCTION sync_prayer_count(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION calculate_automated_karma() TO service_role;