# Plan: Server-Authoritative Karma & Prayer Counting

This plan moves the responsibility of incrementing prayer counts and awarding karma from the client (browser) to the server (Postgres background worker). 

## 1. SQL Migration (Manual Paste)
We will create a background "Heartbeat" function that runs every minute via `pg_cron`.

### Key Features:
- **Offline Progress**: Prayers continue to count even if the browser is closed.
- **Cheat Prevention**: Users cannot "spoof" elapsed time; the server calculates it based on `last_counted_at`.
- **Sinner Redemption**: Automatically detects when a sinner's ban expires and rewards intercessors.
- **Multi-Slot Support**: Processes all active prayers for all users in a single loop.

### The SQL Query:
```sql
-- 1. Enable Required Extensions
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- 2. Create the Heartbeat Function
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
        SELECT p.*, pr.username as user_name
        FROM prayers p
        JOIN profiles pr ON p.user_id = pr.id
        WHERE p.is_praying = true
    LOOP
        -- 1. Calculate Cycle Time (Match frontend logic)
        v_text := COALESCE(r.response_content, r.content);
        -- ~200ms per char, clamped 15s - 180s
        v_cycle_s := GREATEST(15, LEAST(length(v_text) * 0.2, 180))::INT;

        -- 2. Calculate Elapsed Cycles since last update
        v_elapsed_s := EXTRACT(EPOCH FROM (now() - COALESCE(r.last_counted_at, r.activated_at)));
        v_new_cycles := floor(v_elapsed_s / v_cycle_s);

        IF v_new_cycles > 0 THEN
            -- 3. Update Prayer Count
            -- We update last_counted_at to a specific point to prevent "drift" over time
            UPDATE prayers 
            SET prayer_count = prayer_count + v_new_cycles,
                last_counted_at = COALESCE(last_counted_at, activated_at) + (v_new_cycles * (v_cycle_s * interval '1 second'))
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
                SET karma = karma + v_karma_to_award 
                WHERE id = r.user_id;

                UPDATE prayers 
                SET karma_awarded = v_milestones_total 
                WHERE id = r.id;
            END IF;
        END IF;

        -- 5. Handle Intercessory Redemption Check
        IF r.prayer_type = 'intercessory' AND r.source_sinner_id IS NOT NULL THEN
            SELECT (ban_until IS NULL OR ban_until <= now()) INTO v_sinner_redeemed
            FROM profiles WHERE id = r.source_sinner_id;

            IF v_sinner_redeemed THEN
                -- Sinner is free! Stop the prayer and give a "Redemption Bonus"
                UPDATE prayers 
                SET is_praying = false, 
                    last_counted_at = now() 
                WHERE id = r.id;
                
                UPDATE profiles 
                SET karma = karma + 10 -- Bonus for helping someone out of Purgatory
                WHERE id = r.user_id;
            END IF;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Schedule the Cron Job (Runs every minute)
SELECT cron.schedule('prayer-heartbeat', '* * * * *', 'SELECT calculate_automated_karma()');
```

## 2. Frontend Refactor
- **`usePrayerCounter.js`**: 
    - Remove `lastLocalCount` and the logic that sends increments to the server.
    - Change `sync_prayer_count` RPC to just fetch the latest row from the DB.
    - Keep the local "fake" incrementing for a smooth UI, but snap it to the server value every 15-30 seconds.
- **`useAkashicRecords.js`**:
    - Ensure it polls or uses Realtime to show live purgatory updates.

## 3. Implementation Steps
1. [ ] Update local migration file `supabase/migrations/automated-karma.sql`.
2. [ ] Provide the SQL for manual pasting.
3. [ ] Refactor `sync_prayer_count` (RPC) to be a read-only sync.
4. [ ] Refactor `usePrayerCounter.js`.
5. [ ] Refactor `useAkashicRecords.js` for better live status.
