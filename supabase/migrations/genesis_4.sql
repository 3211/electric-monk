-- =====================================================
-- ELECTRIC MONK — GENESIS SEED (Part 4: Triggers, Grants, Cron)
-- Continues from genesis_3.sql
-- Contains:
--   Phase 8:  Triggers (create_profile_on_signup)
--   Phase 9:  GRANT permissions (all tables + functions)
--   Phase 10: Cron job scheduling
--
-- Run AFTER genesis_1.sql, genesis_2.sql, and genesis_3.sql.
-- This is the FINAL file in the Genesis seed sequence.
-- =====================================================

-- ============================================
-- PHASE 8: TRIGGERS
-- ============================================

-- 8a. create_profile_on_signup — grants starting buildings
CREATE OR REPLACE FUNCTION public.create_profile_on_signup()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, email)
    VALUES (NEW.id, NEW.email)
    ON CONFLICT (id) DO NOTHING;

    -- Grant starting buildings: Altar, Pot, Novice
    INSERT INTO public.player_buildings (user_id, building_type, is_active, purchased_with) VALUES
        (NEW.id, 'altar', true, 'starting-altar'),
        (NEW.id, 'pot', true, 'starting-pot'),
        (NEW.id, 'novice', true, 'starting-novice');

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 8b. Drop and recreate the trigger
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.create_profile_on_signup();

-- ============================================
-- PHASE 9: GRANT PERMISSIONS
-- ============================================

-- ------------------------------------------
-- 9a. Table permissions
-- ------------------------------------------

-- game_config: publicly readable
GRANT SELECT ON TABLE game_config TO authenticated;
GRANT SELECT ON TABLE game_config TO anon;
GRANT ALL ON TABLE game_config TO service_role;

-- shop_items: publicly readable
GRANT SELECT ON TABLE shop_items TO authenticated;
GRANT SELECT ON TABLE shop_items TO anon;
GRANT ALL ON TABLE shop_items TO service_role;

-- player_buildings: owner read, service_role all
GRANT SELECT ON TABLE player_buildings TO authenticated;
GRANT ALL ON TABLE player_buildings TO service_role;

-- profiles: handled by RLS policies (authenticated can read/write own row)
-- Service_role needs full access
GRANT ALL ON TABLE profiles TO service_role;

-- prayers: handled by RLS policies
GRANT ALL ON TABLE prayers TO service_role;

-- akashic_logs: publicly readable, insert via SECURITY DEFINER only
GRANT SELECT ON TABLE akashic_logs TO authenticated;
GRANT SELECT ON TABLE akashic_logs TO anon;
GRANT ALL ON TABLE akashic_logs TO service_role;

-- blessing_types: publicly readable
GRANT SELECT ON TABLE blessing_types TO authenticated;
GRANT SELECT ON TABLE blessing_types TO anon;
GRANT ALL ON TABLE blessing_types TO service_role;

-- prayer_blessings: authenticated read, insert via RPC
GRANT SELECT ON TABLE prayer_blessings TO authenticated;
GRANT ALL ON TABLE prayer_blessings TO service_role;

-- research_nodes: publicly readable
GRANT SELECT ON TABLE research_nodes TO authenticated;
GRANT SELECT ON TABLE research_nodes TO anon;
GRANT ALL ON TABLE research_nodes TO service_role;

-- player_research: owner read
GRANT SELECT ON TABLE player_research TO authenticated;
GRANT ALL ON TABLE player_research TO service_role;

-- synods: publicly readable
GRANT SELECT ON TABLE synods TO authenticated;
GRANT SELECT ON TABLE synods TO anon;
GRANT ALL ON TABLE synods TO service_role;

-- synod_wars: authenticated read
GRANT SELECT ON TABLE synod_wars TO authenticated;
GRANT ALL ON TABLE synod_wars TO service_role;

-- relics: publicly readable
GRANT SELECT ON TABLE relics TO authenticated;
GRANT SELECT ON TABLE relics TO anon;
GRANT ALL ON TABLE relics TO service_role;

-- active_miracles: publicly readable
GRANT SELECT ON TABLE active_miracles TO authenticated;
GRANT SELECT ON TABLE active_miracles TO anon;
GRANT ALL ON TABLE active_miracles TO service_role;

-- build_queue: owner read
GRANT SELECT ON TABLE build_queue TO authenticated;
GRANT ALL ON TABLE build_queue TO service_role;

-- ------------------------------------------
-- 9b. Function permissions — Core (from genesis_1)
-- ------------------------------------------

