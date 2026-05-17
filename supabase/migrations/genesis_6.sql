-- =====================================================
-- ELECTRIC MONK — GENESIS 6: Sect Rename, PFP, Username Change
-- Date: 2026-05-17
--
-- Tactical patch for the Rapture Subsequent update:
--   1. Rename sect internal keys to custom nomenclature
--   2. Add PFP (profile picture) schema columns
--   3. Add username uniqueness constraint
--   4. Create change_username RPC function
--   5. Update all affected functions with new sect keys
--
-- Run AFTER genesis_5.sql.
-- This script is idempotent where possible.
-- DO NOT USE EMOJIS IN CODE OR DEBUG LOGS.
-- =====================================================

-- ============================================
-- PHASE 1: DROP OLD CHECK CONSTRAINTS
-- ============================================
-- PostgreSQL auto-generates constraint names from CHECK expressions.
-- We use a DO block to find and drop them dynamically.

DO $$
DECLARE
    v_constraint_name TEXT;
BEGIN
    -- Drop sect_type CHECK on profiles
    SELECT con.conname INTO v_constraint_name
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
    WHERE rel.relname = 'profiles'
      AND nsp.nspname = 'public'
      AND con.contype = 'c'
      AND pg_get_constraintdef(con.oid) LIKE '%prosperity_gospel%';
    IF v_constraint_name IS NOT NULL THEN
        EXECUTE format('ALTER TABLE public.profiles DROP CONSTRAINT %I', v_constraint_name);
    END IF;

    -- Drop sect_restriction CHECK on shop_items
    SELECT con.conname INTO v_constraint_name
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
    WHERE rel.relname = 'shop_items'
      AND nsp.nspname = 'public'
      AND con.contype = 'c'
      AND pg_get_constraintdef(con.oid) LIKE '%prosperity_gospel%';
    IF v_constraint_name IS NOT NULL THEN
        EXECUTE format('ALTER TABLE public.shop_items DROP CONSTRAINT %I', v_constraint_name);
    END IF;

    -- Drop sect_exclusion CHECK on shop_items (second constraint)
    SELECT con.conname INTO v_constraint_name
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
    WHERE rel.relname = 'shop_items'
      AND nsp.nspname = 'public'
      AND con.contype = 'c'
      AND pg_get_constraintdef(con.oid) LIKE '%sect_exclusion%prosperity_gospel%';
    IF v_constraint_name IS NOT NULL THEN
        EXECUTE format('ALTER TABLE public.shop_items DROP CONSTRAINT %I', v_constraint_name);
    END IF;
END $$;

-- ============================================
-- PHASE 2: MIGRATE SECT DATA
-- ============================================

-- profiles.sect_type
UPDATE public.profiles
SET sect_type = CASE sect_type
    WHEN 'prosperity_gospel' THEN 'gilded_path'
    WHEN 'ascetic_order' THEN 'holy_way'
    WHEN 'doomsday_preppers' THEN 'final_watch'
    WHEN 'inquisition' THEN 'black_tribunal'
    ELSE sect_type
END
WHERE sect_type IN ('prosperity_gospel', 'ascetic_order', 'doomsday_preppers', 'inquisition');

-- shop_items.sect_restriction
UPDATE public.shop_items
SET sect_restriction = CASE sect_restriction
    WHEN 'prosperity_gospel' THEN 'gilded_path'
    WHEN 'ascetic_order' THEN 'holy_way'
    WHEN 'doomsday_preppers' THEN 'final_watch'
    WHEN 'inquisition' THEN 'black_tribunal'
    ELSE sect_restriction
END
WHERE sect_restriction IN ('prosperity_gospel', 'ascetic_order', 'doomsday_preppers', 'inquisition');

-- shop_items.sect_exclusion
UPDATE public.shop_items
SET sect_exclusion = CASE sect_exclusion
    WHEN 'prosperity_gospel' THEN 'gilded_path'
    WHEN 'ascetic_order' THEN 'holy_way'
    WHEN 'doomsday_preppers' THEN 'final_watch'
    WHEN 'inquisition' THEN 'black_tribunal'
    ELSE sect_exclusion
END
WHERE sect_exclusion IN ('prosperity_gospel', 'ascetic_order', 'doomsday_preppers', 'inquisition');

