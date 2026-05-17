-- =====================================================
-- ELECTRIC MONK - THE RAPTURE UPDATE
-- Migration Version: 8.0 — Sects, Land, Synods & Indulgences
-- Date: 2026-05-17
--
-- Adds: Asymmetric Sects (Denominations)
--       Sacred Ground (Finite Land / Acres)
--       Scriptorium & Dogma (Light Tech Tree)
--       Occult Library & Heresy (Dark Tech Tree)
--       Inquisition (Espionage)
--       Synods (Alliance System)
--       Global Relics (10 unique items)
--       Indulgences (Premium Currency)
--       Build Queue (Divine Architect)
--       Active Miracles tracking
--
-- CRITICAL: This is an ADDITIVE migration. All ALTER
-- statements use IF NOT EXISTS. All CREATE statements
-- use IF NOT EXISTS. This can be re-run safely.
--
-- PASTE THIS ENTIRE SCRIPT INTO SUPABASE SQL EDITOR
-- Run it as a single transaction.
-- =====================================================

-- ============================================
-- 1. ALTER profiles: Add new columns
-- ============================================

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS sect_type TEXT DEFAULT NULL
  CHECK (sect_type IS NULL OR sect_type IN ('prosperity_gospel', 'ascetic_order', 'doomsday_preppers', 'inquisition'));

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS sacred_acres INT DEFAULT 25
  CHECK (sacred_acres >= 0);

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS dogma INT DEFAULT 0
  CHECK (dogma >= 0);

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS indulgences INT DEFAULT 0
  CHECK (indulgences >= 0);

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS synod_id UUID DEFAULT NULL;

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS papal_bull_until TIMESTAMPTZ DEFAULT NULL;

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS title TEXT DEFAULT NULL;

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS avatar_url TEXT DEFAULT NULL;

-- ============================================
-- 2. ALTER shop_items: Add new columns
-- ============================================

ALTER TABLE shop_items ADD COLUMN IF NOT EXISTS acre_cost INT NOT NULL DEFAULT 0
  CHECK (acre_cost >= 0);

ALTER TABLE shop_items ADD COLUMN IF NOT EXISTS sect_restriction TEXT DEFAULT NULL
  CHECK (sect_restriction IS NULL OR sect_restriction IN ('prosperity_gospel', 'ascetic_order', 'doomsday_preppers', 'inquisition'));

ALTER TABLE shop_items ADD COLUMN IF NOT EXISTS sect_exclusion TEXT DEFAULT NULL
  CHECK (sect_exclusion IS NULL OR sect_exclusion IN ('prosperity_gospel', 'ascetic_order', 'doomsday_preppers', 'inquisition'));

-- ============================================
-- 3. CREATE synods TABLE
-- ============================================

