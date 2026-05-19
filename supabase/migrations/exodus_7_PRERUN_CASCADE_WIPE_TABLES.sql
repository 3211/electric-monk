-- ======================================================================================
-- RESET SEED DATA TABLES
-- ======================================================================================
-- TRUNCATE completely empties the tables. CASCADE wipes any dependent tables too.
-- Since you have no players, this is perfectly safe and cleans up any test data.

BEGIN;

TRUNCATE public.relics CASCADE;
TRUNCATE public.faction_relationships CASCADE;
TRUNCATE public.shop_items CASCADE;
TRUNCATE public.blessing_types CASCADE;
TRUNCATE public.research_nodes CASCADE;

-- Also wipe player-specific tables that reference the above, 
-- so test players don't have orphaned data from old IDs
TRUNCATE public.player_buildings CASCADE;
TRUNCATE public.player_research CASCADE;
TRUNCATE public.prayer_blessings CASCADE;
TRUNCATE public.shout_blessings CASCADE;
TRUNCATE public.build_queue CASCADE;

COMMIT;