-- game_config keys with sect prefix
UPDATE public.game_config SET key = REPLACE(key, 'sect.prosperity_gospel.', 'sect.gilded_path.') WHERE key LIKE 'sect.prosperity_gospel.%';
UPDATE public.game_config SET key = REPLACE(key, 'sect.ascetic_order.', 'sect.holy_way.') WHERE key LIKE 'sect.ascetic_order.%';
UPDATE public.game_config SET key = REPLACE(key, 'sect.doomsday_preppers.', 'sect.final_watch.') WHERE key LIKE 'sect.doomsday_preppers.%';
UPDATE public.game_config SET key = REPLACE(key, 'sect.inquisition.', 'sect.black_tribunal.') WHERE key LIKE 'sect.inquisition.%';

-- ============================================
-- PHASE 3: ADD NEW CHECK CONSTRAINTS
-- ============================================

-- Drop any remaining constraints on these columns (handles edge cases
-- where Phase 1's dynamic drop didn't catch them all)
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_sect_type_check;
ALTER TABLE public.shop_items DROP CONSTRAINT IF EXISTS shop_items_sect_restriction_check;
ALTER TABLE public.shop_items DROP CONSTRAINT IF EXISTS shop_items_sect_exclusion_check;

ALTER TABLE public.profiles ADD CONSTRAINT profiles_sect_type_check
    CHECK (sect_type IS NULL OR sect_type IN ('gilded_path', 'holy_way', 'final_watch', 'black_tribunal'));

ALTER TABLE public.shop_items ADD CONSTRAINT shop_items_sect_restriction_check
    CHECK (sect_restriction IS NULL OR sect_restriction IN ('gilded_path', 'holy_way', 'final_watch', 'black_tribunal'));

ALTER TABLE public.shop_items ADD CONSTRAINT shop_items_sect_exclusion_check
    CHECK (sect_exclusion IS NULL OR sect_exclusion IN ('gilded_path', 'holy_way', 'final_watch', 'black_tribunal'));

-- ============================================
-- PHASE 4: PFP SCHEMA COLUMNS
-- ============================================

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS pfp_index INT DEFAULT 0;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS unlocked_pfps JSONB DEFAULT '[0]'::jsonb;

-- ============================================
-- PHASE 5: USERNAME UNIQUE CONSTRAINT
-- ============================================

-- Create unique index on username, allowing NULLs (multiple users may have no username yet)
CREATE UNIQUE INDEX IF NOT EXISTS profiles_username_unique ON public.profiles (username) WHERE username IS NOT NULL;

-- ============================================
-- PHASE 6: change_username RPC FUNCTION
-- ============================================

CREATE OR REPLACE FUNCTION public.change_username(p_new_username TEXT)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_current_karma INT;
    v_karma_cost INT := 1000;
    v_username_min_length INT := 2;
    v_username_max_length INT := 30;
BEGIN
    -- Validate username length
    IF length(p_new_username) < v_username_min_length OR length(p_new_username) > v_username_max_length THEN
        RAISE EXCEPTION 'Username must be between % and % characters.', v_username_min_length, v_username_max_length;
    END IF;

    -- Validate username format (alphanumeric, underscores, hyphens only)
    IF p_new_username !~ '^[a-zA-Z0-9_-]+$' THEN
        RAISE EXCEPTION 'Username can only contain letters, numbers, underscores, and hyphens.';
    END IF;

    -- Check if username is already taken
    IF EXISTS (SELECT 1 FROM public.profiles WHERE username = p_new_username AND id != v_user_id) THEN
        RAISE EXCEPTION 'This username already exists!';
    END IF;

    -- Check karma balance
    SELECT COALESCE(karma, 0) INTO v_current_karma FROM public.profiles WHERE id = v_user_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Profile not found';
    END IF;

    IF v_current_karma < v_karma_cost THEN
        RAISE EXCEPTION 'Insufficient Karma. You need % Karma to change your username. You have %.', v_karma_cost, v_current_karma;
    END IF;

    -- Deduct karma and update username
    UPDATE public.profiles
    SET username = p_new_username,
        karma = karma - v_karma_cost,
        updated_at = now()
    WHERE id = v_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'new_username', p_new_username,
        'karma_spent', v_karma_cost,
        'karma_remaining', v_current_karma - v_karma_cost
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- PHASE 7: UPDATE AFFECTED FUNCTIONS WITH NEW SECT KEYS
-- ============================================