GRANT EXECUTE ON FUNCTION update_karma(UUID, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION update_karma(UUID, INT) TO service_role;

GRANT EXECUTE ON FUNCTION submit_prayer(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION submit_prayer(TEXT) TO service_role;

GRANT EXECUTE ON FUNCTION purchase_prayer_slot() TO authenticated;
GRANT EXECUTE ON FUNCTION purchase_prayer_slot() TO service_role;

GRANT EXECUTE ON FUNCTION reset_daily_prayer_count(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION reset_daily_prayer_count(UUID) TO service_role;

GRANT EXECUTE ON FUNCTION create_profile_on_signup() TO service_role;

-- ------------------------------------------
-- 9c. Function permissions — Sects, Synods, Research (from genesis_2)
-- ------------------------------------------

GRANT EXECUTE ON FUNCTION choose_sect(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION choose_sect(TEXT) TO service_role;

GRANT EXECUTE ON FUNCTION launch_inquisition(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION launch_inquisition(UUID) TO service_role;

GRANT EXECUTE ON FUNCTION research_tech(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION research_tech(TEXT) TO service_role;

GRANT EXECUTE ON FUNCTION create_synod(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION create_synod(TEXT) TO service_role;

GRANT EXECUTE ON FUNCTION join_synod(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION join_synod(UUID) TO service_role;

GRANT EXECUTE ON FUNCTION leave_synod() TO authenticated;
GRANT EXECUTE ON FUNCTION leave_synod() TO service_role;

GRANT EXECUTE ON FUNCTION declare_holy_war(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION declare_holy_war(UUID) TO service_role;

GRANT EXECUTE ON FUNCTION attempt_relic_steal(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION attempt_relic_steal(UUID) TO service_role;

GRANT EXECUTE ON FUNCTION consume_indulgence(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION consume_indulgence(TEXT) TO service_role;

GRANT EXECUTE ON FUNCTION get_synod_info() TO authenticated;
GRANT EXECUTE ON FUNCTION get_synod_info() TO service_role;

GRANT EXECUTE ON FUNCTION get_relics() TO authenticated;
GRANT EXECUTE ON FUNCTION get_relics() TO anon;

GRANT EXECUTE ON FUNCTION get_research_tree() TO authenticated;
GRANT EXECUTE ON FUNCTION get_research_tree() TO service_role;

GRANT EXECUTE ON FUNCTION get_sect_info() TO authenticated;
GRANT EXECUTE ON FUNCTION get_sect_info() TO service_role;

-- ------------------------------------------
-- 9d. Function permissions — Combat (from genesis_2)
-- ------------------------------------------

GRANT EXECUTE ON FUNCTION launch_crusade(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION launch_crusade(UUID) TO service_role;

GRANT EXECUTE ON FUNCTION declare_schism() TO authenticated;
GRANT EXECUTE ON FUNCTION declare_schism() TO service_role;

GRANT EXECUTE ON FUNCTION cast_plague(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION cast_plague(UUID) TO service_role;

-- ------------------------------------------
-- 9e. Function permissions — Shop & Economy (from genesis_2)
-- ------------------------------------------

GRANT EXECUTE ON FUNCTION purchase_shop_item(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION purchase_shop_item(TEXT) TO service_role;

GRANT EXECUTE ON FUNCTION get_leaderboard(INT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_leaderboard(INT, INT) TO anon;

GRANT EXECUTE ON FUNCTION get_player_economy() TO authenticated;
GRANT EXECUTE ON FUNCTION get_player_economy() TO service_role;

-- ------------------------------------------
-- 9f. Function permissions — Vassalage & Logs (from genesis_2)
-- ------------------------------------------

GRANT EXECUTE ON FUNCTION get_vassalage_info() TO authenticated;
GRANT EXECUTE ON FUNCTION get_vassalage_info() TO service_role;

GRANT EXECUTE ON FUNCTION get_akashic_logs(INT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_akashic_logs(INT, INT) TO service_role;

-- ------------------------------------------
-- 9g. Function permissions — Blessings (from genesis_2)
-- ------------------------------------------

GRANT EXECUTE ON FUNCTION grant_blessing(UUID, TEXT) TO authenticated;

GRANT EXECUTE ON FUNCTION get_prayer_blessings(UUID[]) TO authenticated;

GRANT EXECUTE ON FUNCTION get_public_prayers(INT, INT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_public_prayers(INT, INT, TEXT) TO anon;

-- ------------------------------------------
-- 9h. Function permissions — Heartbeat (from genesis_3)
-- ------------------------------------------

GRANT EXECUTE ON FUNCTION calculate_automated_karma() TO service_role;

-- ============================================
-- PHASE 10: CRON JOB SCHEDULING
-- ============================================

-- Unscheduled any existing prayer-heartbeat job to avoid duplicates
DO $$
BEGIN
    PERFORM cron.unschedule('prayer-heartbeat');
EXCEPTION
    WHEN OTHERS THEN NULL;
END $$;

-- Schedule the heartbeat: runs every minute
SELECT cron.schedule('prayer-heartbeat', '* * * * *', 'SELECT calculate_automated_karma()');

-- ============================================
-- END OF GENESIS SEED
-- ============================================
-- To rebuild the entire database from scratch:
--   1. Drop all existing tables (or reset the database)
--   2. Run genesis_1.sql  (tables, indexes, RLS, seed data, core functions)
--   3. Run genesis_2.sql  (all RPC functions except heartbeat)
--   4. Run genesis_3.sql  (calculate_automated_karma heartbeat)
--   5. Run genesis_4.sql  (triggers, grants, cron)
--
-- All four files are idempotent (CREATE OR REPLACE, INSERT ON CONFLICT,
-- CREATE IF NOT EXISTS). Safe to re-run individually.
-- ============================================