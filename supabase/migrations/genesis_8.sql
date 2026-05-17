-- =====================================================
-- ELECTRIC MONK — GENESIS 8: Player Lookup, Shield Fixes & Newbie Protection
-- Date: 2026-05-17
--
-- Fixes:
--   1. lookup_player() RPC — SECURITY DEFINER bypasses RLS so players
--      can find each other for crusades/curses (was broken by profiles RLS)
--   2. cast_plague() — add Divine Shield + Papal Bull checks (was missing)
--   3. get_leaderboard() — return divine_shield_until so UI can show shields
--   4. create_profile_on_signup() — grant 7-day newbie shield
--
-- Run AFTER genesis_7.sql.
-- This script is idempotent where possible.
-- DO NOT USE EMOJIS IN CODE OR DEBUG LOGS.
-- =====================================================

-- ============================================
-- PHASE 1: lookup_player() RPC
-- ============================================
-- Players need to find each other for crusades and curses, but the profiles
-- RLS policy only allows seeing your own profile or purgatory users.
-- This SECURITY DEFINER function bypasses RLS and returns only the
-- public-facing fields needed for targeting, plus shield info so the
-- frontend can show shield indicators and block invalid attacks.

CREATE OR REPLACE FUNCTION lookup_player(p_search TEXT)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_result JSONB;
BEGIN
    SELECT jsonb_agg(jsonb_build_object(
        'id', p.id,
        'username', p.username,
        'faith', p.faith,
        'divine_shield_until', p.divine_shield_until
    )) INTO v_result
    FROM profiles p
    WHERE p.username ILIKE '%' || p_search || '%'
      AND p.id != v_user_id
      AND p.username IS NOT NULL
    ORDER BY
        CASE
            WHEN p.username ILIKE p_search THEN 0        -- exact match
            WHEN p.username ILIKE p_search || '%' THEN 1 -- prefix match
            ELSE 2                                        -- substring match
        END ASC,
        p.username ASC
    LIMIT 5;

    RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- PHASE 2: cast_plague() — Add Shield + Papal Bull Checks
-- ============================================
-- Previously cast_plague() had NO shield check at all, unlike launch_crusade().
-- This rewrite adds the same Divine Shield and Papal Bull protections.

CREATE OR REPLACE FUNCTION public.cast_plague(p_target_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_caster_id UUID := auth.uid();
    v_heresy INT;
    v_heresy_cost NUMERIC;
    v_target_food INT;
    v_target_shield TIMESTAMPTZ;
    v_target_papal_bull TIMESTAMPTZ;
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

    -- Get target info: food, shield, papal bull
    SELECT food, divine_shield_until, papal_bull_until
    INTO v_target_food, v_target_shield, v_target_papal_bull
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
-- PHASE 3: get_leaderboard() — Add divine_shield_until Column
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
            p.divine_shield_until,
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
-- PHASE 4: create_profile_on_signup() — 7-Day Newbie Shield
-- ============================================

CREATE OR REPLACE FUNCTION public.create_profile_on_signup()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, email, divine_shield_until)
    VALUES (NEW.id, NEW.email, now() + interval '7 days')
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
-- PHASE 5: GRANT PERMISSIONS
-- ============================================

GRANT EXECUTE ON FUNCTION lookup_player(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION lookup_player(TEXT) TO service_role;

GRANT EXECUTE ON FUNCTION cast_plague(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION cast_plague(UUID) TO service_role;

GRANT EXECUTE ON FUNCTION get_leaderboard(INT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_leaderboard(INT, INT) TO anon;

-- ============================================
-- END OF GENESIS 8
-- =====================================================