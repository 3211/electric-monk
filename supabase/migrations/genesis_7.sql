-- =====================================================
-- ELECTRIC MONK — GENESIS 7: Blessing Shield Buff System
-- Date: 2026-05-17
--
-- Makes blessings meaningful by granting Divine Shield
-- protection to both the giver and receiver when a
-- blessing is applied to a prayer. Shield duration scales
-- with blessing karma cost (default: 10 min per karma).
-- Shields stack additively — each blessing extends the
-- timer by its full duration.
--
-- Changes:
--   1. Add shield_minutes column to blessing_types
--   2. Add blessing.shield_minutes_per_karma to game_config
--   3. Rewrite grant_blessing() to grant shields + miracles
--   4. Update get_player_economy() to return active_miracles
--   5. Verify GRANT permissions (no changes needed)
--
-- Run AFTER genesis_6.sql.
-- This script is idempotent where possible.
-- DO NOT USE EMOJIS IN CODE OR DEBUG LOGS.
-- =====================================================

-- ============================================
-- PHASE 1: ADD shield_minutes COLUMN TO blessing_types
-- ============================================

ALTER TABLE public.blessing_types
  ADD COLUMN IF NOT EXISTS shield_minutes INT DEFAULT NULL;

COMMENT ON COLUMN public.blessing_types.shield_minutes IS
  'Override shield duration in minutes. NULL means use karma_cost * blessing.shield_minutes_per_karma from game_config.';

-- ============================================
-- PHASE 2: ADD GAME CONFIG FOR SHIELD DURATION
-- ============================================

INSERT INTO game_config (key, value, description, category)
VALUES ('blessing.shield_minutes_per_karma', 10,
  'Minutes of Divine Shield per karma point spent on a blessing. Used when blessing_types.shield_minutes is NULL.',
  'blessing')
ON CONFLICT (key) DO UPDATE SET
  value = EXCLUDED.value,
  description = EXCLUDED.description,
  category = EXCLUDED.category,
  updated_at = now();

-- ============================================
-- PHASE 3: REWRITE grant_blessing() WITH SHIELD LOGIC
-- ============================================
-- When a blessing is granted:
--   1. Deduct karma from giver
--   2. Award karma rebate to giver
--   3. Award karma to receiver
--   4. Calculate shield duration (additive stacking)
--   5. Extend divine_shield_until on BOTH giver and receiver
--   6. Insert active_miracles rows for both parties
--   7. Insert prayer_blessings record
--   8. Return shield info in response

CREATE OR REPLACE FUNCTION grant_blessing(
  p_prayer_id UUID,
  p_blessing_type_id TEXT
)
RETURNS JSONB AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_cost INT;
  v_giver_karma INT;
  v_receiver_karma INT;
  v_user_current_karma INT;
  v_prayer_owner UUID;
  v_blessing_id UUID;
  v_shield_minutes_per_karma NUMERIC;
  v_shield_minutes INT;
  v_shield_interval INTERVAL;
  v_bt RECORD;