-- 7a. Update choose_sect() with new sect names
CREATE OR REPLACE FUNCTION public.choose_sect(p_sect_type TEXT)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_current_sect TEXT;
BEGIN
    IF p_sect_type NOT IN ('gilded_path', 'holy_way', 'final_watch', 'black_tribunal') THEN
        RAISE EXCEPTION 'Invalid sect type. Must be one of: gilded_path, holy_way, final_watch, black_tribunal';
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

-- 7b. Update launch_inquisition() with new sect name
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
    IF v_sect_type = 'black_tribunal' THEN
        SELECT value INTO v_cost_multiplier FROM game_config WHERE key = 'sect.black_tribunal.inquisition_gold_cost_multiplier';
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

-- 7c. Update launch_crusade() with new sect name for doomsday_preppers -> final_watch
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

    -- Check target is not shielded
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

    -- Apply Final Watch defense bonus (was doomsday_preppers)
    IF v_target_sect = 'final_watch' THEN
        SELECT COALESCE(value, 0.5) INTO v_sect_defense_bonus FROM game_config WHERE key = 'sect.final_watch.crusade_defense_bonus';
        v_defense_rating := v_defense_rating * (1 + v_sect_defense_bonus);
    END IF;

    -- Apply research bonuses (Holy War research: +15% attack)
    IF EXISTS (
        SELECT 1 FROM player_research pr
        JOIN research_nodes rn ON rn.id = pr.node_id
        WHERE pr.user_id = v_attacker_id AND rn.effect_type = 'crusade_attack_bonus'
          AND (pr.expires_at IS NULL OR pr.expires_at > now())
    ) THEN
        v_attack_rating := v_attack_rating * 1.15;
    END IF;

    -- Apply relic bonuses
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

        -- LIFO Ruin Check
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

-- 7d. Update calculate_automated_karma() with new sect names
-- This is the full 8-phase heartbeat function with updated sect key references
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
    -- PHASE 1: KARMA MILESTONE LOGIC
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
            COALESCE(SUM(CASE WHEN gc_food.value IS NOT NULL THEN gc_food.value ELSE 0 END), 0)::NUMERIC AS gross_food_per_day,
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
    -- Apply sect modifiers to production (UPDATED SECT KEYS)
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
                WHEN ap.sect_type = 'gilded_path' THEN ap.gross_mana_per_day * COALESCE((SELECT value FROM game_config WHERE key = 'sect.gilded_path.mana_multiplier'), 0.8)
                WHEN ap.sect_type = 'holy_way' THEN ap.gross_mana_per_day * COALESCE((SELECT value FROM game_config WHERE key = 'sect.holy_way.mana_multiplier'), 1.2)
                WHEN ap.sect_type = 'black_tribunal' THEN ap.gross_mana_per_day * COALESCE((SELECT value FROM game_config WHERE key = 'sect.black_tribunal.mana_multiplier'), 0.7)
                ELSE ap.gross_mana_per_day
            END AS modified_mana_per_day,
            -- Gold with sect multiplier
            CASE
                WHEN ap.sect_type = 'gilded_path' THEN ap.gross_gold_per_day * COALESCE((SELECT value FROM game_config WHERE key = 'sect.gilded_path.gold_multiplier'), 1.5)
                WHEN ap.sect_type = 'final_watch' THEN ap.gross_gold_per_day * COALESCE((SELECT value FROM game_config WHERE key = 'sect.final_watch.gold_multiplier'), 0.75)
                ELSE ap.gross_gold_per_day
            END AS modified_gold_per_day,
            -- Food with sect multiplier
            CASE
                WHEN ap.sect_type = 'final_watch' THEN ap.gross_food_per_day * COALESCE((SELECT value FROM game_config WHERE key = 'sect.final_watch.food_multiplier'), 1.5)
                ELSE ap.gross_food_per_day
            END AS modified_food_per_day,
            -- Gold upkeep with sect multiplier
            CASE
                WHEN ap.sect_type = 'gilded_path' THEN (ap.total_gold_upkeep_per_day + ap.total_coven_gold_upkeep_per_day) * COALESCE((SELECT value FROM game_config WHERE key = 'sect.gilded_path.cathedral_upkeep_multiplier'), 2.0)
                ELSE ap.total_gold_upkeep_per_day + ap.total_coven_gold_upkeep_per_day
            END AS modified_gold_upkeep_per_day,
            -- Food consumption with sect multiplier
            CASE
                WHEN ap.sect_type = 'holy_way' THEN ap.total_food_consumption_per_day * COALESCE((SELECT value FROM game_config WHERE key = 'sect.holy_way.food_consumption_multiplier'), 0.5)
                ELSE ap.total_food_consumption_per_day + ap.total_heresy_food_consume_per_day
            END AS modified_food_consumption_per_day,
            -- Heresy with sect multiplier
            CASE
                WHEN ap.sect_type = 'black_tribunal' THEN ap.gross_heresy_per_day * COALESCE((SELECT value FROM game_config WHERE key = 'sect.black_tribunal.heresy_multiplier'), 2.0)
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
    UPDATE synods s SET
        vault_gold = vault_gold + COALESCE((SELECT SUM(st.gold_synod_tax_tick) FROM synod_tax st WHERE st.synod_id = s.id GROUP BY st.synod_id), 0),
        vault_mana = vault_mana + COALESCE((SELECT SUM(st.mana_synod_tax_tick) FROM synod_tax st WHERE st.synod_id = s.id GROUP BY st.synod_id), 0)
    WHERE s.id IN (SELECT DISTINCT synod_id FROM synod_tax WHERE synod_id IS NOT NULL);

    -- ========================================
    -- PHASE 4: EXPIRE TIMED EFFECTS
    -- ========================================
    DELETE FROM active_miracles WHERE expires_at < now();
    DELETE FROM player_research WHERE expires_at IS NOT NULL AND expires_at < now();
    UPDATE synod_wars SET is_active = false WHERE is_active = true AND expires_at < now();
    UPDATE profiles SET papal_bull_until = NULL WHERE papal_bull_until IS NOT NULL AND papal_bull_until < now();
    UPDATE profiles SET divine_shield_until = NULL WHERE divine_shield_until IS NOT NULL AND divine_shield_until < now();

    -- ========================================
    -- PHASE 5: PROCESS DIVINE ARCHITECT QUEUE
    -- ========================================
    FOR r IN
        SELECT bq.*, si.karma_cost, si.gold_cost, si.heresy_cost, si.effect_type, si.effect_data, si.acre_cost, si.cost_scaling
        FROM build_queue bq
        JOIN shop_items si ON si.id = bq.item_id
        WHERE bq.executed_at IS NULL AND bq.auto_execute = true
    LOOP
        DECLARE
            v_bq_user_karma INT;
            v_bq_user_gold INT;
            v_bq_user_heresy INT;
        BEGIN
            SELECT karma, gold, heresy INTO v_bq_user_karma, v_bq_user_gold, v_bq_user_heresy
            FROM profiles WHERE id = r.user_id;

            IF v_bq_user_karma >= r.karma_cost AND v_bq_user_gold >= r.gold_cost AND v_bq_user_heresy >= r.heresy_cost THEN
                BEGIN
                    PERFORM purchase_shop_item(r.item_id);
                    UPDATE build_queue SET executed_at = now() WHERE id = r.id;
                EXCEPTION WHEN OTHERS THEN
                    NULL;
                END;
            END IF;
        END;
    END LOOP;

    -- Clean up executed queue items older than 7 days
    DELETE FROM build_queue WHERE executed_at IS NOT NULL AND executed_at < now() - interval '7 days';

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7e. Update get_sect_info() — no changes needed, it uses dynamic key lookup
-- (already uses gc.key LIKE 'sect.' || v_sect_type || '.%' so it works with any prefix)

-- 7f. Update purchase_shop_item() — sect_restriction and sect_exclusion are read from
-- shop_items table data, which we already migrated in Phase 2. The function compares
-- v_item.sect_restriction and v_item.sect_exclusion against v_user_sect, which will
-- now contain the new keys. No function changes needed.

-- ============================================
-- PHASE 8: GRANT PERMISSIONS FOR NEW FUNCTION
-- ============================================

GRANT EXECUTE ON FUNCTION change_username(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION change_username(TEXT) TO service_role;

-- ============================================
-- END OF GENESIS 6
-- =====================================================