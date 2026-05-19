-- ============================================
-- Exodus 5: Combat Unification & Siege Rebalance
-- ============================================
--
-- Fixes:
--   1. tithe.percentage config key never inserted (reads
--      always fell back to default 0.10)
--   2. Siege durations rescaled: PvP = 3 days, Holy War = 7 days
--   3. New cancel_combat RPC — attacker withdraws at cost
--   4. New surrender_combat RPC — defender gives up immediately
--   5. combat_sessions.result CHECK extended with 'cancelled'
--
-- Run after exodus_4.

-- ============================================
-- STEP 0: Fix tithe.percentage key (missing)
-- ============================================
INSERT INTO game_config (key, value, description, category)
VALUES ('tithe.percentage', 0.10,
        'Fraction of production paid as tithe to liege',
        'vassalage')
ON CONFLICT (key) DO NOTHING;

-- ============================================
-- STEP 1: Rescale siege durations
-- ============================================
-- PvP: 30 ticks → 4320 ticks (3 days at 1/min)
-- Holy War: 60 ticks → 10080 ticks (7 days at 1/min)
-- Per-tick costs lowered proportionally so total cost
-- over full duration is meaningful but not bankrupting.

UPDATE game_config SET value = 4320, updated_at = now()
WHERE key = 'combat.pvp_max_ticks';

UPDATE game_config SET value = 10080, updated_at = now()
WHERE key = 'combat.holy_war_max_ticks';

UPDATE game_config SET value = 2, updated_at = now()
WHERE key = 'combat.pvp_gold_per_tick';

UPDATE game_config SET value = 10, updated_at = now()
WHERE key = 'combat.holy_war_gold_per_tick';

UPDATE game_config SET value = 0.005, updated_at = now()
WHERE key = 'combat.pvp_leech_pct';

UPDATE game_config SET value = 0.002, updated_at = now()
WHERE key = 'combat.holy_war_leech_pct';

