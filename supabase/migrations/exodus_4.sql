-- ============================================
-- Exodus 4: Karma & Resource Generation Fix
-- ============================================
--
-- Fixes:
--   1. Karma milestones stuck at low values despite
--      1000s of prayer cycles — NULL karma_awarded
--      caused heartbeat milestone checks to silently
--      fail (NULL comparison yields NULL, not TRUE)
--   2. Resource generation (mana/gold/food/heresy/dogma)
--      now ticks per-minute with minimum 1 for any
--      positive daily production, so players feel
--      constant progress
--   3. activate_prayer now syncs karma_awarded on
--      activation to prevent milestone gaps
--
-- Run after all prior exodus scripts.

-- ============================================
-- STEP 0: Fix NULL karma_awarded (the root cause)
-- ============================================
UPDATE prayers SET karma_awarded = 0 WHERE karma_awarded IS NULL;

-- ============================================
-- STEP 1: Replace calculate_automated_karma()
--         with NULL-safe, per-minute version
-- ============================================

CREATE OR REPLACE FUNCTION public.calculate_automated_karma()
RETURNS void AS $$
DECLARE
    r RECORD;
    v_text TEXT;
    v_cycle_s INT;
    v_elapsed_s FLOAT;
    v_new_cycles INT;
    v_new_count INT;
    v_milestones_total INT;
    v_karma_awarded_safe INT;
    v_karma_to_award INT;
    v_sinner_redeemed BOOLEAN;
    v_milestone_threshold NUMERIC;
    v_milestone_payout NUMERIC;
    v_altruistic_multiplier NUMERIC;
    v_tithe_pct NUMERIC;
    v_liege_karma_per_day NUMERIC;
    v_tick_divisor NUMERIC := 1440.0; -- per-minute (1440 min/day)