CREATE TABLE IF NOT EXISTS synods (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL UNIQUE CHECK (LENGTH(name) BETWEEN 3 AND 30),
  leader_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  tax_rate NUMERIC DEFAULT 0.05 CHECK (tax_rate >= 0.01 AND tax_rate <= 0.15),
  vault_gold INT DEFAULT 0,
  vault_mana INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_synods_leader ON synods(leader_id);

ALTER TABLE synods ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Synods are publicly readable" ON synods;
CREATE POLICY "Synods are publicly readable" ON synods
  FOR SELECT USING (true);
DROP POLICY IF EXISTS "Synod leader can update" ON synods;
CREATE POLICY "Synod leader can update" ON synods
  FOR UPDATE USING (auth.uid() = leader_id);

-- Add foreign key from profiles to synods
-- (Do this after synods table exists)
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
-- 4. CREATE synod_wars TABLE
-- ============================================

CREATE TABLE IF NOT EXISTS synod_wars (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  attacker_synod_id UUID REFERENCES synods(id) ON DELETE CASCADE NOT NULL,
  defender_synod_id UUID REFERENCES synods(id) ON DELETE CASCADE NOT NULL,
  declared_at TIMESTAMPTZ DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  is_active BOOLEAN DEFAULT true
);

CREATE INDEX IF NOT EXISTS idx_synod_wars_attacker ON synod_wars(attacker_synod_id);
CREATE INDEX IF NOT EXISTS idx_synod_wars_defender ON synod_wars(defender_synod_id);
CREATE INDEX IF NOT EXISTS idx_synod_wars_active ON synod_wars(is_active) WHERE is_active = true;

ALTER TABLE synod_wars ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Synod wars are publicly readable" ON synod_wars;
CREATE POLICY "Synod wars are publicly readable" ON synod_wars
  FOR SELECT USING (true);

-- ============================================
-- 5. CREATE research_nodes TABLE
-- ============================================

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

ALTER TABLE research_nodes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Research nodes are publicly readable" ON research_nodes;
CREATE POLICY "Research nodes are publicly readable" ON research_nodes
  FOR SELECT USING (true);

-- ============================================
-- 6. CREATE player_research TABLE
-- ============================================

CREATE TABLE IF NOT EXISTS player_research (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  node_id TEXT REFERENCES research_nodes(id) ON DELETE CASCADE NOT NULL,
  unlocked_at TIMESTAMPTZ DEFAULT now(),
  expires_at TIMESTAMPTZ,
  UNIQUE(user_id, node_id)
);

CREATE INDEX IF NOT EXISTS idx_player_research_user ON player_research(user_id);

ALTER TABLE player_research ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Players can read own research" ON player_research;
CREATE POLICY "Players can read own research" ON player_research
  FOR SELECT USING (auth.uid() = user_id);

-- ============================================
-- 7. CREATE relics TABLE
-- ============================================

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

CREATE INDEX IF NOT EXISTS idx_relics_holder ON relics(holder_id);

ALTER TABLE relics ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Relics are publicly readable" ON relics;
CREATE POLICY "Relics are publicly readable" ON relics
  FOR SELECT USING (true);

-- ============================================
-- 8. CREATE active_miracles TABLE
-- ============================================

CREATE TABLE IF NOT EXISTS active_miracles (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  miracle_type TEXT NOT NULL,
  effect_data JSONB NOT NULL DEFAULT '{}'::jsonb,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_active_miracles_user ON active_miracles(user_id);
CREATE INDEX IF NOT EXISTS idx_active_miracles_expires ON active_miracles(expires_at);

ALTER TABLE active_miracles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Miracles are publicly readable" ON active_miracles;
CREATE POLICY "Miracles are publicly readable" ON active_miracles
  FOR SELECT USING (true);

-- ============================================
-- 9. CREATE build_queue TABLE
-- ============================================

CREATE TABLE IF NOT EXISTS build_queue (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  item_id TEXT REFERENCES shop_items(id) ON DELETE CASCADE NOT NULL,
  queued_at TIMESTAMPTZ DEFAULT now(),
  auto_execute BOOLEAN DEFAULT true,
  executed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_build_queue_user ON build_queue(user_id);
CREATE INDEX IF NOT EXISTS idx_build_queue_pending ON build_queue(user_id) WHERE executed_at IS NULL;

ALTER TABLE build_queue ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Players can read own build queue" ON build_queue;
CREATE POLICY "Players can read own build queue" ON build_queue
  FOR SELECT USING (auth.uid() = user_id);

-- ============================================
-- 10. SEED game_config: Sect Modifiers
-- ============================================

INSERT INTO game_config (key, value, description, category) VALUES
  -- Prosperity Gospel: +50% Gold, -20% Faith (mana), +100% Cathedral upkeep
  ('sect.prosperity_gospel.gold_multiplier', 1.5, 'Prosperity Gospel: +50% Gold generation', 'sect'),
  ('sect.prosperity_gospel.mana_multiplier', 0.8, 'Prosperity Gospel: -20% Mana generation', 'sect'),
  ('sect.prosperity_gospel.cathedral_upkeep_multiplier', 2.0, 'Prosperity Gospel: +100% Cathedral gold upkeep', 'sect'),
  -- Ascetic Order: -50% Food consumption, +20% Faith (mana), max tier 2 mana buildings
  ('sect.ascetic_order.food_consumption_multiplier', 0.5, 'Ascetic Order: -50% Food consumption', 'sect'),
  ('sect.ascetic_order.mana_multiplier', 1.2, 'Ascetic Order: +20% Mana generation', 'sect'),
  ('sect.ascetic_order.max_building_tier', 2, 'Ascetic Order: Max building tier for mana estates (Shrine)', 'sect'),
  -- Doomsday Preppers: +50% Food generation, +50% Crusade defense, -25% Gold
  ('sect.doomsday_preppers.food_multiplier', 1.5, 'Doomsday Preppers: +50% Food generation', 'sect'),
  ('sect.doomsday_preppers.crusade_defense_bonus', 0.5, 'Doomsday Preppers: +50% defensive power in Crusades', 'sect'),
  ('sect.doomsday_preppers.gold_multiplier', 0.75, 'Doomsday Preppers: -25% Gold generation', 'sect'),
  -- Inquisition: +100% Heresy, -30% Mana, Inquisitions cost 50% less Gold
  ('sect.inquisition.heresy_multiplier', 2.0, 'Inquisition: +100% Heresy generation', 'sect'),
  ('sect.inquisition.mana_multiplier', 0.7, 'Inquisition: -30% Mana generation', 'sect'),
  ('sect.inquisition.inquisition_gold_cost_multiplier', 0.5, 'Inquisition: -50% Gold cost for Inquisitions', 'sect')
ON CONFLICT (key) DO UPDATE SET
  value = EXCLUDED.value,
  description = EXCLUDED.description,
  category = EXCLUDED.category,
  updated_at = now();

-- ============================================
-- 11. SEED game_config: Building Acre Costs
-- ============================================

INSERT INTO game_config (key, value, description, category) VALUES
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
  ('building.scriptorium.acre_cost', 4, 'Sacred acres consumed by a Scriptorium', 'acres')
ON CONFLICT (key) DO UPDATE SET
  value = EXCLUDED.value,
  description = EXCLUDED.description,
  category = EXCLUDED.category,
  updated_at = now();

-- ============================================
-- 12. SEED game_config: Scriptorium Production
-- ============================================

INSERT INTO game_config (key, value, description, category) VALUES
  ('building.scriptorium.dogma_per_day', 20, 'Dogma generated per day by a Scriptorium', 'production'),
  ('building.scriptorium.gold_per_day', 0, 'Scriptorium produces no gold', 'production'),
  ('building.scriptorium.food_consumption_per_day', 4, 'Food consumed per day by a Scriptorium', 'upkeep'),
  ('building.scriptorium.gold_upkeep_per_day', 2, 'Gold upkeep per day for a Scriptorium', 'upkeep'),
  ('cap.dogma_multiplier', 10, 'Dogma cap = total_daily_dogma * this multiplier', 'caps')
ON CONFLICT (key) DO UPDATE SET
  value = EXCLUDED.value,
  description = EXCLUDED.description,
  category = EXCLUDED.category,
  updated_at = now();

-- ============================================
-- 13. SEED game_config: Inquisition Config
-- ============================================

INSERT INTO game_config (key, value, description, category) VALUES
  ('inquisition.gold_cost', 200, 'Gold cost to launch an Inquisition', 'combat'),
  ('crusade.acres_stolen', 3, 'Sacred acres stolen from defender on successful Crusade', 'combat')
ON CONFLICT (key) DO UPDATE SET
  value = EXCLUDED.value,
  description = EXCLUDED.description,
  category = EXCLUDED.category,
  updated_at = now();

-- ============================================
-- 14. SEED game_config: Synod Config
-- ============================================

INSERT INTO game_config (key, value, description, category) VALUES
  ('synod.max_members', 20, 'Maximum members per Synod', 'synod'),
  ('synod.creation_cost_gold', 500, 'Gold cost to create a Synod', 'synod'),
  ('synod.holy_war_duration_hours', 48, 'Duration of Holy War bonus in hours', 'synod'),
  ('synod.holy_war_attack_bonus', 0.20, '+20% attack bonus during Holy War', 'synod'),
  ('synod.relic_steal_crusades_required', 5, 'Unique Synod members required to steal a relic', 'synod'),
  ('synod.relic_steal_window_hours', 1, 'Hours window for coordinated relic theft', 'synod')
ON CONFLICT (key) DO UPDATE SET
  value = EXCLUDED.value,
  description = EXCLUDED.description,
  category = EXCLUDED.category,
  updated_at = now();

-- ============================================
-- 15. SEED game_config: Indulgence Config
-- ============================================

INSERT INTO game_config (key, value, description, category) VALUES
  ('indulgence.papal_bull_cost', 500, 'Indulgences cost for Papal Bull of Protection', 'indulgences'),
  ('indulgence.papal_bull_duration_hours', 12, 'Hours of immunity from Papal Bull', 'indulgences'),
  ('indulgence.divine_architect_cost', 200, 'Indulgences cost for Divine Architect', 'indulgences'),
  ('indulgence.divine_architect_queue_limit', 5, 'Max queued buildings with Divine Architect', 'indulgences')
ON CONFLICT (key) DO UPDATE SET
  value = EXCLUDED.value,
  description = EXCLUDED.description,
  category = EXCLUDED.category,
  updated_at = now();

-- ============================================
-- 16. SEED shop_items: Scriptorium + Acre Costs
-- ============================================

INSERT INTO shop_items (id, category, name, description, emoji_icon, karma_cost, gold_cost, heresy_cost, effect_type, effect_data, purchase_limit, requires_building, sort_order, is_active, cost_scaling, acre_cost, sect_restriction, sect_exclusion) VALUES
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

-- Update existing shop items with acre costs and sect exclusions
-- Ascetic Order cannot purchase Temple, Church, Cathedral
UPDATE shop_items SET acre_cost = 3, sect_exclusion = 'ascetic_order' WHERE id = 'temple';
UPDATE shop_items SET acre_cost = 5, sect_exclusion = 'ascetic_order' WHERE id = 'church';
UPDATE shop_items SET acre_cost = 8, sect_exclusion = 'ascetic_order' WHERE id = 'cathedral';

-- Mana Estate acre costs
UPDATE shop_items SET acre_cost = 1 WHERE id = 'altar';
UPDATE shop_items SET acre_cost = 2 WHERE id = 'shrine';

-- Food Estate acre costs
UPDATE shop_items SET acre_cost = 1 WHERE id = 'pot';
UPDATE shop_items SET acre_cost = 2 WHERE id = 'patch';
UPDATE shop_items SET acre_cost = 3 WHERE id = 'garden';
UPDATE shop_items SET acre_cost = 5 WHERE id = 'field';
UPDATE shop_items SET acre_cost = 8 WHERE id = 'farm';

-- Workforce acre costs
UPDATE shop_items SET acre_cost = 1 WHERE id = 'novice';
UPDATE shop_items SET acre_cost = 1 WHERE id = 'monk';
UPDATE shop_items SET acre_cost = 2 WHERE id = 'cleric';
UPDATE shop_items SET acre_cost = 3 WHERE id = 'bishop';
UPDATE shop_items SET acre_cost = 5 WHERE id = 'cardinal';

-- Catacombs acre costs
UPDATE shop_items SET acre_cost = 1 WHERE id = 'cultist';
UPDATE shop_items SET acre_cost = 3 WHERE id = 'coven';

-- Infrastructure (no acre cost)
UPDATE shop_items SET acre_cost = 0 WHERE id IN ('prayer-slot-2', 'prayer-slot-3', 'prayer-slot-4', 'prayer-slot-5');

-- ============================================
-- 17. SEED research_nodes: Light Tech Tree
-- ============================================

INSERT INTO research_nodes (id, name, description, emoji_icon, alignment, cost, effect_type, effect_data, requires_node, sort_order, is_active) VALUES
  ('tax_evasion', 'Tax Evasion', 'Reduces vassal tithe from 10% to 5%', '💸', 'light', 200, 'vassal_tithe_reduction', '{"reduction_percent": 50}'::jsonb, NULL, 1, true),
  ('holy_war', 'Holy War', '+15% Crusade Attack Power', '⚔', 'light', 300, 'crusade_attack_bonus', '{"bonus_percent": 15}'::jsonb, 'tax_evasion', 2, true),
  ('divine_architecture', 'Divine Architecture', 'Reduces all building acre costs by 20%', '🏛', 'light', 400, 'acre_cost_reduction', '{"reduction_percent": 20}'::jsonb, 'holy_war', 3, true),
  ('fertile_ground', 'Fertile Ground', '+25% Food generation', '🌱', 'light', 350, 'food_bonus', '{"bonus_percent": 25}'::jsonb, NULL, 4, true),
  ('consecrated_ground', 'Consecrated Ground', '+10 Sacred Acres', '✞', 'light', 500, 'acres_bonus', '{"acres_bonus": 10}'::jsonb, 'fertile_ground', 5, true)
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

-- ============================================
-- 18. SEED research_nodes: Dark Tech Tree
-- ============================================

INSERT INTO research_nodes (id, name, description, emoji_icon, alignment, cost, effect_type, effect_data, requires_node, sort_order, is_active) VALUES
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

-- ============================================
-- 19. SEED relics: 10 Global Relics
-- ============================================

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

-- ============================================
-- 20. RPC: choose_sect(p_sect_type TEXT)
-- ============================================

CREATE OR REPLACE FUNCTION public.choose_sect(p_sect_type TEXT)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_current_sect TEXT;
BEGIN
    IF p_sect_type NOT IN ('prosperity_gospel', 'ascetic_order', 'doomsday_preppers', 'inquisition') THEN
        RAISE EXCEPTION 'Invalid sect type. Must be one of: prosperity_gospel, ascetic_order, doomsday_preppers, inquisition';
    END IF;

    SELECT sect_type INTO v_current_sect FROM profiles WHERE id = v_user_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found'; END IF;

    IF v_current_sect IS NOT NULL THEN
        RAISE EXCEPTION 'Sect already chosen. This decision is permanent.';
    END IF;

    UPDATE profiles SET sect_type = p_sect_type, updated_at = now() WHERE id = v_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'sect_type', p_sect_type
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 21. RPC: launch_inquisition(p_target_id UUID)
-- ============================================

CREATE OR REPLACE FUNCTION public.launch_inquisition(p_target_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_user_gold INT;
    v_gold_cost NUMERIC;
    v_cost_multiplier NUMERIC;
    v_target_heresy INT;
    v_target_miracles JSONB;
    v_target_worker RECORD;
    v_worker_killed BOOLEAN := false;
    v_sect_type TEXT;
    v_has_shadow_veil BOOLEAN;
BEGIN
    IF p_target_id = v_user_id THEN
        RAISE EXCEPTION 'Cannot inquisition yourself';
    END IF;

    -- Load base cost
    SELECT value INTO v_gold_cost FROM game_config WHERE key = 'inquisition.gold_cost';
    IF v_gold_cost IS NULL THEN v_gold_cost := 200; END IF;

    -- Check if user's sect has cost reduction
    SELECT sect_type INTO v_sect_type FROM profiles WHERE id = v_user_id;
    IF v_sect_type = 'inquisition' THEN
        SELECT value INTO v_cost_multiplier FROM game_config WHERE key = 'sect.inquisition.inquisition_gold_cost_multiplier';
        IF v_cost_multiplier IS NULL THEN v_cost_multiplier := 0.5; END IF;
        v_gold_cost := FLOOR(v_gold_cost * v_cost_multiplier);
    END IF;

    -- Check gold balance
    SELECT gold INTO v_user_gold FROM profiles WHERE id = v_user_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found'; END IF;
    IF v_user_gold < v_gold_cost THEN
        RAISE EXCEPTION 'Insufficient Gold. Need %, have %.', v_gold_cost, v_user_gold;
    END IF;

    -- Check if target has Shadow Veil
    SELECT EXISTS(
        SELECT 1 FROM player_research pr
        JOIN research_nodes rn ON rn.id = pr.node_id
        WHERE pr.user_id = p_target_id
          AND rn.effect_type = 'inquisition_immunity'
          AND (pr.expires_at IS NULL OR pr.expires_at > now())
    ) INTO v_has_shadow_veil;

    IF v_has_shadow_veil THEN
        RAISE EXCEPTION 'Target is protected by Shadow Veil. Inquisition cannot proceed.';
    END IF;

    -- Deduct gold
    UPDATE profiles SET gold = gold - v_gold_cost, updated_at = now() WHERE id = v_user_id;

    -- Get target heresy
    SELECT heresy INTO v_target_heresy FROM profiles WHERE id = p_target_id;

    -- Get target active miracles
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'miracle_type', miracle_type,
        'effect_data', effect_data,
        'expires_at', expires_at
    )), '[]'::jsonb) INTO v_target_miracles
    FROM active_miracles WHERE user_id = p_target_id AND expires_at > now();

    -- Assassinate highest-tier worker (Cardinal > Bishop > Cleric > Monk > Novice)
    FOR v_target_worker IN
        SELECT pb.id, pb.building_type
        FROM player_buildings pb
        WHERE pb.user_id = p_target_id AND pb.is_active = true
          AND pb.building_type IN ('cardinal', 'bishop', 'cleric', 'monk', 'novice')
        ORDER BY CASE pb.building_type
            WHEN 'cardinal' THEN 5
            WHEN 'bishop' THEN 4
            WHEN 'cleric' THEN 3
            WHEN 'monk' THEN 2
            WHEN 'novice' THEN 1
        END DESC
        LIMIT 1
    LOOP
        UPDATE player_buildings SET is_active = false WHERE id = v_target_worker.id;
        v_worker_killed := true;
        EXIT;
    END LOOP;

    -- Log to akashic_logs
    INSERT INTO akashic_logs (target_id, actor_id, action_type, result_data)
    VALUES (p_target_id, v_user_id, 'inquisition', jsonb_build_object(
        'gold_cost', v_gold_cost,
        'target_heresy_revealed', v_target_heresy,
        'miracles_revealed', v_target_miracles,
        'worker_killed', v_worker_killed,
        'worker_type', CASE WHEN v_worker_killed THEN v_target_worker.building_type ELSE NULL END
    ));

    RETURN jsonb_build_object(
        'success', true,
        'gold_cost', v_gold_cost,
        'target_heresy', v_target_heresy,
        'miracles_revealed', v_target_miracles,
        'worker_killed', v_worker_killed,
        'worker_type', CASE WHEN v_worker_killed THEN v_target_worker.building_type ELSE NULL END
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 22. RPC: research_tech(p_node_id TEXT)
-- ============================================

CREATE OR REPLACE FUNCTION public.research_tech(p_node_id TEXT)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_node RECORD;
    v_user_dogma INT;
    v_user_heresy INT;
    v_already_unlocked INT;
    v_prereq_met BOOLEAN;
    v_expiry TIMESTAMPTZ;
BEGIN
    SELECT * INTO v_node FROM research_nodes WHERE id = p_node_id AND is_active = true;
    IF NOT FOUND THEN RAISE EXCEPTION 'Research node not found or inactive'; END IF;

    -- Check if already unlocked
    SELECT COUNT(*) INTO v_already_unlocked FROM player_research
    WHERE user_id = v_user_id AND node_id = p_node_id
      AND (expires_at IS NULL OR expires_at > now());
    IF v_already_unlocked > 0 THEN
        RAISE EXCEPTION 'Already researched: %', p_node_id;
    END IF;

    -- Check prerequisite
    IF v_node.requires_node IS NOT NULL THEN
        SELECT EXISTS(
            SELECT 1 FROM player_research
            WHERE user_id = v_user_id AND node_id = v_node.requires_node
              AND (expires_at IS NULL OR expires_at > now())
        ) INTO v_prereq_met;
        IF NOT v_prereq_met THEN
            RAISE EXCEPTION 'Prerequisite not met: %', v_node.requires_node;
        END IF;
    END IF;

    -- Check currency and deduct
    IF v_node.alignment = 'light' THEN
        SELECT dogma INTO v_user_dogma FROM profiles WHERE id = v_user_id;
        IF v_user_dogma < v_node.cost THEN
            RAISE EXCEPTION 'Insufficient Dogma. Need %, have %.', v_node.cost, v_user_dogma;
        END IF;
        UPDATE profiles SET dogma = dogma - v_node.cost, updated_at = now() WHERE id = v_user_id;
    ELSIF v_node.alignment = 'dark' THEN
        SELECT heresy INTO v_user_heresy FROM profiles WHERE id = v_user_id;
        IF v_user_heresy < v_node.cost THEN
            RAISE EXCEPTION 'Insufficient Heresy. Need %, have %.', v_node.cost, v_user_heresy;
        END IF;
        UPDATE profiles SET heresy = heresy - v_node.cost, updated_at = now() WHERE id = v_user_id;
    END IF;

    -- Set expiry for timed effects
    IF v_node.effect_type = 'tithe_intercept' THEN
        v_expiry := now() + (COALESCE((v_node.effect_data->>'duration_hours')::NUMERIC, 12) * interval '1 hour');
    ELSIF v_node.effect_type = 'inquisition_immunity' THEN
        v_expiry := now() + (COALESCE((v_node.effect_data->>'duration_hours')::NUMERIC, 24) * interval '1 hour');
    ELSE
        v_expiry := NULL;
    END IF;

    -- Insert research unlock
    INSERT INTO player_research (user_id, node_id, expires_at)
    VALUES (v_user_id, p_node_id, v_expiry);

    -- Apply immediate effects (like acres bonus)
    IF v_node.effect_type = 'acres_bonus' THEN
        UPDATE profiles SET sacred_acres = sacred_acres + COALESCE((v_node.effect_data->>'acres_bonus')::INT, 10), updated_at = now()
        WHERE id = v_user_id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'node_id', p_node_id,
        'alignment', v_node.alignment,
        'cost', v_node.cost,
        'effect_type', v_node.effect_type,
        'effect_data', v_node.effect_data,
        'expires_at', v_expiry
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 23. RPC: create_synod(p_name TEXT)
-- ============================================

CREATE OR REPLACE FUNCTION public.create_synod(p_name TEXT)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_user_gold INT;
    v_creation_cost NUMERIC;
    v_existing_synod UUID;
    v_new_synod_id UUID;
BEGIN
    -- Check name length
    IF LENGTH(p_name) < 3 OR LENGTH(p_name) > 30 THEN
        RAISE EXCEPTION 'Synod name must be between 3 and 30 characters';
    END IF;

    -- Check user not already in a synod
    SELECT synod_id INTO v_existing_synod FROM profiles WHERE id = v_user_id;
    IF v_existing_synod IS NOT NULL THEN
        RAISE EXCEPTION 'You are already in a Synod. Leave your current Synod first.';
    END IF;

    -- Check gold
    SELECT value INTO v_creation_cost FROM game_config WHERE key = 'synod.creation_cost_gold';
    IF v_creation_cost IS NULL THEN v_creation_cost := 500; END IF;

    SELECT gold INTO v_user_gold FROM profiles WHERE id = v_user_id;
    IF v_user_gold < v_creation_cost THEN
        RAISE EXCEPTION 'Insufficient Gold. Need %, have %.', v_creation_cost, v_user_gold;
    END IF;

    -- Deduct gold
    UPDATE profiles SET gold = gold - v_creation_cost, updated_at = now() WHERE id = v_user_id;

    -- Create synod
    INSERT INTO synods (name, leader_id, tax_rate)
    VALUES (p_name, v_user_id, 0.05)
    RETURNING id INTO v_new_synod_id;

    -- Set user's synod_id
    UPDATE profiles SET synod_id = v_new_synod_id, updated_at = now() WHERE id = v_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'synod_id', v_new_synod_id,
        'name', p_name,
        'gold_spent', v_creation_cost
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 24. RPC: join_synod(p_synod_id UUID)
-- ============================================

CREATE OR REPLACE FUNCTION public.join_synod(p_synod_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_existing_synod UUID;
    v_member_count INT;
    v_max_members NUMERIC;
BEGIN
    -- Check user not already in a synod
    SELECT synod_id INTO v_existing_synod FROM profiles WHERE id = v_user_id;
    IF v_existing_synod IS NOT NULL THEN
        RAISE EXCEPTION 'You are already in a Synod. Leave your current Synod first.';
    END IF;

    -- Check synod exists
    IF NOT EXISTS (SELECT 1 FROM synods WHERE id = p_synod_id) THEN
        RAISE EXCEPTION 'Synod not found';
    END IF;

    -- Check member count
    SELECT value INTO v_max_members FROM game_config WHERE key = 'synod.max_members';
    IF v_max_members IS NULL THEN v_max_members := 20; END IF;

    SELECT COUNT(*) INTO v_member_count FROM profiles WHERE synod_id = p_synod_id;
    IF v_member_count >= v_max_members THEN
        RAISE EXCEPTION 'Synod is full. Maximum % members.', v_max_members;
    END IF;

    -- Join
    UPDATE profiles SET synod_id = p_synod_id, updated_at = now() WHERE id = v_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'synod_id', p_synod_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 25. RPC: leave_synod()
-- ============================================

CREATE OR REPLACE FUNCTION public.leave_synod()
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_synod_id UUID;
    v_is_leader BOOLEAN;
    v_member_count INT;
    v_oldest_member_id UUID;
BEGIN
    SELECT synod_id INTO v_synod_id FROM profiles WHERE id = v_user_id;
    IF v_synod_id IS NULL THEN
        RAISE EXCEPTION 'You are not in a Synod';
    END IF;

    -- Check if leader
    SELECT (leader_id = v_user_id), id INTO v_is_leader, v_synod_id
    FROM synods WHERE id = v_synod_id;

    -- Remove user from synod
    UPDATE profiles SET synod_id = NULL, updated_at = now() WHERE id = v_user_id;

    IF v_is_leader THEN
        -- Find oldest member to promote
        SELECT id INTO v_oldest_member_id
        FROM profiles
        WHERE synod_id = v_synod_id AND id != v_user_id
        ORDER BY created_at ASC
        LIMIT 1;

        IF v_oldest_member_id IS NOT NULL THEN
            -- Promote new leader
            UPDATE synods SET leader_id = v_oldest_member_id WHERE id = v_synod_id;
        ELSE
            -- No members left, dissolve synod
            DELETE FROM synods WHERE id = v_synod_id;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'former_synod_id', v_synod_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 26. RPC: declare_holy_war(p_target_synod_id UUID)
-- ============================================

CREATE OR REPLACE FUNCTION public.declare_holy_war(p_target_synod_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_attacker_synod_id UUID;
    v_is_leader BOOLEAN;
    v_duration_hours NUMERIC;
    v_already_at_war INT;
BEGIN
    -- Get user's synod
    SELECT synod_id INTO v_attacker_synod_id FROM profiles WHERE id = v_user_id;
    IF v_attacker_synod_id IS NULL THEN
        RAISE EXCEPTION 'You are not in a Synod';
    END IF;

    -- Check user is leader
    SELECT (leader_id = v_user_id) INTO v_is_leader FROM synods WHERE id = v_attacker_synod_id;
    IF NOT v_is_leader THEN
        RAISE EXCEPTION 'Only the Synod leader can declare Holy War';
    END IF;

    -- Can't declare war on yourself
    IF p_target_synod_id = v_attacker_synod_id THEN
        RAISE EXCEPTION 'Cannot declare Holy War on your own Synod';
    END IF;

    -- Check target synod exists
    IF NOT EXISTS (SELECT 1 FROM synods WHERE id = p_target_synod_id) THEN
        RAISE EXCEPTION 'Target Synod not found';
    END IF;

    -- Check not already at war
    SELECT COUNT(*) INTO v_already_at_war FROM synod_wars
    WHERE attacker_synod_id = v_attacker_synod_id
      AND defender_synod_id = p_target_synod_id
      AND is_active = true;

    IF v_already_at_war > 0 THEN
        RAISE EXCEPTION 'Already at war with this Synod';
    END IF;

    -- Get duration
    SELECT value INTO v_duration_hours FROM game_config WHERE key = 'synod.holy_war_duration_hours';
    IF v_duration_hours IS NULL THEN v_duration_hours := 48; END IF;

    -- Create war
    INSERT INTO synod_wars (attacker_synod_id, defender_synod_id, expires_at)
    VALUES (v_attacker_synod_id, p_target_synod_id, now() + (v_duration_hours * interval '1 hour'));

    RETURN jsonb_build_object(
        'success', true,
        'attacker_synod_id', v_attacker_synod_id,
        'defender_synod_id', p_target_synod_id,
        'duration_hours', v_duration_hours
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 27. RPC: attempt_relic_steal(p_relic_id UUID)
-- ============================================

CREATE OR REPLACE FUNCTION public.attempt_relic_steal(p_relic_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_relic RECORD;
    v_user_synod_id UUID;
    v_required_crusades INT;
    v_window_hours NUMERIC;
    v_stolen BOOLEAN := false;
BEGIN
    -- Get user's synod
    SELECT synod_id INTO v_user_synod_id FROM profiles WHERE id = v_user_id;
    IF v_user_synod_id IS NULL THEN
        RAISE EXCEPTION 'You must be in a Synod to steal a relic';
    END IF;

    -- Get relic
    SELECT * INTO v_relic FROM relics WHERE id = p_relic_id AND is_active = true;
    IF NOT FOUND THEN RAISE EXCEPTION 'Relic not found'; END IF;

    -- Can't steal from yourself
    IF v_relic.holder_id = v_user_id THEN
        RAISE EXCEPTION 'You already hold this relic';
    END IF;

    -- Can't steal unowned relics (shouldn't happen but safety check)
    IF v_relic.holder_id IS NULL THEN
        -- Claim it directly
        UPDATE relics SET holder_id = v_user_id, last_stolen_at = now(), steal_progress = 0, steal_window_start = NULL
        WHERE id = p_relic_id;
        RETURN jsonb_build_object('success', true, 'action', 'claimed', 'relic_id', p_relic_id);
    END IF;

    -- Get config
    SELECT value INTO v_required_crusades FROM game_config WHERE key = 'synod.relic_steal_crusades_required';
    IF v_required_crusades IS NULL THEN v_required_crusades := 5; END IF;

    SELECT value INTO v_window_hours FROM game_config WHERE key = 'synod.relic_steal_window_hours';
    IF v_window_hours IS NULL THEN v_window_hours := 1; END IF;

    -- Check if window has expired, reset if so
    IF v_relic.steal_window_start IS NOT NULL AND v_relic.steal_window_start < (now() - (v_window_hours * interval '1 hour')) THEN
        -- Window expired, reset progress
        UPDATE relics SET steal_progress = 0, steal_window_start = NULL WHERE id = p_relic_id;
        v_relic.steal_progress := 0;
        v_relic.steal_window_start := NULL;
    END IF;

    -- Start new window if needed
    IF v_relic.steal_window_start IS NULL THEN
        UPDATE relics SET steal_window_start = now(), steal_progress = 0 WHERE id = p_relic_id;
        v_relic.steal_window_start := now();
        v_relic.steal_progress := 0;
    END IF;

    -- Check if this user's synod has already contributed (unique member check)
    -- We track via akashic_logs: each successful crusade by a synod member against the holder counts
    -- For simplicity, we increment steal_progress and transfer when threshold met
    UPDATE relics SET steal_progress = steal_progress + 1 WHERE id = p_relic_id;

    -- Check if threshold met
    SELECT steal_progress INTO v_relic.steal_progress FROM relics WHERE id = p_relic_id;

    IF v_relic.steal_progress >= v_required_crusades THEN
        -- Transfer relic to attacking synod leader
        UPDATE relics SET holder_id = v_user_id, last_stolen_at = now(), steal_progress = 0, steal_window_start = NULL
        WHERE id = p_relic_id;
        v_stolen := true;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'relic_id', p_relic_id,
        'steal_progress', LEAST(v_relic.steal_progress + 1, v_required_crusades),
        'required_progress', v_required_crusades,
        'stolen', v_stolen
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 28. RPC: consume_indulgence(p_action_type TEXT)
-- ============================================

CREATE OR REPLACE FUNCTION public.consume_indulgence(p_action_type TEXT)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_user_indulgences INT;
    v_user_synod_id UUID;
    v_cost INT;
    v_duration_hours NUMERIC;
    v_at_war BOOLEAN;
    v_queue_limit INT;
    v_current_queue INT;
    v_papal_bull_cost NUMERIC;
    v_architect_cost NUMERIC;
BEGIN
    -- Get user indulgences
    SELECT indulgences, synod_id INTO v_user_indulgences, v_user_synod_id
    FROM profiles WHERE id = v_user_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found'; END IF;

    CASE p_action_type
        WHEN 'papal_bull' THEN
            -- Get cost
            SELECT value INTO v_papal_bull_cost FROM game_config WHERE key = 'indulgence.papal_bull_cost';
            IF v_papal_bull_cost IS NULL THEN v_papal_bull_cost := 500; END IF;
            v_cost := v_papal_bull_cost::INT;

            -- Get duration
            SELECT value INTO v_duration_hours FROM game_config WHERE key = 'indulgence.papal_bull_duration_hours';
            IF v_duration_hours IS NULL THEN v_duration_hours := 12; END IF;

            -- Check if in active Holy War
            IF v_user_synod_id IS NOT NULL THEN
                SELECT EXISTS(
                    SELECT 1 FROM synod_wars
                    WHERE (attacker_synod_id = v_user_synod_id OR defender_synod_id = v_user_synod_id)
                      AND is_active = true
                ) INTO v_at_war;
                IF v_at_war THEN
                    RAISE EXCEPTION 'Cannot activate Papal Bull during an active Holy War';
                END IF;
            END IF;

            -- Check balance
            IF v_user_indulgences < v_cost THEN
                RAISE EXCEPTION 'Insufficient Indulgences. Need %, have %.', v_cost, v_user_indulgences;
            END IF;

            -- Deduct and activate
            UPDATE profiles SET
                indulgences = indulgences - v_cost,
                papal_bull_until = now() + (v_duration_hours * interval '1 hour'),
                updated_at = now()
            WHERE id = v_user_id;

            -- Create active_miracles record
            INSERT INTO active_miracles (user_id, miracle_type, effect_data, expires_at)
            VALUES (v_user_id, 'papal_bull', '{"immunity": true}'::jsonb, now() + (v_duration_hours * interval '1 hour'));

            RETURN jsonb_build_object(
                'success', true,
                'action', 'papal_bull',
                'indulgences_spent', v_cost,
                'expires_at', now() + (v_duration_hours * interval '1 hour')
            );

        WHEN 'divine_architect' THEN
            -- Get cost
            SELECT value INTO v_architect_cost FROM game_config WHERE key = 'indulgence.divine_architect_cost';
            IF v_architect_cost IS NULL THEN v_architect_cost := 200; END IF;
            v_cost := v_architect_cost::INT;

            -- Get queue limit
            SELECT value INTO v_queue_limit FROM game_config WHERE key = 'indulgence.divine_architect_queue_limit';
            IF v_queue_limit IS NULL THEN v_queue_limit := 5; END IF;

            -- Check current queue
            SELECT COUNT(*) INTO v_current_queue FROM build_queue
            WHERE user_id = v_user_id AND executed_at IS NULL;

            IF v_current_queue >= v_queue_limit THEN
                RAISE EXCEPTION 'Build queue is full. Maximum % items.', v_queue_limit;
            END IF;

            -- Check balance
            IF v_user_indulgences < v_cost THEN
                RAISE EXCEPTION 'Insufficient Indulgences. Need %, have %.', v_cost, v_user_indulgences;
            END IF;

            -- Deduct
            UPDATE profiles SET indulgences = indulgences - v_cost, updated_at = now() WHERE id = v_user_id;

            -- Create active_miracles record for tracking
            INSERT INTO active_miracles (user_id, miracle_type, effect_data, expires_at)
            VALUES (v_user_id, 'divine_architect', jsonb_build_object('queue_limit', v_queue_limit), now() + interval '7 days');

            RETURN jsonb_build_object(
                'success', true,
                'action', 'divine_architect',
                'indulgences_spent', v_cost,
                'queue_limit', v_queue_limit
            );

        ELSE
            RAISE EXCEPTION 'Unknown indulgence action: %', p_action_type;
    END CASE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 29. RPC: get_synod_info()
-- ============================================

CREATE OR REPLACE FUNCTION public.get_synod_info()
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_synod_id UUID;
    v_synod JSONB;
    v_members JSONB;
    v_member_count INT;
    v_wars JSONB;
BEGIN
    SELECT synod_id INTO v_synod_id FROM profiles WHERE id = v_user_id;
    IF v_synod_id IS NULL THEN
        RETURN jsonb_build_object('in_synod', false);
    END IF;

    -- Get synod details
    SELECT jsonb_build_object(
        'id', s.id,
        'name', s.name,
        'leader_id', s.leader_id,
        'tax_rate', s.tax_rate,
        'vault_gold', s.vault_gold,
        'vault_mana', s.vault_mana,
        'created_at', s.created_at
    ) INTO v_synod FROM synods s WHERE s.id = v_synod_id;

    -- Get members
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', p.id,
        'username', p.username,
        'faith', p.faith,
        'sect_type', p.sect_type
    )), '[]'::jsonb), COUNT(*)::INT INTO v_members, v_member_count
    FROM profiles p WHERE p.synod_id = v_synod_id;

    -- Get active wars
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', sw.id,
        'attacker_synod_id', sw.attacker_synod_id,
        'defender_synod_id', sw.defender_synod_id,
        'declared_at', sw.declared_at,
        'expires_at', sw.expires_at,
        'is_attacker', sw.attacker_synod_id = v_synod_id
    )), '[]'::jsonb) INTO v_wars
    FROM synod_wars sw
    WHERE (sw.attacker_synod_id = v_synod_id OR sw.defender_synod_id = v_synod_id)
      AND sw.is_active = true;

    RETURN jsonb_build_object(
        'in_synod', true,
        'synod', v_synod,
        'members', v_members,
        'member_count', v_member_count,
        'wars', v_wars
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 30. RPC: get_relics()
-- ============================================

CREATE OR REPLACE FUNCTION public.get_relics()
RETURNS JSONB AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', r.id,
        'name', r.name,
        'description', r.description,
        'emoji_icon', r.emoji_icon,
        'effect_type', r.effect_type,
        'effect_data', r.effect_data,
        'holder_id', r.holder_id,
        'holder_username', p.username,
        'steal_progress', r.steal_progress,
        'last_stolen_at', r.last_stolen_at
    )), '[]'::jsonb) INTO v_result
    FROM relics r
    LEFT JOIN profiles p ON p.id = r.holder_id
    WHERE r.is_active = true;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 31. RPC: get_research_tree()