-- ============================================
-- STEP 2: cancel_combat — Attacker withdraws
-- ============================================
CREATE OR REPLACE FUNCTION public.cancel_combat(p_session_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_session RECORD;
    v_gold_per_tick NUMERIC;
    v_penalty_gold INT;
    v_user_gold INT;
    v_total_penalty INT;
BEGIN
    SELECT * INTO v_session FROM combat_sessions
    WHERE id = p_session_id AND is_active = true;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Session not found or already resolved'
        );
    END IF;

    IF v_session.attacker_id != v_user_id THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Only the attacker can cancel a siege'
        );
    END IF;

    -- Determine gold per tick based on combat type
    IF v_session.combat_type = 'holy_war' THEN
        SELECT COALESCE(value, 10) INTO v_gold_per_tick
        FROM game_config WHERE key = 'combat.holy_war_gold_per_tick';
    ELSE
        SELECT COALESCE(value, 2) INTO v_gold_per_tick
        FROM game_config WHERE key = 'combat.pvp_gold_per_tick';
    END IF;

    -- 50% of remaining tick cost
    v_penalty_gold := FLOOR(v_session.ticks_remaining * v_gold_per_tick * 0.5);
    IF v_penalty_gold < 1 THEN v_penalty_gold := 1; END IF;

    SELECT gold INTO v_user_gold FROM profiles WHERE id = v_user_id;

    -- Drain what we can, cap at available gold
    IF v_user_gold < v_penalty_gold THEN
        v_total_penalty := v_user_gold;
    ELSE
        v_total_penalty := v_penalty_gold;
    END IF;

    -- Deduct gold
    IF v_total_penalty > 0 THEN
        UPDATE profiles SET gold = GREATEST(0, gold - v_total_penalty),
            updated_at = now()
        WHERE id = v_user_id;
    END IF;

    -- Karma penalty
    UPDATE profiles SET karma = karma - 5, updated_at = now()
    WHERE id = v_user_id;

    -- Resolve the session as defender_win via cancellation
    UPDATE combat_sessions SET
        is_active = false,
        result = 'defender_win',
        ticks_remaining = v_session.ticks_remaining,
        last_tick_at = now()
    WHERE id = p_session_id;

    -- Clear attacker state
    IF v_session.combat_type = 'pvp' THEN
        UPDATE profiles SET active_combat_target_id = NULL
        WHERE id = v_user_id;
    ELSIF v_session.combat_type = 'holy_war' THEN
        UPDATE synods SET active_war_id = NULL
        WHERE id = v_session.attacker_synod_id;
    END IF;

    -- Log to akashic
    INSERT INTO akashic_logs (target_id, actor_id, action_type, result_data)
    VALUES (
        v_session.defender_id, v_user_id, 'crusade',
        jsonb_build_object(
            'type', CASE WHEN v_session.combat_type = 'holy_war'
                     THEN 'holy_war_cancelled' ELSE 'pvp_cancelled' END,
            'session_id', p_session_id,
            'gold_penalty', v_total_penalty,
            'karma_penalty', -5,
            'ticks_remaining', v_session.ticks_remaining
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'gold_penalty', v_total_penalty,
        'karma_penalty', -5,
        'result', 'defender_win'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- STEP 3: surrender_combat — Defender gives up
-- ============================================
CREATE OR REPLACE FUNCTION public.surrender_combat(p_session_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_session RECORD;
BEGIN
    SELECT * INTO v_session FROM combat_sessions
    WHERE id = p_session_id AND is_active = true;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Session not found or already resolved'
        );
    END IF;

    IF v_session.defender_id != v_user_id THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Only the defender can surrender'
        );
    END IF;

    -- Set vassaldom immediately (PvP only — Holy War surrenders
    -- go through vanquish)
    IF v_session.combat_type = 'pvp' THEN
        -- Check defender doesn't already have a suzerain
        IF NOT EXISTS (
            SELECT 1 FROM profiles
            WHERE id = v_session.defender_id AND suzerain_id IS NOT NULL
        ) THEN
            UPDATE profiles SET suzerain_id = v_session.attacker_id,
                updated_at = now()
            WHERE id = v_session.defender_id;
        END IF;
    ELSIF v_session.combat_type = 'holy_war' THEN
        -- Trigger vanquish for Holy War surrender
        PERFORM vanquish_synod(v_session.defender_synod_id, p_session_id);

        -- Clear attacker state
        UPDATE synods SET active_war_id = NULL
        WHERE id = v_session.attacker_synod_id;

        -- Resolve session
        UPDATE combat_sessions SET
            is_active = false,
            result = 'attacker_win',
            last_tick_at = now()
        WHERE id = p_session_id;

        RETURN jsonb_build_object(
            'success', true,
            'result', 'attacker_win',
            'vanquished', true
        );
    END IF;

    -- Resolve the session
    UPDATE combat_sessions SET
        is_active = false,
        result = 'attacker_win',
        last_tick_at = now()
    WHERE id = p_session_id;

    -- Clear attacker state
    UPDATE profiles SET active_combat_target_id = NULL
    WHERE id = v_session.attacker_id;

    -- Log to akashic
    INSERT INTO akashic_logs (target_id, actor_id, action_type, result_data)
    VALUES (
        v_session.defender_id, v_session.attacker_id, 'crusade',
        jsonb_build_object(
            'type', 'pvp_surrendered',
            'session_id', p_session_id,
            'new_suzerain_id', v_session.attacker_id
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'result', 'attacker_win',
        'vassaldom', true,
        'suzerain_id', v_session.attacker_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- STEP 4: GRANT EXECUTE on new RPCs
-- ============================================
GRANT EXECUTE ON FUNCTION cancel_combat(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION cancel_combat(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION surrender_combat(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION surrender_combat(UUID) TO service_role;

-- ============================================
-- END OF EXODUS 5
-- ============================================