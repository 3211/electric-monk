-- =====================================================
-- ELECTRIC MONK — GENESIS 9: Synod Membership Fix, Roles & Synod-Wide Relic Buffs
-- Date: 2026-05-17
--
-- Fixes:
--   1. Synod membership persistence (backend was fine; frontend never re-fetched on auth)
--   2. Add synod_role column (leader/officer/member) for member management
--   3. Add name_key unique index to prevent case-insensitive duplicate synod names
--   4. Create promote/demote/kick RPCs
--   5. Fix get_relics() holder_name field (was holder_username)
--   6. Create get_synod_relics() helper for synod-wide relic benefit queries
--   7. Update get_synod_info() to return roles and synod_relics
--   8. Update get_player_economy() to include synod_relics
--   9. Update launch_crusade() and cast_plague() to check synod-wide relics
--  10. Update tick function to apply synod-wide relic production multipliers
--
-- Run AFTER genesis_8.sql.
-- This script is idempotent where possible.
-- DO NOT USE EMOJIS IN CODE OR DEBUG LOGS.
-- =====================================================

-- ============================================
-- PHASE 1: SCHEMA CHANGES
-- ============================================

-- 1a. Add synod_role to profiles
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS synod_role TEXT DEFAULT NULL
  CHECK (synod_role IN ('leader', 'officer', 'member') OR synod_role IS NULL);

COMMENT ON COLUMN public.profiles.synod_role IS
  'Role within the synod: leader, officer, or member. NULL when not in a synod.';

-- 1b. Add name_key to synods (case-insensitive unique name)
ALTER TABLE public.synods
  ADD COLUMN IF NOT EXISTS name_key TEXT DEFAULT NULL;

-- Backfill name_key from existing names
UPDATE synods SET name_key = LOWER(name) WHERE name_key IS NULL;

-- Make name_key NOT NULL now that its populated
ALTER TABLE public.synods ALTER COLUMN name_key SET NOT NULL;

-- Create unique index on name_key
CREATE UNIQUE INDEX IF NOT EXISTS synods_name_key_unique ON public.synods(name_key);

-- 1c. Backfill synod_role for existing leaders
UPDATE profiles p
SET synod_role = 'leader'
FROM synods s
WHERE p.synod_id = s.id AND p.id = s.leader_id AND p.synod_role IS NULL;

-- Backfill synod_role for existing members (not leaders)
UPDATE profiles p
SET synod_role = 'member'
FROM synods s
WHERE p.synod_id = s.id AND p.id != s.leader_id AND p.synod_role IS NULL;

-- 1d. Add power_level and steal_cost columns to relics if missing
-- (The frontend references these but they may not exist in the table yet)
ALTER TABLE public.relics
  ADD COLUMN IF NOT EXISTS power_level INT DEFAULT 1;
ALTER TABLE public.relics
  ADD COLUMN IF NOT EXISTS steal_cost INT DEFAULT 50;

-- ============================================
-- PHASE 2: UPDATED RPCs — create_synod, join_synod, leave_synod
-- ============================================

-- 2a. Update create_synod: set name_key and synod_role
CREATE OR REPLACE FUNCTION public.create_synod(p_name TEXT)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_user_gold INT;
    v_creation_cost NUMERIC;
    v_existing_synod UUID;
    v_new_synod_id UUID;
    v_name_key TEXT;
BEGIN
    -- Check name length
    IF LENGTH(p_name) < 3 OR LENGTH(p_name) > 30 THEN
        RAISE EXCEPTION 'Synod name must be between 3 and 30 characters';
    END IF;

    -- Compute name_key for case-insensitive uniqueness
    v_name_key := LOWER(p_name);

    -- Check user not already in a synod
    SELECT synod_id INTO v_existing_synod FROM profiles WHERE id = v_user_id;
    IF v_existing_synod IS NOT NULL THEN
        RAISE EXCEPTION 'You are already in a Synod. Leave your current Synod first.';
    END IF;

    -- Check name_key uniqueness (gives better error than UNIQUE constraint violation)
    IF EXISTS (SELECT 1 FROM synods WHERE name_key = v_name_key) THEN
        RAISE EXCEPTION 'A Synod with that name already exists (case-insensitive).';
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

    -- Create synod with name_key
    INSERT INTO synods (name, name_key, leader_id, tax_rate)
    VALUES (p_name, v_name_key, v_user_id, 0.05)
    RETURNING id INTO v_new_synod_id;

    -- Set user's synod_id and synod_role
    UPDATE profiles SET synod_role = 'leader', synod_id = v_new_synod_id, updated_at = now() WHERE id = v_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'synod_id', v_new_synod_id,
        'name', p_name,
        'gold_spent', v_creation_cost
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2b. Update join_synod: set synod_role = 'member'
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

    -- Join with member role
    UPDATE profiles SET synod_id = p_synod_id, synod_role = 'member', updated_at = now() WHERE id = v_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'synod_id', p_synod_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2c. Update leave_synod: clear synod_role, handle role succession
CREATE OR REPLACE FUNCTION public.leave_synod()
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_synod_id UUID;
    v_is_leader BOOLEAN;
    v_member_count INT;
    v_oldest_member_id UUID;
    v_oldest_role TEXT;
BEGIN
    SELECT synod_id INTO v_synod_id FROM profiles WHERE id = v_user_id;
    IF v_synod_id IS NULL THEN
        RAISE EXCEPTION 'You are not in a Synod';
    END IF;

    -- Check if leader
    SELECT (leader_id = v_user_id), id INTO v_is_leader, v_synod_id
    FROM synods WHERE id = v_synod_id;

    -- Remove user from synod
    UPDATE profiles SET synod_id = NULL, synod_role = NULL, updated_at = now() WHERE id = v_user_id;

    -- If leader, handle succession
    IF v_is_leader THEN
        -- Try to promote the highest role member (officer first, then member by seniority)
        SELECT id INTO v_oldest_member_id
        FROM profiles
        WHERE synod_id = v_synod_id
        ORDER BY
            CASE synod_role
                WHEN 'officer' THEN 0
                WHEN 'member' THEN 1
                ELSE 2
            END ASC,
            created_at ASC
        LIMIT 1;

        IF v_oldest_member_id IS NOT NULL THEN
            -- Promote new leader
            UPDATE synods SET leader_id = v_oldest_member_id WHERE id = v_synod_id;
            UPDATE profiles SET synod_role = 'leader', updated_at = now() WHERE id = v_oldest_member_id;
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
-- PHASE 3: NEW RPCs — promote, demote, kick
-- ============================================