BEGIN
    -- Load config with safe defaults
    SELECT COALESCE(value, 50)  INTO v_milestone_threshold  FROM game_config WHERE key = 'karma.milestone_threshold';
    SELECT COALESCE(value, 5)   INTO v_milestone_payout     FROM game_config WHERE key = 'karma.milestone_payout';
    SELECT COALESCE(value, 2)   INTO v_altruistic_multiplier FROM game_config WHERE key = 'karma.altruistic_multiplier';
    SELECT COALESCE(value, 0.10) INTO v_tithe_pct            FROM game_config WHERE key = 'tithe.percentage';
    SELECT COALESCE(value, 5)   INTO v_liege_karma_per_day   FROM game_config WHERE key = 'vassalage.liege_karma_per_day';

    -- ========================================
    -- PHASE 1: KARMA MILESTONES (NULL-safe)
    -- ========================================
    FOR r IN SELECT p.* FROM prayers p WHERE p.is_praying = true LOOP
        v_text := COALESCE(r.response_content, r.content, '');
        v_cycle_s := GREATEST(15, LEAST(length(v_text) * 0.2, 180))::INT;
        v_elapsed_s := EXTRACT(EPOCH FROM (now() - COALESCE(r.last_counted_at, r.activated_at)));
        v_new_cycles := floor(v_elapsed_s / v_cycle_s);

        IF v_new_cycles > 0 THEN
            -- Advance last_counted_at by completed cycles only
            UPDATE prayers SET
                prayer_count = prayer_count + v_new_cycles,
                last_counted_at = COALESCE(last_counted_at, activated_at)
                    + (v_new_cycles * (v_cycle_s * interval '1 second')),
                updated_at = now()
            WHERE id = r.id
            RETURNING prayer_count INTO v_new_count;

            -- NULL-safe: treat NULL karma_awarded as 0
            v_karma_awarded_safe := COALESCE(r.karma_awarded, 0);
            -- Use the actual updated count for milestone calc
            v_milestones_total := floor(v_new_count / v_milestone_threshold);

            IF v_milestones_total > v_karma_awarded_safe THEN
                v_karma_to_award := (v_milestones_total - v_karma_awarded_safe)
                    * v_milestone_payout
                    * (CASE WHEN r.prayer_type = 'altruistic'
                       THEN v_altruistic_multiplier ELSE 1 END);
                UPDATE profiles SET karma = karma + v_karma_to_award,
                    updated_at = now() WHERE id = r.user_id;
                UPDATE prayers SET karma_awarded = v_milestones_total
                WHERE id = r.id;
            END IF;
        END IF;

        -- Intercessory: sinner redemption check
        IF r.prayer_type = 'intercessory' AND r.source_sinner_id IS NOT NULL THEN
            SELECT (ban_until IS NULL OR ban_until <= now())
                INTO v_sinner_redeemed FROM profiles WHERE id = r.source_sinner_id;
            IF v_sinner_redeemed THEN
                UPDATE prayers SET is_praying = false,
                    last_counted_at = now(), updated_at = now() WHERE id = r.id;
                UPDATE profiles SET karma = karma + 10,
                    updated_at = now() WHERE id = r.user_id;
            END IF;
        END IF;
    END LOOP;

    -- ========================================
    -- PHASE 2: RESOURCE GENERATION (per-minute)
    -- ========================================
    -- Each minute tick = daily_rate / 1440, minimum 1
    -- for any positive daily production.
    WITH user_production AS (
        SELECT pb.user_id,
            COALESCE(SUM(CASE WHEN gc_mana.value IS NOT NULL
                THEN gc_mana.value ELSE 0 END), 0)::NUMERIC AS gross_mana,
            COALESCE(SUM(CASE WHEN gc_gold.value IS NOT NULL
                THEN gc_gold.value ELSE 0 END), 0)::NUMERIC AS gross_gold,
            COALESCE(SUM(CASE WHEN gc_food.value IS NOT NULL
                THEN gc_food.value ELSE 0 END), 0)::NUMERIC AS gross_food,
            COALESCE(SUM(CASE WHEN gc_gold_upk.value IS NOT NULL
                THEN gc_gold_upk.value ELSE 0 END), 0)::NUMERIC AS gold_upkeep,
            COALESCE(SUM(CASE WHEN gc_food_con.value IS NOT NULL
                THEN gc_food_con.value ELSE 0 END), 0)::NUMERIC AS food_consume,
            COALESCE(SUM(CASE WHEN gc_heresy.value IS NOT NULL
                THEN gc_heresy.value ELSE 0 END), 0)::NUMERIC AS gross_heresy,
            COALESCE(SUM(CASE WHEN gc_dogma.value IS NOT NULL
                THEN gc_dogma.value ELSE 0 END), 0)::NUMERIC AS gross_dogma,
            COALESCE(SUM(CASE WHEN pb.building_type = 'coven'
                THEN 1 ELSE 0 END), 0)::INT AS coven_count
        FROM player_buildings pb
        LEFT JOIN game_config gc_mana
            ON gc_mana.key = 'building.' || pb.building_type || '.mana_per_day'
        LEFT JOIN game_config gc_gold
            ON gc_gold.key = 'building.' || pb.building_type || '.gold_per_day'
        LEFT JOIN game_config gc_food
            ON gc_food.key = 'building.' || pb.building_type || '.food_per_day'
        LEFT JOIN game_config gc_gold_upk
            ON gc_gold_upk.key = 'building.' || pb.building_type || '.gold_upkeep_per_day'
        LEFT JOIN game_config gc_food_con
            ON gc_food_con.key = 'building.' || pb.building_type || '.food_consumption_per_day'
        LEFT JOIN game_config gc_heresy
            ON gc_heresy.key = 'building.' || pb.building_type || '.heresy_per_day'
        LEFT JOIN game_config gc_dogma
            ON gc_dogma.key = 'building.' || pb.building_type || '.dogma_per_day'
        WHERE pb.is_active = true GROUP BY pb.user_id
    ),
    all_players AS (
        SELECT p.id AS user_id, p.sect_type, p.synod_id, p.suzerain_id,
            COALESCE(up.gross_mana, 0)   AS gross_mana,
            COALESCE(up.gross_gold, 0)   AS gross_gold,
            COALESCE(up.gross_food, 0)   AS gross_food,
            COALESCE(up.gold_upkeep, 0)  AS gold_upkeep,
            COALESCE(up.food_consume, 0) AS food_consume,
            COALESCE(up.gross_heresy, 0) AS gross_heresy,
            COALESCE(up.gross_dogma, 0)  AS gross_dogma,
            COALESCE(up.coven_count, 0)  AS coven_count
        FROM profiles p LEFT JOIN user_production up ON p.id = up.user_id
    ),
    -- Apply sect multipliers (same as exodus_2)
    sect_modified AS (
        SELECT ap.user_id, ap.synod_id, ap.suzerain_id,
            CASE WHEN ap.sect_type = 'gilded_path'
                THEN ap.gross_mana * COALESCE(
                    (SELECT value FROM game_config WHERE key = 'sect.gilded_path.mana_multiplier'), 0.8)
                 WHEN ap.sect_type = 'holy_way'
                THEN ap.gross_mana * COALESCE(
                    (SELECT value FROM game_config WHERE key = 'sect.holy_way.mana_multiplier'), 1.2)
                 WHEN ap.sect_type = 'black_tribunal'
                THEN ap.gross_mana * COALESCE(
                    (SELECT value FROM game_config WHERE key = 'sect.black_tribunal.mana_multiplier'), 0.7)
                 ELSE ap.gross_mana END AS mod_mana,
            CASE WHEN ap.sect_type = 'gilded_path'
                THEN ap.gross_gold * COALESCE(
                    (SELECT value FROM game_config WHERE key = 'sect.gilded_path.gold_multiplier'), 1.5)
                 WHEN ap.sect_type = 'final_watch'
                THEN ap.gross_gold * COALESCE(
                    (SELECT value FROM game_config WHERE key = 'sect.final_watch.gold_multiplier'), 0.75)
                 ELSE ap.gross_gold END AS mod_gold,
            CASE WHEN ap.sect_type = 'final_watch'
                THEN ap.gross_food * COALESCE(
                    (SELECT value FROM game_config WHERE key = 'sect.final_watch.food_multiplier'), 1.5)
                 ELSE ap.gross_food END AS mod_food,
            CASE WHEN ap.sect_type = 'gilded_path'
                THEN ap.gold_upkeep * COALESCE(
                    (SELECT value FROM game_config WHERE key = 'sect.gilded_path.cathedral_upkeep_multiplier'), 2.0)
                 ELSE ap.gold_upkeep END AS mod_gold_upkeep,
            CASE WHEN ap.sect_type = 'holy_way'
                THEN ap.food_consume * COALESCE(
                    (SELECT value FROM game_config WHERE key = 'sect.holy_way.food_consumption_multiplier'), 0.5)
                 ELSE ap.food_consume END AS mod_food_consume,
            CASE WHEN ap.sect_type = 'black_tribunal'
                THEN ap.gross_heresy * COALESCE(
                    (SELECT value FROM game_config WHERE key = 'sect.black_tribunal.heresy_multiplier'), 2.0)
                 ELSE ap.gross_heresy END AS mod_heresy,
            ap.gross_dogma, ap.coven_count
        FROM all_players ap
    ),
    -- Per-minute ticks: daily/1440, minimum 1 for positive production
    tick_production AS (
        SELECT sm.user_id, sm.synod_id, sm.suzerain_id,
            CASE WHEN sm.mod_mana > 0
                THEN GREATEST(1, FLOOR(sm.mod_mana / v_tick_divisor))
                ELSE 0 END::INT AS mana_tick,
            CASE WHEN sm.mod_gold > 0
                THEN GREATEST(1, FLOOR(sm.mod_gold / v_tick_divisor))
                ELSE 0 END::INT AS gold_tick,
            CASE WHEN sm.mod_food > 0
                THEN GREATEST(1, FLOOR(sm.mod_food / v_tick_divisor))
                ELSE 0 END::INT AS food_tick,
            CASE WHEN sm.mod_heresy > 0
                THEN GREATEST(1, FLOOR(sm.mod_heresy / v_tick_divisor))
                ELSE 0 END::INT AS heresy_tick,
            CASE WHEN sm.gross_dogma > 0
                THEN GREATEST(1, FLOOR(sm.gross_dogma / v_tick_divisor))
                ELSE 0 END::INT AS dogma_tick,
            GREATEST(0, FLOOR(sm.mod_gold_upkeep / v_tick_divisor))::INT AS gold_upkeep_tick,
            GREATEST(0, FLOOR(sm.mod_food_consume / v_tick_divisor))::INT AS food_consume_tick,
            -- Tithes
            CASE WHEN sm.suzerain_id IS NOT NULL
                THEN FLOOR(sm.mod_mana / v_tick_divisor * v_tithe_pct)
                ELSE 0 END::INT AS mana_tithe,
            CASE WHEN sm.suzerain_id IS NOT NULL
                THEN FLOOR(sm.mod_gold / v_tick_divisor * v_tithe_pct)
                ELSE 0 END::INT AS gold_tithe,
            CASE WHEN sm.suzerain_id IS NOT NULL
                THEN FLOOR(sm.mod_food / v_tick_divisor * v_tithe_pct)
                ELSE 0 END::INT AS food_tithe
        FROM sect_modified sm
    ),
    tithe_inbound AS (
        SELECT tp.suzerain_id,
            COALESCE(SUM(tp.mana_tithe), 0)::INT AS recv_mana,
            COALESCE(SUM(tp.gold_tithe), 0)::INT AS recv_gold,
            COALESCE(SUM(tp.food_tithe), 0)::INT AS recv_food
        FROM tick_production tp
        WHERE tp.suzerain_id IS NOT NULL GROUP BY tp.suzerain_id
    ),
    synod_tax AS (
        SELECT tp.user_id, tp.synod_id,
            FLOOR(tp.gold_tick * COALESCE(s.tax_rate, 0.05))::INT AS gold_tax,
            FLOOR(tp.mana_tick * COALESCE(s.tax_rate, 0.05))::INT AS mana_tax
        FROM tick_production tp
        JOIN synods s ON s.id = tp.synod_id
        WHERE tp.synod_id IS NOT NULL
    )
    UPDATE profiles p SET
        mana   = p.mana   + tp.mana_tick   - tp.mana_tithe
               + COALESCE(ti.recv_mana, 0),
        gold   = GREATEST(0,
                 p.gold   + tp.gold_tick   - tp.gold_upkeep_tick
               - tp.gold_tithe + COALESCE(ti.recv_gold, 0)
               - COALESCE(st.gold_tax, 0)),
        food   = GREATEST(0,
                 p.food   + tp.food_tick   - tp.food_consume_tick
               - tp.food_tithe + COALESCE(ti.recv_food, 0)),
        heresy = p.heresy + tp.heresy_tick,
        dogma  = p.dogma  + tp.dogma_tick,
        updated_at = now()
    FROM tick_production tp
    LEFT JOIN tithe_inbound ti ON ti.suzerain_id = p.id
    LEFT JOIN synod_tax st ON st.user_id = p.id
    WHERE p.id = tp.user_id;

    -- ========================================
    -- PHASE 3: SYNOD VAULT
    -- ========================================
    UPDATE synods s SET
        vault_gold = vault_gold + COALESCE((
            SELECT SUM(st2.gold_tax) FROM synod_tax st2
            WHERE st2.synod_id = s.id), 0),
        vault_mana = vault_mana + COALESCE((
            SELECT SUM(st2.mana_tax) FROM synod_tax st2
            WHERE st2.synod_id = s.id), 0)
    WHERE s.id IN (SELECT DISTINCT synod_id FROM synod_tax
                   WHERE synod_id IS NOT NULL);

    -- ========================================
    -- PHASE 4: EXPIRE EFFECTS
    -- ========================================
    DELETE FROM active_miracles WHERE expires_at < now();
    DELETE FROM player_research WHERE expires_at IS NOT NULL AND expires_at < now();
    UPDATE synod_wars SET is_active = false
        WHERE is_active = true AND expires_at < now();
    UPDATE profiles SET papal_bull_until = NULL
        WHERE papal_bull_until IS NOT NULL AND papal_bull_until < now();
    UPDATE profiles SET divine_shield_until = NULL
        WHERE divine_shield_until IS NOT NULL AND divine_shield_until < now();

    -- ========================================
    -- PHASE 5: DIVINE ARCHITECT QUEUE
    -- ========================================
    FOR r IN SELECT bq.*, si.karma_cost, si.gold_cost, si.heresy_cost,
                     si.effect_type, si.effect_data, si.acre_cost, si.cost_scaling
        FROM build_queue bq
        JOIN shop_items si ON si.id = bq.item_id
        WHERE bq.executed_at IS NULL AND bq.auto_execute = true
    LOOP
        DECLARE v_k INT; v_g INT; v_h INT;
        BEGIN
            SELECT karma, gold, heresy INTO v_k, v_g, v_h
            FROM profiles WHERE id = r.user_id;
            IF v_k >= r.karma_cost AND v_g >= r.gold_cost
               AND v_h >= r.heresy_cost THEN
                BEGIN
                    PERFORM purchase_shop_item(r.item_id);
                    UPDATE build_queue SET executed_at = now() WHERE id = r.id;
                EXCEPTION WHEN OTHERS THEN NULL; END;
            END IF;
        END;
    END LOOP;
    DELETE FROM build_queue
        WHERE executed_at IS NOT NULL
          AND executed_at < now() - interval '7 days';

    -- ========================================
    -- PHASE 6: COMBAT TICKS (same as exodus_2)
    -- ========================================
    FOR r IN SELECT id FROM combat_sessions
        WHERE is_active = true AND combat_type = 'pvp' LOOP
        DECLARE
            v_s RECORD; v_leech_pct NUMERIC; v_gold_per_tick NUMERIC;
            v_attrition NUMERIC; v_exertion NUMERIC;
            v_attacker_gold INT; v_defender_gold INT; v_leech INT;
            v_result TEXT; v_kill_karma INT;
            v_attacker_mana INT; v_defender_mana INT;
            v_attacker_workers INT; v_defender_workers INT;
        BEGIN
            SELECT * INTO v_s FROM combat_sessions
            WHERE id = r.id AND is_active = true;
            IF NOT FOUND THEN CONTINUE; END IF;

            SELECT COALESCE(value, 0.02) INTO v_leech_pct
                FROM game_config WHERE key = 'combat.pvp_leech_pct';
            SELECT COALESCE(value, 10) INTO v_gold_per_tick
                FROM game_config WHERE key = 'combat.pvp_gold_per_tick';
            SELECT COALESCE(value, 0.10) INTO v_attrition
                FROM game_config WHERE key = 'combat.pvp_attrition_pct';
            SELECT COALESCE(value, 0.05) INTO v_exertion
                FROM game_config WHERE key = 'combat.pvp_exertion_pct';

            SELECT mana, gold, (
                SELECT COUNT(*)::INT FROM player_buildings
                WHERE user_id = v_s.attacker_id AND is_active = true
                AND building_type IN ('novice','monk','cleric','bishop','cardinal','cultist')
            ) INTO v_attacker_mana, v_attacker_gold, v_attacker_workers
            FROM profiles WHERE id = v_s.attacker_id;

            SELECT mana, gold, (
                SELECT COUNT(*)::INT FROM player_buildings
                WHERE user_id = v_s.defender_id AND is_active = true
                AND building_type IN ('novice','monk','cleric','bishop','cardinal','cultist')
            ) INTO v_defender_mana, v_defender_gold, v_defender_workers
            FROM profiles WHERE id = v_s.defender_id;

            -- Damage
            UPDATE profiles SET mana = GREATEST(0, mana - v_attacker_workers)
            WHERE id = v_s.defender_id;
            IF v_defender_workers > 0 THEN
                UPDATE profiles SET mana = GREATEST(0, mana - v_defender_workers)
                WHERE id = v_s.attacker_id;
            END IF;

            -- Leech gold
            v_leech := FLOOR(v_defender_gold * v_leech_pct);
            IF v_leech > 0 THEN
                UPDATE profiles SET gold = GREATEST(0, gold - v_leech)
                WHERE id = v_s.defender_id;
                UPDATE profiles SET gold = gold + v_leech, updated_at = now()
                WHERE id = v_s.attacker_id;
            END IF;

            IF v_attacker_gold >= v_gold_per_tick THEN
                UPDATE profiles SET gold = gold - v_gold_per_tick, updated_at = now()
                WHERE id = v_s.attacker_id;
            END IF;

            v_s.gold_stolen := COALESCE(v_s.gold_stolen, 0) + v_leech;
            v_s.gold_spent := COALESCE(v_s.gold_spent, 0) + v_gold_per_tick;
            v_s.ticks_remaining := v_s.ticks_remaining - 1;

            SELECT mana INTO v_attacker_mana FROM profiles WHERE id = v_s.attacker_id;
            SELECT mana INTO v_defender_mana FROM profiles WHERE id = v_s.defender_id;
            SELECT gold INTO v_attacker_gold FROM profiles WHERE id = v_s.attacker_id;

            IF v_defender_mana <= 0 THEN v_result := 'attacker_win';
            ELSIF v_attacker_mana <= 0 OR v_attacker_gold < v_gold_per_tick
                THEN v_result := 'defender_win';
            ELSIF v_s.ticks_remaining <= 0 THEN v_result := 'stalemate';
            END IF;

            IF v_result = 'attacker_win' THEN
                DECLARE v_att_sect TEXT; v_def_sect TEXT; v_fr RECORD;
                BEGIN
                    SELECT sect_type INTO v_att_sect FROM profiles
                    WHERE id = v_s.attacker_id;
                    SELECT sect_type INTO v_def_sect FROM profiles
                    WHERE id = v_s.defender_id;
                    SELECT * INTO v_fr FROM faction_relationships
                    WHERE sect_key = v_att_sect;

                    IF v_fr.enemy_sect = v_def_sect THEN
                        SELECT COALESCE(value, 5) INTO v_kill_karma
                        FROM game_config WHERE key = 'combat.kill_enemy_karma';
                    ELSE
                        SELECT COALESCE(value, 1) INTO v_kill_karma
                        FROM game_config WHERE key = 'combat.kill_neutral_karma';
                    END IF;
                END;

                UPDATE profiles SET karma = karma + v_kill_karma, updated_at = now()
                WHERE id = v_s.attacker_id;

                IF NOT EXISTS (SELECT 1 FROM profiles
                    WHERE id = v_s.defender_id AND suzerain_id IS NOT NULL) THEN
                    UPDATE profiles SET suzerain_id = v_s.attacker_id, updated_at = now()
                    WHERE id = v_s.defender_id;
                END IF;

                INSERT INTO akashic_logs (target_id, actor_id, action_type, result_data)
                VALUES (v_s.defender_id, v_s.attacker_id, 'crusade',
                    jsonb_build_object('type','pvp_victory','session_id',v_s.id,
                    'karma_gained',v_kill_karma,'vassaldom',true));

            ELSIF v_result = 'defender_win' THEN
                INSERT INTO akashic_logs (target_id, actor_id, action_type, result_data)
                VALUES (v_s.defender_id, v_s.attacker_id, 'crusade',
                    jsonb_build_object('type','pvp_retreat','session_id',v_s.id));
            END IF;

            IF v_result IS NOT NULL THEN
                UPDATE profiles SET active_combat_target_id = NULL
                WHERE id = v_s.attacker_id;
            END IF;

            UPDATE combat_sessions SET
                attacker_mana = v_attacker_mana, defender_mana = v_defender_mana,
                attacker_workers = v_attacker_workers, defender_workers = v_defender_workers,
                ticks_remaining = v_s.ticks_remaining, gold_stolen = v_s.gold_stolen,
                gold_spent = v_s.gold_spent, last_tick_at = now(),
                is_active = CASE WHEN v_result IS NOT NULL THEN false ELSE true END,
                result = v_result
            WHERE id = v_s.id;
        END;
    END LOOP;

    -- Holy War ticks
    FOR r IN SELECT id FROM combat_sessions
        WHERE is_active = true AND combat_type = 'holy_war' LOOP
        PERFORM process_holy_war_tick(r.id);
    END LOOP;

    -- ========================================
    -- PHASE 7: SUBJUGATION TIMERS
    -- ========================================
    FOR r IN SELECT cs.attacker_id, cs.defender_id
        FROM combat_sessions cs
        WHERE cs.combat_type = 'pvp' AND cs.is_active = true
          AND EXISTS (SELECT 1 FROM subjugation_timers st
            WHERE st.liege_id = cs.attacker_id
              AND st.vassal_id = cs.defender_id
              AND st.accumulated_hours < 168)
    LOOP
        UPDATE subjugation_timers
        SET accumulated_hours = accumulated_hours + (1.0 / 60.0),
            last_attack_at = now()
        WHERE liege_id = r.attacker_id AND vassal_id = r.defender_id
          AND accumulated_hours < 168;

        IF EXISTS (SELECT 1 FROM subjugation_timers
            WHERE liege_id = r.attacker_id AND vassal_id = r.defender_id
              AND accumulated_hours >= 168) THEN
            UPDATE profiles SET suzerain_id = r.attacker_id, updated_at = now()
            WHERE id = r.defender_id AND suzerain_id IS NULL;

            INSERT INTO akashic_logs (target_id, actor_id, action_type, result_data)
            VALUES (r.defender_id, r.attacker_id, 'crusade',
                jsonb_build_object('type','subjugation_complete',
                'liege_id',r.attacker_id,'vassal_id',r.defender_id));

            DELETE FROM subjugation_timers
            WHERE liege_id = r.attacker_id AND vassal_id = r.defender_id;
        END IF;
    END LOOP;

    -- ========================================
    -- PHASE 8: VASSAL TITHES + LIEGE KARMA
    -- ========================================
    FOR r IN SELECT p.id AS vassal_id, p.suzerain_id AS liege_id
        FROM profiles p WHERE p.suzerain_id IS NOT NULL
    LOOP
        DECLARE v_vassal_gold_tick INT;
        BEGIN
            SELECT COALESCE(FLOOR(SUM(COALESCE((
                SELECT value FROM game_config
                WHERE key = 'building.' || pb.building_type || '.gold_per_day'
            ), 0)) / v_tick_divisor * v_tithe_pct), 0)
            INTO v_vassal_gold_tick
            FROM player_buildings pb
            WHERE pb.user_id = r.vassal_id AND pb.is_active = true;

            IF v_vassal_gold_tick > 0 THEN
                UPDATE profiles SET gold = GREATEST(0, gold - v_vassal_gold_tick),
                    updated_at = now() WHERE id = r.vassal_id;
                UPDATE profiles SET gold = gold + v_vassal_gold_tick,
                    updated_at = now() WHERE id = r.liege_id;
            END IF;
        END;

        UPDATE profiles SET karma = karma
            + ROUND(v_liege_karma_per_day / 1440.0, 4)::NUMERIC
        WHERE id = r.liege_id;
    END LOOP;

    -- ========================================
    -- PHASE 9: APPLY PENDING BANS
    -- ========================================
    PERFORM apply_pending_bans();

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- STEP 2: Replace activate_prayer with
--         karma_awarded sync on activation
-- ============================================