BEGIN
  -- Get blessing type details (including new shield_minutes column)
  SELECT karma_cost, karma_to_giver, karma_to_receiver, shield_minutes
  INTO v_bt
  FROM blessing_types
  WHERE id = p_blessing_type_id AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Blessing type not found or inactive';
  END IF;

  v_cost := v_bt.karma_cost;
  v_giver_karma := v_bt.karma_to_giver;
  v_receiver_karma := v_bt.karma_to_receiver;

  -- Get prayer owner
  SELECT user_id INTO v_prayer_owner FROM prayers WHERE id = p_prayer_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Prayer not found';
  END IF;

  -- Prevent self-blessing
  IF v_prayer_owner = v_user_id THEN
    RAISE EXCEPTION 'Cannot bless your own prayer';
  END IF;

  -- Prevent duplicate blessing (same user, same type, same prayer)
  IF EXISTS (
    SELECT 1 FROM prayer_blessings
    WHERE prayer_id = p_prayer_id
      AND blessing_type_id = p_blessing_type_id
      AND giver_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Already blessed this prayer with this blessing';
  END IF;

  -- Check karma balance
  SELECT karma INTO v_user_current_karma FROM profiles WHERE id = v_user_id;
  IF v_user_current_karma < v_cost THEN
    RAISE EXCEPTION 'Insufficient karma. You have % but need %.', v_user_current_karma, v_cost;
  END IF;

  -- Deduct cost from giver
  PERFORM update_karma(v_user_id, -v_cost);

  -- Award rebate to giver
  IF v_giver_karma > 0 THEN
    PERFORM update_karma(v_user_id, v_giver_karma);
  END IF;

  -- Award karma to receiver (prayer owner)
  IF v_receiver_karma > 0 THEN
    PERFORM update_karma(v_prayer_owner, v_receiver_karma);
  END IF;

  -- ========================================
  -- SHIELD BUFF LOGIC
  -- ========================================

  -- Load shield duration multiplier from config
  SELECT value INTO v_shield_minutes_per_karma FROM game_config WHERE key = 'blessing.shield_minutes_per_karma';
  IF v_shield_minutes_per_karma IS NULL THEN v_shield_minutes_per_karma := 10; END IF;

  -- Calculate shield duration: per-blessing override or formula
  -- shield_minutes = COALESCE(bt.shield_minutes, bt.karma_cost * config_value)
  IF v_bt.shield_minutes IS NOT NULL THEN
    v_shield_minutes := v_bt.shield_minutes;
  ELSE
    v_shield_minutes := v_bt.karma_cost * v_shield_minutes_per_karma;
  END IF;

  -- Only grant shields if duration > 0
  IF v_shield_minutes > 0 THEN
    v_shield_interval := v_shield_minutes * interval '1 minute';

    -- Extend giver shield (additive: adds duration to any existing shield)
    UPDATE profiles
    SET divine_shield_until = COALESCE(divine_shield_until, now()) + v_shield_interval,
        updated_at = now()
    WHERE id = v_user_id;

    -- Extend receiver shield (additive: adds duration to any existing shield)
    UPDATE profiles
    SET divine_shield_until = COALESCE(divine_shield_until, now()) + v_shield_interval,
        updated_at = now()
    WHERE id = v_prayer_owner;

    -- Insert miracle records for both parties
    INSERT INTO active_miracles (user_id, miracle_type, effect_data, expires_at) VALUES
      (v_user_id, 'blessing_shield', jsonb_build_object(
        'blessing_type_id', p_blessing_type_id,
        'source', 'given',
        'prayer_id', p_prayer_id,
        'shield_minutes', v_shield_minutes
      ), now() + v_shield_interval),
      (v_prayer_owner, 'blessing_shield', jsonb_build_object(
        'blessing_type_id', p_blessing_type_id,
        'source', 'received',
        'prayer_id', p_prayer_id,
        'shield_minutes', v_shield_minutes
      ), now() + v_shield_interval);
  END IF;

  -- Insert blessing record
  INSERT INTO prayer_blessings (prayer_id, blessing_type_id, giver_id, receiver_id)
  VALUES (p_prayer_id, p_blessing_type_id, v_user_id, v_prayer_owner)
  RETURNING id INTO v_blessing_id;

  -- Return result with shield info
  RETURN jsonb_build_object(
    'id', v_blessing_id,
    'blessing_type_id', p_blessing_type_id,
    'karma_spent', v_cost,
    'karma_to_giver', v_giver_karma,
    'karma_to_receiver', v_receiver_karma,
    'shield_minutes', v_shield_minutes,
    'shield_giver_until', CASE WHEN v_shield_minutes > 0 THEN
      COALESCE((SELECT divine_shield_until FROM profiles WHERE id = v_user_id), now() + v_shield_interval)
    ELSE NULL END,
    'shield_receiver_until', CASE WHEN v_shield_minutes > 0 THEN
      COALESCE((SELECT divine_shield_until FROM profiles WHERE id = v_prayer_owner), now() + v_shield_interval)
    ELSE NULL END
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- PHASE 4: UPDATE get_player_economy() — ADD active_miracles
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
        'active_miracles', v_active_miracles
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- PHASE 5: VERIFY GRANT PERMISSIONS
-- ============================================
-- grant_blessing() runs as SECURITY DEFINER, so it can INSERT
-- into active_miracles without additional GRANTs.
-- The function already has EXECUTE grants from genesis_4.sql.
-- get_player_economy() also already has EXECUTE grants.
-- No new GRANT statements needed.

-- Verify existing grants are in place (idempotent)
GRANT EXECUTE ON FUNCTION grant_blessing(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION grant_blessing(UUID, TEXT) TO service_role;

GRANT EXECUTE ON FUNCTION get_player_economy() TO authenticated;
GRANT EXECUTE ON FUNCTION get_player_economy() TO service_role;

-- ============================================
-- PHASE 6: ONBOARDING TRACKING
-- ============================================
-- Tracks whether the user has completed the onboarding wizard.
-- If FALSE or NULL, the user will be intercepted with the onboarding flow.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS onboarding_complete BOOLEAN DEFAULT FALSE;

COMMENT ON COLUMN public.profiles.onboarding_complete IS
  'Whether the user has completed the onboarding wizard. FALSE = needs onboarding.';

-- ============================================
-- END OF GENESIS 7
-- =====================================================