-- ============================================

CREATE OR REPLACE FUNCTION public.get_research_tree()
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_nodes JSONB;
    v_unlocks JSONB;
BEGIN
    -- Get all research nodes
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', rn.id,
        'name', rn.name,
        'description', rn.description,
        'emoji_icon', rn.emoji_icon,
        'alignment', rn.alignment,
        'cost', rn.cost,
        'effect_type', rn.effect_type,
        'effect_data', rn.effect_data,
        'requires_node', rn.requires_node,
        'sort_order', rn.sort_order
    )), '[]'::jsonb) INTO v_nodes
    FROM research_nodes rn WHERE rn.is_active = true;

    -- Get user's unlocked research
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'node_id', pr.node_id,
        'unlocked_at', pr.unlocked_at,
        'expires_at', pr.expires_at
    )), '[]'::jsonb) INTO v_unlocks
    FROM player_research pr
    WHERE pr.user_id = v_user_id
      AND (pr.expires_at IS NULL OR pr.expires_at > now());

    RETURN jsonb_build_object(
        'nodes', v_nodes,
        'unlocks', v_unlocks
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 32. RPC: get_sect_info()
-- ============================================

CREATE OR REPLACE FUNCTION public.get_sect_info()
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_sect_type TEXT;
    v_modifiers JSONB;
BEGIN
    SELECT sect_type INTO v_sect_type FROM profiles WHERE id = v_user_id;

    IF v_sect_type IS NULL THEN
        RETURN jsonb_build_object('sect_type', NULL, 'modifiers', '[]'::jsonb);
    END IF;

    -- Get all modifiers for this sect
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'key', gc.key,
        'value', gc.value,
        'description', gc.description
    )), '[]'::jsonb) INTO v_modifiers
    FROM game_config gc
    WHERE gc.key LIKE 'sect.' || v_sect_type || '.%';

    RETURN jsonb_build_object(
        'sect_type', v_sect_type,
        'modifiers', v_modifiers
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 33. MODIFY: launch_crusade() — Acre Theft + LIFO Ruin + Sect/Relic/War Bonuses
-- ============================================

CREATE OR REPLACE FUNCTION public.launch_crusade(p_target_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_attacker_id UUID := auth.uid();
    v_attacker_mana INT;
    v_attacker_clerics INT;
    v_target_churches INT;
    v_target_cathedrals INT;
    v_target_shield TIMESTAMPTZ;
    v_target_papal_bull TIMESTAMPTZ;
    v_target_suzerain UUID;
    v_mana_cost NUMERIC;
    v_attack_rating NUMERIC;
    v_defense_rating NUMERIC;
    v_attack_roll NUMERIC;
    v_defense_roll NUMERIC;
    v_cathedral_rating NUMERIC;
    v_success BOOLEAN;
    v_result JSONB;
    v_in_chain BOOLEAN;
    v_attacker_sect TEXT;
    v_target_sect TEXT;
    v_attacker_synod UUID;
    v_target_synod UUID;
    v_holy_war_bonus NUMERIC;
    v_acres_stolen INT;
    v_target_acres INT;
    v_target_used_acres INT;
    v_sect_defense_bonus NUMERIC;
    v_sect_gold_multiplier NUMERIC;
    v_acre_cost NUMERIC;
    v_ruined_buildings INT;
    v_relic_attack_bonus NUMERIC;
    v_relic_defense_bonus NUMERIC;
BEGIN
    -- Validate: cannot crusade yourself
    IF p_target_id = v_attacker_id THEN
        RAISE EXCEPTION 'Cannot crusade yourself';
    END IF;

    -- Load mana cost from config
    SELECT value INTO v_mana_cost FROM game_config WHERE key = 'crusade.mana_cost';
    IF v_mana_cost IS NULL THEN v_mana_cost := 50; END IF;

    -- Check attacker has enough mana
    SELECT mana, sect_type, synod_id INTO v_attacker_mana, v_attacker_sect, v_attacker_synod
    FROM profiles WHERE id = v_attacker_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Attacker profile not found'; END IF;
    IF v_attacker_mana < v_mana_cost THEN
        RAISE EXCEPTION 'Insufficient Mana. Need %, have %.', v_mana_cost, v_attacker_mana;
    END IF;

    -- Check target exists and get info
    SELECT suzerain_id, divine_shield_until, papal_bull_until, sect_type, synod_id, sacred_acres
    INTO v_target_suzerain, v_target_shield, v_target_papal_bull, v_target_sect, v_target_synod, v_target_acres
    FROM profiles WHERE id = p_target_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Target not found'; END IF;

    -- Check target is not shielded (Divine Shield from Schism)
    IF v_target_shield IS NOT NULL AND v_target_shield > now() THEN
        RAISE EXCEPTION 'Target is protected by Divine Shield until %.', v_target_shield;
    END IF;

    -- Check target is not protected by Papal Bull
    IF v_target_papal_bull IS NOT NULL AND v_target_papal_bull > now() THEN
        RAISE EXCEPTION 'Target is protected by Papal Bull until %.', v_target_papal_bull;
    END IF;

    -- Check target is not already your vassal
    IF v_target_suzerain = v_attacker_id THEN
        RAISE EXCEPTION 'Target is already your vassal';
    END IF;

    -- Circular vassalage check
    WITH RECURSIVE chain AS (
        SELECT id, suzerain_id FROM profiles WHERE id = v_attacker_id
        UNION ALL
        SELECT p.id, p.suzerain_id FROM profiles p
        JOIN chain c ON p.id = c.suzerain_id
    )
    SELECT EXISTS(SELECT 1 FROM chain WHERE id = p_target_id) INTO v_in_chain;
    IF v_in_chain THEN
        RAISE EXCEPTION 'Cannot vassalize someone in your chain of command';
    END IF;

    -- Deduct mana cost regardless of outcome
    UPDATE profiles SET mana = mana - v_mana_cost, updated_at = now() WHERE id = v_attacker_id;

    -- Calculate attack power
    SELECT COALESCE(value, 10) INTO v_attack_rating FROM game_config WHERE key = 'crusade.attack_rating_per_cleric';
    SELECT COUNT(*)::INT INTO v_attacker_clerics
    FROM player_buildings WHERE user_id = v_attacker_id AND building_type = 'cleric' AND is_active = true;
    v_attack_rating := GREATEST(1, v_attacker_mana) + (v_attacker_clerics * v_attack_rating);

    -- Calculate defense power
    SELECT COALESCE(value, 15) INTO v_defense_rating FROM game_config WHERE key = 'crusade.defense_rating_per_church';
    SELECT COUNT(*)::INT INTO v_target_churches
    FROM player_buildings WHERE user_id = p_target_id AND building_type = 'church' AND is_active = true;
    SELECT COUNT(*)::INT INTO v_target_cathedrals
    FROM player_buildings WHERE user_id = p_target_id AND building_type = 'cathedral' AND is_active = true;
    SELECT COALESCE(value, 40) INTO v_cathedral_rating FROM game_config WHERE key = 'crusade.defense_rating_per_cathedral';
    v_defense_rating := (v_target_churches * v_defense_rating) + (v_target_cathedrals * v_cathedral_rating);
    v_defense_rating := GREATEST(1, v_defense_rating);

    -- Apply Holy War bonus if applicable
    v_holy_war_bonus := 0;
    IF v_attacker_synod IS NOT NULL AND v_target_synod IS NOT NULL AND v_attacker_synod != v_target_synod THEN
        SELECT COALESCE(value, 0.20) INTO v_holy_war_bonus FROM game_config WHERE key = 'synod.holy_war_attack_bonus';
        -- Check if there's an active war
        IF NOT EXISTS (
            SELECT 1 FROM synod_wars
            WHERE attacker_synod_id = v_attacker_synod AND defender_synod_id = v_target_synod AND is_active = true
        ) AND NOT EXISTS (
            SELECT 1 FROM synod_wars
            WHERE attacker_synod_id = v_target_synod AND defender_synod_id = v_attacker_synod AND is_active = true
        ) THEN
            v_holy_war_bonus := 0;
        END IF;
    END IF;

    -- Apply Doomsday Preppers defense bonus
    IF v_target_sect = 'doomsday_preppers' THEN
        SELECT COALESCE(value, 0.5) INTO v_sect_defense_bonus FROM game_config WHERE key = 'sect.doomsday_preppers.crusade_defense_bonus';
        v_defense_rating := v_defense_rating * (1 + v_sect_defense_bonus);
    END IF;

    -- Apply research bonuses
    -- Holy War research: +15% attack
    IF EXISTS (
        SELECT 1 FROM player_research pr
        JOIN research_nodes rn ON rn.id = pr.node_id
        WHERE pr.user_id = v_attacker_id AND rn.effect_type = 'crusade_attack_bonus'
          AND (pr.expires_at IS NULL OR pr.expires_at > now())
    ) THEN
        v_attack_rating := v_attack_rating * 1.15;
    END IF;

    -- Apply relic bonuses
    -- Check if attacker holds Iron Rosary (+50% defense) or other attack relics
    v_relic_attack_bonus := 0;
    IF EXISTS (
        SELECT 1 FROM relics r WHERE r.holder_id = v_attacker_id AND r.effect_type = 'mana_double' AND r.is_active = true
    ) THEN
        v_relic_attack_bonus := v_relic_attack_bonus + 0;  -- Mana double doesn't affect combat directly
    END IF;

    v_relic_defense_bonus := 0;
    IF EXISTS (
        SELECT 1 FROM relics r WHERE r.holder_id = p_target_id AND r.effect_type = 'crusade_defense_bonus' AND r.is_active = true
    ) THEN
        v_relic_defense_bonus := v_relic_defense_bonus + 0.50;
    END IF;
    v_defense_rating := v_defense_rating * (1 + v_relic_defense_bonus);

    -- Apply Holy War bonus to attack
    v_attack_rating := v_attack_rating * (1 + v_holy_war_bonus);

    -- Roll the dice
    v_attack_roll := v_attack_rating * (0.7 + random() * 0.6);
    v_defense_roll := v_defense_rating * (0.7 + random() * 0.6);

    v_success := v_attack_roll > v_defense_roll;

    IF v_success THEN
        -- Set target's suzerain to attacker
        UPDATE profiles SET suzerain_id = v_attacker_id, updated_at = now() WHERE id = p_target_id;

        -- Steal sacred acres
        SELECT COALESCE(value, 3)::INT INTO v_acres_stolen FROM game_config WHERE key = 'crusade.acres_stolen';
        IF v_acres_stolen IS NULL THEN v_acres_stolen := 3; END IF;

        -- Can't steal more acres than target has
        IF v_acres_stolen > v_target_acres THEN
            v_acres_stolen := v_target_acres;
        END IF;

        -- Transfer acres
        UPDATE profiles SET sacred_acres = sacred_acres + v_acres_stolen, updated_at = now() WHERE id = v_attacker_id;
        UPDATE profiles SET sacred_acres = GREATEST(0, sacred_acres - v_acres_stolen), updated_at = now() WHERE id = p_target_id;

        -- LIFO Ruin Check: Deactivate buildings if defender's used acres exceed remaining acres
        -- First, calculate total acres used by active buildings
        WITH active_buildings AS (
            SELECT pb.id, pb.building_type, pb.purchased_at,
                COALESCE((SELECT value FROM game_config WHERE key = 'building.' || pb.building_type || '.acre_cost'), 0)::NUMERIC AS acre_cost
            FROM player_buildings pb
            WHERE pb.user_id = p_target_id AND pb.is_active = true
        ),
        running_total AS (
            SELECT id, building_type, acre_cost,
                SUM(acre_cost) OVER (ORDER BY purchased_at ASC) AS cumulative_acres
            FROM active_buildings
        )
        UPDATE player_buildings SET is_active = false
        WHERE id IN (
            SELECT rt.id FROM running_total rt
            WHERE rt.cumulative_acres > (v_target_acres - v_acres_stolen)
        );
    END IF;

    -- Log to akashic_logs
    INSERT INTO akashic_logs (target_id, actor_id, action_type, result_data)
    VALUES (p_target_id, v_attacker_id, 'crusade', jsonb_build_object(
        'success', v_success,
        'attack_power', v_attack_rating,
        'defense_power', v_defense_rating,
        'attack_roll', v_attack_roll,
        'defense_roll', v_defense_roll,
        'mana_cost', v_mana_cost,
        'acres_stolen', CASE WHEN v_success THEN v_acres_stolen ELSE 0 END,
        'holy_war_bonus', v_holy_war_bonus
    ));

    RETURN jsonb_build_object(
        'success', v_success,
        'attack_power', v_attack_rating,
        'defense_power', v_defense_rating,
        'attack_roll', v_attack_roll,
        'defense_roll', v_defense_roll,
        'mana_cost', v_mana_cost,
        'new_suzerain_id', CASE WHEN v_success THEN v_attacker_id ELSE NULL END,
        'acres_stolen', CASE WHEN v_success THEN v_acres_stolen ELSE 0 END
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 34. MODIFY: purchase_shop_item() — Acre Validation + Sect Restrictions
-- ============================================

CREATE OR REPLACE FUNCTION public.purchase_shop_item(p_item_id TEXT)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_item RECORD;
    v_user_karma INT;
    v_user_gold INT;
    v_user_heresy INT;
    v_user_acres INT;
    v_user_used_acres INT;
    v_user_sect TEXT;
    v_actual_karma_cost INT;
    v_actual_gold_cost INT;
    v_actual_heresy_cost INT;
    v_owned_count INT;
    v_effect_building_type TEXT;
    v_building_count INT;
    v_scaling_multiplier NUMERIC;
    v_acre_reduction NUMERIC;
    v_effective_acre_cost INT;
BEGIN
    -- Look up the shop item
    SELECT * INTO v_item FROM shop_items WHERE id = p_item_id AND is_active = true;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Shop item not found or inactive';
    END IF;

    -- Get user info
    SELECT karma, gold, heresy, sacred_acres, sect_type
    INTO v_user_karma, v_user_gold, v_user_heresy, v_user_acres, v_user_sect
    FROM profiles WHERE id = v_user_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found'; END IF;

    -- Check sect exclusion
    IF v_item.sect_exclusion IS NOT NULL AND v_item.sect_exclusion = v_user_sect THEN
        RAISE EXCEPTION 'Your sect (%) cannot purchase this item.', v_user_sect;
    END IF;

    -- Check sect restriction
    IF v_item.sect_restriction IS NOT NULL AND v_item.sect_restriction != v_user_sect THEN
        RAISE EXCEPTION 'Only members of the % sect can purchase this item.', v_item.sect_restriction;
    END IF;

    -- Calculate actual costs (with scaling for buildings)
    IF v_item.cost_scaling AND v_item.effect_type = 'add_building' THEN
        v_effect_building_type := v_item.effect_data->>'building_type';

        SELECT COUNT(*)::INT INTO v_owned_count
        FROM player_buildings
        WHERE user_id = v_user_id AND building_type = v_effect_building_type AND is_active = true;

        SELECT value INTO v_scaling_multiplier FROM game_config WHERE key = 'shop.cost_scaling_multiplier';
        IF v_scaling_multiplier IS NULL THEN v_scaling_multiplier := 1.15; END IF;

        v_actual_karma_cost := FLOOR(v_item.karma_cost * POWER(v_scaling_multiplier, v_owned_count))::INT;
        v_actual_gold_cost := FLOOR(v_item.gold_cost * POWER(v_scaling_multiplier, v_owned_count))::INT;
        v_actual_heresy_cost := FLOOR(v_item.heresy_cost * POWER(v_scaling_multiplier, v_owned_count))::INT;
    ELSE
        v_actual_karma_cost := v_item.karma_cost;
        v_actual_gold_cost := v_item.gold_cost;
        v_actual_heresy_cost := v_item.heresy_cost;
    END IF;

    -- Check all currency balances
    IF v_user_karma < v_actual_karma_cost THEN
        RAISE EXCEPTION 'Insufficient karma. You have % but need %.', v_user_karma, v_actual_karma_cost;
    END IF;
    IF v_user_gold < v_actual_gold_cost THEN
        RAISE EXCEPTION 'Insufficient gold. You have % but need %.', v_user_gold, v_actual_gold_cost;
    END IF;
    IF v_user_heresy < v_actual_heresy_cost THEN
        RAISE EXCEPTION 'Insufficient heresy. You have % but need %.', v_user_heresy, v_actual_heresy_cost;
    END IF;

    -- Check building prerequisite
    IF v_item.requires_building IS NOT NULL THEN
        SELECT COUNT(*)::INT INTO v_building_count
        FROM player_buildings
        WHERE user_id = v_user_id AND building_type = v_item.requires_building AND is_active = true;
        IF v_building_count = 0 THEN
            RAISE EXCEPTION 'You must own a % before purchasing this item.', v_item.requires_building;
        END IF;
    END IF;

    -- Check sacred acres availability for buildings
    IF v_item.effect_type = 'add_building' AND v_item.acre_cost > 0 THEN
        v_effect_building_type := v_item.effect_data->>'building_type';

        -- Calculate effective acre cost (with Divine Architecture research reduction)
        v_effective_acre_cost := v_item.acre_cost;
        IF EXISTS (
            SELECT 1 FROM player_research pr
            JOIN research_nodes rn ON rn.id = pr.node_id
            WHERE pr.user_id = v_user_id AND rn.effect_type = 'acre_cost_reduction'
              AND (pr.expires_at IS NULL OR pr.expires_at > now())
        ) THEN
            SELECT COALESCE(value, 20) INTO v_acre_reduction FROM game_config WHERE key = 'sect.prosperity_gospel.cathedral_upkeep_multiplier';
            -- Use the research effect data directly
            v_effective_acre_cost := GREATEST(1, FLOOR(v_item.acre_cost * (1 - 0.20)));
        END IF;

        -- Calculate currently used acres
        SELECT COALESCE(SUM(COALESCE((SELECT value FROM game_config WHERE key = 'building.' || pb.building_type || '.acre_cost'), 0)), 0)::INT
        INTO v_user_used_acres
        FROM player_buildings pb
        WHERE pb.user_id = v_user_id AND pb.is_active = true;

        IF (v_user_used_acres + v_effective_acre_cost) > v_user_acres THEN
            RAISE EXCEPTION 'Insufficient Sacred Acres. You have % total, % used, and need % more. Free: %.',
                v_user_acres, v_user_used_acres, v_effective_acre_cost, v_user_acres - v_user_used_acres;
        END IF;
    END IF;

    -- Deduct all currencies
    UPDATE profiles SET
        karma = karma - v_actual_karma_cost,
        gold = GREATEST(0, gold - v_actual_gold_cost),
        heresy = heresy - v_actual_heresy_cost,
        updated_at = now()
    WHERE id = v_user_id;

    -- Apply effect based on type
    CASE v_item.effect_type
        WHEN 'add_building' THEN
            v_effect_building_type := v_item.effect_data->>'building_type';
            INSERT INTO player_buildings (user_id, building_type, is_active, purchased_with)
            VALUES (v_user_id, v_effect_building_type, true, v_item.id);

        WHEN 'add_prayer_slot' THEN
            UPDATE profiles
            SET max_prayer_slots = max_prayer_slots + COALESCE((v_item.effect_data->>'slots_to_add')::INT, 1),
                daily_token_limit = daily_token_limit + COALESCE((v_item.effect_data->>'daily_devotion_bonus')::INT, 100),
                updated_at = now()
            WHERE id = v_user_id;

        ELSE
            RAISE EXCEPTION 'Unknown effect type: %', v_item.effect_type;
    END CASE;

    -- Return updated profile data
    RETURN jsonb_build_object(
        'success', true,
        'item_id', p_item_id,
        'karma_spent', v_actual_karma_cost,
        'gold_spent', v_actual_gold_cost,
        'heresy_spent', v_actual_heresy_cost,
        'new_karma', (SELECT karma FROM profiles WHERE id = v_user_id),
        'new_mana', (SELECT mana FROM profiles WHERE id = v_user_id),
        'new_gold', (SELECT gold FROM profiles WHERE id = v_user_id),
        'new_food', (SELECT food FROM profiles WHERE id = v_user_id),
        'new_heresy', (SELECT heresy FROM profiles WHERE id = v_user_id),
        'new_max_slots', (SELECT max_prayer_slots FROM profiles WHERE id = v_user_id),
        'new_sacred_acres', (SELECT sacred_acres FROM profiles WHERE id = v_user_id)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 35. MODIFY: get_player_economy() — Include all new data
-- ============================================

CREATE OR REPLACE FUNCTION public.get_player_economy()
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_profile RECORD;
    v_buildings JSONB;
    v_production JSONB;
    v_suzerain JSONB;
    v_vassals JSONB;
    v_vassal_count INT;
    v_tithe_pct NUMERIC;
    v_daily_tithes JSONB;
    v_heresy_base NUMERIC;
    v_coven_bonus NUMERIC;
    v_coven_count INT;
    v_research_unlocks JSONB;
    v_held_relics JSONB;
    v_synod_info JSONB;
    v_used_acres INT;
    v_dogma_per_day NUMERIC;
    v_dogma_cap NUMERIC;
    v_dogma_multiplier NUMERIC;
    v_papal_bull_active BOOLEAN;
BEGIN
    -- Get profile resources including all new columns
    SELECT karma, mana, gold, food, heresy, dogma, max_prayer_slots, daily_token_limit,
           suzerain_id, schism_count, divine_shield_until, papal_bull_until,
           sect_type, sacred_acres, indulgences, synod_id, title, avatar_url
    INTO v_profile
    FROM profiles WHERE id = v_user_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found'; END IF;

    -- Get player buildings
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', id,
        'building_type', building_type,
        'is_active', is_active,
        'purchased_with', purchased_with,
        'purchased_at', purchased_at
    )), '[]'::jsonb) INTO v_buildings
    FROM player_buildings WHERE user_id = v_user_id;

    -- Calculate daily production rates including dogma
    WITH user_buildings AS (
        SELECT building_type, COUNT(*)::INT AS count
        FROM player_buildings WHERE user_id = v_user_id AND is_active = true
        GROUP BY building_type
    )
    SELECT COALESCE(jsonb_build_object(
        'mana_per_day', COALESCE(SUM(
            (SELECT COALESCE(value, 0) FROM game_config WHERE key = 'building.' || ub.building_type || '.mana_per_day') * ub.count
        ), 0),
        'gold_per_day', COALESCE(SUM(
            (SELECT COALESCE(value, 0) FROM game_config WHERE key = 'building.' || ub.building_type || '.gold_per_day') * ub.count
        ), 0),
        'food_per_day', COALESCE(SUM(
            (SELECT COALESCE(value, 0) FROM game_config WHERE key = 'building.' || ub.building_type || '.food_per_day') * ub.count
        ), 0),
        'gold_upkeep_per_day', COALESCE(SUM(
            (SELECT COALESCE(value, 0) FROM game_config WHERE key = 'building.' || ub.building_type || '.gold_upkeep_per_day') * ub.count
        ), 0) + COALESCE(SUM(
            CASE WHEN ub.building_type = 'coven' THEN
                (SELECT COALESCE(value, 3) FROM game_config WHERE key = 'building.coven.gold_upkeep_per_day') * ub.count
            ELSE 0 END
        ), 0),
        'food_consumption_per_day', COALESCE(SUM(
            (SELECT COALESCE(value, 0) FROM game_config WHERE key = 'building.' || ub.building_type || '.food_consumption_per_day') * ub.count
        ), 0),
        'heresy_per_day', COALESCE(SUM(
            (SELECT COALESCE(value, 0) FROM game_config WHERE key = 'building.' || ub.building_type || '.heresy_per_day') * ub.count
        ), 0),
        'dogma_per_day', COALESCE(SUM(
            (SELECT COALESCE(value, 0) FROM game_config WHERE key = 'building.' || ub.building_type || '.dogma_per_day') * ub.count
        ), 0)
    ), '{}'::jsonb) INTO v_production
    FROM user_buildings ub;

    -- Calculate heresy cap
    SELECT value INTO v_heresy_base FROM game_config WHERE key = 'cap.heresy_base';
    IF v_heresy_base IS NULL THEN v_heresy_base := 100; END IF;
    SELECT COALESCE(value, 50) INTO v_coven_bonus FROM game_config WHERE key = 'building.coven.heresy_cap_bonus';
    SELECT COUNT(*)::INT INTO v_coven_count
    FROM player_buildings WHERE user_id = v_user_id AND building_type = 'coven' AND is_active = true;

    -- Calculate dogma cap
    SELECT COALESCE(value, 10) INTO v_dogma_multiplier FROM game_config WHERE key = 'cap.dogma_multiplier';

    -- Build production with caps
    v_production := v_production || jsonb_build_object(
        'heresy_cap', (v_heresy_base + v_coven_count * v_coven_bonus)::INT,
        'dogma_cap', FLOOR(COALESCE((v_production->>'dogma_per_day')::NUMERIC, 0) * v_dogma_multiplier)::INT
    );

    -- Get suzerain info
    IF v_profile.suzerain_id IS NOT NULL THEN
        SELECT jsonb_build_object('id', s.id, 'username', s.username, 'faith', s.faith)
        INTO v_suzerain FROM profiles s WHERE s.id = v_profile.suzerain_id;
    ELSE
        v_suzerain := 'null'::jsonb;
    END IF;

    -- Get vassals
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', v.id, 'username', v.username, 'faith', v.faith
    )), '[]'::jsonb), COUNT(*)::INT INTO v_vassals, v_vassal_count
    FROM profiles v WHERE v.suzerain_id = v_user_id;

    -- Calculate daily tithes
    SELECT value INTO v_tithe_pct FROM game_config WHERE key = 'tithe.percentage';
    IF v_tithe_pct IS NULL THEN v_tithe_pct := 0.10; END IF;

    WITH vassal_production AS (
        SELECT vp.user_id,
            COALESCE(SUM(CASE WHEN gc_mana.value IS NOT NULL THEN gc_mana.value ELSE 0 END), 0)::NUMERIC AS vassal_mana_per_day,
            COALESCE(SUM(CASE WHEN gc_gold.value IS NOT NULL THEN gc_gold.value ELSE 0 END), 0)::NUMERIC AS vassal_gold_per_day,
            COALESCE(SUM(Case WHEN gc_food.value IS NOT NULL THEN gc_food.value ELSE 0 END), 0)::NUMERIC AS vassal_food_per_day
        FROM profiles p
        JOIN player_buildings vp ON vp.user_id = p.id AND vp.is_active = true
        LEFT JOIN game_config gc_mana ON gc_mana.key = 'building.' || vp.building_type || '.mana_per_day'
        LEFT JOIN game_config gc_gold ON gc_gold.key = 'building.' || vp.building_type || '.gold_per_day'
        LEFT JOIN game_config gc_food ON gc_food.key = 'building.' || vp.building_type || '.food_per_day'
        WHERE p.suzerain_id = v_user_id
        GROUP BY vp.user_id
    )
    SELECT COALESCE(jsonb_build_object(
        'mana_per_day', FLOOR(SUM(vassal_mana_per_day * v_tithe_pct)),
        'gold_per_day', FLOOR(SUM(vassal_gold_per_day * v_tithe_pct)),
        'food_per_day', FLOOR(SUM(vassal_food_per_day * v_tithe_pct))
    ), '{"mana_per_day": 0, "gold_per_day": 0, "food_per_day": 0}'::jsonb) INTO v_daily_tithes
    FROM vassal_production;

    -- Get research unlocks
    SELECT COALESCE(jsonb_agg(pr.node_id), '[]'::jsonb) INTO v_research_unlocks
    FROM player_research pr
    WHERE pr.user_id = v_user_id AND (pr.expires_at IS NULL OR pr.expires_at > now());

    -- Get held relics
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', r.id, 'name', r.name, 'emoji_icon', r.emoji_icon, 'effect_type', r.effect_type
    )), '[]'::jsonb) INTO v_held_relics
    FROM relics r WHERE r.holder_id = v_user_id AND r.is_active = true;

    -- Get synod info
    IF v_profile.synod_id IS NOT NULL THEN
        SELECT jsonb_build_object('id', s.id, 'name', s.name, 'leader_id', s.leader_id, 'tax_rate', s.tax_rate)
        INTO v_synod_info FROM synods s WHERE s.id = v_profile.synod_id;
    ELSE
        v_synod_info := 'null'::jsonb;
    END IF;

    -- Calculate used acres
    SELECT COALESCE(SUM(COALESCE((SELECT value FROM game_config WHERE key = 'building.' || pb.building_type || '.acre_cost'), 0)), 0)::INT
    INTO v_used_acres
    FROM player_buildings pb
    WHERE pb.user_id = v_user_id AND pb.is_active = true;

    -- Check papal bull
    v_papal_bull_active := v_profile.papal_bull_until IS NOT NULL AND v_profile.papal_bull_until > now();

    RETURN jsonb_build_object(
        'karma', v_profile.karma,
        'mana', v_profile.mana,
        'gold', v_profile.gold,
        'food', v_profile.food,
        'heresy', v_profile.heresy,
        'dogma', v_profile.dogma,
        'indulgences', v_profile.indulgences,
        'sacred_acres', v_profile.sacred_acres,
        'sacred_acres_used', v_used_acres,
        'sacred_acres_free', v_profile.sacred_acres - v_used_acres,
        'max_prayer_slots', v_profile.max_prayer_slots,
        'daily_devotion_limit', v_profile.daily_token_limit,
        'suzerain_id', v_profile.suzerain_id,
        'schism_count', v_profile.schism_count,
        'divine_shield_until', v_profile.divine_shield_until,
        'papal_bull_until', v_profile.papal_bull_until,
        'papal_bull_active', v_papal_bull_active,
        'sect_type', v_profile.sect_type,
        'synod_id', v_profile.synod_id,
        'title', v_profile.title,
        'avatar_url', v_profile.avatar_url,
        'suzerain', v_suzerain,
        'vassals', COALESCE(v_vassals, '[]'::jsonb),
        'vassal_count', v_vassal_count,
        'daily_tithes', v_daily_tithes,
        'buildings', v_buildings,
        'daily_rates', v_production,
        'research_unlocks', v_research_unlocks,
        'held_relics', v_held_relics,
        'synod', v_synod_info
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 36. MODIFY: calculate_automated_karma() — Full 8-phase rewrite
-- ============================================

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
    v_milestone_threshold NUMERIC;
    v_milestone_payout NUMERIC;
    v_altruistic_multiplier NUMERIC;
    v_mana_cap_multiplier NUMERIC;
    v_gold_cap_multiplier NUMERIC;
    v_food_cap_multiplier NUMERIC;
    v_dogma_cap_multiplier NUMERIC;
    v_heresy_base_cap NUMERIC;
    v_tithe_pct NUMERIC;
    v_synod_tax_rate NUMERIC;
BEGIN
    -- Load karma milestone settings
    SELECT value INTO v_milestone_threshold FROM game_config WHERE key = 'karma.milestone_threshold';
    SELECT value INTO v_milestone_payout FROM game_config WHERE key = 'karma.milestone_payout';
    SELECT value INTO v_altruistic_multiplier FROM game_config WHERE key = 'karma.altruistic_multiplier';
    IF v_milestone_threshold IS NULL THEN v_milestone_threshold := 50; END IF;
    IF v_milestone_payout IS NULL THEN v_milestone_payout := 5; END IF;
    IF v_altruistic_multiplier IS NULL THEN v_altruistic_multiplier := 2; END IF;

    -- Load cap multipliers
    SELECT value INTO v_mana_cap_multiplier FROM game_config WHERE key = 'cap.mana_multiplier';
    SELECT value INTO v_gold_cap_multiplier FROM game_config WHERE key = 'cap.gold_multiplier';
    SELECT value INTO v_food_cap_multiplier FROM game_config WHERE key = 'cap.food_multiplier';
    SELECT value INTO v_dogma_cap_multiplier FROM game_config WHERE key = 'cap.dogma_multiplier';
    IF v_mana_cap_multiplier IS NULL THEN v_mana_cap_multiplier := 10; END IF;
    IF v_gold_cap_multiplier IS NULL THEN v_gold_cap_multiplier := 10; END IF;
    IF v_food_cap_multiplier IS NULL THEN v_food_cap_multiplier := 10; END IF;
    IF v_dogma_cap_multiplier IS NULL THEN v_dogma_cap_multiplier := 10; END IF;

    -- Load heresy base cap
    SELECT value INTO v_heresy_base_cap FROM game_config WHERE key = 'cap.heresy_base';
    IF v_heresy_base_cap IS NULL THEN v_heresy_base_cap := 100; END IF;

    -- Load tithe percentage
    SELECT value INTO v_tithe_pct FROM game_config WHERE key = 'tithe.percentage';
    IF v_tithe_pct IS NULL THEN v_tithe_pct := 0.10; END IF;

    -- ========================================
    -- PHASE 1: KARMA MILESTONE LOGIC (unchanged)
    -- ========================================
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

            v_milestones_total := floor((r.prayer_count + v_new_cycles) / v_milestone_threshold);
            IF v_milestones_total > r.karma_awarded THEN
                v_karma_to_award := (v_milestones_total - r.karma_awarded) * v_milestone_payout * (
                    CASE WHEN r.prayer_type = 'altruistic' THEN v_altruistic_multiplier ELSE 1 END
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

    -- ========================================
    -- PHASE 2: RESOURCE GENERATION + SECT MODIFIERS + RELIC BONUSES
    -- ========================================
    WITH user_production AS (
        SELECT
            pb.user_id,
            COALESCE(SUM(CASE WHEN gc_mana.value IS NOT NULL THEN gc_mana.value ELSE 0 END), 0)::NUMERIC AS gross_mana_per_day,
            COALESCE(SUM(CASE WHEN gc_gold.value IS NOT NULL THEN gc_gold.value ELSE 0 END), 0)::NUMERIC AS gross_gold_per_day,
            COALESCE(SUM(Case WHEN gc_food.value IS NOT NULL THEN gc_food.value ELSE 0 END), 0)::NUMERIC AS gross_food_per_day,
            COALESCE(SUM(CASE WHEN gc_gold_upkeep.value IS NOT NULL THEN gc_gold_upkeep.value ELSE 0 END), 0)::NUMERIC AS total_gold_upkeep_per_day,
            COALESCE(SUM(CASE WHEN gc_food_consume.value IS NOT NULL THEN gc_food_consume.value ELSE 0 END), 0)::NUMERIC AS total_food_consumption_per_day,
            COALESCE(SUM(CASE WHEN gc_heresy.value IS NOT NULL THEN gc_heresy.value ELSE 0 END), 0)::NUMERIC AS gross_heresy_per_day,
            COALESCE(SUM(CASE WHEN gc_heresy_consume.value IS NOT NULL THEN gc_heresy_consume.value ELSE 0 END), 0)::NUMERIC AS total_heresy_food_consume_per_day,
            COALESCE(SUM(CASE WHEN gc_coven_upkeep.value IS NOT NULL THEN gc_coven_upkeep.value ELSE 0 END), 0)::NUMERIC AS total_coven_gold_upkeep_per_day,
            COALESCE(SUM(CASE WHEN gc_dogma.value IS NOT NULL THEN gc_dogma.value ELSE 0 END), 0)::NUMERIC AS gross_dogma_per_day,
            COALESCE(SUM(CASE WHEN pb.building_type = 'coven' THEN 1 ELSE 0 END), 0)::INT AS coven_count,
            COALESCE(SUM(CASE WHEN pb.building_type = 'scriptorium' THEN 1 ELSE 0 END), 0)::INT AS scriptorium_count
        FROM player_buildings pb
        LEFT JOIN game_config gc_mana ON gc_mana.key = 'building.' || pb.building_type || '.mana_per_day'
        LEFT JOIN game_config gc_gold ON gc_gold.key = 'building.' || pb.building_type || '.gold_per_day'
        LEFT JOIN game_config gc_food ON gc_food.key = 'building.' || pb.building_type || '.food_per_day'
        LEFT JOIN game_config gc_gold_upkeep ON gc_gold_upkeep.key = 'building.' || pb.building_type || '.gold_upkeep_per_day'
        LEFT JOIN game_config gc_food_consume ON gc_food_consume.key = 'building.' || pb.building_type || '.food_consumption_per_day'
        LEFT JOIN game_config gc_heresy ON gc_heresy.key = 'building.' || pb.building_type || '.heresy_per_day'
        LEFT JOIN game_config gc_heresy_consume ON gc_heresy_consume.key = 'building.' || pb.building_type || '.food_consumption_per_day' AND pb.building_type = 'cultist'
        LEFT JOIN game_config gc_coven_upkeep ON gc_coven_upkeep.key = 'building.coven.gold_upkeep_per_day' AND pb.building_type = 'coven'
        LEFT JOIN game_config gc_dogma ON gc_dogma.key = 'building.' || pb.building_type || '.dogma_per_day'
        WHERE pb.is_active = true
        GROUP BY pb.user_id
    ),
    all_players AS (
        SELECT p.id AS user_id,
            p.sect_type,
            p.sacred_acres,
            p.synod_id,
            p.papal_bull_until,
            COALESCE(up.gross_mana_per_day, 0) AS gross_mana_per_day,
            COALESCE(up.gross_gold_per_day, 0) AS gross_gold_per_day,
            COALESCE(up.gross_food_per_day, 0) AS gross_food_per_day,
            COALESCE(up.total_gold_upkeep_per_day, 0) AS total_gold_upkeep_per_day,
            COALESCE(up.total_food_consumption_per_day, 0) AS total_food_consumption_per_day,
            COALESCE(up.gross_heresy_per_day, 0) AS gross_heresy_per_day,
            COALESCE(up.total_heresy_food_consume_per_day, 0) AS total_heresy_food_consume_per_day,
            COALESCE(up.total_coven_gold_upkeep_per_day, 0) AS total_coven_gold_upkeep_per_day,
            COALESCE(up.gross_dogma_per_day, 0) AS gross_dogma_per_day,
            COALESCE(up.coven_count, 0) AS coven_count,
            COALESCE(up.scriptorium_count, 0) AS scriptorium_count,
            p.suzerain_id
        FROM profiles p
        LEFT JOIN user_production up ON p.id = up.user_id
    ),
    -- Apply sect modifiers to production
    sect_modified AS (
        SELECT
            ap.user_id,
            ap.sect_type,
            ap.sacred_acres,
            ap.synod_id,
            ap.papal_bull_until,
            ap.suzerain_id,
            -- Mana with sect multiplier
            CASE
                WHEN ap.sect_type = 'prosperity_gospel' THEN ap.gross_mana_per_day * COALESCE((SELECT value FROM game_config WHERE key = 'sect.prosperity_gospel.mana_multiplier'), 0.8)
                WHEN ap.sect_type = 'ascetic_order' THEN ap.gross_mana_per_day * COALESCE((SELECT value FROM game_config WHERE key = 'sect.ascetic_order.mana_multiplier'), 1.2)
                WHEN ap.sect_type = 'inquisition' THEN ap.gross_mana_per_day * COALESCE((SELECT value FROM game_config WHERE key = 'sect.inquisition.mana_multiplier'), 0.7)
                ELSE ap.gross_mana_per_day
            END AS modified_mana_per_day,
            -- Gold with sect multiplier
            CASE
                WHEN ap.sect_type = 'prosperity_gospel' THEN ap.gross_gold_per_day * COALESCE((SELECT value FROM game_config WHERE key = 'sect.prosperity_gospel.gold_multiplier'), 1.5)
                WHEN ap.sect_type = 'doomsday_preppers' THEN ap.gross_gold_per_day * COALESCE((SELECT value FROM game_config WHERE key = 'sect.doomsday_preppers.gold_multiplier'), 0.75)
                ELSE ap.gross_gold_per_day
            END AS modified_gold_per_day,
            -- Food with sect multiplier
            CASE
                WHEN ap.sect_type = 'doomsday_preppers' THEN ap.gross_food_per_day * COALESCE((SELECT value FROM game_config WHERE key = 'sect.doomsday_preppers.food_multiplier'), 1.5)
                ELSE ap.gross_food_per_day
            END AS modified_food_per_day,
            -- Gold upkeep with sect multiplier
            CASE
                WHEN ap.sect_type = 'prosperity_gospel' THEN (ap.total_gold_upkeep_per_day + ap.total_coven_gold_upkeep_per_day) * COALESCE((SELECT value FROM game_config WHERE key = 'sect.prosperity_gospel.cathedral_upkeep_multiplier'), 2.0)
                ELSE ap.total_gold_upkeep_per_day + ap.total_coven_gold_upkeep_per_day
            END AS modified_gold_upkeep_per_day,
            -- Food consumption with sect multiplier
            CASE
                WHEN ap.sect_type = 'ascetic_order' THEN ap.total_food_consumption_per_day * COALESCE((SELECT value FROM game_config WHERE key = 'sect.ascetic_order.food_consumption_multiplier'), 0.5)
                ELSE ap.total_food_consumption_per_day + ap.total_heresy_food_consume_per_day
            END AS modified_food_consumption_per_day,
            -- Heresy with sect multiplier
            CASE
                WHEN ap.sect_type = 'inquisition' THEN ap.gross_heresy_per_day * COALESCE((SELECT value FROM game_config WHERE key = 'sect.inquisition.heresy_multiplier'), 2.0)
                ELSE ap.gross_heresy_per_day
            END AS modified_heresy_per_day,
            ap.gross_dogma_per_day,
            ap.coven_count,
            ap.scriptorium_count
        FROM all_players ap
    ),
    -- Calculate per-tick values
    tick_production AS (
        SELECT
            sm.user_id,
            sm.sect_type,
            sm.sacred_acres,
            sm.synod_id,
            sm.papal_bull_until,
            sm.suzerain_id,
            CASE WHEN sm.modified_mana_per_day > 0 THEN GREATEST(1, FLOOR(sm.modified_mana_per_day / 1440))
                 ELSE 0 END AS mana_per_tick,
            CASE WHEN sm.modified_gold_per_day > 0 THEN GREATEST(1, FLOOR(sm.modified_gold_per_day / 1440))
                 ELSE 0 END AS gold_per_tick,
            CASE WHEN sm.modified_food_per_day > 0 THEN GREATEST(1, FLOOR(sm.modified_food_per_day / 1440))
                 ELSE 0 END AS food_per_tick,
            CASE WHEN sm.modified_heresy_per_day > 0 THEN GREATEST(1, FLOOR(sm.modified_heresy_per_day / 1440))
                 ELSE 0 END AS heresy_per_tick,
            CASE WHEN sm.gross_dogma_per_day > 0 THEN GREATEST(1, FLOOR(sm.gross_dogma_per_day / 1440))
                 ELSE 0 END AS dogma_per_tick,
            GREATEST(0, FLOOR(sm.modified_gold_upkeep_per_day / 1440)) AS gold_upkeep_tick,
            GREATEST(0, FLOOR(sm.modified_food_consumption_per_day / 1440)) AS food_consume_tick,
            FLOOR(sm.modified_mana_per_day * v_mana_cap_multiplier) AS mana_cap,
            FLOOR(sm.modified_gold_per_day * v_gold_cap_multiplier) AS gold_cap,
            FLOOR(sm.modified_food_per_day * v_food_cap_multiplier) AS food_cap,
            (v_heresy_base_cap + (sm.coven_count * COALESCE((SELECT value FROM game_config WHERE key = 'building.coven.heresy_cap_bonus'), 50)))::INT AS heresy_cap,
            FLOOR(sm.gross_dogma_per_day * v_dogma_cap_multiplier) AS dogma_cap,
            -- Tithe amounts
            CASE WHEN sm.suzerain_id IS NOT NULL THEN FLOOR(sm.modified_mana_per_day / 1440 * v_tithe_pct)
                 ELSE 0 END::INT AS mana_tithe_tick,
            CASE WHEN sm.suzerain_id IS NOT NULL THEN FLOOR(sm.modified_gold_per_day / 1440 * v_tithe_pct)
                 ELSE 0 END::INT AS gold_tithe_tick,
            CASE WHEN sm.suzerain_id IS NOT NULL THEN FLOOR(sm.modified_food_per_day / 1440 * v_tithe_pct)
                 ELSE 0 END::INT AS food_tithe_tick
        FROM sect_modified sm
    ),
    -- Aggregate incoming tithes per suzerain
    tithe_inbound AS (
        SELECT
            tp.suzerain_id,
            COALESCE(SUM(tp.mana_tithe_tick), 0)::INT AS received_mana_tick,
            COALESCE(SUM(tp.gold_tithe_tick), 0)::INT AS received_gold_tick,
            COALESCE(SUM(tp.food_tithe_tick), 0)::INT AS received_food_tick
        FROM tick_production tp
        WHERE tp.suzerain_id IS NOT NULL
        GROUP BY tp.suzerain_id
    ),
    -- Calculate synod tax per member
    synod_tax AS (
        SELECT
            tp.user_id,
            tp.synod_id,
            FLOOR(tp.gold_per_tick * COALESCE(s.tax_rate, 0.05))::INT AS gold_synod_tax_tick,
            FLOOR(tp.mana_per_tick * COALESCE(s.tax_rate, 0.05))::INT AS mana_synod_tax_tick
        FROM tick_production tp
        JOIN synods s ON s.id = tp.synod_id
        WHERE tp.synod_id IS NOT NULL
    )
    -- Single UPDATE joining all CTEs
    UPDATE profiles p SET
        mana = LEAST(
            p.mana + tp.mana_per_tick - tp.mana_tithe_tick + COALESCE(ti.received_mana_tick, 0),
            tp.mana_cap
        ),
        gold = GREATEST(0,
            p.gold + tp.gold_per_tick - tp.gold_upkeep_tick - tp.gold_tithe_tick + COALESCE(ti.received_gold_tick, 0) - COALESCE(st.gold_synod_tax_tick, 0)
        ),
        food = GREATEST(0,
            p.food + tp.food_per_tick - tp.food_consume_tick - tp.food_tithe_tick + COALESCE(ti.received_food_tick, 0)
        ),
        heresy = LEAST(
            p.heresy + tp.heresy_per_tick,
            tp.heresy_cap
        ),
        dogma = LEAST(
            p.dogma + tp.dogma_per_tick,
            tp.dogma_cap
        ),
        updated_at = now()
    FROM tick_production tp
    LEFT JOIN tithe_inbound ti ON ti.suzerain_id = p.id
    LEFT JOIN synod_tax st ON st.user_id = p.id
    WHERE p.id = tp.user_id;

    -- ========================================
    -- PHASE 3: SYNOD VAULT DEPOSITS
    -- ========================================
    -- Deposit collected taxes into synod vaults
    UPDATE synods s SET
        vault_gold = vault_gold + COALESCE((SELECT SUM(st.gold_synod_tax_tick) FROM synod_tax st WHERE st.synod_id = s.id GROUP BY st.synod_id), 0),
        vault_mana = vault_mana + COALESCE((SELECT SUM(st.mana_synod_tax_tick) FROM synod_tax st WHERE st.synod_id = s.id GROUP BY st.synod_id), 0)
    WHERE s.id IN (SELECT DISTINCT synod_id FROM synod_tax WHERE synod_id IS NOT NULL);

    -- ========================================
    -- PHASE 4: EXPIRE TIMED EFFECTS
    -- ========================================
    -- Expire active miracles
    DELETE FROM active_miracles WHERE expires_at < now();

    -- Expire timed research
    DELETE FROM player_research WHERE expires_at IS NOT NULL AND expires_at < now();

    -- Expire Holy Wars
    UPDATE synod_wars SET is_active = false WHERE is_active = true AND expires_at < now();

    -- Clear expired Papal Bulls
    UPDATE profiles SET papal_bull_until = NULL WHERE papal_bull_until IS NOT NULL AND papal_bull_until < now();

    -- Clear expired Divine Shields
    UPDATE profiles SET divine_shield_until = NULL WHERE divine_shield_until IS NOT NULL AND divine_shield_until < now();

    -- ========================================
    -- PHASE 5: PROCESS DIVINE ARCHITECT QUEUE
    -- ========================================
    -- Auto-execute queued builds when resources are met
    FOR r IN
        SELECT bq.*, si.karma_cost, si.gold_cost, si.heresy_cost, si.effect_type, si.effect_data, si.acre_cost, si.cost_scaling
        FROM build_queue bq
        JOIN shop_items si ON si.id = bq.item_id
        WHERE bq.executed_at IS NULL AND bq.auto_execute = true
    LOOP
        -- Check if user has sufficient resources
        -- (simplified: just check karma/gold/heresy, acre check is in purchase_shop_item)
        DECLARE
            v_bq_user_karma INT;
            v_bq_user_gold INT;
            v_bq_user_heresy INT;
        BEGIN
            SELECT karma, gold, heresy INTO v_bq_user_karma, v_bq_user_gold, v_bq_user_heresy
            FROM profiles WHERE id = r.user_id;

            IF v_bq_user_karma >= r.karma_cost AND v_bq_user_gold >= r.gold_cost AND v_bq_user_heresy >= r.heresy_cost THEN
                -- Execute the build via purchase_shop_item
                BEGIN
                    PERFORM purchase_shop_item(r.item_id);
                    UPDATE build_queue SET executed_at = now() WHERE id = r.id;
                EXCEPTION WHEN OTHERS THEN
                    -- Build failed (insufficient acres, etc.), leave in queue
                    NULL;
                END;
            END IF;
        END;
    END LOOP;

    -- Clean up executed queue items older than 7 days
    DELETE FROM build_queue WHERE executed_at IS NOT NULL AND executed_at < now() - interval '7 days';

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 37. GRANT PERMISSIONS
-- ============================================

-- New RPCs
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

-- Re-grant on modified functions
GRANT EXECUTE ON FUNCTION launch_crusade(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION launch_crusade(UUID) TO service_role;

GRANT EXECUTE ON FUNCTION purchase_shop_item(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION purchase_shop_item(TEXT) TO service_role;

GRANT EXECUTE ON FUNCTION get_player_economy() TO authenticated;
GRANT EXECUTE ON FUNCTION get_player_economy() TO service_role;

GRANT EXECUTE ON FUNCTION calculate_automated_karma() TO service_role;

-- New table permissions
GRANT SELECT ON TABLE research_nodes TO authenticated;
GRANT SELECT ON TABLE research_nodes TO anon;
GRANT ALL ON TABLE research_nodes TO service_role;

GRANT SELECT ON TABLE synod_wars TO authenticated;
GRANT ALL ON TABLE synod_wars TO service_role;

GRANT SELECT ON TABLE relics TO authenticated;
GRANT SELECT ON TABLE relics TO anon;
GRANT ALL ON TABLE relics TO service_role;

GRANT SELECT ON TABLE active_miracles TO authenticated;
GRANT SELECT ON TABLE active_miracles TO anon;
GRANT ALL ON TABLE active_miracles TO service_role;

GRANT SELECT ON TABLE player_research TO authenticated;
GRANT ALL ON TABLE player_research TO service_role;

GRANT SELECT ON TABLE synods TO authenticated;
GRANT SELECT ON TABLE synods TO anon;
GRANT ALL ON TABLE synods TO service_role;

GRANT SELECT ON TABLE build_queue TO authenticated;
GRANT ALL ON TABLE build_queue TO service_role;

-- ============================================
-- 38. VERIFY CRON JOB
-- ============================================

DO $$
DECLARE
    v_count INT;
BEGIN
    SELECT COUNT(*) INTO v_count FROM cron.job WHERE jobname = 'prayer-heartbeat';
    IF v_count = 0 THEN
        PERFORM cron.schedule('prayer-heartbeat', '* * * * *', 'SELECT calculate_automated_karma()');
    END IF;
END $$;

-- ============================================
-- END OF RAPTURE UPDATE
-- ============================================