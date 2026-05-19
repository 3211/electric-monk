-- supabase/migrations/exodus_6_hotfix.sql
-- Description: v5 - Wraps Phase 2 and Phase 3 into a single Data-Modifying CTE to share scope.

BEGIN;

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
    v_tithe_pct NUMERIC;
    v_tick_divisor NUMERIC;
    v_liege_karma_per_day NUMERIC;
BEGIN
    -- Load config
    SELECT value INTO v_milestone_threshold FROM game_config WHERE key = 'karma.milestone_threshold';
    SELECT value INTO v_milestone_payout FROM game_config WHERE key = 'karma.milestone_payout';
    SELECT value INTO v_altruistic_multiplier FROM game_config WHERE key = 'karma.altruistic_multiplier';
    SELECT value INTO v_tithe_pct FROM game_config WHERE key = 'tithe.percentage';
    SELECT value INTO v_tick_divisor FROM game_config WHERE key = 'tick.production_divisor';
    SELECT value INTO v_liege_karma_per_day FROM game_config WHERE key = 'vassalage.liege_karma_per_day';

    IF v_milestone_threshold IS NULL THEN v_milestone_threshold := 50; END IF;
    IF v_milestone_payout IS NULL THEN v_milestone_payout := 5; END IF;
    IF v_altruistic_multiplier IS NULL THEN v_altruistic_multiplier := 2; END IF;
    IF v_tithe_pct IS NULL THEN v_tithe_pct := 0.10; END IF;
    IF v_tick_divisor IS NULL THEN v_tick_divisor := 144; END IF;
    IF v_liege_karma_per_day IS NULL THEN v_liege_karma_per_day := 5; END IF;

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
                last_counted_at = COALESCE(last_counted_at, activated_at) + (v_new_cycles * (v_cycle_s * interval '1 second'))
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
    -- PHASE 2 & 3: RESOURCE GENERATION & SYNOD TAX (Combined)
    -- ========================================
    WITH user_production AS (
        SELECT
            pb.user_id,
            COALESCE(SUM(gc_mana.value), 0)::NUMERIC AS gross_mana_per_day,
            COALESCE(SUM(gc_gold.value), 0)::NUMERIC AS gross_gold_per_day,
            COALESCE(SUM(gc_food.value), 0)::NUMERIC AS gross_food_per_day,
            COALESCE(SUM(gc_gold_upkeep.value), 0)::NUMERIC AS total_gold_upkeep_per_day,
            COALESCE(SUM(gc_food_consume.value), 0)::NUMERIC AS total_food_consumption_per_day,
            COALESCE(SUM(gc_heresy.value), 0)::NUMERIC AS gross_heresy_per_day,
            COALESCE(SUM(gc_dogma.value), 0)::NUMERIC AS gross_dogma_per_day,
            COUNT(CASE WHEN pb.building_type = 'coven' THEN 1 END)::INT AS coven_count
        FROM player_buildings pb
        LEFT JOIN game_config gc_mana ON gc_mana.key = 'building.' || pb.building_type || '.mana_per_day'
        LEFT JOIN game_config gc_gold ON gc_gold.key = 'building.' || pb.building_type || '.gold_per_day'
        LEFT JOIN game_config gc_food ON gc_food.key = 'building.' || pb.building_type || '.food_per_day'
        LEFT JOIN game_config gc_gold_upkeep ON gc_gold_upkeep.key = 'building.' || pb.building_type || '.gold_upkeep_per_day'
        LEFT JOIN game_config gc_food_consume ON gc_food_consume.key = 'building.' || pb.building_type || '.food_consumption_per_day'
        LEFT JOIN game_config gc_heresy ON gc_heresy.key = 'building.' || pb.building_type || '.heresy_per_day'
        LEFT JOIN game_config gc_dogma ON gc_dogma.key = 'building.' || pb.building_type || '.dogma_per_day'
        WHERE pb.is_active = true
        GROUP BY pb.user_id
    ),
    all_players AS (
        SELECT
            p.id AS user_id,
            p.sect_type,
            p.synod_id,
            p.suzerain_id,
            COALESCE(up.gross_mana_per_day, 0) AS gross_mana_per_day,
            COALESCE(up.gross_gold_per_day, 0) AS gross_gold_per_day,
            COALESCE(up.gross_food_per_day, 0) AS gross_food_per_day,
            COALESCE(up.total_gold_upkeep_per_day, 0) AS total_gold_upkeep_per_day,
            COALESCE(up.total_food_consumption_per_day, 0) AS total_food_consumption_per_day,
            COALESCE(up.gross_heresy_per_day, 0) AS gross_heresy_per_day,
            COALESCE(up.gross_dogma_per_day, 0) AS gross_dogma_per_day,
            COALESCE(up.coven_count, 0) AS coven_count
        FROM profiles p
        LEFT JOIN user_production up ON p.id = up.user_id
    ),
    sect_modified AS (
        SELECT
            ap.user_id, ap.sect_type, ap.synod_id, ap.suzerain_id,
            CASE WHEN ap.sect_type = 'gilded_path' THEN ap.gross_mana_per_day * COALESCE((SELECT value FROM game_config WHERE key = 'sect.gilded_path.mana_multiplier'), 0.8)
                 WHEN ap.sect_type = 'holy_way' THEN ap.gross_mana_per_day * COALESCE((SELECT value FROM game_config WHERE key = 'sect.holy_way.mana_multiplier'), 1.2)
                 WHEN ap.sect_type = 'black_tribunal' THEN ap.gross_mana_per_day * COALESCE((SELECT value FROM game_config WHERE key = 'sect.black_tribunal.mana_multiplier'), 0.7)
                 ELSE ap.gross_mana_per_day END AS mod_mana,
            CASE WHEN ap.sect_type = 'gilded_path' THEN ap.gross_gold_per_day * COALESCE((SELECT value FROM game_config WHERE key = 'sect.gilded_path.gold_multiplier'), 1.5)
                 WHEN ap.sect_type = 'final_watch' THEN ap.gross_gold_per_day * COALESCE((SELECT value FROM game_config WHERE key = 'sect.final_watch.gold_multiplier'), 0.75)
                 ELSE ap.gross_gold_per_day END AS mod_gold,
            CASE WHEN ap.sect_type = 'final_watch' THEN ap.gross_food_per_day * COALESCE((SELECT value FROM game_config WHERE key = 'sect.final_watch.food_multiplier'), 1.5)
                 ELSE ap.gross_food_per_day END AS mod_food,
            CASE WHEN ap.sect_type = 'gilded_path' THEN ap.total_gold_upkeep_per_day * COALESCE((SELECT value FROM game_config WHERE key = 'sect.gilded_path.cathedral_upkeep_multiplier'), 2.0)
                 ELSE ap.total_gold_upkeep_per_day END AS mod_gold_upkeep,
            CASE WHEN ap.sect_type = 'holy_way' THEN ap.total_food_consumption_per_day * COALESCE((SELECT value FROM game_config WHERE key = 'sect.holy_way.food_consumption_multiplier'), 0.5)
                 ELSE ap.total_food_consumption_per_day END AS mod_food_consume,
            CASE WHEN ap.sect_type = 'black_tribunal' THEN ap.gross_heresy_per_day * COALESCE((SELECT value FROM game_config WHERE key = 'sect.black_tribunal.heresy_multiplier'), 2.0)
                 ELSE ap.gross_heresy_per_day END AS mod_heresy,
            ap.gross_dogma_per_day,
            ap.coven_count
        FROM all_players ap
    ),
    tick_production AS (
        SELECT
            sm.user_id, sm.synod_id, sm.suzerain_id,
            GREATEST(0, FLOOR(sm.mod_mana / v_tick_divisor)) AS mana_tick,
            GREATEST(0, FLOOR(sm.mod_gold / v_tick_divisor)) AS gold_tick,
            GREATEST(0, FLOOR(sm.mod_food / v_tick_divisor)) AS food_tick,
            GREATEST(0, FLOOR(sm.mod_heresy / v_tick_divisor)) AS heresy_tick,
            GREATEST(0, FLOOR(sm.gross_dogma_per_day / v_tick_divisor)) AS dogma_tick,
            GREATEST(0, FLOOR(sm.mod_gold_upkeep / v_tick_divisor)) AS gold_upkeep_tick,
            GREATEST(0, FLOOR(sm.mod_food_consume / v_tick_divisor)) AS food_consume_tick,
            CASE WHEN sm.suzerain_id IS NOT NULL THEN FLOOR(sm.mod_mana / v_tick_divisor * v_tithe_pct) ELSE 0 END::INT AS mana_tithe_tick,
            CASE WHEN sm.suzerain_id IS NOT NULL THEN FLOOR(sm.mod_gold / v_tick_divisor * v_tithe_pct) ELSE 0 END::INT AS gold_tithe_tick,
            CASE WHEN sm.suzerain_id IS NOT NULL THEN FLOOR(sm.mod_food / v_tick_divisor * v_tithe_pct) ELSE 0 END::INT AS food_tithe_tick
        FROM sect_modified sm
    ),
    tithe_inbound AS (
        SELECT
            tp.suzerain_id AS receiver_id,
            COALESCE(SUM(tp.mana_tithe_tick), 0)::INT AS received_mana_tick,
            COALESCE(SUM(tp.gold_tithe_tick), 0)::INT AS received_gold_tick,
            COALESCE(SUM(tp.food_tithe_tick), 0)::INT AS received_food_tick
        FROM tick_production tp WHERE tp.suzerain_id IS NOT NULL
        GROUP BY tp.suzerain_id
    ),
    synod_tax AS (
        SELECT
            tp.user_id, tp.synod_id,
            FLOOR(tp.gold_tick * COALESCE(s.tax_rate, 0.05))::INT AS gold_synod_tax_tick,
            FLOOR(tp.mana_tick * COALESCE(s.tax_rate, 0.05))::INT AS mana_synod_tax_tick
        FROM tick_production tp
        JOIN synods s ON s.id = tp.synod_id WHERE tp.synod_id IS NOT NULL
    ),
    update_profiles AS (
        UPDATE profiles p SET
            mana = p.mana + tp.mana_tick - tp.mana_tithe_tick + COALESCE((SELECT received_mana_tick FROM tithe_inbound WHERE receiver_id = p.id), 0),
            gold = GREATEST(0, p.gold + tp.gold_tick - tp.gold_upkeep_tick - tp.gold_tithe_tick + COALESCE((SELECT received_gold_tick FROM tithe_inbound WHERE receiver_id = p.id), 0) - COALESCE((SELECT gold_synod_tax_tick FROM synod_tax WHERE user_id = p.id), 0)),
            food = GREATEST(0, p.food + tp.food_tick - tp.food_consume_tick - tp.food_tithe_tick + COALESCE((SELECT received_food_tick FROM tithe_inbound WHERE receiver_id = p.id), 0)),
            heresy = p.heresy + tp.heresy_tick,
            dogma = p.dogma + tp.dogma_tick,
            updated_at = now()
        FROM tick_production tp
        WHERE p.id = tp.user_id
    )
    UPDATE synods s SET
        vault_gold = vault_gold + COALESCE((SELECT SUM(st.gold_synod_tax_tick) FROM synod_tax st WHERE st.synod_id = s.id), 0),
        vault_mana = vault_mana + COALESCE((SELECT SUM(st.mana_synod_tax_tick) FROM synod_tax st WHERE st.synod_id = s.id), 0)
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
                EXCEPTION WHEN OTHERS THEN NULL;
                END;
            END IF;
        END;
    END LOOP;

    DELETE FROM build_queue WHERE executed_at IS NOT NULL AND executed_at < now() - interval '7 days';

    -- ========================================
    -- PHASE 6: PROCESS COMBAT TICKS
    -- ========================================
    FOR r IN SELECT id FROM combat_sessions WHERE is_active = true AND combat_type = 'pvp' LOOP
        DECLARE
            v_s RECORD;
            v_leech_pct NUMERIC;
            v_gold_per_tick NUMERIC;
            v_attrition NUMERIC;
            v_exertion NUMERIC;
            v_attacker_gold INT;
            v_defender_gold INT;
            v_leech INT;
            v_result TEXT;
            v_kill_karma INT;
        BEGIN
            SELECT * INTO v_s FROM combat_sessions WHERE id = r.id AND is_active = true;
            IF NOT FOUND THEN CONTINUE; END IF;

            SELECT COALESCE(value, 0.02) INTO v_leech_pct FROM game_config WHERE key = 'combat.pvp_leech_pct';
            SELECT COALESCE(value, 10) INTO v_gold_per_tick FROM game_config WHERE key = 'combat.pvp_gold_per_tick';
            SELECT COALESCE(value, 0.10) INTO v_attrition FROM game_config WHERE key = 'combat.pvp_attrition_pct';
            SELECT COALESCE(value, 0.05) INTO v_exertion FROM game_config WHERE key = 'combat.pvp_exertion_pct';

            SELECT gold INTO v_attacker_gold FROM profiles WHERE id = v_s.attacker_id;
            SELECT gold INTO v_defender_gold FROM profiles WHERE id = v_s.defender_id;

            v_s.defender_mana := GREATEST(0, v_s.defender_mana - v_s.attacker_workers);
            IF v_s.defender_workers > 0 THEN
                v_s.attacker_mana := GREATEST(0, v_s.attacker_mana - v_s.defender_workers);
            END IF;

            v_s.attacker_workers := GREATEST(0, v_s.attacker_workers - FLOOR(v_s.attacker_workers * v_attrition));
            v_s.attacker_mana := GREATEST(0, v_s.attacker_mana - FLOOR(v_s.attacker_mana * v_exertion));
            IF v_s.defender_workers > 0 THEN
                v_s.defender_workers := GREATEST(0, v_s.defender_workers - FLOOR(v_s.defender_workers * v_attrition));
            END IF;

            v_leech := FLOOR(v_defender_gold * v_leech_pct);
            v_s.gold_stolen := v_s.gold_stolen + v_leech;
            v_s.gold_spent := v_s.gold_spent + v_gold_per_tick;
            v_s.ticks_remaining := v_s.ticks_remaining - 1;

            IF v_s.defender_mana <= 0 THEN v_result := 'attacker_win';
            ELSIF v_s.attacker_mana <= 0 OR v_attacker_gold < v_gold_per_tick THEN v_result := 'defender_win';
            ELSIF v_s.ticks_remaining <= 0 THEN v_result := 'stalemate';
            END IF;

            IF v_leech > 0 THEN
                UPDATE profiles SET gold = GREATEST(0, gold - v_leech) WHERE id = v_s.defender_id;
            END IF;
            IF v_attacker_gold >= v_gold_per_tick THEN
                UPDATE profiles SET gold = gold - v_gold_per_tick, updated_at = now() WHERE id = v_s.attacker_id;
            END IF;

            IF v_result = 'attacker_win' THEN
                DECLARE
                    v_att_sect TEXT; v_def_sect TEXT; v_fr RECORD;
                BEGIN
                    SELECT sect_type INTO v_att_sect FROM profiles WHERE id = v_s.attacker_id;
                    SELECT sect_type INTO v_def_sect FROM profiles WHERE id = v_s.defender_id;
                    SELECT * INTO v_fr FROM faction_relationships WHERE sect_key = v_att_sect;

                    IF v_fr.enemy_sect = v_def_sect THEN
                        SELECT COALESCE(value, 5) INTO v_kill_karma FROM game_config WHERE key = 'combat.kill_enemy_karma';
                    ELSE
                        SELECT COALESCE(value, 1) INTO v_kill_karma FROM game_config WHERE key = 'combat.kill_neutral_karma';
                    END IF;
                END;

                UPDATE profiles SET karma = karma + v_kill_karma, updated_at = now() WHERE id = v_s.attacker_id;

                INSERT INTO akashic_logs (target_id, actor_id, action_type, result_data)
                VALUES (v_s.defender_id, v_s.attacker_id, 'crusade',
                    jsonb_build_object('type', 'pvp_victory', 'session_id', v_s.id, 'karma_gained', v_kill_karma));

            ELSIF v_result = 'defender_win' THEN
                INSERT INTO akashic_logs (target_id, actor_id, action_type, result_data)
                VALUES (v_s.defender_id, v_s.attacker_id, 'crusade',
                    jsonb_build_object('type', 'pvp_retreat', 'session_id', v_s.id));
            END IF;

            UPDATE combat_sessions SET
                attacker_mana = v_s.attacker_mana, defender_mana = v_s.defender_mana,
                attacker_workers = v_s.attacker_workers, defender_workers = v_s.defender_workers,
                ticks_remaining = v_s.ticks_remaining, gold_stolen = v_s.gold_stolen,
                gold_spent = v_s.gold_spent, last_tick_at = now(),
                is_active = CASE WHEN v_result IS NOT NULL THEN false ELSE true END,
                result = v_result
            WHERE id = v_s.id;
        END;
    END LOOP;

    FOR r IN SELECT id FROM combat_sessions WHERE is_active = true AND combat_type = 'holy_war' LOOP
        PERFORM process_holy_war_tick(r.id);
    END LOOP;

    -- ========================================
    -- PHASE 7: ADVANCE SUBJUGATION TIMERS
    -- ========================================
    FOR r IN
        SELECT cs.attacker_id, cs.defender_id
        FROM combat_sessions cs
        WHERE cs.combat_type = 'pvp' AND cs.is_active = true
          AND EXISTS (SELECT 1 FROM subjugation_timers st
                       WHERE st.liege_id = cs.attacker_id AND st.vassal_id = cs.defender_id
                         AND st.accumulated_hours < 168)
    LOOP
        UPDATE subjugation_timers
        SET accumulated_hours = accumulated_hours + (1.0 / 60.0),
            last_attack_at = now()
        WHERE liege_id = r.attacker_id AND vassal_id = r.defender_id
          AND accumulated_hours < 168;

        IF EXISTS (
            SELECT 1 FROM subjugation_timers
            WHERE liege_id = r.attacker_id AND vassal_id = r.defender_id
              AND accumulated_hours >= 168
        ) THEN
            UPDATE profiles SET suzerain_id = r.attacker_id, updated_at = now()
            WHERE id = r.defender_id AND suzerain_id IS NULL;

            INSERT INTO akashic_logs (target_id, actor_id, action_type, result_data)
            VALUES (r.defender_id, r.attacker_id, 'crusade',
                jsonb_build_object('type', 'subjugation_complete', 'liege_id', r.attacker_id, 'vassal_id', r.defender_id));

            DELETE FROM subjugation_timers WHERE liege_id = r.attacker_id AND vassal_id = r.defender_id;
        END IF;
    END LOOP;

    -- ========================================
    -- PHASE 8: VASSAL TITHES + LIEGE KARMA
    -- ========================================
    FOR r IN
        SELECT p.id AS vassal_id, p.suzerain_id AS liege_id
        FROM profiles p WHERE p.suzerain_id IS NOT NULL
    LOOP
        DECLARE
            v_vassal_gold_tick INT;
        BEGIN
            SELECT COALESCE(
                FLOOR(SUM(COALESCE((SELECT value FROM game_config WHERE key = 'building.' || pb.building_type || '.gold_per_day'), 0)) / v_tick_divisor * v_tithe_pct),
                0
            ) INTO v_vassal_gold_tick
            FROM player_buildings pb
            WHERE pb.user_id = r.vassal_id AND pb.is_active = true;

            IF v_vassal_gold_tick > 0 THEN
                UPDATE profiles SET gold = GREATEST(0, gold - v_vassal_gold_tick), updated_at = now()
                WHERE id = r.vassal_id;
                UPDATE profiles SET gold = gold + v_vassal_gold_tick, updated_at = now()
                WHERE id = r.liege_id;
            END IF;
        END;

        UPDATE profiles SET karma = karma + ROUND(v_liege_karma_per_day / 1440.0, 4)::NUMERIC
        WHERE id = r.liege_id;
    END LOOP;

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT;