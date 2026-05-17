-- =====================================================
-- ELECTRIC MONK - VASSALAGE & HERESY EXPANSION
-- Migration Version: 7.0 - The ML-MMO of the Soul
-- Date: 2026-05-17
--
-- Adds: Vassalage pyramid with 10% tithe siphon
--       Heresy resource + Catacombs economy
--       Asymmetric combat: Crusade, Schism, Plague
--       Akashic Logs for battle reports
--       Multi-currency shop (karma + gold + heresy)
--       Deadlock-safe cron with CTE-based tithe math
--
-- PASTE THIS ENTIRE SCRIPT INTO SUPABASE SQL EDITOR
-- Run it as a single transaction. This migration is
-- separate from theological-pbbg-pivot.sql and can be
-- reverted independently.
-- =====================================================

-- ============================================
-- 1. ALTER profiles: Add vassalage + heresy columns
-- ============================================

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS suzerain_id UUID REFERENCES profiles(id) ON DELETE SET NULL;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS heresy INT DEFAULT 0;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS schism_count INT DEFAULT 0;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS divine_shield_until TIMESTAMPTZ;

-- Index for suzerain lookups (finding all vassals of a suzerain)
CREATE INDEX IF NOT EXISTS idx_profiles_suzerain ON profiles(suzerain_id);
-- Index for divine shield checks
CREATE INDEX IF NOT EXISTS idx_profiles_divine_shield ON profiles(divine_shield_until) WHERE divine_shield_until IS NOT NULL;

-- ============================================
-- 2. ALTER shop_items: Add gold_cost and heresy_cost
-- ============================================

ALTER TABLE shop_items ADD COLUMN IF NOT EXISTS gold_cost INT NOT NULL DEFAULT 0;
ALTER TABLE shop_items ADD COLUMN IF NOT EXISTS heresy_cost INT NOT NULL DEFAULT 0;

-- ============================================
-- 3. CREATE akashic_logs TABLE
-- ============================================

CREATE TABLE IF NOT EXISTS akashic_logs (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  target_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  actor_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
  action_type TEXT NOT NULL CHECK (action_type IN ('crusade', 'schism', 'plague')),
  result_data JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_akashic_target ON akashic_logs(target_id);
CREATE INDEX IF NOT EXISTS idx_akashic_actor ON akashic_logs(actor_id);
CREATE INDEX IF NOT EXISTS idx_akashic_action_type ON akashic_logs(action_type);
CREATE INDEX IF NOT EXISTS idx_akashic_created_at ON akashic_logs(created_at DESC);

-- RLS: anyone authenticated can read, only service_role / SECURITY DEFINER can insert
ALTER TABLE akashic_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Akashic logs are publicly readable" ON akashic_logs;
CREATE POLICY "Akashic logs are publicly readable" ON akashic_logs
  FOR SELECT USING (true);

-- ============================================
-- 4. SEED game_config: Heresy + Vassalage + Combat
-- ============================================

INSERT INTO game_config (key, value, description, category) VALUES
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
  -- Combat: Schism
  ('schism.base_cost', 100, 'Base heresy cost to declare schism', 'combat'),
  ('schism.scaling_factor', 2.0, 'Cost multiplier per previous schism: base * factor^count', 'combat'),
  ('schism.shield_duration_hours', 24, 'Hours of Divine Shield granted after successful schism', 'combat'),
  -- Combat: Plague
  ('plague.heresy_cost', 75, 'Heresy cost to cast a plague', 'combat')
ON CONFLICT (key) DO UPDATE SET
  value = EXCLUDED.value,
  description = EXCLUDED.description,
  category = EXCLUDED.category,
  updated_at = now();

-- ============================================
-- 5. SEED shop_items: Catacombs category
-- ============================================

INSERT INTO shop_items (id, category, name, description, emoji_icon, karma_cost, gold_cost, heresy_cost, effect_type, effect_data, purchase_limit, requires_building, sort_order, is_active, cost_scaling) VALUES
  ('cultist', 'catacombs', 'Cultist', 'A shadow disciple who generates Heresy. Consumes Food like any worker.', '🧟', 0, 50, 0, 'add_building', '{"building_type": "cultist"}'::jsonb, NULL, NULL, 41, true, true),
  ('coven', 'catacombs', 'Coven', 'A hidden gathering place that increases your Heresy capacity. Requires gold upkeep.', '🔮', 0, 200, 0, 'add_building', '{"building_type": "coven"}'::jsonb, NULL, 'cultist', 42, true, true)
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
  cost_scaling = EXCLUDED.cost_scaling;

-- ============================================
-- 6. REWRITE: calculate_automated_karma()
--    Now with CTE-based tithe math (deadlock-safe)
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
    -- Resource generation variables
    v_mana_cap_multiplier NUMERIC;
    v_gold_cap_multiplier NUMERIC;
    v_food_cap_multiplier NUMERIC;
    v_heresy_base_cap NUMERIC;
    v_tithe_pct NUMERIC;
BEGIN
    -- Load configurable karma milestone settings
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
    IF v_mana_cap_multiplier IS NULL THEN v_mana_cap_multiplier := 10; END IF;
    IF v_gold_cap_multiplier IS NULL THEN v_gold_cap_multiplier := 10; END IF;
    IF v_food_cap_multiplier IS NULL THEN v_food_cap_multiplier := 10; END IF;

    -- Load heresy base cap
    SELECT value INTO v_heresy_base_cap FROM game_config WHERE key = 'cap.heresy_base';
    IF v_heresy_base_cap IS NULL THEN v_heresy_base_cap := 100; END IF;

    -- Load tithe percentage
    SELECT value INTO v_tithe_pct FROM game_config WHERE key = 'tithe.percentage';
    IF v_tithe_pct IS NULL THEN v_tithe_pct := 0.10; END IF;

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
    -- PHASE 2: RESOURCE GENERATION + UPKEEP + TITHE + HERESY
    -- Using CTE-based approach to avoid deadlocks
    -- ========================================

    -- Single set-based UPDATE using CTEs for production, tithes, and caps
    WITH user_production AS (
        -- Per-player gross production and upkeep from active buildings
        SELECT
            pb.user_id,
            COALESCE(SUM(
                CASE WHEN gc_mana.value IS NOT NULL THEN gc_mana.value ELSE 0 END
            ), 0)::NUMERIC AS gross_mana_per_day,
            COALESCE(SUM(
                CASE WHEN gc_gold.value IS NOT NULL THEN gc_gold.value ELSE 0 END
            ), 0)::NUMERIC AS gross_gold_per_day,
            COALESCE(SUM(
                CASE WHEN gc_food.value IS NOT NULL THEN gc_food.value ELSE 0 END
            ), 0)::NUMERIC AS gross_food_per_day,
            COALESCE(SUM(
                CASE WHEN gc_gold_upkeep.value IS NOT NULL THEN gc_gold_upkeep.value ELSE 0 END
            ), 0)::NUMERIC AS total_gold_upkeep_per_day,
            COALESCE(SUM(
                CASE WHEN gc_food_consume.value IS NOT NULL THEN gc_food_consume.value ELSE 0 END
            ), 0)::NUMERIC AS total_food_consumption_per_day,
            COALESCE(SUM(
                CASE WHEN gc_heresy.value IS NOT NULL THEN gc_heresy.value ELSE 0 END
            ), 0)::NUMERIC AS gross_heresy_per_day,
            COALESCE(SUM(
                CASE WHEN gc_heresy_consume.value IS NOT NULL THEN gc_heresy_consume.value ELSE 0 END
            ), 0)::NUMERIC AS total_heresy_food_consume_per_day,
            -- Coven gold upkeep
            COALESCE(SUM(
                CASE WHEN gc_coven_upkeep.value IS NOT NULL THEN gc_coven_upkeep.value ELSE 0 END
            ), 0)::NUMERIC AS total_coven_gold_upkeep_per_day,
            -- Coven count for heresy cap
            COALESCE(SUM(
                CASE WHEN pb.building_type = 'coven' THEN 1 ELSE 0 END
            ), 0)::INT AS coven_count
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
        LEFT JOIN game_config gc_heresy
            ON gc_heresy.key = 'building.' || pb.building_type || '.heresy_per_day'
        LEFT JOIN game_config gc_heresy_consume
            ON gc_heresy_consume.key = 'building.' || pb.building_type || '.food_consumption_per_day'
            AND pb.building_type = 'cultist'
        LEFT JOIN game_config gc_coven_upkeep
            ON gc_coven_upkeep.key = 'building.coven.gold_upkeep_per_day'
            AND pb.building_type = 'coven'
        WHERE pb.is_active = true
        GROUP BY pb.user_id
    ),
    -- Include players with no buildings (they still need upkeep checks on heresy cap)
    all_players AS (
        SELECT p.id AS user_id,
               COALESCE(up.gross_mana_per_day, 0) AS gross_mana_per_day,
               COALESCE(up.gross_gold_per_day, 0) AS gross_gold_per_day,
               COALESCE(up.gross_food_per_day, 0) AS gross_food_per_day,
               COALESCE(up.total_gold_upkeep_per_day, 0) AS total_gold_upkeep_per_day,
               COALESCE(up.total_food_consumption_per_day, 0) AS total_food_consumption_per_day,
               COALESCE(up.gross_heresy_per_day, 0) AS gross_heresy_per_day,
               COALESCE(up.total_heresy_food_consume_per_day, 0) AS total_heresy_food_consume_per_day,
               COALESCE(up.total_coven_gold_upkeep_per_day, 0) AS total_coven_gold_upkeep_per_day,
               COALESCE(up.coven_count, 0) AS coven_count,
               p.suzerain_id
        FROM profiles p
        LEFT JOIN user_production up ON p.id = up.user_id
    ),
    -- Calculate per-tick amounts (1440 minutes per day)
    tick_production AS (
        SELECT
            ap.user_id,
            ap.suzerain_id,
            -- Per-tick gross production (floor, minimum 1 if any daily production)
            CASE WHEN ap.gross_mana_per_day > 0 THEN GREATEST(1, FLOOR(ap.gross_mana_per_day / 1440))
                 ELSE 0 END AS mana_per_tick,
            CASE WHEN ap.gross_gold_per_day > 0 THEN GREATEST(1, FLOOR(ap.gross_gold_per_day / 1440))
                 ELSE 0 END AS gold_per_tick,
            CASE WHEN ap.gross_food_per_day > 0 THEN GREATEST(1, FLOOR(ap.gross_food_per_day / 1440))
                 ELSE 0 END AS food_per_tick,
            CASE WHEN ap.gross_heresy_per_day > 0 THEN GREATEST(1, FLOOR(ap.gross_heresy_per_day / 1440))
                 ELSE 0 END AS heresy_per_tick,
            -- Per-tick upkeep
            GREATEST(0, FLOOR(ap.total_gold_upkeep_per_day / 1440) +
                      FLOOR(ap.total_coven_gold_upkeep_per_day / 1440)) AS gold_upkeep_tick,
            GREATEST(0, FLOOR(ap.total_food_consumption_per_day / 1440) +
                      FLOOR(ap.total_heresy_food_consume_per_day / 1440)) AS food_consume_tick,
            -- Resource caps
            FLOOR(ap.gross_mana_per_day * v_mana_cap_multiplier) AS mana_cap,
            FLOOR(ap.gross_gold_per_day * v_gold_cap_multiplier) AS gold_cap,
            FLOOR(ap.gross_food_per_day * v_food_cap_multiplier) AS food_cap,
            -- Heresy cap: base + (coven_count * bonus)
            (v_heresy_base_cap + (ap.coven_count * (
                SELECT COALESCE(value, 50) FROM game_config WHERE key = 'building.coven.heresy_cap_bonus'
            )))::INT AS heresy_cap,
            -- Tithe amounts (10% of gross, per tick, floored)
            CASE WHEN ap.suzerain_id IS NOT NULL THEN FLOOR(ap.gross_mana_per_day / 1440 * v_tithe_pct)
                 ELSE 0 END::INT AS mana_tithe_tick,
            CASE WHEN ap.suzerain_id IS NOT NULL THEN FLOOR(ap.gross_gold_per_day / 1440 * v_tithe_pct)
                 ELSE 0 END::INT AS gold_tithe_tick,
            CASE WHEN ap.suzerain_id IS NOT NULL THEN FLOOR(ap.gross_food_per_day / 1440 * v_tithe_pct)
                 ELSE 0 END::INT AS food_tithe_tick
        FROM all_players ap
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
    )
    -- Single UPDATE joining all CTEs
    UPDATE profiles p SET
        mana = LEAST(
            p.mana + tp.mana_per_tick - tp.mana_tithe_tick + COALESCE(ti.received_mana_tick, 0),
            tp.mana_cap
        ),
        gold = GREATEST(0,
            p.gold + tp.gold_per_tick - tp.gold_upkeep_tick - tp.gold_tithe_tick + COALESCE(ti.received_gold_tick, 0)
        ),
        food = GREATEST(0,
            p.food + tp.food_per_tick - tp.food_consume_tick - tp.food_tithe_tick + COALESCE(ti.received_food_tick, 0)
        ),
        heresy = LEAST(
            p.heresy + tp.heresy_per_tick,
            tp.heresy_cap
        ),
        updated_at = now()
    FROM tick_production tp
    LEFT JOIN tithe_inbound ti ON ti.suzerain_id = p.id
    WHERE p.id = tp.user_id;

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 7. CREATE: launch_crusade(target_id UUID)
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
    v_target_suzerain UUID;
    v_mana_cost NUMERIC;
    v_attack_rating NUMERIC;
    v_defense_rating NUMERIC;
    v_attack_roll NUMERIC;
    v_defense_roll NUMERIC;
    v_cathedral_rating NUMERIC;
    v_success BOOLEAN;
    v_result JSONB;
    -- Circular vassalage check
    v_in_chain BOOLEAN;
BEGIN
    -- Validate: cannot crusade yourself
    IF p_target_id = v_attacker_id THEN
        RAISE EXCEPTION 'Cannot crusade yourself';
    END IF;

    -- Load mana cost from config
    SELECT value INTO v_mana_cost FROM game_config WHERE key = 'crusade.mana_cost';
    IF v_mana_cost IS NULL THEN v_mana_cost := 50; END IF;

    -- Check attacker has enough mana
    SELECT mana INTO v_attacker_mana FROM profiles WHERE id = v_attacker_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Attacker profile not found'; END IF;
    IF v_attacker_mana < v_mana_cost THEN
        RAISE EXCEPTION 'Insufficient Mana. Need %, have %.', v_mana_cost, v_attacker_mana;
    END IF;

    -- Check target exists
    SELECT suzerain_id, divine_shield_until INTO v_target_suzerain, v_target_shield
    FROM profiles WHERE id = p_target_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Target not found'; END IF;

    -- Check target is not shielded
    IF v_target_shield IS NOT NULL AND v_target_shield > now() THEN
        RAISE EXCEPTION 'Target is protected by Divine Shield until %.', v_target_shield;
    END IF;

    -- Check target is not already your vassal
    IF v_target_suzerain = v_attacker_id THEN
        RAISE EXCEPTION 'Target is already your vassal';
    END IF;

    -- Circular vassalage check: walk up attacker's chain to ensure target is not an ancestor
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

    -- Calculate attack power: mana + (clerics * rating_per_cleric)
    SELECT COALESCE(value, 10) INTO v_attack_rating FROM game_config WHERE key = 'crusade.attack_rating_per_cleric';

    SELECT COUNT(*)::INT INTO v_attacker_clerics
    FROM player_buildings WHERE user_id = v_attacker_id AND building_type = 'cleric' AND is_active = true;

    v_attack_rating := GREATEST(1, v_attacker_mana) + (v_attacker_clerics * v_attack_rating);

    -- Calculate defense power: (churches * rating) + (cathedrals * rating)
    SELECT COALESCE(value, 15) INTO v_defense_rating FROM game_config WHERE key = 'crusade.defense_rating_per_church';

    SELECT COUNT(*)::INT INTO v_target_churches
    FROM player_buildings WHERE user_id = p_target_id AND building_type = 'church' AND is_active = true;

    SELECT COUNT(*)::INT INTO v_target_cathedrals
    FROM player_buildings WHERE user_id = p_target_id AND building_type = 'cathedral' AND is_active = true;

    -- Add cathedral defense rating
    SELECT COALESCE(value, 40) INTO v_cathedral_rating FROM game_config WHERE key = 'crusade.defense_rating_per_cathedral';
    v_defense_rating := (v_target_churches * v_defense_rating) + (v_target_cathedrals * v_cathedral_rating);

    -- Minimum defense of 1 so roll matters
    v_defense_rating := GREATEST(1, v_defense_rating);

    -- Roll the dice (0.7 to 1.3 multiplier)
    v_attack_roll := v_attack_rating * (0.7 + random() * 0.6);
    v_defense_roll := v_defense_rating * (0.7 + random() * 0.6);

    v_success := v_attack_roll > v_defense_roll;

    IF v_success THEN
        -- Set target's suzerain to attacker
        UPDATE profiles SET suzerain_id = v_attacker_id, updated_at = now() WHERE id = p_target_id;
    END IF;

    -- Log to akashic_logs
    INSERT INTO akashic_logs (target_id, actor_id, action_type, result_data)
    VALUES (p_target_id, v_attacker_id, 'crusade', jsonb_build_object(
        'success', v_success,
        'attack_power', v_attack_rating,
        'defense_power', v_defense_rating,
        'attack_roll', v_attack_roll,
        'defense_roll', v_defense_roll,
        'mana_cost', v_mana_cost
    ));

    RETURN jsonb_build_object(
        'success', v_success,
        'attack_power', v_attack_rating,
        'defense_power', v_defense_rating,
        'attack_roll', v_attack_roll,
        'defense_roll', v_defense_roll,
        'mana_cost', v_mana_cost,
        'new_suzerain_id', CASE WHEN v_success THEN v_attacker_id ELSE NULL END
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 8. CREATE: declare_schism()
-- ============================================

CREATE OR REPLACE FUNCTION public.declare_schism()
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_suzerain_id UUID;
    v_heresy INT;
    v_schism_count INT;
    v_base_cost NUMERIC;
    v_scaling_factor NUMERIC;
    v_actual_cost INT;
    v_shield_hours NUMERIC;
    v_shield_until TIMESTAMPTZ;
BEGIN
    -- Must be a vassal
    SELECT suzerain_id, heresy, schism_count INTO v_suzerain_id, v_heresy, v_schism_count
    FROM profiles WHERE id = v_user_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found'; END IF;
    IF v_suzerain_id IS NULL THEN RAISE EXCEPTION 'You are not a vassal. Nothing to schism from.'; END IF;

    -- Calculate cost: base * factor^count
    SELECT value INTO v_base_cost FROM game_config WHERE key = 'schism.base_cost';
    SELECT value INTO v_scaling_factor FROM game_config WHERE key = 'schism.scaling_factor';
    IF v_base_cost IS NULL THEN v_base_cost := 100; END IF;
    IF v_scaling_factor IS NULL THEN v_scaling_factor := 2.0; END IF;

    v_actual_cost := FLOOR(v_base_cost * POWER(v_scaling_factor, v_schism_count))::INT;

    -- Check heresy balance
    IF v_heresy < v_actual_cost THEN
        RAISE EXCEPTION 'Insufficient Heresy. Need %, have %.', v_actual_cost, v_heresy;
    END IF;

    -- Load shield duration
    SELECT value INTO v_shield_hours FROM game_config WHERE key = 'schism.shield_duration_hours';
    IF v_shield_hours IS NULL THEN v_shield_hours := 24; END IF;

    v_shield_until := now() + (v_shield_hours * interval '1 hour');

    -- Deduct heresy, nullify suzerain, increment schism count, set shield
    UPDATE profiles SET
        heresy = heresy - v_actual_cost,
        suzerain_id = NULL,
        schism_count = schism_count + 1,
        divine_shield_until = v_shield_until,
        updated_at = now()
    WHERE id = v_user_id;

    -- Log to akashic_logs
    INSERT INTO akashic_logs (target_id, actor_id, action_type, result_data)
    VALUES (v_user_id, v_user_id, 'schism', jsonb_build_object(
        'success', true,
        'heresy_cost', v_actual_cost,
        'former_suzerain_id', v_suzerain_id,
        'shield_until', v_shield_until,
        'schism_count', v_schism_count + 1
    ));

    RETURN jsonb_build_object(
        'success', true,
        'heresy_cost', v_actual_cost,
        'former_suzerain_id', v_suzerain_id,
        'shield_until', v_shield_until,
        'schism_count', v_schism_count + 1
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 9. CREATE: cast_plague(target_id UUID)
-- ============================================

CREATE OR REPLACE FUNCTION public.cast_plague(p_target_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_caster_id UUID := auth.uid();
    v_heresy INT;
    v_heresy_cost NUMERIC;
    v_target_food INT;
BEGIN
    -- Cannot plague yourself
    IF p_target_id = v_caster_id THEN
        RAISE EXCEPTION 'Cannot cast plague on yourself';
    END IF;

    -- Load heresy cost
    SELECT value INTO v_heresy_cost FROM game_config WHERE key = 'plague.heresy_cost';
    IF v_heresy_cost IS NULL THEN v_heresy_cost := 75; END IF;

    -- Check caster heresy balance
    SELECT heresy INTO v_heresy FROM profiles WHERE id = v_caster_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found'; END IF;
    IF v_heresy < v_heresy_cost THEN
        RAISE EXCEPTION 'Insufficient Heresy. Need %, have %.', v_heresy_cost, v_heresy;
    END IF;

    -- Get target's current food
    SELECT food INTO v_target_food FROM profiles WHERE id = p_target_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Target not found'; END IF;

    -- Deduct heresy from caster
    UPDATE profiles SET heresy = heresy - v_heresy_cost, updated_at = now() WHERE id = v_caster_id;

    -- Zero out target's food
    UPDATE profiles SET food = 0, updated_at = now() WHERE id = p_target_id;

    -- Log to akashic_logs with NULL actor_id for anonymity
    INSERT INTO akashic_logs (target_id, actor_id, action_type, result_data)
    VALUES (p_target_id, NULL, 'plague', jsonb_build_object(
        'success', true,
        'heresy_cost', v_heresy_cost,
        'food_destroyed', v_target_food
    ));

    RETURN jsonb_build_object(
        'success', true,
        'heresy_cost', v_heresy_cost,
        'food_destroyed', v_target_food
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 10. MODIFY: get_player_economy() - add heresy + vassalage data
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
BEGIN
    -- Get profile resources including new columns
    SELECT karma, mana, gold, food, heresy, max_prayer_slots, daily_token_limit,
           suzerain_id, schism_count, divine_shield_until
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
        ), 0)
    ), '{}'::jsonb) INTO v_production
    FROM user_buildings ub;

    -- Get suzerain info
    IF v_profile.suzerain_id IS NOT NULL THEN
        SELECT jsonb_build_object(
            'id', s.id,
            'username', s.username,
            'faith', s.faith
        ) INTO v_suzerain
        FROM profiles s WHERE s.id = v_profile.suzerain_id;
    ELSE
        v_suzerain := 'null'::jsonb;
    END IF;

    -- Get vassals (direct)
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', v.id,
        'username', v.username,
        'faith', v.faith
    )), '[]'::jsonb), COUNT(*)::INT
    INTO v_vassals, v_vassal_count
    FROM profiles v WHERE v.suzerain_id = v_user_id;

    -- Calculate estimated daily tithes from vassals
    SELECT value INTO v_tithe_pct FROM game_config WHERE key = 'tithe.percentage';
    IF v_tithe_pct IS NULL THEN v_tithe_pct := 0.10; END IF;

    WITH vassal_production AS (
        SELECT
            vp.user_id,
            COALESCE(SUM(
                CASE WHEN gc_mana.value IS NOT NULL THEN gc_mana.value ELSE 0 END
            ), 0)::NUMERIC AS vassal_mana_per_day,
            COALESCE(SUM(
                CASE WHEN gc_gold.value IS NOT NULL THEN gc_gold.value ELSE 0 END
            ), 0)::NUMERIC AS vassal_gold_per_day,
            COALESCE(SUM(
                CASE WHEN gc_food.value IS NOT NULL THEN gc_food.value ELSE 0 END
            ), 0)::NUMERIC AS vassal_food_per_day
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

    -- Calculate heresy cap
    SELECT value INTO v_heresy_base FROM game_config WHERE key = 'cap.heresy_base';
    IF v_heresy_base IS NULL THEN v_heresy_base := 100; END IF;

    SELECT COALESCE(value, 50) INTO v_coven_bonus FROM game_config WHERE key = 'building.coven.heresy_cap_bonus';

    SELECT COUNT(*)::INT INTO v_coven_count
    FROM player_buildings WHERE user_id = v_user_id AND building_type = 'coven' AND is_active = true;

    -- Build production with heresy cap
    v_production := v_production || jsonb_build_object(
        'heresy_cap', (v_heresy_base + v_coven_count * v_coven_bonus)::INT
    );

    RETURN jsonb_build_object(
        'karma', v_profile.karma,
        'mana', v_profile.mana,
        'gold', v_profile.gold,
        'food', v_profile.food,
        'heresy', v_profile.heresy,
        'max_prayer_slots', v_profile.max_prayer_slots,
        'daily_devotion_limit', v_profile.daily_token_limit,
        'suzerain_id', v_profile.suzerain_id,
        'schism_count', v_profile.schism_count,
        'divine_shield_until', v_profile.divine_shield_until,
        'suzerain', v_suzerain,
        'vassals', COALESCE(v_vassals, '[]'::jsonb),
        'vassal_count', v_vassal_count,
        'daily_tithes', v_daily_tithes,
        'buildings', v_buildings,
        'daily_rates', v_production
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 11. MODIFY: purchase_shop_item() - multi-currency support
-- ============================================

CREATE OR REPLACE FUNCTION public.purchase_shop_item(p_item_id TEXT)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_item RECORD;
    v_user_karma INT;
    v_user_gold INT;
    v_user_heresy INT;
    v_actual_karma_cost INT;
    v_actual_gold_cost INT;
    v_actual_heresy_cost INT;
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
    SELECT karma, gold, heresy INTO v_user_karma, v_user_gold, v_user_heresy
    FROM profiles WHERE id = v_user_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Profile not found';
    END IF;

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
        'new_max_slots', (SELECT max_prayer_slots FROM profiles WHERE id = v_user_id)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 12. CREATE: get_vassalage_info()
-- ============================================

CREATE OR REPLACE FUNCTION public.get_vassalage_info()
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_suzerain JSONB;
    v_vassals JSONB;
    v_vassal_count INT;
    v_chain_depth INT;
    v_tithe_pct NUMERIC;
    v_daily_tithes JSONB;
    v_is_protected BOOLEAN;
BEGIN
    -- Get suzerain info
    SELECT jsonb_build_object(
        'id', s.id,
        'username', s.username,
        'faith', s.faith
    ) INTO v_suzerain
    FROM profiles p
    JOIN profiles s ON s.id = p.suzerain_id
    WHERE p.id = v_user_id;

    IF v_suzerain IS NULL THEN
        v_suzerain := 'null'::jsonb;
    END IF;

    -- Calculate chain depth (how deep in the hierarchy)
    WITH RECURSIVE chain AS (
        SELECT id, suzerain_id, 0 AS depth FROM profiles WHERE id = v_user_id
        UNION ALL
        SELECT p.id, p.suzerain_id, c.depth + 1
        FROM profiles p JOIN chain c ON p.id = c.suzerain_id
    )
    SELECT MAX(depth) INTO v_chain_depth FROM chain;

    IF v_chain_depth IS NULL THEN v_chain_depth := 0; END IF;

    -- Get direct vassals
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', v.id,
        'username', v.username,
        'faith', v.faith
    )), '[]'::jsonb), COUNT(*)::INT
    INTO v_vassals, v_vassal_count
    FROM profiles v WHERE v.suzerain_id = v_user_id;

    -- Check divine shield
    SELECT (divine_shield_until IS NOT NULL AND divine_shield_until > now()) INTO v_is_protected
    FROM profiles WHERE id = v_user_id;

    -- Calculate estimated daily tithes from vassals
    SELECT value INTO v_tithe_pct FROM game_config WHERE key = 'tithe.percentage';
    IF v_tithe_pct IS NULL THEN v_tithe_pct := 0.10; END IF;

    WITH vassal_production AS (
        SELECT
            vp.user_id,
            COALESCE(SUM(
                CASE WHEN gc_mana.value IS NOT NULL THEN gc_mana.value ELSE 0 END
            ), 0)::NUMERIC AS vassal_mana_per_day,
            COALESCE(SUM(
                CASE WHEN gc_gold.value IS NOT NULL THEN gc_gold.value ELSE 0 END
            ), 0)::NUMERIC AS vassal_gold_per_day,
            COALESCE(SUM(
                CASE WHEN gc_food.value IS NOT NULL THEN gc_food.value ELSE 0 END
            ), 0)::NUMERIC AS vassal_food_per_day
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

    RETURN jsonb_build_object(
        'suzerain', v_suzerain,
        'vassals', COALESCE(v_vassals, '[]'::jsonb),
        'vassal_count', v_vassal_count,
        'daily_tithes', v_daily_tithes,
        'is_protected', COALESCE(v_is_protected, false),
        'chain_depth', v_chain_depth
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 13. CREATE: get_akashic_logs()
-- ============================================

CREATE OR REPLACE FUNCTION public.get_akashic_logs(
    p_limit INT DEFAULT 50,
    p_offset INT DEFAULT 0
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_result JSONB;
BEGIN
    -- Return logs where user is either actor or target
    -- For plagues, actor_id is NULL so only target sees them
    SELECT jsonb_agg(row_to_json(t)) INTO v_result
    FROM (
        SELECT
            al.id,
            al.action_type,
            al.result_data,
            al.created_at,
            al.actor_id,
            al.target_id,
            actor.username AS actor_username,
            target.username AS target_username
        FROM akashic_logs al
        LEFT JOIN profiles actor ON actor.id = al.actor_id
        JOIN profiles target ON target.id = al.target_id
        WHERE al.actor_id = v_user_id OR al.target_id = v_user_id
        ORDER BY al.created_at DESC
        LIMIT p_limit OFFSET p_offset
    ) t;

    RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 14. GRANT PERMISSIONS
-- ============================================

-- Akashic logs: read for authenticated, insert via SECURITY DEFINER only
GRANT SELECT ON TABLE akashic_logs TO authenticated;
GRANT SELECT ON TABLE akashic_logs TO anon;
GRANT ALL ON TABLE akashic_logs TO service_role;

-- Profiles: allow reading suzerain_id, heresy, etc. via existing policies
-- (Existing RLS on profiles should already allow authenticated users to read)

-- RPC permissions
GRANT EXECUTE ON FUNCTION launch_crusade(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION launch_crusade(UUID) TO service_role;

GRANT EXECUTE ON FUNCTION declare_schism() TO authenticated;
GRANT EXECUTE ON FUNCTION declare_schism() TO service_role;

GRANT EXECUTE ON FUNCTION cast_plague(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION cast_plague(UUID) TO service_role;

GRANT EXECUTE ON FUNCTION get_vassalage_info() TO authenticated;
GRANT EXECUTE ON FUNCTION get_vassalage_info() TO service_role;

GRANT EXECUTE ON FUNCTION get_akashic_logs(INT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_akashic_logs(INT, INT) TO service_role;

-- Re-grant permissions on modified functions
GRANT EXECUTE ON FUNCTION get_player_economy() TO authenticated;
GRANT EXECUTE ON FUNCTION get_player_economy() TO service_role;

GRANT EXECUTE ON FUNCTION purchase_shop_item(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION purchase_shop_item(TEXT) TO service_role;

GRANT EXECUTE ON FUNCTION calculate_automated_karma() TO service_role;

-- ============================================
-- 15. VERIFY CRON JOB IS STILL SCHEDULED
-- ============================================

-- The cron job calls calculate_automated_karma() which we just replaced.
-- Verify it is still scheduled (it should be from the previous migration).
DO $$
DECLARE
    v_jobid BIGINT;
    v_count INT;
BEGIN
    -- Check if the cron job exists
    SELECT COUNT(*) INTO v_count FROM cron.job WHERE jobname = 'prayer-heartbeat';
    IF v_count = 0 THEN
        -- Reschedule if missing
        PERFORM cron.schedule('prayer-heartbeat', '* * * * *', 'SELECT calculate_automated_karma()');
    END IF;
END $$;