CREATE OR REPLACE FUNCTION public.activate_prayer(p_prayer_id UUID)
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
    v_milestone_threshold INT;
BEGIN
    SELECT max_prayer_slots INTO v_max_slots
    FROM profiles WHERE id = v_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Profile not found';
    END IF;

    -- Load milestone threshold for karma_awarded sync
    SELECT COALESCE(value, 50) INTO v_milestone_threshold
    FROM game_config WHERE key = 'karma.milestone_threshold';

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

            v_cycle_time_ms := GREATEST(15000,
                LEAST(length(v_deactivated.cycle_text) * 200, 180000));
            v_elapsed_counts := GREATEST(0, floor(
                EXTRACT(EPOCH FROM (now()
                    - COALESCE(v_deactivated.last_counted_at,
                               v_deactivated.activated_at)))
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
    SET is_praying = true, activated_at = now(), last_counted_at = now(),
        -- Sync karma_awarded to match current prayer_count milestones
        karma_awarded = GREATEST(
            COALESCE(karma_awarded, 0),
            floor(prayer_count / v_milestone_threshold)
        )
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

-- ============================================
-- STEP 3: Grants
-- ============================================

GRANT EXECUTE ON FUNCTION calculate_automated_karma() TO service_role;
GRANT EXECUTE ON FUNCTION activate_prayer(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION activate_prayer(UUID) TO service_role;

-- ============================================
-- END OF EXODUS 4
-- ============================================