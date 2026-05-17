-- =====================================================
-- ELECTRIC MONK — GENESIS 9 HOTFIX: Resilient get_player_economy()
-- Date: 2026-05-17
--
-- Problem: genesis_9 added a call to get_synod_relics() inside
-- get_player_economy() without error handling. If get_synod_relics()
-- throws (permissions, missing table column, function not found, etc.),
-- the ENTIRE get_player_economy() RPC fails, causing the frontend to
-- show 0 for all resources (mana, gold, food, heresy, dogma).
--
-- Fix: Wrap the get_synod_relics() call in a BEGIN/EXCEPTION block
-- so it gracefully returns '[]' on failure instead of crashing the
-- whole economy fetch.
--
-- Run AFTER genesis_9.sql.
-- This script is idempotent.
-- DO NOT USE EMOJIS IN CODE OR DEBUG LOGS.
-- =====================================================

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

    -- HOTFIX: Wrap get_synod_relics() in exception handler so it never crashes the entire economy fetch.
    -- If get_synod_relics() fails (permissions, missing columns, function not found, etc.),
    -- we return an empty array instead of crashing get_player_economy() entirely.
    BEGIN
        v_synod_relics := public.get_synod_relics(v_user_id);
    EXCEPTION WHEN OTHERS THEN
        v_synod_relics := '[]'::jsonb;
    END;

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

-- Re-grant permissions (idempotent)
GRANT EXECUTE ON FUNCTION get_player_economy() TO authenticated;
GRANT EXECUTE ON FUNCTION get_player_economy() TO service_role;

-- =====================================================
-- END OF GENESIS 9 HOTFIX
-- =====================================================