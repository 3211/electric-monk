-- =====================================================
-- ELECTRIC MONK - THEOLOGICAL PBBG PIVOT (THE GREAT SCHISM)
-- Migration Version: 6.0 — Idle-Game Tier System
-- Date: 2026-05-17
--
-- Adds: 4-resource economy (Karma, Mana, Gold, Food)
--       game_config table (centralized balance values)
--       shop_items table (server-authoritative catalog)
--       player_buildings table (building ownership, stacking)
--       Resource generation + upkeep in cron heartbeat
--       Starting assets: Altar, Pot, Novice
--       Cost scaling: base_cost * 1.15^owned (deflationary)
--       5-tier progression per category with prerequisites
--
-- PASTE THIS ENTIRE SCRIPT INTO SUPABASE SQL EDITOR
-- Run it as a single transaction
-- =====================================================

-- ============================================
-- 1. CREATE game_config TABLE
-- ============================================
-- Central configuration for ALL tweakable game balance values.
-- Change a row here to rebalance the game. No code changes needed.

CREATE TABLE IF NOT EXISTS game_config (
  key TEXT PRIMARY KEY,
  value NUMERIC NOT NULL,
  description TEXT,
  category TEXT DEFAULT 'production',
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- RLS: anyone authenticated can read, only service_role can write
ALTER TABLE game_config ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Game config is publicly readable" ON game_config;
CREATE POLICY "Game config is publicly readable" ON game_config
  FOR SELECT USING (true);

-- ============================================
-- 2. SEED game_config WITH DEFAULT VALUES
-- ============================================
-- Clear old building config entries (safe to re-run)
DELETE FROM game_config WHERE key LIKE 'building.%';
DELETE FROM game_config WHERE key = 'shop.cost_scaling_multiplier';

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
  -- Resource caps (multiplier of daily production, 0 = uncapped)
  ('cap.mana_multiplier', 10, 'Mana cap = total_daily_mana * this multiplier', 'caps'),
  ('cap.gold_multiplier', 10, 'Gold cap = total_daily_gold * this multiplier', 'caps'),
  ('cap.food_multiplier', 10, 'Food cap = total_daily_food * this multiplier', 'caps'),
  -- Karma milestone settings
  ('karma.milestone_threshold', 50, 'Prayer count threshold per karma milestone', 'karma'),
  ('karma.milestone_payout', 5, 'Karma awarded per milestone', 'karma'),
  ('karma.altruistic_multiplier', 2, 'Multiplier for altruistic prayer milestones', 'karma')
ON CONFLICT (key) DO UPDATE SET
  value = EXCLUDED.value,
  description = EXCLUDED.description,
  category = EXCLUDED.category,
  updated_at = now();

-- ============================================
-- 3. CREATE shop_items TABLE
-- ============================================
-- Server-authoritative catalog of all purchasable items.
-- Costs and effects live here, not in frontend code.

CREATE TABLE IF NOT EXISTS shop_items (
  id TEXT PRIMARY KEY,
  category TEXT NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  emoji_icon TEXT,
  karma_cost INT NOT NULL DEFAULT 0,
  effect_type TEXT NOT NULL,
  effect_data JSONB NOT NULL DEFAULT '{}'::jsonb,
  purchase_limit INT,
  requires_building TEXT,
  sort_order INT DEFAULT 0,
  is_active BOOLEAN DEFAULT true,
  cost_scaling BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Add cost_scaling column if it doesn't exist (migration safety)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'shop_items' AND column_name = 'cost_scaling'
  ) THEN
    ALTER TABLE shop_items ADD COLUMN cost_scaling BOOLEAN DEFAULT false;
  END IF;
END $$;

-- RLS: anyone authenticated can read, only service_role can write
ALTER TABLE shop_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Shop items are publicly readable" ON shop_items;
CREATE POLICY "Shop items are publicly readable" ON shop_items
  FOR SELECT USING (true);

-- ============================================
-- 4. SEED shop_items WITH TIER CATALOG
-- ============================================
-- 5 tiers per category, stacking buildings with cost scaling.
-- Prices shown are BASE costs; actual cost = base * 1.15^owned.

-- Remove old catalog items
DELETE FROM shop_items WHERE id IN (
  'garden-2', 'garden-3', 'garden-4',
  'temple-1', 'temple-2', 'temple-3',
  'church-upgrade',
  'worker-2', 'worker-3', 'worker-4'
);

INSERT INTO shop_items (id, category, name, description, emoji_icon, karma_cost, effect_type, effect_data, purchase_limit, requires_building, sort_order, is_active, cost_scaling) VALUES
  -- ======= MANA ESTATES (5 tiers) =======
  ('altar', 'mana', 'Altar', 'A humble altar where devotion begins. Generates Mana.', '🕯️', 10, 'add_building', '{"building_type": "altar"}'::jsonb, NULL, NULL, 1, true, true),
  ('shrine', 'mana', 'Shrine', 'A shrine channeling greater spiritual energy. Generates more Mana.', '⛩️', 50, 'add_building', '{"building_type": "shrine"}'::jsonb, NULL, 'altar', 2, true, true),
  ('temple', 'mana', 'Temple', 'A grand temple of devotion. Generates significant Mana. Requires gold upkeep.', '🏛️', 250, 'add_building', '{"building_type": "temple"}'::jsonb, NULL, 'shrine', 3, true, true),
  ('church', 'mana', 'Church', 'A holy church radiating divine power. Generates abundant Mana. Requires gold upkeep.', '⛪', 1200, 'add_building', '{"building_type": "church"}'::jsonb, NULL, 'temple', 4, true, true),
  ('cathedral', 'mana', 'Cathedral', 'A towering cathedral, pinnacle of spiritual architecture. Requires gold upkeep.', '🏰', 6000, 'add_building', '{"building_type": "cathedral"}'::jsonb, NULL, 'church', 5, true, true),
  -- ======= FOOD ESTATES (5 tiers) =======
  ('pot', 'food', 'Pot', 'A simple pot for brewing sustenance. Generates Food.', '🍲', 10, 'add_building', '{"building_type": "pot"}'::jsonb, NULL, NULL, 11, true, true),
  ('patch', 'food', 'Patch', 'A garden patch for growing crops. Generates more Food.', '🌱', 50, 'add_building', '{"building_type": "patch"}'::jsonb, NULL, 'pot', 12, true, true),
  ('garden', 'food', 'Garden', 'A lush garden of plenty. Generates significant Food.', '🌾', 250, 'add_building', '{"building_type": "garden"}'::jsonb, NULL, 'patch', 13, true, true),
  ('field', 'food', 'Field', 'A sprawling field of golden grain. Generates abundant Food.', '🌻', 1200, 'add_building', '{"building_type": "field"}'::jsonb, NULL, 'garden', 14, true, true),
  ('farm', 'food', 'Farm', 'A grand farm estate, pinnacle of agricultural mastery.', '🏡', 6000, 'add_building', '{"building_type": "farm"}'::jsonb, NULL, 'field', 15, true, true),
  -- ======= WORKFORCE (5 tiers) =======
  ('novice', 'workforce', 'Novice', 'A novice devotee learning the ways. Generates Gold, consumes Food.', '🙏', 15, 'add_building', '{"building_type": "novice"}'::jsonb, NULL, NULL, 21, true, true),
  ('monk', 'workforce', 'Monk', 'A disciplined monk. Generates more Gold, consumes more Food.', '🧘', 75, 'add_building', '{"building_type": "monk"}'::jsonb, NULL, 'novice', 22, true, true),
  ('cleric', 'workforce', 'Cleric', 'A powerful cleric channeling divine wealth. Generates significant Gold.', '🧙', 400, 'add_building', '{"building_type": "cleric"}'::jsonb, NULL, 'monk', 23, true, true),
  ('bishop', 'workforce', 'Bishop', 'A bishop commanding vast resources. Generates abundant Gold.', '👑', 2000, 'add_building', '{"building_type": "bishop"}'::jsonb, NULL, 'cleric', 24, true, true),
  ('cardinal', 'workforce', 'Cardinal', 'A cardinal, highest authority in the divine hierarchy. Generates immense Gold.', '⭐', 10000, 'add_building', '{"building_type": "cardinal"}'::jsonb, NULL, 'bishop', 25, true, true),
  -- ======= INFRASTRUCTURE: Prayer Slots (fixed cost, no scaling) =======
  ('prayer-slot-2', 'infrastructure', 'Second Prayer Slot', 'Pray two prayers simultaneously. +100 Devotion per day.', '🙏', 100, 'add_prayer_slot', '{"slots_to_add": 1, "daily_devotion_bonus": 100}'::jsonb, NULL, NULL, 31, true, false),
  ('prayer-slot-3', 'infrastructure', 'Third Prayer Slot', 'The truly devoted can pray three prayers at once. +100 Devotion per day.', '🙏', 300, 'add_prayer_slot', '{"slots_to_add": 1, "daily_devotion_bonus": 100}'::jsonb, NULL, NULL, 32, true, false),
  ('prayer-slot-4', 'infrastructure', 'Fourth Prayer Slot', 'Four simultaneous prayers. A holy multitasker. +100 Devotion per day.', '🙏', 800, 'add_prayer_slot', '{"slots_to_add": 1, "daily_devotion_bonus": 100}'::jsonb, NULL, NULL, 33, true, false),
  ('prayer-slot-5', 'infrastructure', 'Fifth Prayer Slot', 'Five prayers at once. Divine concurrency. +100 Devotion per day.', '🙏', 2000, 'add_prayer_slot', '{"slots_to_add": 1, "daily_devotion_bonus": 100}'::jsonb, NULL, NULL, 34, true, false)
ON CONFLICT (id) DO UPDATE SET
  category = EXCLUDED.category,
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  emoji_icon = EXCLUDED.emoji_icon,
  karma_cost = EXCLUDED.karma_cost,
  effect_type = EXCLUDED.effect_type,
  effect_data = EXCLUDED.effect_data,
  purchase_limit = EXCLUDED.purchase_limit,
  requires_building = EXCLUDED.requires_building,
  sort_order = EXCLUDED.sort_order,
  is_active = EXCLUDED.is_active,
  cost_scaling = EXCLUDED.cost_scaling;

-- ============================================
-- 5. CREATE player_buildings TABLE
-- ============================================
-- Tracks building ownership per player.
-- Buildings STACK: multiple Pots = multiple food production.
-- Production rates come from game_config, NOT from this table.

CREATE TABLE IF NOT EXISTS player_buildings (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  building_type TEXT NOT NULL,
  is_active BOOLEAN DEFAULT true,
  purchased_with TEXT,
  purchased_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_player_buildings_user ON player_buildings(user_id);
CREATE INDEX IF NOT EXISTS idx_player_buildings_user_type ON player_buildings(user_id, building_type);

-- RLS: users can read own buildings, no direct INSERT/UPDATE (use RPC)
ALTER TABLE player_buildings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Players can read own buildings" ON player_buildings;
CREATE POLICY "Players can read own buildings" ON player_buildings
  FOR SELECT USING (auth.uid() = user_id);

-- ============================================
-- 6. ADD NEW COLUMNS TO profiles
-- ============================================

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS mana INT DEFAULT 0;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS gold INT DEFAULT 0;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS food INT DEFAULT 0;

-- ============================================
-- 7. RPC: purchase_shop_item (with cost scaling)
-- ============================================
-- Atomic purchase that validates cost, deducts karma, applies effect.
-- For stacking buildings: actual cost = base_cost * multiplier^owned_count
-- For prayer slots: cost is fixed (no scaling)

CREATE OR REPLACE FUNCTION purchase_shop_item(p_item_id TEXT)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_item RECORD;
    v_user_karma INT;
    v_actual_cost INT;
    v_owned_count INT;
    v_effect_building_type TEXT;
    v_building_count INT;
    v_scaling_multiplier NUMERIC;
    v_new_max_slots INT;
    v_new_daily_limit INT;
BEGIN
    -- Look up the shop item
    SELECT * INTO v_item FROM shop_items WHERE id = p_item_id AND is_active = true;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Shop item not found or inactive';
    END IF;

    -- Calculate actual cost (with scaling for buildings)
    IF v_item.cost_scaling AND v_item.effect_type = 'add_building' THEN
        -- Get building type from effect_data
        v_effect_building_type := v_item.effect_data->>'building_type';

        -- Count how many of this building type the player already owns
        SELECT COUNT(*)::INT INTO v_owned_count
        FROM player_buildings
        WHERE user_id = v_user_id AND building_type = v_effect_building_type AND is_active = true;

        -- Get scaling multiplier from game_config
        SELECT value INTO v_scaling_multiplier FROM game_config WHERE key = 'shop.cost_scaling_multiplier';
        IF v_scaling_multiplier IS NULL THEN v_scaling_multiplier := 1.15; END IF;

        -- Calculate: base_cost * multiplier^owned
        v_actual_cost := FLOOR(v_item.karma_cost * POWER(v_scaling_multiplier, v_owned_count))::INT;
    ELSE
        v_actual_cost := v_item.karma_cost;
    END IF;

    -- Check karma balance against actual cost
    SELECT karma INTO v_user_karma FROM profiles WHERE id = v_user_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Profile not found';
    END IF;
    IF v_user_karma < v_actual_cost THEN
        RAISE EXCEPTION 'Insufficient karma. You have % but need %.', v_user_karma, v_actual_cost;
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

    -- Deduct actual cost
    UPDATE profiles SET karma = karma - v_actual_cost, updated_at = now()
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
        'karma_spent', v_actual_cost,
        'new_karma', (SELECT karma FROM profiles WHERE id = v_user_id),
        'new_mana', (SELECT mana FROM profiles WHERE id = v_user_id),
        'new_gold', (SELECT gold FROM profiles WHERE id = v_user_id),
        'new_food', (SELECT food FROM profiles WHERE id = v_user_id),
        'new_max_slots', (SELECT max_prayer_slots FROM profiles WHERE id = v_user_id)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 8. RPC: get_leaderboard
-- ============================================

CREATE OR REPLACE FUNCTION get_leaderboard(
    p_offset INT DEFAULT 0,
    p_limit INT DEFAULT 100
)
RETURNS JSONB AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT jsonb_agg(row_to_json(t)) INTO v_result
    FROM (
        SELECT
            p.id,
            p.username,
            p.faith,
            p.karma,
            p.mana,
            p.gold,
            p.food,
            p.max_prayer_slots,
            ROW_NUMBER() OVER (ORDER BY p.karma DESC, p.mana DESC, p.created_at ASC) AS rank
        FROM profiles p
        WHERE p.username IS NOT NULL
        ORDER BY p.karma DESC, p.mana DESC, p.created_at ASC
        LIMIT p_limit OFFSET p_offset
    ) t;

    RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 9. RPC: get_player_economy
-- ============================================
-- Returns the current user's full economy data: resources, buildings, and production rates.

CREATE OR REPLACE FUNCTION get_player_economy()
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_profile RECORD;
    v_buildings JSONB;
    v_production JSONB;
BEGIN
    -- Get profile resources
    SELECT karma, mana, gold, food, max_prayer_slots, daily_token_limit
    INTO v_profile
    FROM profiles WHERE id = v_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Profile not found';
    END IF;

    -- Get player buildings
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', id,
        'building_type', building_type,
        'is_active', is_active,
        'purchased_with', purchased_with,
        'purchased_at', purchased_at
    )), '[]'::jsonb) INTO v_buildings
    FROM player_buildings
    WHERE user_id = v_user_id;

    -- Calculate daily production rates from game_config + buildings
    WITH user_buildings AS (
        SELECT building_type, COUNT(*)::INT AS count
        FROM player_buildings
        WHERE user_id = v_user_id AND is_active = true
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
        ), 0),
        'food_consumption_per_day', COALESCE(SUM(
            (SELECT COALESCE(value, 0) FROM game_config WHERE key = 'building.' || ub.building_type || '.food_consumption_per_day') * ub.count
        ), 0)
    ), '{}'::jsonb) INTO v_production
    FROM user_buildings ub;

    RETURN jsonb_build_object(
        'karma', v_profile.karma,
        'mana', v_profile.mana,
        'gold', v_profile.gold,
        'food', v_profile.food,
        'max_prayer_slots', v_profile.max_prayer_slots,
        'daily_devotion_limit', v_profile.daily_token_limit,
        'buildings', v_buildings,
        'daily_rates', v_production
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 10. MODIFY: calculate_automated_karma (add resource generation + upkeep)
-- ============================================
-- Now handles: karma milestones + mana/gold/food generation + gold/food upkeep
-- All production rates read from game_config for central rebalancing.

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
    -- Resource generation variables
    v_mana_cap_multiplier NUMERIC;
    v_gold_cap_multiplier NUMERIC;
    v_food_cap_multiplier NUMERIC;
    v_mana_per_tick INT;
    v_gold_per_tick INT;
    v_food_per_tick INT;
    v_gold_upkeep_tick INT;
    v_food_consume_tick INT;
    v_mana_cap INT;
    v_gold_cap INT;
    v_food_cap INT;
BEGIN
    -- Load configurable karma milestone settings
    SELECT value INTO v_milestone_threshold FROM game_config WHERE key = 'karma.milestone_threshold';
    SELECT value INTO v_milestone_payout FROM game_config WHERE key = 'karma.milestone_payout';
    SELECT value INTO v_altruistic_multiplier FROM game_config WHERE key = 'karma.altruistic_multiplier';

    -- Default fallbacks if config missing
    IF v_milestone_threshold IS NULL THEN v_milestone_threshold := 50; END IF;
    IF v_milestone_payout IS NULL THEN v_milestone_payout := 5; END IF;
    IF v_altruistic_multiplier IS NULL THEN v_altruistic_multiplier := 2; END IF;

    -- ========================================
    -- PHASE 1: EXISTING KARMA MILESTONE LOGIC
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

        -- Intercessory prayer redemption check
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
    -- PHASE 2: RESOURCE GENERATION + UPKEEP
    -- ========================================
    -- Load configurable cap multipliers
    SELECT value INTO v_mana_cap_multiplier FROM game_config WHERE key = 'cap.mana_multiplier';
    SELECT value INTO v_gold_cap_multiplier FROM game_config WHERE key = 'cap.gold_multiplier';
    SELECT value INTO v_food_cap_multiplier FROM game_config WHERE key = 'cap.food_multiplier';

    -- Default fallbacks
    IF v_mana_cap_multiplier IS NULL THEN v_mana_cap_multiplier := 10; END IF;
    IF v_gold_cap_multiplier IS NULL THEN v_gold_cap_multiplier := 10; END IF;
    IF v_food_cap_multiplier IS NULL THEN v_food_cap_multiplier := 10; END IF;

    -- Per-player: sum production and upkeep from active buildings via game_config
    FOR r IN
        SELECT
            pb.user_id,
            COALESCE(SUM(
                CASE WHEN gc_mana.value IS NOT NULL THEN gc_mana.value ELSE 0 END
            ), 0)::NUMERIC AS total_mana_per_day,
            COALESCE(SUM(
                CASE WHEN gc_gold.value IS NOT NULL THEN gc_gold.value ELSE 0 END
            ), 0)::NUMERIC AS total_gold_per_day,
            COALESCE(SUM(
                CASE WHEN gc_food.value IS NOT NULL THEN gc_food.value ELSE 0 END
            ), 0)::NUMERIC AS total_food_per_day,
            COALESCE(SUM(
                CASE WHEN gc_gold_upkeep.value IS NOT NULL THEN gc_gold_upkeep.value ELSE 0 END
            ), 0)::NUMERIC AS total_gold_upkeep_per_day,
            COALESCE(SUM(
                CASE WHEN gc_food_consume.value IS NOT NULL THEN gc_food_consume.value ELSE 0 END
            ), 0)::NUMERIC AS total_food_consumption_per_day
        FROM player_buildings pb
        LEFT JOIN game_config gc_mana
            ON gc_mana.key = 'building.' || pb.building_type || '.mana_per_day'
        LEFT JOIN game_config gc_gold
            ON gc_gold.key = 'building.' || pb.building_type || '.gold_per_day'
        LEFT JOIN game_config gc_food
            ON gc_food.key = 'building.' || pb.building_type || '.food_per_day'
        LEFT JOIN game_config gc_gold_upkeep
            ON gc_gold_upkeep.key = 'building.' || pb.building_type || '.gold_upkeep_per_day'
        LEFT JOIN game_config gc_food_consume
            ON gc_food_consume.key = 'building.' || pb.building_type || '.food_consumption_per_day'
        WHERE pb.is_active = true
        GROUP BY pb.user_id
    LOOP
        -- Per-tick amounts (1440 minutes per day)
        v_mana_per_tick := GREATEST(0, FLOOR(r.total_mana_per_day / 1440));
        v_gold_per_tick := GREATEST(0, FLOOR(r.total_gold_per_day / 1440));
        v_food_per_tick := GREATEST(0, FLOOR(r.total_food_per_day / 1440));
        v_gold_upkeep_tick := GREATEST(0, FLOOR(r.total_gold_upkeep_per_day / 1440));
        v_food_consume_tick := GREATEST(0, FLOOR(r.total_food_consumption_per_day / 1440));

        -- Ensure at least 1 resource per tick for active players with any production
        IF r.total_mana_per_day > 0 AND v_mana_per_tick = 0 THEN v_mana_per_tick := 1; END IF;
        IF r.total_gold_per_day > 0 AND v_gold_per_tick = 0 THEN v_gold_per_tick := 1; END IF;
        IF r.total_food_per_day > 0 AND v_food_per_tick = 0 THEN v_food_per_tick := 1; END IF;

        -- Calculate caps
        v_mana_cap := FLOOR(r.total_mana_per_day * v_mana_cap_multiplier);
        v_gold_cap := FLOOR(r.total_gold_per_day * v_gold_cap_multiplier);
        v_food_cap := FLOOR(r.total_food_per_day * v_food_cap_multiplier);

        -- Update resources: mana capped, gold and food net with floor at 0
        UPDATE profiles SET
            mana = LEAST(mana + v_mana_per_tick, v_mana_cap),
            gold = GREATEST(0, gold + v_gold_per_tick - v_gold_upkeep_tick),
            food = GREATEST(0, food + v_food_per_tick - v_food_consume_tick),
            updated_at = now()
        WHERE id = r.user_id;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 11. MODIFY: create_profile_on_signup (grant starting buildings)
-- ============================================

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

-- ============================================
-- 12. BACKFILL: Reset buildings and grant new starting assets
-- ============================================
-- Clean slate: remove all old buildings, grant new starting set.

-- Remove all existing buildings (old system used shrine/garden/worker/temple/church)
TRUNCATE player_buildings;

-- Grant starting buildings to all existing users
INSERT INTO player_buildings (user_id, building_type, is_active, purchased_with)
SELECT p.id, 'altar', true, 'starting-altar'
FROM profiles p;

INSERT INTO player_buildings (user_id, building_type, is_active, purchased_with)
SELECT p.id, 'pot', true, 'starting-pot'
FROM profiles p;

INSERT INTO player_buildings (user_id, building_type, is_active, purchased_with)
SELECT p.id, 'novice', true, 'starting-novice'
FROM profiles p;

-- ============================================
-- 13. GRANT PERMISSIONS
-- ============================================

GRANT SELECT ON TABLE game_config TO authenticated;
GRANT SELECT ON TABLE game_config TO anon;
GRANT ALL ON TABLE game_config TO service_role;

GRANT SELECT ON TABLE shop_items TO authenticated;
GRANT SELECT ON TABLE shop_items TO anon;
GRANT ALL ON TABLE shop_items TO service_role;

GRANT SELECT ON TABLE player_buildings TO authenticated;
GRANT ALL ON TABLE player_buildings TO service_role;

GRANT EXECUTE ON FUNCTION purchase_shop_item(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION purchase_shop_item(TEXT) TO service_role;

GRANT EXECUTE ON FUNCTION get_leaderboard(INT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_leaderboard(INT, INT) TO anon;

GRANT EXECUTE ON FUNCTION get_player_economy() TO authenticated;
GRANT EXECUTE ON FUNCTION get_player_economy() TO service_role;

GRANT EXECUTE ON FUNCTION calculate_automated_karma() TO service_role;

-- ============================================
-- 13b. FIX: Replace broken reset_daily_prayer_count function
-- ============================================

CREATE OR REPLACE FUNCTION reset_daily_prayer_count(p_user_id UUID)
RETURNS VOID AS $$
BEGIN
    UPDATE profiles
    SET tokens_spent_today = 0,
        last_prayer_date = CURRENT_DATE
    WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION reset_daily_prayer_count(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION reset_daily_prayer_count(UUID) TO service_role;

-- ============================================
-- 14. VERIFY CRON JOB IS SCHEDULED
-- ============================================

DO $$
BEGIN
    PERFORM cron.unschedule('prayer-heartbeat');
EXCEPTION
    WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule('prayer-heartbeat', '* * * * *', 'SELECT calculate_automated_karma()');