-- 3a. Promote a synod member
CREATE OR REPLACE FUNCTION public.promote_synod_member(p_target_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_user_synod_id UUID;
    v_user_role TEXT;
    v_target_synod_id UUID;
    v_target_role TEXT;
    v_current_leader_id UUID;
BEGIN
    -- Get caller info
    SELECT synod_id, synod_role INTO v_user_synod_id, v_user_role
    FROM profiles WHERE id = v_user_id;
    IF v_user_synod_id IS NULL THEN
        RAISE EXCEPTION 'You are not in a Synod';
    END IF;
    IF v_user_role != 'leader' THEN
        RAISE EXCEPTION 'Only the leader can promote members';
    END IF;

    -- Get target info
    SELECT synod_id, synod_role INTO v_target_synod_id, v_target_role
    FROM profiles WHERE id = p_target_id;
    IF v_target_synod_id IS NULL OR v_target_synod_id != v_user_synod_id THEN
        RAISE EXCEPTION 'Target is not in your Synod';
    END IF;

    -- Promote based on current role
    IF v_target_role = 'member' THEN
        UPDATE profiles SET synod_role = 'officer', updated_at = now() WHERE id = p_target_id;
        RETURN jsonb_build_object('success', true, 'new_role', 'officer');
    ELSIF v_target_role = 'officer' THEN
        -- Transferring leadership: caller becomes officer, target becomes leader
        UPDATE profiles SET synod_role = 'leader', updated_at = now() WHERE id = p_target_id;
        UPDATE profiles SET synod_role = 'officer', updated_at = now() WHERE id = v_user_id;
        UPDATE synods SET leader_id = p_target_id WHERE id = v_user_synod_id;
        RETURN jsonb_build_object('success', true, 'new_role', 'leader', 'transferred', true);
    ELSIF v_target_role = 'leader' THEN
        RAISE EXCEPTION 'Target is already the leader';
    ELSE
        RAISE EXCEPTION 'Target has no role (not in synod)';
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3b. Demote a synod member
CREATE OR REPLACE FUNCTION public.demote_synod_member(p_target_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_user_synod_id UUID;
    v_user_role TEXT;
    v_target_synod_id UUID;
    v_target_role TEXT;
BEGIN
    -- Get caller info
    SELECT synod_id, synod_role INTO v_user_synod_id, v_user_role
    FROM profiles WHERE id = v_user_id;
    IF v_user_synod_id IS NULL THEN
        RAISE EXCEPTION 'You are not in a Synod';
    END IF;
    IF v_user_role != 'leader' THEN
        RAISE EXCEPTION 'Only the leader can demote members';
    END IF;

    -- Get target info
    SELECT synod_id, synod_role INTO v_target_synod_id, v_target_role
    FROM profiles WHERE id = p_target_id;
    IF v_target_synod_id IS NULL OR v_target_synod_id != v_user_synod_id THEN
        RAISE EXCEPTION 'Target is not in your Synod';
    END IF;

    -- Cannot demote yourself (use leave/transfer instead)
    IF p_target_id = v_user_id THEN
        RAISE EXCEPTION 'Cannot demote yourself. Transfer leadership instead.';
    END IF;

    -- Demote based on current role
    IF v_target_role = 'officer' THEN
        UPDATE profiles SET synod_role = 'member', updated_at = now() WHERE id = p_target_id;
        RETURN jsonb_build_object('success', true, 'new_role', 'member');
    ELSIF v_target_role = 'leader' THEN
        RAISE EXCEPTION 'Cannot demote the leader. Transfer leadership instead.';
    ELSE
        RAISE EXCEPTION 'Target is already a member';
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3c. Kick a synod member
CREATE OR REPLACE FUNCTION public.kick_synod_member(p_target_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_user_synod_id UUID;
    v_user_role TEXT;
    v_target_synod_id UUID;
    v_target_role TEXT;
BEGIN
    -- Get caller info
    SELECT synod_id, synod_role INTO v_user_synod_id, v_user_role
    FROM profiles WHERE id = v_user_id;
    IF v_user_synod_id IS NULL THEN
        RAISE EXCEPTION 'You are not in a Synod';
    END IF;

    -- Get target info
    SELECT synod_id, synod_role INTO v_target_synod_id, v_target_role
    FROM profiles WHERE id = p_target_id;
    IF v_target_synod_id IS NULL OR v_target_synod_id != v_user_synod_id THEN
        RAISE EXCEPTION 'Target is not in your Synod';
    END IF;

    -- Cannot kick yourself
    IF p_target_id = v_user_id THEN
        RAISE EXCEPTION 'Cannot kick yourself. Use leave_synod instead.';
    END IF;

    -- Check permissions: leaders can kick anyone, officers can kick members only
    IF v_user_role = 'officer' THEN
        IF v_target_role IN ('leader', 'officer') THEN
            RAISE EXCEPTION 'Officers cannot kick leaders or other officers';
        END IF;
    ELSIF v_user_role = 'member' THEN
        RAISE EXCEPTION 'Members cannot kick other members';
    ELSIF v_user_role != 'leader' THEN
        RAISE EXCEPTION 'You do not have permission to kick members';
    END IF;

    -- Remove target from synod
    UPDATE profiles SET synod_id = NULL, synod_role = NULL, updated_at = now() WHERE id = p_target_id;

    RETURN jsonb_build_object('success', true, 'kicked_user_id', p_target_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- PHASE 4: HELPER FUNCTION — get_synod_relics
-- ============================================

CREATE OR REPLACE FUNCTION public.get_synod_relics(p_user_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_synod_id UUID;
    v_relics JSONB;
BEGIN
    SELECT synod_id INTO v_synod_id FROM profiles WHERE id = p_user_id;

    IF v_synod_id IS NULL THEN
        -- Not in a synod: return only own relics
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'id', r.id,
            'name', r.name,
            'effect_type', r.effect_type,
            'effect_data', r.effect_data,
            'holder_id', r.holder_id,
            'holder_name', p.username
        )), '[]'::jsonb) INTO v_relics
        FROM relics r
        LEFT JOIN profiles p ON p.id = r.holder_id
        WHERE r.holder_id = p_user_id AND r.is_active = true;
    ELSE
        -- In a synod: return all relics held by synod members
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'id', r.id,
            'name', r.name,
            'effect_type', r.effect_type,
            'effect_data', r.effect_data,
            'holder_id', r.holder_id,
            'holder_name', p.username
        )), '[]'::jsonb) INTO v_relics
        FROM relics r
        JOIN profiles p ON p.id = r.holder_id
        WHERE p.synod_id = v_synod_id AND r.is_active = true;
    END IF;

    RETURN COALESCE(v_relics, '[]'::jsonb);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- PHASE 5: UPDATED RPC — get_synod_info (with roles + synod_relics)
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
    v_synod_relics JSONB;
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

    -- Get members with roles
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'user_id', p.id,
        'username', p.username,
        'faith', p.faith,
        'sect_type', p.sect_type,
        'role', COALESCE(p.synod_role, 'member'),
        'joined_at', p.created_at
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

    -- Get synod-wide relics
    v_synod_relics := public.get_synod_relics(v_user_id);

    RETURN jsonb_build_object(
        'in_synod', true,
        'synod', v_synod,
        'members', v_members,
        'member_count', v_member_count,
        'wars', v_wars,
        'synod_relics', v_synod_relics
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- PHASE 6: FIX get_relics() — holder_name + icon + captured_at
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
        'icon', r.emoji_icon,
        'effect_type', r.effect_type,
        'effect_data', r.effect_data,
        'power_level', r.power_level,
        'steal_cost', r.steal_cost,
        'holder_id', r.holder_id,
        'holder_name', p.username,
        'steal_progress', r.steal_progress,
        'captured_at', r.last_stolen_at
    )), '[]'::jsonb) INTO v_result
    FROM relics r
    LEFT JOIN profiles p ON p.id = r.holder_id
    WHERE r.is_active = true;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- PHASE 7: UPDATE get_player_economy() — add synod_relics
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
    v_synod_relics JSONB;
    v_used_acres INT;
    v_dogma_per_day NUMERIC;
    v_dogma_cap NUMERIC;
    v_dogma_multiplier NUMERIC;
    v_papal_bull_active BOOLEAN;
    v_active_miracles JSONB;
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
    FROM user_buildings;

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

    -- Get held relics (personal)
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

    -- Get synod-wide relics (includes own relics if not in a synod)
    v_synod_relics := public.get_synod_relics(v_user_id);

    -- Calculate used acres
    SELECT COALESCE(SUM(COALESCE((SELECT value FROM game_config WHERE key = 'building.' || pb.building_type || '.acre_cost'), 0)), 0)::INT
    INTO v_used_acres
    FROM player_buildings pb
    WHERE pb.user_id = v_user_id AND pb.is_active = true;

    -- Check papal bull
    v_papal_bull_active := v_profile.papal_bull_until IS NOT NULL AND v_profile.papal_bull_until > now();

    -- Get active miracles/buffs
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', am.id,
        'miracle_type', am.miracle_type,
        'effect_data', am.effect_data,
        'expires_at', am.expires_at
    )), '[]'::jsonb) INTO v_active_miracles
    FROM active_miracles am
    WHERE am.user_id = v_user_id AND am.expires_at > now();

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
        'synod', v_synod_info,
        'synod_relics', v_synod_relics,
        'active_miracles', v_active_miracles
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- PHASE 8: UPDATE launch_crusade() — synod-wide relic checks
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

    -- Apply Final Watch defense bonus
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

    -- Apply relic bonuses (SYNOD-WIDE: check if ANY synod member holds the relic)
    v_relic_attack_bonus := 0;

    -- Check attacker's synod for mana_double relic (does not affect combat directly, but we check for completeness)
    IF v_attacker_synod IS NOT NULL THEN
        IF EXISTS (
            SELECT 1 FROM relics r
            JOIN profiles p ON p.id = r.holder_id AND r.is_active = true
            WHERE p.synod_id = v_attacker_synod AND r.effect_type = 'mana_double'
        ) THEN
            v_relic_attack_bonus := v_relic_attack_bonus + 0;  -- Mana double doesn't affect combat
        END IF;
    ELSE
        -- Not in synod: check individual relics only
        IF EXISTS (
            SELECT 1 FROM relics r WHERE r.holder_id = v_attacker_id AND r.effect_type = 'mana_double' AND r.is_active = true
        ) THEN
            v_relic_attack_bonus := v_relic_attack_bonus + 0;
        END IF;
    END IF;

    v_relic_defense_bonus := 0;
    -- Check target's synod for crusade_defense_bonus relic
    IF v_target_synod IS NOT NULL THEN
        IF EXISTS (
            SELECT 1 FROM relics r
            JOIN profiles p ON p.id = r.holder_id AND r.is_active = true
            WHERE p.synod_id = v_target_synod AND r.effect_type = 'crusade_defense_bonus'
        ) THEN
            v_relic_defense_bonus := v_relic_defense_bonus + 0.50;
        END IF;
    ELSE
        -- Not in synod: check individual relics only
        IF EXISTS (
            SELECT 1 FROM relics r WHERE r.holder_id = p_target_id AND r.effect_type = 'crusade_defense_bonus' AND r.is_active = true
        ) THEN
            v_relic_defense_bonus := v_relic_defense_bonus + 0.50;
        END IF;
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
        'acres_stolen', CASE WHEN v_success THEN v_acres_stolen ELSE 0 END,
        'holy_war_bonus', v_holy_war_bonus
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- PHASE 9: UPDATE cast_plague() — synod-wide plague immunity
-- ============================================

