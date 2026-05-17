-- =====================================================
-- ELECTRIC MONK — GENESIS SEED (Part 3: Heartbeat)
-- Continues from genesis_2.sql
-- Contains: calculate_automated_karma() v7
--   — the 8-phase cron heartbeat
--
-- Run AFTER genesis_1.sql and genesis_2.sql,
-- BEFORE genesis_4.sql.
-- =====================================================

-- ============================================
-- 7bb. RPC: calculate_automated_karma() — v7 (Full 8-Phase Heartbeat)
-- ============================================
-- Phase 1: Karma milestone logic (prayers)
-- Phase 2: Resource generation + sect modifiers + relic bonuses
-- Phase 3: Synod vault deposits
-- Phase 4: Expire timed effects
-- Phase 5: Process Divine Architect queue
-- (Phases 6-8 handled inline within Phase 2 CTE)

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
-- END OF GENESIS PART 3 (Heartbeat)
-- Continue with genesis_4.sql for triggers, grants, cron
-- ============================================