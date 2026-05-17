-- =====================================================
-- ELECTRIC MONK — GENESIS SEED
-- Migration Version: 9.0 — Complete Database Rebuild
-- Date: 2026-05-17
--
-- This is the MASTER seed. It consolidates ALL prior
-- migrations into a single idempotent script that can
-- rebuild the entire game from scratch.
--
-- Includes: Base schema, Akashic Records, Intercessory
-- Features, Automated Karma, Multi-Slot Prayers,
-- Theological PBBG Pivot, Vassalage & Heresy,
-- Rapture Update, Karma Shop Blessings, and all hotfixes.
--
-- PASTE THIS ENTIRE SCRIPT INTO SUPABASE SQL EDITOR.
-- Run it as a single transaction. Safe to re-run.
-- =====================================================

-- ============================================
-- PHASE 1: EXTENSIONS
-- ============================================

CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- ============================================
-- PHASE 2: CORE TABLES
-- ============================================
-- Order satisfies all FK dependencies.
-- Circular FK (profiles.synod_id -> synods.id)
-- is added via ALTER TABLE after both tables exist.

-- 2a. game_config — central balance values
CREATE TABLE IF NOT EXISTS game_config (
  key TEXT PRIMARY KEY,
  value NUMERIC NOT NULL,
  description TEXT,
  category TEXT DEFAULT 'production',
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 2b. profiles — player data (all columns from all migrations)
CREATE TABLE IF NOT EXISTS profiles (
  id UUID REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
  email TEXT,
  ban_until TIMESTAMPTZ,
  tokens_spent_today INT DEFAULT 0,
  daily_token_limit INT DEFAULT 100,
  last_prayer_date DATE,
  username TEXT,
  faith TEXT,
  karma INT DEFAULT 0,
  max_prayer_slots INT DEFAULT 1,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  -- Theological PBBG Pivot: resources
  mana INT DEFAULT 0,
  gold INT DEFAULT 0,
  food INT DEFAULT 0,
  -- Vassalage & Heresy
  suzerain_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
  heresy INT DEFAULT 0,
  schism_count INT DEFAULT 0,
  divine_shield_until TIMESTAMPTZ,
  -- Rapture Update: sects, land, indulgences
  sect_type TEXT DEFAULT NULL
    CHECK (sect_type IS NULL OR sect_type IN ('prosperity_gospel', 'ascetic_order', 'doomsday_preppers', 'inquisition')),
  sacred_acres INT DEFAULT 25 CHECK (sacred_acres >= 0),
  dogma INT DEFAULT 0 CHECK (dogma >= 0),
  indulgences INT DEFAULT 0 CHECK (indulgences >= 0),
  synod_id UUID DEFAULT NULL,
  papal_bull_until TIMESTAMPTZ DEFAULT NULL,
  title TEXT DEFAULT NULL,
  avatar_url TEXT DEFAULT NULL
);

-- 2c. shop_items — server-authoritative catalog
CREATE TABLE IF NOT EXISTS shop_items (
  id TEXT PRIMARY KEY,
  category TEXT NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  emoji_icon TEXT,
  karma_cost INT NOT NULL DEFAULT 0,
  gold_cost INT NOT NULL DEFAULT 0,
  heresy_cost INT NOT NULL DEFAULT 0,
  effect_type TEXT NOT NULL,
  effect_data JSONB NOT NULL DEFAULT '{}'::jsonb,
  purchase_limit INT,
  requires_building TEXT,
  sort_order INT DEFAULT 0,
  is_active BOOLEAN DEFAULT true,
  cost_scaling BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  -- Rapture Update: acre costs & sect restrictions
  acre_cost INT NOT NULL DEFAULT 0 CHECK (acre_cost >= 0),
  sect_restriction TEXT DEFAULT NULL
    CHECK (sect_restriction IS NULL OR sect_restriction IN ('prosperity_gospel', 'ascetic_order', 'doomsday_preppers', 'inquisition')),
  sect_exclusion TEXT DEFAULT NULL
    CHECK (sect_exclusion IS NULL OR sect_exclusion IN ('prosperity_gospel', 'ascetic_order', 'doomsday_preppers', 'inquisition'))
);

-- 2d. prayers — prayer requests and their status
CREATE TABLE IF NOT EXISTS prayers (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  content TEXT NOT NULL,
  response_content TEXT,
  is_rejected BOOLEAN DEFAULT false,
  rejection_reason TEXT,
  is_praying BOOLEAN DEFAULT false,
  is_archived BOOLEAN DEFAULT false,
  status TEXT DEFAULT 'pending',
  prayer_count INT DEFAULT 0,
  last_counted_at TIMESTAMPTZ,
  activated_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  -- Akashic Records columns
  karma_awarded INT DEFAULT 0,
  source_prayer_id UUID REFERENCES prayers(id) ON DELETE SET NULL,
  source_sinner_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
  prayer_type TEXT DEFAULT 'own'
    CHECK (prayer_type IN ('own', 'altruistic', 'intercessory'))
);

-- 2e. indulgences — ad view ban reduction records
CREATE TABLE IF NOT EXISTS indulgences (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  time_removed_seconds INT DEFAULT 900,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 2f. player_buildings — building ownership per player
CREATE TABLE IF NOT EXISTS player_buildings (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  building_type TEXT NOT NULL,
  is_active BOOLEAN DEFAULT true,
  purchased_with TEXT,
  purchased_at TIMESTAMPTZ DEFAULT now()
);

-- 2g. akashic_logs — battle/combat reports
CREATE TABLE IF NOT EXISTS akashic_logs (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  target_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  actor_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
  action_type TEXT NOT NULL CHECK (action_type IN ('crusade', 'schism', 'plague', 'inquisition')),
  result_data JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 2h. blessing_types — blessing catalog
CREATE TABLE IF NOT EXISTS blessing_types (
  id TEXT PRIMARY KEY,
  emoji TEXT NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  karma_cost INT NOT NULL DEFAULT 0,
  karma_to_giver INT NOT NULL DEFAULT 0,
  karma_to_receiver INT NOT NULL DEFAULT 0,
  sort_order INT DEFAULT 0,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 2i. prayer_blessings — junction table
CREATE TABLE IF NOT EXISTS prayer_blessings (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  prayer_id UUID REFERENCES prayers(id) ON DELETE CASCADE NOT NULL,
  blessing_type_id TEXT REFERENCES blessing_types(id) ON DELETE CASCADE NOT NULL,
  giver_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  receiver_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(prayer_id, blessing_type_id, giver_id)
);

-- 2j. synods — alliance system
CREATE TABLE IF NOT EXISTS synods (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL UNIQUE CHECK (LENGTH(name) BETWEEN 3 AND 30),
  leader_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  tax_rate NUMERIC DEFAULT 0.05 CHECK (tax_rate >= 0.01 AND tax_rate <= 0.15),
  vault_gold INT DEFAULT 0,
  vault_mana INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 2k. synod_wars — war declarations between synods
CREATE TABLE IF NOT EXISTS synod_wars (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  attacker_synod_id UUID REFERENCES synods(id) ON DELETE CASCADE NOT NULL,
  defender_synod_id UUID REFERENCES synods(id) ON DELETE CASCADE NOT NULL,
  declared_at TIMESTAMPTZ DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  is_active BOOLEAN DEFAULT true
);

-- 2l. research_nodes — tech tree definition
CREATE TABLE IF NOT EXISTS research_nodes (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  emoji_icon TEXT,
  alignment TEXT NOT NULL CHECK (alignment IN ('light', 'dark')),
  cost INT NOT NULL CHECK (cost > 0),
  effect_type TEXT NOT NULL,
  effect_data JSONB NOT NULL DEFAULT '{}'::jsonb,
  requires_node TEXT REFERENCES research_nodes(id) ON DELETE SET NULL,
  sort_order INT DEFAULT 0,
  is_active BOOLEAN DEFAULT true
);

-- 2m. player_research — unlocked tech per player
CREATE TABLE IF NOT EXISTS player_research (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  node_id TEXT REFERENCES research_nodes(id) ON DELETE CASCADE NOT NULL,
  unlocked_at TIMESTAMPTZ DEFAULT now(),
  expires_at TIMESTAMPTZ,
  UNIQUE(user_id, node_id)
);

-- 2n. relics — 10 global unique items
CREATE TABLE IF NOT EXISTS relics (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  description TEXT,
  emoji_icon TEXT,
  effect_type TEXT NOT NULL,
  effect_data JSONB NOT NULL DEFAULT '{}'::jsonb,
  holder_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
  last_stolen_at TIMESTAMPTZ,
  steal_progress INT DEFAULT 0,
  steal_window_start TIMESTAMPTZ,
  is_active BOOLEAN DEFAULT true
);

-- 2o. active_miracles — timed effect tracking
CREATE TABLE IF NOT EXISTS active_miracles (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  miracle_type TEXT NOT NULL,
  effect_data JSONB NOT NULL DEFAULT '{}'::jsonb,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 2p. build_queue — Divine Architect queued builds
CREATE TABLE IF NOT EXISTS build_queue (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  item_id TEXT REFERENCES shop_items(id) ON DELETE CASCADE NOT NULL,
  queued_at TIMESTAMPTZ DEFAULT now(),
  auto_execute BOOLEAN DEFAULT true,
  executed_at TIMESTAMPTZ
);

-- ============================================
-- PHASE 3: DEFERRED FK CONSTRAINTS
-- ============================================
-- Circular dependency: profiles.synod_id -> synods.id

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'profiles_synod_id_fkey'
  ) THEN
    ALTER TABLE profiles ADD CONSTRAINT profiles_synod_id_fkey
      FOREIGN KEY (synod_id) REFERENCES synods(id) ON DELETE SET NULL;
  END IF;
END $$;

-- ============================================
-- PHASE 4: INDEXES
-- ============================================

-- Profiles indexes
CREATE INDEX IF NOT EXISTS idx_profiles_suzerain ON profiles(suzerain_id);
CREATE INDEX IF NOT EXISTS idx_profiles_divine_shield ON profiles(divine_shield_until) WHERE divine_shield_until IS NOT NULL;

-- Prayers indexes
CREATE INDEX IF NOT EXISTS idx_prayers_public_feed
  ON prayers(is_rejected, is_archived, created_at DESC)
  WHERE is_rejected = false AND is_archived = false;
CREATE INDEX IF NOT EXISTS idx_prayers_type_active
  ON prayers(user_id, prayer_type, is_praying)
  WHERE is_praying = true;
CREATE INDEX IF NOT EXISTS idx_prayers_most_prayed
  ON prayers(prayer_count DESC)
  WHERE is_rejected = false AND is_archived = false AND prayer_type = 'own';

-- Player buildings indexes
CREATE INDEX IF NOT EXISTS idx_player_buildings_user ON player_buildings(user_id);
CREATE INDEX IF NOT EXISTS idx_player_buildings_user_type ON player_buildings(user_id, building_type);

-- Akashic logs indexes
CREATE INDEX IF NOT EXISTS idx_akashic_target ON akashic_logs(target_id);
CREATE INDEX IF NOT EXISTS idx_akashic_actor ON akashic_logs(actor_id);
CREATE INDEX IF NOT EXISTS idx_akashic_action_type ON akashic_logs(action_type);
CREATE INDEX IF NOT EXISTS idx_akashic_created_at ON akashic_logs(created_at DESC);

-- Blessing indexes
CREATE INDEX IF NOT EXISTS idx_prayer_blessings_prayer ON prayer_blessings(prayer_id);
CREATE INDEX IF NOT EXISTS idx_prayer_blessings_giver ON prayer_blessings(giver_id);
CREATE INDEX IF NOT EXISTS idx_prayer_blessings_type ON prayer_blessings(blessing_type_id);
CREATE INDEX IF NOT EXISTS idx_prayer_blessings_receiver ON prayer_blessings(receiver_id);

-- Synod indexes
CREATE INDEX IF NOT EXISTS idx_synods_leader ON synods(leader_id);
CREATE INDEX IF NOT EXISTS idx_synod_wars_attacker ON synod_wars(attacker_synod_id);
CREATE INDEX IF NOT EXISTS idx_synod_wars_defender ON synod_wars(defender_synod_id);
CREATE INDEX IF NOT EXISTS idx_synod_wars_active ON synod_wars(is_active) WHERE is_active = true;

-- Player research indexes
CREATE INDEX IF NOT EXISTS idx_player_research_user ON player_research(user_id);

-- Relics indexes
CREATE INDEX IF NOT EXISTS idx_relics_holder ON relics(holder_id);

-- Active miracles indexes
CREATE INDEX IF NOT EXISTS idx_active_miracles_user ON active_miracles(user_id);
CREATE INDEX IF NOT EXISTS idx_active_miracles_expires ON active_miracles(expires_at);

-- Build queue indexes
CREATE INDEX IF NOT EXISTS idx_build_queue_user ON build_queue(user_id);
CREATE INDEX IF NOT EXISTS idx_build_queue_pending ON build_queue(user_id) WHERE executed_at IS NULL;

-- ============================================
-- PHASE 5: ROW LEVEL SECURITY
-- ============================================

-- game_config: publicly readable
ALTER TABLE game_config ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Game config is publicly readable" ON game_config;
CREATE POLICY "Game config is publicly readable" ON game_config
  FOR SELECT USING (true);

-- shop_items: publicly readable
ALTER TABLE shop_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Shop items are publicly readable" ON shop_items;
CREATE POLICY "Shop items are publicly readable" ON shop_items
  FOR SELECT USING (true);

-- profiles: users can view own profile + purgatory users
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view own profile" ON profiles;
DROP POLICY IF EXISTS "Users can view profiles" ON profiles;
CREATE POLICY "Users can view profiles" ON profiles
  FOR SELECT USING (
    auth.uid() = id
    OR (ban_until IS NOT NULL AND ban_until > now())
  );

-- prayers: see own + approved completed prayers of others
ALTER TABLE prayers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view own prayers" ON prayers;
DROP POLICY IF EXISTS "Users can view approved prayers" ON prayers;
CREATE POLICY "Users can view approved prayers" ON prayers
  FOR SELECT USING (
    auth.uid() = user_id
    OR (is_rejected = false AND is_archived = false AND status = 'completed')
  );
DROP POLICY IF EXISTS "Users can insert own prayers" ON prayers;
CREATE POLICY "Users can insert own prayers" ON prayers
  FOR INSERT WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can update own prayers" ON prayers;
CREATE POLICY "Users can update own prayers" ON prayers
  FOR UPDATE USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- indulgences: users can insert own
ALTER TABLE indulgences ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can insert own indulgences" ON indulgences;
CREATE POLICY "Users can insert own indulgences" ON indulgences
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- player_buildings: users can read own
ALTER TABLE player_buildings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Players can read own buildings" ON player_buildings;
CREATE POLICY "Players can read own buildings" ON player_buildings
  FOR SELECT USING (auth.uid() = user_id);

-- akashic_logs: publicly readable, insert via SECURITY DEFINER only
ALTER TABLE akashic_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Akashic logs are publicly readable" ON akashic_logs;
CREATE POLICY "Akashic logs are publicly readable" ON akashic_logs
  FOR SELECT USING (true);

-- blessing_types: publicly readable
ALTER TABLE blessing_types ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Blessing types are publicly readable" ON blessing_types;
CREATE POLICY "Blessing types are publicly readable" ON blessing_types
  FOR SELECT USING (true);

-- prayer_blessings: publicly readable
ALTER TABLE prayer_blessings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Prayer blessings are publicly readable" ON prayer_blessings;
CREATE POLICY "Prayer blessings are publicly readable" ON prayer_blessings
  FOR SELECT USING (true);

-- synods: publicly readable, leader can update
ALTER TABLE synods ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Synods are publicly readable" ON synods;
CREATE POLICY "Synods are publicly readable" ON synods
  FOR SELECT USING (true);
DROP POLICY IF EXISTS "Synod leader can update" ON synods;
CREATE POLICY "Synod leader can update" ON synods
  FOR UPDATE USING (auth.uid() = leader_id);

-- synod_wars: publicly readable
ALTER TABLE synod_wars ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Synod wars are publicly readable" ON synod_wars;
CREATE POLICY "Synod wars are publicly readable" ON synod_wars
  FOR SELECT USING (true);

-- research_nodes: publicly readable
ALTER TABLE research_nodes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Research nodes are publicly readable" ON research_nodes;
CREATE POLICY "Research nodes are publicly readable" ON research_nodes
  FOR SELECT USING (true);

-- player_research: users can read own
ALTER TABLE player_research ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Players can read own research" ON player_research;
CREATE POLICY "Players can read own research" ON player_research
  FOR SELECT USING (auth.uid() = user_id);

-- relics: publicly readable
ALTER TABLE relics ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Relics are publicly readable" ON relics;
CREATE POLICY "Relics are publicly readable" ON relics
  FOR SELECT USING (true);

-- active_miracles: publicly readable
ALTER TABLE active_miracles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Miracles are publicly readable" ON active_miracles;
CREATE POLICY "Miracles are publicly readable" ON active_miracles
  FOR SELECT USING (true);

-- build_queue: users can read own
ALTER TABLE build_queue ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Players can read own build queue" ON build_queue;
CREATE POLICY "Players can read own build queue" ON build_queue
  FOR SELECT USING (auth.uid() = user_id);

-- ============================================
-- PHASE 6: SEED DATA
-- ============================================

-- 6a. game_config — all balance values merged from all migrations
INSERT INTO game_config (key, value, description, category) VALUES
  -- Mana Estate production rates
  ('building.altar.mana_per_day', 5, 'Mana generated per day by an Altar', 'production'),
  ('building.shrine.mana_per_day', 12, 'Mana generated per day by a Shrine', 'production'),
  ('building.temple.mana_per_day', 30, 'Mana generated per day by a Temple', 'production'),
  ('building.church.mana_per_day', 80, 'Mana generated per day by a Church', 'production'),
  ('building.cathedral.mana_per_day', 200, 'Mana generated per day by a Cathedral', 'production'),
  -- Food Estate production rates
  ('building.pot.food_per_day', 3, 'Food generated per day by a Pot', 'production'),
  ('building.patch.food_per_day', 8, 'Food generated per day by a Patch', 'production'),
  ('building.garden.food_per_day', 20, 'Food generated per day by a Garden', 'production'),
  ('building.field.food_per_day', 55, 'Food generated per day by a Field', 'production'),
  ('building.farm.food_per_day', 150, 'Food generated per day by a Farm', 'production'),
  -- Workforce production rates (Gold)
  ('building.novice.gold_per_day', 2, 'Gold generated per day by a Novice', 'production'),
  ('building.monk.gold_per_day', 5, 'Gold generated per day by a Monk', 'production'),
  ('building.cleric.gold_per_day', 14, 'Gold generated per day by a Cleric', 'production'),
  ('building.bishop.gold_per_day', 40, 'Gold generated per day by a Bishop', 'production'),
  ('building.cardinal.gold_per_day', 100, 'Gold generated per day by a Cardinal', 'production'),
  -- Mana Estate upkeep (higher tiers cost gold)
  ('building.temple.gold_upkeep_per_day', 1, 'Gold upkeep per day for a Temple', 'upkeep'),
  ('building.church.gold_upkeep_per_day', 2, 'Gold upkeep per day for a Church', 'upkeep'),
  ('building.cathedral.gold_upkeep_per_day', 5, 'Gold upkeep per day for a Cathedral', 'upkeep'),
  -- Workforce upkeep (all workers consume food)
  ('building.novice.food_consumption_per_day', 1, 'Food consumed per day by a Novice', 'upkeep'),
  ('building.monk.food_consumption_per_day', 2, 'Food consumed per day by a Monk', 'upkeep'),
  ('building.cleric.food_consumption_per_day', 4, 'Food consumed per day by a Cleric', 'upkeep'),
  ('building.bishop.food_consumption_per_day', 8, 'Food consumed per day by a Bishop', 'upkeep'),
  ('building.cardinal.food_consumption_per_day', 15, 'Food consumed per day by a Cardinal', 'upkeep'),
  -- Shop cost scaling
  ('shop.cost_scaling_multiplier', 1.15, 'Cost scaling multiplier per owned building (exponential)', 'shop'),
  -- Resource caps (multiplier of daily production)
  ('cap.mana_multiplier', 10, 'Mana cap = total_daily_mana * this multiplier', 'caps'),
  ('cap.gold_multiplier', 10, 'Gold cap = total_daily_gold * this multiplier', 'caps'),
  ('cap.food_multiplier', 10, 'Food cap = total_daily_food * this multiplier', 'caps'),
  -- Karma milestone settings
  ('karma.milestone_threshold', 50, 'Prayer count threshold per karma milestone', 'karma'),
  ('karma.milestone_payout', 5, 'Karma awarded per milestone', 'karma'),
  ('karma.altruistic_multiplier', 2, 'Multiplier for altruistic prayer milestones', 'karma'),
  -- Heresy production
  ('building.cultist.heresy_per_day', 3, 'Heresy generated per day by a Cultist', 'production'),
  ('building.cultist.food_consumption_per_day', 2, 'Food consumed per day by a Cultist', 'upkeep'),
  ('building.coven.heresy_cap_bonus', 50, 'Additional heresy capacity per Coven owned', 'caps'),
  ('building.coven.gold_upkeep_per_day', 3, 'Gold upkeep per day for a Coven', 'upkeep'),
  -- Heresy cap
  ('cap.heresy_base', 100, 'Base heresy capacity before Coven bonuses', 'caps'),
  ('cap.heresy_multiplier', 0, 'Heresy cap multiplier on daily production (0 = use base + coven bonus only)', 'caps'),
  -- Vassalage
  ('tithe.percentage', 0.10, 'Fraction of gross production taken as tithe by suzerain', 'vassalage'),
  -- Combat: Crusade
  ('crusade.mana_cost', 50, 'Mana cost to launch a crusade', 'combat'),
  ('crusade.attack_rating_per_cleric', 10, 'Attack power contributed per Cleric building', 'combat'),
  ('crusade.defense_rating_per_church', 15, 'Defense power contributed per Church building', 'combat'),
  ('crusade.defense_rating_per_cathedral', 40, 'Defense power contributed per Cathedral building', 'combat'),
  ('crusade.acres_stolen', 3, 'Sacred acres stolen from defender on successful Crusade', 'combat'),
  -- Combat: Schism
  ('schism.base_cost', 100, 'Base heresy cost to declare schism', 'combat'),
  ('schism.scaling_factor', 2.0, 'Cost multiplier per previous schism: base * factor^count', 'combat'),
  ('schism.shield_duration_hours', 24, 'Hours of Divine Shield granted after successful schism', 'combat'),
  -- Combat: Plague
  ('plague.heresy_cost', 75, 'Heresy cost to cast a plague', 'combat'),
  -- Combat: Inquisition
  ('inquisition.gold_cost', 200, 'Gold cost to launch an Inquisition', 'combat'),
  -- Sect modifiers
  ('sect.prosperity_gospel.gold_multiplier', 1.5, 'Prosperity Gospel: +50% Gold generation', 'sect'),
  ('sect.prosperity_gospel.mana_multiplier', 0.8, 'Prosperity Gospel: -20% Mana generation', 'sect'),
  ('sect.prosperity_gospel.cathedral_upkeep_multiplier', 2.0, 'Prosperity Gospel: +100% Cathedral gold upkeep', 'sect'),
  ('sect.ascetic_order.food_consumption_multiplier', 0.5, 'Ascetic Order: -50% Food consumption', 'sect'),
  ('sect.ascetic_order.mana_multiplier', 1.2, 'Ascetic Order: +20% Mana generation', 'sect'),
  ('sect.ascetic_order.max_building_tier', 2, 'Ascetic Order: Max building tier for mana estates (Shrine)', 'sect'),
  ('sect.doomsday_preppers.food_multiplier', 1.5, 'Doomsday Preppers: +50% Food generation', 'sect'),
  ('sect.doomsday_preppers.crusade_defense_bonus', 0.5, 'Doomsday Preppers: +50% defensive power in Crusades', 'sect'),
  ('sect.doomsday_preppers.gold_multiplier', 0.75, 'Doomsday Preppers: -25% Gold generation', 'sect'),
  ('sect.inquisition.heresy_multiplier', 2.0, 'Inquisition: +100% Heresy generation', 'sect'),
  ('sect.inquisition.mana_multiplier', 0.7, 'Inquisition: -30% Mana generation', 'sect'),
  ('sect.inquisition.inquisition_gold_cost_multiplier', 0.5, 'Inquisition: -50% Gold cost for Inquisitions', 'sect'),
  -- Building acre costs
  ('building.altar.acre_cost', 1, 'Sacred acres consumed by an Altar', 'acres'),
  ('building.shrine.acre_cost', 2, 'Sacred acres consumed by a Shrine', 'acres'),
  ('building.temple.acre_cost', 3, 'Sacred acres consumed by a Temple', 'acres'),
  ('building.church.acre_cost', 5, 'Sacred acres consumed by a Church', 'acres'),
  ('building.cathedral.acre_cost', 8, 'Sacred acres consumed by a Cathedral', 'acres'),
  ('building.pot.acre_cost', 1, 'Sacred acres consumed by a Pot', 'acres'),
  ('building.patch.acre_cost', 2, 'Sacred acres consumed by a Patch', 'acres'),
  ('building.garden.acre_cost', 3, 'Sacred acres consumed by a Garden', 'acres'),
  ('building.field.acre_cost', 5, 'Sacred acres consumed by a Field', 'acres'),
  ('building.farm.acre_cost', 8, 'Sacred acres consumed by a Farm', 'acres'),
  ('building.novice.acre_cost', 1, 'Sacred acres consumed by a Novice', 'acres'),
  ('building.monk.acre_cost', 1, 'Sacred acres consumed by a Monk', 'acres'),
  ('building.cleric.acre_cost', 2, 'Sacred acres consumed by a Cleric', 'acres'),
  ('building.bishop.acre_cost', 3, 'Sacred acres consumed by a Bishop', 'acres'),
  ('building.cardinal.acre_cost', 5, 'Sacred acres consumed by a Cardinal', 'acres'),
  ('building.cultist.acre_cost', 1, 'Sacred acres consumed by a Cultist', 'acres'),
  ('building.coven.acre_cost', 3, 'Sacred acres consumed by a Coven', 'acres'),
  ('building.scriptorium.acre_cost', 4, 'Sacred acres consumed by a Scriptorium', 'acres'),
  -- Scriptorium production
  ('building.scriptorium.dogma_per_day', 20, 'Dogma generated per day by a Scriptorium', 'production'),
  ('building.scriptorium.gold_per_day', 0, 'Scriptorium produces no gold', 'production'),
  ('building.scriptorium.food_consumption_per_day', 4, 'Food consumed per day by a Scriptorium', 'upkeep'),
  ('building.scriptorium.gold_upkeep_per_day', 2, 'Gold upkeep per day for a Scriptorium', 'upkeep'),
  -- Dogma cap
  ('cap.dogma_multiplier', 10, 'Dogma cap = total_daily_dogma * this multiplier', 'caps'),
  -- Synod config
  ('synod.max_members', 20, 'Maximum members per Synod', 'synod'),
  ('synod.creation_cost_gold', 500, 'Gold cost to create a Synod', 'synod'),
  ('synod.holy_war_duration_hours', 48, 'Duration of Holy War bonus in hours', 'synod'),
  ('synod.holy_war_attack_bonus', 0.20, '+20% attack bonus during Holy War', 'synod'),
  ('synod.relic_steal_crusades_required', 5, 'Unique Synod members required to steal a relic', 'synod'),
  ('synod.relic_steal_window_hours', 1, 'Hours window for coordinated relic theft', 'synod'),
  -- Indulgence config
  ('indulgence.papal_bull_cost', 500, 'Indulgences cost for Papal Bull of Protection', 'indulgences'),
  ('indulgence.papal_bull_duration_hours', 12, 'Hours of immunity from Papal Bull', 'indulgences'),
  ('indulgence.divine_architect_cost', 200, 'Indulgences cost for Divine Architect', 'indulgences'),
  ('indulgence.divine_architect_queue_limit', 5, 'Max queued buildings with Divine Architect', 'indulgences')
ON CONFLICT (key) DO UPDATE SET
  value = EXCLUDED.value,
  description = EXCLUDED.description,
  category = EXCLUDED.category,
  updated_at = now();

-- 6b. shop_items — complete catalog with all costs
INSERT INTO shop_items (id, category, name, description, emoji_icon, karma_cost, gold_cost, heresy_cost, effect_type, effect_data, purchase_limit, requires_building, sort_order, is_active, cost_scaling, acre_cost, sect_restriction, sect_exclusion) VALUES
  -- Mana Estates (5 tiers)
  ('altar', 'mana', 'Altar', 'A humble altar where devotion begins. Generates Mana.', '🕯️', 10, 0, 0, 'add_building', '{"building_type": "altar"}'::jsonb, NULL, NULL, 1, true, true, 1, NULL, NULL),
  ('shrine', 'mana', 'Shrine', 'A shrine channeling greater spiritual energy. Generates more Mana.', '⛩️', 50, 0, 0, 'add_building', '{"building_type": "shrine"}'::jsonb, NULL, 'altar', 2, true, true, 2, NULL, NULL),
  ('temple', 'mana', 'Temple', 'A grand temple of devotion. Generates significant Mana. Requires gold upkeep.', '🏛️', 250, 0, 0, 'add_building', '{"building_type": "temple"}'::jsonb, NULL, 'shrine', 3, true, true, 3, NULL, 'ascetic_order'),
  ('church', 'mana', 'Church', 'A holy church radiating divine power. Generates abundant Mana. Requires gold upkeep.', '⛪', 1200, 0, 0, 'add_building', '{"building_type": "church"}'::jsonb, NULL, 'temple', 4, true, true, 5, NULL, 'ascetic_order'),
  ('cathedral', 'mana', 'Cathedral', 'A towering cathedral, pinnacle of spiritual architecture. Requires gold upkeep.', '🏰', 6000, 0, 0, 'add_building', '{"building_type": "cathedral"}'::jsonb, NULL, 'church', 5, true, true, 8, NULL, 'ascetic_order'),
  -- Food Estates (5 tiers)
  ('pot', 'food', 'Pot', 'A simple pot for brewing sustenance. Generates Food.', '🍲', 10, 0, 0, 'add_building', '{"building_type": "pot"}'::jsonb, NULL, NULL, 11, true, true, 1, NULL, NULL),
  ('patch', 'food', 'Patch', 'A garden patch for growing crops. Generates more Food.', '🌱', 50, 0, 0, 'add_building', '{"building_type": "patch"}'::jsonb, NULL, 'pot', 12, true, true, 2, NULL, NULL),
  ('garden', 'food', 'Garden', 'A lush garden of plenty. Generates significant Food.', '🌾', 250, 0, 0, 'add_building', '{"building_type": "garden"}'::jsonb, NULL, 'patch', 13, true, true, 3, NULL, NULL),
  ('field', 'food', 'Field', 'A sprawling field of golden grain. Generates abundant Food.', '🌻', 1200, 0, 0, 'add_building', '{"building_type": "field"}'::jsonb, NULL, 'garden', 14, true, true, 5, NULL, NULL),
  ('farm', 'food', 'Farm', 'A grand farm estate, pinnacle of agricultural mastery.', '🏡', 6000, 0, 0, 'add_building', '{"building_type": "farm"}'::jsonb, NULL, 'field', 15, true, true, 8, NULL, NULL),
  -- Workforce (5 tiers)
  ('novice', 'workforce', 'Novice', 'A novice devotee learning the ways. Generates Gold, consumes Food.', '🙏', 15, 0, 0, 'add_building', '{"building_type": "novice"}'::jsonb, NULL, NULL, 21, true, true, 1, NULL, NULL),
  ('monk', 'workforce', 'Monk', 'A disciplined monk. Generates more Gold, consumes more Food.', '🧘', 75, 0, 0, 'add_building', '{"building_type": "monk"}'::jsonb, NULL, 'novice', 22, true, true, 1, NULL, NULL),
  ('cleric', 'workforce', 'Cleric', 'A powerful cleric channeling divine wealth. Generates significant Gold.', '🧙', 400, 0, 0, 'add_building', '{"building_type": "cleric"}'::jsonb, NULL, 'monk', 23, true, true, 2, NULL, NULL),
  ('bishop', 'workforce', 'Bishop', 'A bishop commanding vast resources. Generates abundant Gold.', '👑', 2000, 0, 0, 'add_building', '{"building_type": "bishop"}'::jsonb, NULL, 'cleric', 24, true, true, 3, NULL, NULL),
  ('cardinal', 'workforce', 'Cardinal', 'A cardinal, highest authority in the divine hierarchy. Generates immense Gold.', '⭐', 10000, 0, 0, 'add_building', '{"building_type": "cardinal"}'::jsonb, NULL, 'bishop', 25, true, true, 5, NULL, NULL),
  -- Infrastructure: Prayer Slots (fixed cost, no scaling)
  ('prayer-slot-2', 'infrastructure', 'Second Prayer Slot', 'Pray two prayers simultaneously. +100 Devotion per day.', '🙏', 100, 0, 0, 'add_prayer_slot', '{"slots_to_add": 1, "daily_devotion_bonus": 100}'::jsonb, NULL, NULL, 31, true, false, 0, NULL, NULL),
  ('prayer-slot-3', 'infrastructure', 'Third Prayer Slot', 'The truly devoted can pray three prayers at once. +100 Devotion per day.', '🙏', 300, 0, 0, 'add_prayer_slot', '{"slots_to_add": 1, "daily_devotion_bonus": 100}'::jsonb, NULL, NULL, 32, true, false, 0, NULL, NULL),
  ('prayer-slot-4', 'infrastructure', 'Fourth Prayer Slot', 'Four simultaneous prayers. A holy multitasker. +100 Devotion per day.', '🙏', 800, 0, 0, 'add_prayer_slot', '{"slots_to_add": 1, "daily_devotion_bonus": 100}'::jsonb, NULL, NULL, 33, true, false, 0, NULL, NULL),
  ('prayer-slot-5', 'infrastructure', 'Fifth Prayer Slot', 'Five prayers at once. Divine concurrency. +100 Devotion per day.', '🙏', 2000, 0, 0, 'add_prayer_slot', '{"slots_to_add": 1, "daily_devotion_bonus": 100}'::jsonb, NULL, NULL, 34, true, false, 0, NULL, NULL),
  -- Catacombs (Heresy economy)
  ('cultist', 'catacombs', 'Cultist', 'A shadow disciple who generates Heresy. Consumes Food like any worker.', '🧟', 0, 50, 0, 'add_building', '{"building_type": "cultist"}'::jsonb, NULL, NULL, 41, true, true, 1, NULL, NULL),
  ('coven', 'catacombs', 'Coven', 'A hidden gathering place that increases your Heresy capacity. Requires gold upkeep.', '🔮', 0, 200, 0, 'add_building', '{"building_type": "coven"}'::jsonb, NULL, 'cultist', 42, true, true, 3, NULL, NULL),
  -- Research: Scriptorium
  ('scriptorium', 'research', 'Scriptorium', 'A monastery scriptorium where Clerics transcribe sacred texts. Generates Dogma instead of Gold when active. Requires gold upkeep and consumes Food.', '📜', 500, 300, 0, 'add_building', '{"building_type": "scriptorium"}'::jsonb, NULL, 'cleric', 51, true, true, 4, NULL, NULL)
ON CONFLICT (id) DO UPDATE SET
  category = EXCLUDED.category,
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  emoji_icon = EXCLUDED.emoji_icon,
  karma_cost = EXCLUDED.karma_cost,
  gold_cost = EXCLUDED.gold_cost,
  heresy_cost = EXCLUDED.heresy_cost,
  effect_type = EXCLUDED.effect_type,
  effect_data = EXCLUDED.effect_data,
  purchase_limit = EXCLUDED.purchase_limit,
  requires_building = EXCLUDED.requires_building,
  sort_order = EXCLUDED.sort_order,
  is_active = EXCLUDED.is_active,
  cost_scaling = EXCLUDED.cost_scaling,
  acre_cost = EXCLUDED.acre_cost,
  sect_restriction = EXCLUDED.sect_restriction,
  sect_exclusion = EXCLUDED.sect_exclusion;

-- 6c. research_nodes — Light + Dark tech trees
INSERT INTO research_nodes (id, name, description, emoji_icon, alignment, cost, effect_type, effect_data, requires_node, sort_order, is_active) VALUES
  ('tax_evasion', 'Tax Evasion', 'Reduces vassal tithe from 10% to 5%', '💸', 'light', 200, 'vassal_tithe_reduction', '{"reduction_percent": 50}'::jsonb, NULL, 1, true),
  ('holy_war', 'Holy War', '+15% Crusade Attack Power', '⚔', 'light', 300, 'crusade_attack_bonus', '{"bonus_percent": 15}'::jsonb, 'tax_evasion', 2, true),
  ('divine_architecture', 'Divine Architecture', 'Reduces all building acre costs by 20%', '🏛', 'light', 400, 'acre_cost_reduction', '{"reduction_percent": 20}'::jsonb, 'holy_war', 3, true),
  ('fertile_ground', 'Fertile Ground', '+25% Food generation', '🌱', 'light', 350, 'food_bonus', '{"bonus_percent": 25}'::jsonb, NULL, 4, true),
  ('consecrated_ground', 'Consecrated Ground', '+10 Sacred Acres', '✞', 'light', 500, 'acres_bonus', '{"acres_bonus": 10}'::jsonb, 'fertile_ground', 5, true),
  ('false_prophet', 'False Prophet', 'Intercept 25% of a target''s incoming tithes for 12 hours', '👴', 'dark', 150, 'tithe_intercept', '{"intercept_percent": 25, "duration_hours": 12}'::jsonb, NULL, 11, true),
  ('shadow_veil', 'Shadow Veil', 'Immune to Inquisitions for 24 hours', '🗨', 'dark', 200, 'inquisition_immunity', '{"duration_hours": 24}'::jsonb, 'false_prophet', 12, true),
  ('dark_harvest', 'Dark Harvest', '+50% Heresy generation', '☠', 'dark', 250, 'heresy_bonus', '{"bonus_percent": 50}'::jsonb, NULL, 13, true),
  ('plague_mastery', 'Plague Mastery', 'Plagues destroy 150% of food instead of 100%', '🦠', 'dark', 300, 'plague_amplification', '{"amplification_percent": 150}'::jsonb, 'dark_harvest', 14, true)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  emoji_icon = EXCLUDED.emoji_icon,
  alignment = EXCLUDED.alignment,
  cost = EXCLUDED.cost,
  effect_type = EXCLUDED.effect_type,
  effect_data = EXCLUDED.effect_data,
  requires_node = EXCLUDED.requires_node,
  sort_order = EXCLUDED.sort_order,
  is_active = EXCLUDED.is_active;

-- 6d. relics — 10 Global Relics
INSERT INTO relics (name, description, emoji_icon, effect_type, effect_data) VALUES
  ('The Shroud of Turing', '+100% Mana generation', '📜', 'mana_double', '{"mana_multiplier": 2.0}'::jsonb),
  ('The Holy Server Rack', '+50 Sacred Acres', '🖥', 'acres_bonus', '{"acres_bonus": 50}'::jsonb),
  ('The Golden Compiler', '+100% Gold generation', '✨', 'gold_double', '{"gold_multiplier": 2.0}'::jsonb),
  ('The Eternal Patch', '+100% Food generation', '🌾', 'food_double', '{"food_multiplier": 2.0}'::jsonb),
  ('The Obsidian Bible', '+100% Heresy generation', '📕', 'heresy_double', '{"heresy_multiplier": 2.0}'::jsonb),
  ('The Iron Rosary', '+50% Crusade defense', '📿', 'crusade_defense_bonus', '{"bonus_percent": 50}'::jsonb),
  ('The Sacred Firewall', 'Immune to Plagues', '🛡', 'plague_immunity', '{"immune": true}'::jsonb),
  ('The Daemon Core', '+100% Dogma generation', '🔥', 'dogma_double', '{"dogma_multiplier": 2.0}'::jsonb),
  ('The Papal Buffer', '-50% all upkeep costs', '📛', 'upkeep_reduction', '{"reduction_percent": 50}'::jsonb),
  ('The Null Pointer Relic', '+100% Dogma AND Heresy generation', '💥', 'dual_research_double', '{"dogma_multiplier": 2.0, "heresy_multiplier": 2.0}'::jsonb)
ON CONFLICT (name) DO NOTHING;

-- 6e. blessing_types — 4 blessings for the Karma Shop
INSERT INTO blessing_types (id, emoji, name, description, karma_cost, karma_to_giver, karma_to_receiver, sort_order) VALUES
  ('golden-light', '✨', 'Golden Light', 'A radiant blessing that illuminates the prayer with divine light.', 10, 1, 5, 1),
  ('holy-flame', '🔥', 'Holy Flame', 'The sacred fire that purifies and elevates the spirit.', 25, 2, 10, 2),
  ('dove-of-peace', '🕊️', 'Dove of Peace', 'A gentle blessing that brings tranquility and grace.', 50, 5, 20, 3),
  ('divine-crown', '👑', 'Divine Crown', 'The highest honor — a crown of divine recognition.', 100, 10, 50, 4)
ON CONFLICT (id) DO UPDATE SET
  emoji = EXCLUDED.emoji,
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  karma_cost = EXCLUDED.karma_cost,
  karma_to_giver = EXCLUDED.karma_to_giver,
  karma_to_receiver = EXCLUDED.karma_to_receiver,
  sort_order = EXCLUDED.sort_order,
  is_active = true;

-- ============================================
-- PHASE 7: FUNCTIONS (latest version of each only)
-- ============================================

-- 7a. Core utility functions

CREATE OR REPLACE FUNCTION update_karma(p_user_id UUID, p_karma_change INT)
RETURNS VOID AS $$
BEGIN
  UPDATE profiles
  SET karma = COALESCE(karma, 0) + p_karma_change,
      updated_at = now()
  WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION reset_daily_prayer_count(p_user_id UUID)
RETURNS VOID AS $$
BEGIN
    UPDATE profiles
    SET tokens_spent_today = 0,
        last_prayer_date = CURRENT_DATE
    WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION refill_tokens(p_amount INT)
RETURNS INT AS $$
DECLARE
    v_new_spent INT;
BEGIN
    UPDATE profiles
    SET tokens_spent_today = GREATEST(0, tokens_spent_today - p_amount)
    WHERE id = auth.uid()
    RETURNING tokens_spent_today INTO v_new_spent;
    RETURN v_new_spent;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION reduce_ban_time(p_user_id UUID)
RETURNS INTERVAL AS $$
DECLARE
  current_ban_end TIMESTAMPTZ;
  new_ban_end TIMESTAMPTZ;
  reduction INTERVAL := INTERVAL '15 minutes';
BEGIN
  SELECT ban_until INTO current_ban_end FROM profiles WHERE id = p_user_id;
  IF current_ban_end IS NULL OR current_ban_end < now() THEN
    RETURN INTERVAL '0';
  END IF;
  new_ban_end := current_ban_end - reduction;
  IF new_ban_end < now() THEN
    new_ban_end := now();
  END IF;
  UPDATE profiles SET ban_until = new_ban_end WHERE id = p_user_id;
  INSERT INTO indulgences (user_id, time_removed_seconds)
  VALUES (p_user_id, 900);
  RETURN reduction;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7b. Profile creation trigger (with starting buildings)

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

-- 7c. Prayer functions (slot-aware FIFO)

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
    SELECT tokens_spent_today, daily_token_limit, max_prayer_slots
    INTO v_spent, v_limit, v_max_slots
    FROM profiles WHERE id = v_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Profile not found';
    END IF;

    IF length(prayer_content) > v_char_limit THEN
        RAISE EXCEPTION 'Prayer exceeds maximum length of % characters.', v_char_limit;
    END IF;

    v_cost := ceil(length(prayer_content)::float / v_token_ratio);

    IF (v_spent + v_cost) > v_limit THEN
        RAISE EXCEPTION 'Insufficient Mana. This prayer costs % Mana, but you only have % remaining.', v_cost, (v_limit - v_spent);
    END IF;

    SELECT COUNT(*)::INT INTO v_active_count
    FROM prayers WHERE user_id = v_user_id AND is_praying = true;

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

    INSERT INTO prayers (user_id, content, is_praying, activated_at, last_counted_at)
    VALUES (v_user_id, prayer_content, true, now(), now())
    RETURNING id INTO v_new_prayer_id;

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
    SELECT max_prayer_slots INTO v_max_slots
    FROM profiles WHERE id = v_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Profile not found';
    END IF;

    SELECT COUNT(*)::INT INTO v_active_count
    FROM prayers
    WHERE user_id = v_user_id AND is_praying = true AND id != p_prayer_id;

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

CREATE OR REPLACE FUNCTION deactivate_prayer(
  p_prayer_id UUID,
  p_elapsed_counts INT
)
RETURNS JSONB AS $$
DECLARE
  v_user_id UUID;
  v_prayer RECORD;
  v_milestones INT;
  v_karma_change INT := 0;
BEGIN
  SELECT user_id INTO v_user_id
  FROM prayers WHERE id = p_prayer_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Prayer not found';
  END IF;

  IF v_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  UPDATE prayers
  SET prayer_count = prayer_count + p_elapsed_counts,
      last_counted_at = now(),
      is_praying = false,
      activated_at = NULL
  WHERE id = p_prayer_id
  RETURNING id, prayer_count, is_praying, activated_at, prayer_type, karma_awarded, user_id
  INTO v_prayer;

  v_milestones := floor(v_prayer.prayer_count / 50);

  IF v_milestones > v_prayer.karma_awarded THEN
    v_karma_change := (v_milestones - v_prayer.karma_awarded) * 5 * (
        CASE WHEN v_prayer.prayer_type = 'altruistic' THEN 2 ELSE 1 END
    );
    PERFORM update_karma(v_prayer.user_id, v_karma_change);
    UPDATE prayers SET karma_awarded = v_milestones WHERE id = p_prayer_id;
  END IF;

  RETURN jsonb_build_object(
    'id', v_prayer.id,
    'prayer_count', v_prayer.prayer_count,
    'is_praying', v_prayer.is_praying,
    'activated_at', v_prayer.activated_at,
    'karma_change', v_karma_change
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Read-only sync (client polling)
CREATE OR REPLACE FUNCTION sync_prayer_count(p_prayer_id UUID)
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

-- Full sync with ban reduction (intercessory prayer)
DROP FUNCTION IF EXISTS sync_prayer_count(UUID, INT) CASCADE;
CREATE OR REPLACE FUNCTION sync_prayer_count(
  p_prayer_id UUID,
  p_elapsed_counts INT
)
RETURNS JSONB AS $$
DECLARE
  v_user_id UUID;
  v_prayer RECORD;
  v_milestones INT;
  v_karma_change INT := 0;
  v_ban_check TIMESTAMPTZ;
  v_sinner_redeemed BOOLEAN := false;
  v_ban_reduction INTERVAL;
  v_redemption_bonus INT := 5;
BEGIN
  SELECT user_id, is_praying, prayer_type, source_sinner_id, karma_awarded
  INTO v_prayer
  FROM prayers WHERE id = p_prayer_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'Prayer not found'; END IF;

  IF v_prayer.is_praying = false AND v_prayer.prayer_type = 'intercessory' THEN
    IF v_prayer.activated_at IS NULL OR (now() - v_prayer.activated_at) > INTERVAL '5 minutes' THEN
      RAISE EXCEPTION 'Prayer is not active and was not recently active';
    END IF;
  ELSIF v_prayer.is_praying = false THEN
    RAISE EXCEPTION 'Prayer is not active';
  END IF;

  IF v_prayer.user_id != auth.uid() THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  UPDATE prayers
  SET prayer_count = prayer_count + p_elapsed_counts,
      last_counted_at = now()
  WHERE id = p_prayer_id
  RETURNING id, prayer_count, last_counted_at, activated_at, prayer_type, karma_awarded, user_id, source_sinner_id
  INTO v_prayer;

  v_milestones := floor(v_prayer.prayer_count / 50);

  IF v_milestones > v_prayer.karma_awarded THEN
    v_karma_change := (v_milestones - v_prayer.karma_awarded) * 5 * (
        CASE WHEN v_prayer.prayer_type = 'altruistic' THEN 2 ELSE 1 END
    );
    PERFORM update_karma(v_prayer.user_id, v_karma_change);
    UPDATE prayers SET karma_awarded = v_milestones WHERE id = p_prayer_id;
  END IF;

  IF v_prayer.prayer_type = 'intercessory' AND v_prayer.source_sinner_id IS NOT NULL THEN
    v_ban_reduction := p_elapsed_counts * INTERVAL '1 minute';

    UPDATE profiles
    SET ban_until = GREATEST(now(), ban_until - v_ban_reduction),
        updated_at = now()
    WHERE id = v_prayer.source_sinner_id
      AND ban_until IS NOT NULL
      AND ban_until > now();

    SELECT ban_until INTO v_ban_check
    FROM profiles WHERE id = v_prayer.source_sinner_id;

    IF v_ban_check IS NULL OR v_ban_check <= now() THEN
      UPDATE profiles SET ban_until = NULL, updated_at = now()
      WHERE id = v_prayer.source_sinner_id;
      PERFORM update_karma(v_prayer.user_id, v_redemption_bonus);
      v_karma_change := v_karma_change + v_redemption_bonus;
      UPDATE prayers SET is_praying = false, activated_at = NULL WHERE id = p_prayer_id;
      v_sinner_redeemed := true;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'prayer_count', v_prayer.prayer_count,
    'last_counted_at', v_prayer.last_counted_at,
    'activated_at', v_prayer.activated_at,
    'karma_change', v_karma_change,
    'sinner_redeemed', v_sinner_redeemed
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

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
    SELECT max_prayer_slots INTO v_max_slots
    FROM profiles WHERE id = v_user_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found'; END IF;

    IF p_response_content IS NULL THEN
        SELECT response_content, content INTO v_target
        FROM prayers WHERE id = p_target_prayer_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'Target prayer not found'; END IF;
        p_response_content := COALESCE(v_target.response_content, v_target.content);
    END IF;

    SELECT COUNT(*)::INT INTO v_active_count
    FROM prayers WHERE user_id = v_user_id AND is_praying = true;

    IF v_active_count >= v_max_slots THEN
        SELECT id INTO v_deactivated_id
        FROM prayers
        WHERE user_id = v_user_id AND is_praying = true
        ORDER BY activated_at ASC NULLS LAST
        LIMIT 1;

        IF v_deactivated_id IS NOT NULL THEN
            UPDATE prayers SET is_praying = false, activated_at = NULL
            WHERE id = v_deactivated_id;
        END IF;
    END IF;

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
    SELECT max_prayer_slots INTO v_max_slots
    FROM profiles WHERE id = v_user_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found'; END IF;

    SELECT COUNT(*)::INT INTO v_active_count
    FROM prayers WHERE user_id = v_user_id AND is_praying = true;

    IF v_active_count >= v_max_slots THEN
        SELECT id INTO v_deactivated_id
        FROM prayers
        WHERE user_id = v_user_id AND is_praying = true
        ORDER BY activated_at ASC NULLS LAST
        LIMIT 1;

        IF v_deactivated_id IS NOT NULL THEN
            UPDATE prayers SET is_praying = false, activated_at = NULL
            WHERE id = v_deactivated_id;
        END IF;
    END IF;

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

CREATE OR REPLACE FUNCTION get_public_prayers(
  p_offset INT DEFAULT 0,
  p_limit INT DEFAULT 20,
  p_sort_by TEXT DEFAULT 'newest'
)
RETURNS JSONB AS $$
DECLARE
  v_result JSONB;
  v_order_clause TEXT;
BEGIN
  IF p_sort_by = 'most_prayed' THEN
    v_order_clause := 'prayer_count DESC, created_at DESC';
  ELSE
    v_order_clause := 'created_at DESC';
  END IF;

  EXECUTE format(
    'SELECT jsonb_agg(row_to_json(t)) FROM (
      SELECT p.id, p.user_id, p.response_content, p.prayer_count,
             p.created_at, p.prayer_type,
             pr.username, pr.faith,
             COALESCE(
               (SELECT jsonb_agg(jsonb_build_object(
                  ''blessing_type_id'', pb.blessing_type_id,
                  ''emoji'', bt.emoji,
                  ''name'', bt.name,
                  ''count'', pb.cnt
                ) ORDER BY bt.sort_order)
                FROM (
                  SELECT blessing_type_id, COUNT(*) as cnt
                  FROM prayer_blessings
                  WHERE prayer_id = p.id
                  GROUP BY blessing_type_id
                ) pb
                JOIN blessing_types bt ON pb.blessing_type_id = bt.id
              ),
              ''[]''::jsonb
             ) as blessings
      FROM prayers p
      LEFT JOIN profiles pr ON p.user_id = pr.id
      WHERE p.is_rejected = false
        AND p.is_archived = false
        AND p.status = ''completed''
        AND p.prayer_type = ''own''
      ORDER BY %s
      LIMIT %s OFFSET %s
    ) t',
    v_order_clause, p_limit, p_offset
  ) INTO v_result;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION get_sinners()
RETURNS JSONB AS $$
DECLARE
  v_result JSONB;
BEGIN
  SELECT jsonb_agg(jsonb_build_object(
    'id', p.id,
    'username', p.username,
    'faith', p.faith,
    'ban_until', p.ban_until,
    'rejection_reason', pr.rejection_reason,
    'rejected_content', pr.content
  ))
  INTO v_result
  FROM (
    SELECT p.id, p.username, p.faith, p.ban_until
    FROM profiles p
    WHERE p.ban_until IS NOT NULL
      AND p.ban_until > now()
    ORDER BY p.ban_until ASC
  ) p
  LEFT JOIN LATERAL (
    SELECT content, rejection_reason
    FROM prayers
    WHERE prayers.user_id = p.id
      AND prayers.is_rejected = true
    ORDER BY created_at DESC
    LIMIT 1
  ) pr ON true;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION get_intercessory_prayer_count(p_sinner_id UUID)
RETURNS INT AS $$
  SELECT COUNT(*)::INT FROM prayers
  WHERE source_sinner_id = p_sinner_id
    AND is_praying = true
    AND prayer_type = 'intercessory';
$$ LANGUAGE sql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION purchase_prayer_slot()
RETURNS JSONB AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_current_slots INT;
  v_current_karma INT;
  v_slot_cost INT;
BEGIN
  SELECT max_prayer_slots, COALESCE(karma, 0)
  INTO v_current_slots, v_current_karma
  FROM profiles WHERE id = v_user_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found'; END IF;

  v_slot_cost := 25 * v_current_slots;

  IF v_current_karma < v_slot_cost THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Insufficient karma',
      'cost', v_slot_cost,
      'current_karma', v_current_karma
    );
  END IF;

  UPDATE profiles
  SET karma = karma - v_slot_cost,
      max_prayer_slots = max_prayer_slots + 1,
      daily_token_limit = daily_token_limit + 100,
      updated_at = now()
  WHERE id = v_user_id;

  RETURN jsonb_build_object(
    'success', true,
    'new_slots', v_current_slots + 1,
    'new_daily_limit', (SELECT daily_token_limit FROM profiles WHERE id = v_user_id),
    'new_karma', (SELECT karma FROM profiles WHERE id = v_user_id),
    'cost', v_slot_cost
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;