CREATE OR REPLACE FUNCTION public.cast_plague(p_target_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_caster_id UUID := auth.uid();
    v_heresy INT;
    v_heresy_cost NUMERIC;
    v_target_food INT;
    v_target_shield TIMESTAMPTZ;
    v_target_papal_bull TIMESTAMPTZ;
    v_target_synod_id UUID;
    v_has_plague_immunity BOOLEAN;
BEGIN
    -- Cannot plague yourself
    IF p_target_id = v_caster_id THEN
        RAISE EXCEPTION 'Cannot cast a curse on yourself';
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

    -- Get target info: food, shield, papal bull, synod_id
    SELECT food, divine_shield_until, papal_bull_until, synod_id
    INTO v_target_food, v_target_shield, v_target_papal_bull, v_target_synod_id
    FROM profiles WHERE id = p_target_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Target not found'; END IF;

    -- Check target is not shielded (Divine Shield)
    IF v_target_shield IS NOT NULL AND v_target_shield > now() THEN
        RAISE EXCEPTION 'Target is protected by Divine Shield until %.', v_target_shield;
    END IF;

    -- Check target is not protected by Papal Bull
    IF v_target_papal_bull IS NOT NULL AND v_target_papal_bull > now() THEN
        RAISE EXCEPTION 'Target is protected by Papal Bull until %.', v_target_papal_bull;
    END IF;

    -- Check synod-wide plague immunity (if target is in a synod, ANY member's relic protects all)
    v_has_plague_immunity := false;
    IF v_target_synod_id IS NOT NULL THEN
        -- Target is in a synod: check if ANY synod member holds the plague_immunity relic
        IF EXISTS (
            SELECT 1 FROM relics r
            JOIN profiles p ON p.id = r.holder_id AND r.is_active = true
            WHERE p.synod_id = v_target_synod_id AND r.effect_type = 'plague_immunity'
        ) THEN
            v_has_plague_immunity := true;
        END IF;
    ELSE
        -- Not in a synod: check individual relics only
        IF EXISTS (
            SELECT 1 FROM relics r WHERE r.holder_id = p_target_id AND r.effect_type = 'plague_immunity' AND r.is_active = true
        ) THEN
            v_has_plague_immunity := true;
        END IF;
    END IF;

    IF v_has_plague_immunity THEN
        RAISE EXCEPTION 'Target (or their Synod) is protected by the Sacred Firewall relic';
    END IF;

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
-- PHASE 10: UPDATE tick function — synod-wide relic production multipliers
-- ============================================

CREATE OR REPLACE FUNCTION public.process_game_tick()
RETURNS VOID AS $$
DECLARE
    v_mana_cap_multiplier NUMERIC;
    v_gold_cap_multiplier NUMERIC;
    v_food_cap_multiplier NUMERIC;
    v_heresy_base_cap NUMERIC;
    v_dogma_cap_multiplier NUMERIC;
    v_tithe_pct NUMERIC;
    v_r RECORD;
BEGIN
    -- Load config multipliers
    SELECT COALESCE(value, 10) INTO v_mana_cap_multiplier FROM game_config WHERE key = 'cap.mana_multiplier';
    SELECT COALESCE(value, 10) INTO v_gold_cap_multiplier FROM game_config WHERE key = 'cap.gold_multiplier';
    SELECT COALESCE(value, 10) INTO v_food_cap_multiplier FROM game_config WHERE key = 'cap.food_multiplier';
    SELECT COALESCE(value, 100) INTO v_heresy_base_cap FROM game_config WHERE key = 'cap.heresy_base';
    SELECT COALESCE(value, 10) INTO v_dogma_cap_multiplier FROM game_config WHERE key = 'cap.dogma_multiplier';
    SELECT COALESCE(value, 0.10) INTO v_tithe_pct FROM game_config WHERE key = 'tithe.percentage';

    -- ========================================
    -- PHASE 1: COMPUTE PRODUCTION
    -- ========================================
    WITH all_players AS (
        SELECT
            p.id AS user_id,
            p.mana,
            p.gold,
            p.food,
            p.heresy,
            p.dogma,
            p.sect_type,
            p.sacred_acres,
            p.synod_id,
            p.papal_bull_until,
            p.suzerain_id,
            -- Mana with sect multiplier
            CASE
                WHEN p.sect_type = 'gilded_path' THEN (SELECT COALESCE(SUM(COALESCE((SELECT value FROM game_config WHERE key = 'building.' || pb.building_type || '.mana_per_day'), 0) * (SELECT COUNT(*) FROM player_buildings WHERE user_id = p.id AND building_type = pb.building_type AND is_active = true)), 0) FROM player_buildings pb WHERE pb.user_id = p.id AND pb.is_active = true) * COALESCE((SELECT value FROM game_config WHERE key = 'sect.gilded_path.mana_multiplier'), 0.8)
                WHEN p.sect_type = 'holy_way' THEN (SELECT COALESCE(SUM(COALESCE((SELECT value FROM game_config WHERE key = 'building.' || pb.building_type || '.mana_per_day'), 0) * (SELECT COUNT(*) FROM player_buildings WHERE user_id = p.id AND building_type = pb.building_type AND is_active = true)), 0) FROM player_buildings pb WHERE pb.user_id = p.id AND pb.is_active = true) * COALESCE((SELECT value FROM game_config WHERE key = 'sect.holy_way.mana_multiplier'), 1.2)
                WHEN p.sect_type = 'black_tribunal' THEN (SELECT COALESCE(SUM(COALESCE((SELECT value FROM game_config WHERE key = 'building.' || pb.building_type || '.mana_per_day'), 0) * (SELECT COUNT(*) FROM player_buildings WHERE user_id = p.id AND building_type = pb.building_type AND is_active = true)), 0) FROM player_buildings pb WHERE pb.user_id = p.id AND pb.is_active = true) * COALESCE((SELECT value FROM game_config WHERE key = 'sect.black_tribunal.mana_multiplier'), 0.7)
                ELSE (SELECT COALESCE(SUM(COALESCE((SELECT value FROM game_config WHERE key = 'building.' || pb.building_type || '.mana_per_day'), 0) * (SELECT COUNT(*) FROM player_buildings WHERE user_id = p.id AND building_type = pb.building_type AND is_active = true)), 0) FROM player_buildings pb WHERE pb.user_id = p.id AND pb.is_active = true)
            END AS gross_mana_per_day,
            -- Gold with sect multiplier
            CASE
                WHEN p.sect_type = 'gilded_path' THEN (SELECT COALESCE(SUM(COALESCE((SELECT value FROM game_config WHERE key = 'building.' || pb.building_type || '.gold_per_day'), 0) * (SELECT COUNT(*) FROM player_buildings WHERE user_id = p.id AND building_type = pb.building_type AND is_active = true)), 0) FROM player_buildings pb WHERE pb.user_id = p.id AND pb.is_active = true) * COALESCE((SELECT value FROM game_config WHERE key = 'sect.gilded_path.gold_multiplier'), 1.5)
                WHEN p.sect_type = 'final_watch' THEN (SELECT COALESCE(SUM(COALESCE((SELECT value FROM game_config WHERE key = 'building.' || pb.building_type || '.gold_per_day'), 0) * (SELECT COUNT(*) FROM player_buildings WHERE user_id = p.id AND building_type = pb.building_type AND is_active = true)), 0) FROM player_buildings pb WHERE pb.user_id = p.id AND pb.is_active = true) * COALESCE((SELECT value FROM game_config WHERE key = 'sect.final_watch.gold_multiplier'), 0.75)
                ELSE (SELECT COALESCE(SUM(COALESCE((SELECT value FROM game_config WHERE key = 'building.' || pb.building_type || '.gold_per_day'), 0) * (SELECT COUNT(*) FROM player_buildings WHERE user_id = p.id AND building_type = pb.building_type AND is_active = true)), 0) FROM player_buildings pb WHERE pb.user_id = p.id AND pb.is_active = true)
            END AS gross_gold_per_day,
            -- Food with sect multiplier
            CASE
                WHEN p.sect_type = 'final_watch' THEN (SELECT COALESCE(SUM(COALESCE((SELECT value FROM game_config WHERE key = 'building.' || pb.building_type || '.food_per_day'), 0) * (SELECT COUNT(*) FROM player_buildings WHERE user_id = p.id AND building_type = pb.building_type AND is_active = true)), 0) FROM player_buildings pb WHERE pb.user_id = p.id AND pb.is_active = true) * COALESCE((SELECT value FROM game_config WHERE key = 'sect.final_watch.food_multiplier'), 1.5)
                ELSE (SELECT COALESCE(SUM(COALESCE((SELECT value FROM game_config WHERE key = 'building.' || pb.building_type || '.food_per_day'), 0) * (SELECT COUNT(*) FROM player_buildings WHERE user_id = p.id AND building_type = pb.building_type AND is_active = true)), 0) FROM player_buildings pb WHERE pb.user_id = p.id AND pb.is_active = true)
            END AS gross_food_per_day,
            -- Gold upkeep with sect multiplier
            CASE
                WHEN p.sect_type = 'gilded_path' THEN (SELECT COALESCE(SUM(COALESCE((SELECT value FROM game_config WHERE key = 'building.' || pb.building_type || '.gold_upkeep_per_day'), 0) * (SELECT COUNT(*) FROM player_buildings WHERE user_id = p.id AND building_type = pb.building_type AND is_active = true)), 0) FROM player_buildings pb WHERE pb.user_id = p.id AND pb.is_active = true) + (SELECT COALESCE(SUM(CASE WHEN pb.building_type = 'coven' THEN COALESCE((SELECT value FROM game_config WHERE key = 'building.coven.gold_upkeep_per_day'), 3) * (SELECT COUNT(*) FROM player_buildings WHERE user_id = p.id AND building_type = 'coven' AND is_active = true) ELSE 0 END), 0) FROM player_buildings pb WHERE pb.user_id = p.id AND pb.is_active = true) * COALESCE((SELECT value FROM game_config WHERE key = 'sect.gilded_path.cathedral_upkeep_multiplier'), 2.0)
                ELSE (SELECT COALESCE(SUM(COALESCE((SELECT value FROM game_config WHERE key = 'building.' || pb.building_type || '.gold_upkeep_per_day'), 0) * (SELECT COUNT(*) FROM player_buildings WHERE user_id = p.id AND building_type = pb.building_type AND is_active = true)), 0) FROM player_buildings pb WHERE pb.user_id = p.id AND pb.is_active = true) + COALESCE((SELECT SUM(CASE WHEN pb.building_type = 'coven' THEN COALESCE((SELECT value FROM game_config WHERE key = 'building.coven.gold_upkeep_per_day'), 3) ELSE 0 END) FROM player_buildings pb WHERE pb.user_id = p.id AND pb.is_active = true), 0)
            END AS total_gold_upkeep_per_day,
            -- Food consumption with sect multiplier
            CASE
                WHEN p.sect_type = 'holy_way' THEN (SELECT COALESCE(SUM(COALESCE((SELECT value FROM game_config WHERE key = 'building.' || pb.building_type || '.food_consumption_per_day'), 0) * (SELECT COUNT(*) FROM player_buildings WHERE user_id = p.id AND building_type = pb.building_type AND is_active = true)), 0) FROM player_buildings pb WHERE pb.user_id = p.id AND pb.is_active = true) * COALESCE((SELECT value FROM game_config WHERE key = 'sect.holy_way.food_consumption_multiplier'), 0.5)
                ELSE (SELECT COALESCE(SUM(COALESCE((SELECT value FROM game_config WHERE key = 'building.' || pb.building_type || '.food_consumption_per_day'), 0) * (SELECT COUNT(*) FROM player_buildings WHERE user_id = p.id AND building_type = pb.building_type AND is_active = true)), 0) FROM player_buildings pb WHERE pb.user_id = p.id AND pb.is_active = true)
            END AS total_food_consumption_per_day,
            -- Heresy with sect multiplier
            CASE
                WHEN p.sect_type = 'black_tribunal' THEN (SELECT COALESCE(SUM(COALESCE((SELECT value FROM game_config WHERE key = 'building.' || pb.building_type || '.heresy_per_day'), 0) * (SELECT COUNT(*) FROM player_buildings WHERE user_id = p.id AND building_type = pb.building_type AND is_active = true)), 0) FROM player_buildings pb WHERE pb.user_id = p.id AND pb.is_active = true) * COALESCE((SELECT value FROM game_config WHERE key = 'sect.black_tribunal.heresy_multiplier'), 2.0)
                ELSE (SELECT COALESCE(SUM(COALESCE((SELECT value FROM game_config WHERE key = 'building.' || pb.building_type || '.heresy_per_day'), 0) * (SELECT COUNT(*) FROM player_buildings WHERE user_id = p.id AND building_type = pb.building_type AND is_active = true)), 0) FROM player_buildings pb WHERE pb.user_id = p.id AND pb.is_active = true)
            END AS gross_heresy_per_day,
            -- Dogma (no sect multiplier)
            (SELECT COALESCE(SUM(COALESCE((SELECT value FROM game_config WHERE key = 'building.' || pb.building_type || '.dogma_per_day'), 0) * (SELECT COUNT(*) FROM player_buildings WHERE user_id = p.id AND building_type = pb.building_type AND is_active = true)), 0) FROM player_buildings pb WHERE pb.user_id = p.id AND pb.is_active = true) AS gross_dogma_per_day,
            -- Coven count for heresy cap
            (SELECT COUNT(*)::INT FROM player_buildings WHERE user_id = p.id AND building_type = 'coven' AND is_active = true) AS coven_count,
            -- Food consumed by coven heresy
            COALESCE((SELECT SUM(COALESCE((SELECT value FROM game_config WHERE key = 'building.coven.food_consumption_per_day'), 0) * (SELECT COUNT(*) FROM player_buildings WHERE user_id = p.id AND building_type = 'coven' AND is_active = true)) FROM player_buildings WHERE user_id = p.id AND building_type = 'coven' AND is_active = true), 0) AS total_heresy_food_consume_per_day,
            -- Scriptitorium count (for research)
            (SELECT COUNT(*)::INT FROM player_buildings WHERE user_id = p.id AND building_type = 'scriptorium' AND is_active = true) AS scriptorium_count
        FROM profiles p
    ),
    -- Calculate per-tick values with synod relic multipliers
    tick_production AS (
        SELECT
            ap.user_id,
            ap.sect_type,
            ap.sacred_acres,
            ap.synod_id,
            ap.papal_bull_until,
            ap.suzerain_id,
            -- Apply synod-wide relic multipliers to production
            CASE WHEN ap.synod_id IS NOT NULL AND EXISTS (
                SELECT 1 FROM relics r JOIN profiles rp ON rp.id = r.holder_id AND r.is_active = true
                WHERE rp.synod_id = ap.synod_id AND r.effect_type = 'mana_double'
            ) THEN GREATEST(1, FLOOR(ap.gross_mana_per_day * 2.0 / 1440))
                 ELSE GREATEST(1, FLOOR(ap.gross_mana_per_day / 1440))
            END AS mana_per_tick,
            CASE WHEN ap.synod_id IS NOT NULL AND EXISTS (
                SELECT 1 FROM relics r JOIN profiles rp ON rp.id = r.holder_id AND r.is_active = true
                WHERE rp.synod_id = ap.synod_id AND r.effect_type = 'gold_double'
            ) THEN GREATEST(1, FLOOR(ap.gross_gold_per_day * 2.0 / 1440))
                 ELSE GREATEST(1, FLOOR(ap.gross_gold_per_day / 1440))
            END AS gold_per_tick,
            CASE WHEN ap.synod_id IS NOT NULL AND EXISTS (
                SELECT 1 FROM relics r JOIN profiles rp ON rp.id = r.holder_id AND r.is_active = true
                WHERE rp.synod_id = ap.synod_id AND r.effect_type = 'food_double'
            ) THEN GREATEST(1, FLOOR(ap.gross_food_per_day * 2.0 / 1440))
                 ELSE GREATEST(1, FLOOR(ap.gross_food_per_day / 1440))
            END AS food_per_tick,
            CASE WHEN ap.synod_id IS NOT NULL AND EXISTS (
                SELECT 1 FROM relics r JOIN profiles rp ON rp.id = r.holder_id AND r.is_active = true
                WHERE rp.synod_id = ap.synod_id AND r.effect_type = 'heresy_double'
            ) THEN GREATEST(1, FLOOR(ap.gross_heresy_per_day * 2.0 / 1440))
                 ELSE GREATEST(1, FLOOR(ap.gross_heresy_per_day / 1440))
            END AS heresy_per_tick,
            CASE
                WHEN ap.synod_id IS NOT NULL AND EXISTS (
                    SELECT 1 FROM relics r JOIN profiles rp ON rp.id = r.holder_id AND r.is_active = true
                    WHERE rp.synod_id = ap.synod_id AND r.effect_type = 'dual_research_double'
                ) THEN GREATEST(1, FLOOR(ap.gross_dogma_per_day * 2.0 / 1440))
                ELSE GREATEST(1, FLOOR(ap.gross_dogma_per_day / 1440))
            END AS dogma_per_tick,
            -- Upkeep: apply upkeep_reduction relic if any synod member holds it
            CASE WHEN ap.synod_id IS NOT NULL AND EXISTS (
                SELECT 1 FROM relics r JOIN profiles rp ON rp.id = r.holder_id AND r.is_active = true
                WHERE rp.synod_id = ap.synod_id AND r.effect_type = 'upkeep_reduction'
            ) THEN GREATEST(0, FLOOR(ap.total_gold_upkeep_per_day * 0.5 / 1440))
                 ELSE GREATEST(0, FLOOR(ap.total_gold_upkeep_per_day / 1440))
            END AS gold_upkeep_tick,
            CASE WHEN ap.synod_id IS NOT NULL AND EXISTS (
                SELECT 1 FROM relics r JOIN profiles rp ON rp.id = r.holder_id AND r.is_active = true
                WHERE rp.synod_id = ap.synod_id AND r.effect_type = 'upkeep_reduction'
            ) THEN GREATEST(0, FLOOR(ap.total_food_consumption_per_day * 0.5 / 1440))
                 ELSE GREATEST(0, FLOOR(ap.total_food_consumption_per_day / 1440))
            END AS food_consume_tick,
            FLOOR(ap.gross_mana_per_day * v_mana_cap_multiplier) AS mana_cap,
            FLOOR(ap.gross_gold_per_day * v_gold_cap_multiplier) AS gold_cap,
            FLOOR(ap.gross_food_per_day * v_food_cap_multiplier) AS food_cap,
            (v_heresy_base_cap + (ap.coven_count * COALESCE((SELECT value FROM game_config WHERE key = 'building.coven.heresy_cap_bonus'), 50)))::INT AS heresy_cap,
            FLOOR(ap.gross_dogma_per_day * v_dogma_cap_multiplier) AS dogma_cap,
            -- Tithe amounts
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
    -- PHASE 2: SYNOD VAULT DEPOSITS
    -- ========================================
    UPDATE synods s SET
        vault_gold = vault_gold + COALESCE((SELECT SUM(st.gold_synod_tax_tick) FROM synod_tax st WHERE st.synod_id = s.id GROUP BY st.synod_id), 0),
        vault_mana = vault_mana + COALESCE((SELECT SUM(st.mana_synod_tax_tick) FROM synod_tax st WHERE st.synod_id = s.id GROUP BY st.synod_id), 0)
    WHERE s.id IN (SELECT DISTINCT synod_id FROM synod_tax WHERE synod_id IS NOT NULL);

    -- ========================================
    -- PHASE 3: EXPIRE TIMED EFFECTS
    -- ========================================
    DELETE FROM active_miracles WHERE expires_at < now();
    DELETE FROM player_research WHERE expires_at IS NOT NULL AND expires_at < now();
    UPDATE synod_wars SET is_active = false WHERE is_active = true AND expires_at < now();
    UPDATE profiles SET papal_bull_until = NULL WHERE papal_bull_until IS NOT NULL AND papal_bull_until < now();
    UPDATE profiles SET divine_shield_until = NULL WHERE divine_shield_until IS NOT NULL AND divine_shield_until < now();

    -- ========================================
    -- PHASE 4: PROCESS DIVINE ARCHITECT QUEUE
    -- ========================================
    FOR v_r IN
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
            FROM profiles WHERE id = v_r.user_id;

            IF v_bq_user_karma >= v_r.karma_cost AND v_bq_user_gold >= v_r.gold_cost AND v_bq_user_heresy >= v_r.heresy_cost THEN
                BEGIN
                    PERFORM purchase_shop_item(v_r.item_id);
                    UPDATE build_queue SET executed_at = now() WHERE id = v_r.id;
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

-- ============================================
-- PHASE 11: GRANT PERMISSIONS
-- ============================================

GRANT EXECUTE ON FUNCTION promote_synod_member(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION promote_synod_member(UUID) TO service_role;

GRANT EXECUTE ON FUNCTION demote_synod_member(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION demote_synod_member(UUID) TO service_role;

GRANT EXECUTE ON FUNCTION kick_synod_member(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION kick_synod_member(UUID) TO service_role;

GRANT EXECUTE ON FUNCTION get_synod_relics(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_synod_relics(UUID) TO service_role;

-- Re-grant on replaced functions (idempotent)
GRANT EXECUTE ON FUNCTION create_synod(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION create_synod(TEXT) TO service_role;

GRANT EXECUTE ON FUNCTION join_synod(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION join_synod(UUID) TO service_role;

GRANT EXECUTE ON FUNCTION leave_synod() TO authenticated;
GRANT EXECUTE ON FUNCTION leave_synod() TO service_role;

GRANT EXECUTE ON FUNCTION get_synod_info() TO authenticated;
GRANT EXECUTE ON FUNCTION get_synod_info() TO service_role;

GRANT EXECUTE ON FUNCTION get_relics() TO authenticated;
GRANT EXECUTE ON FUNCTION get_relics() TO anon;

GRANT EXECUTE ON FUNCTION get_player_economy() TO authenticated;
GRANT EXECUTE ON FUNCTION get_player_economy() TO service_role;

GRANT EXECUTE ON FUNCTION launch_crusade(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION launch_crusade(UUID) TO service_role;

GRANT EXECUTE ON FUNCTION cast_plague(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION cast_plague(UUID) TO service_role;

GRANT EXECUTE ON FUNCTION process_game_tick() TO authenticated;
GRANT EXECUTE ON FUNCTION process_game_tick() TO service_role;

-- ============================================
-- END OF GENESIS 9
-- =====================================================