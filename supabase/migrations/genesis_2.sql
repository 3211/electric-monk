-- =====================================================
-- ELECTRIC MONK — GENESIS SEED (Part 2: RPC Functions)
-- Continues from genesis_1.sql
-- Contains: All game RPC functions except
--   calculate_automated_karma (see genesis_3.sql)
--
-- Run AFTER genesis_1.sql, BEFORE genesis_3.sql.
-- =====================================================

-- ============================================
-- 7d. RPC: choose_sect(p_sect_type TEXT)
-- ============================================

CREATE OR REPLACE FUNCTION public.choose_sect(p_sect_type TEXT)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_current_sect TEXT;
BEGIN
    IF p_sect_type NOT IN ('prosperity_gospel', 'ascetic_order', 'doomsday_preppers', 'inquisition') THEN
        RAISE EXCEPTION 'Invalid sect type. Must be one of: prosperity_gospel, ascetic_order, doomsday_preppers, inquisition';
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

-- ============================================
-- 7e. RPC: launch_inquisition(p_target_id UUID)
-- ============================================

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
    IF v_sect_type = 'inquisition' THEN
        SELECT value INTO v_cost_multiplier FROM game_config WHERE key = 'sect.inquisition.inquisition_gold_cost_multiplier';
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

-- ============================================
-- 7f. RPC: research_tech(p_node_id TEXT)
-- ============================================

CREATE OR REPLACE FUNCTION public.research_tech(p_node_id TEXT)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_node RECORD;
    v_user_dogma INT;
    v_user_heresy INT;
    v_already_unlocked INT;
    v_prereq_met BOOLEAN;
    v_expiry TIMESTAMPTZ;
BEGIN
    SELECT * INTO v_node FROM research_nodes WHERE id = p_node_id AND is_active = true;
    IF NOT FOUND THEN RAISE EXCEPTION 'Research node not found or inactive'; END IF;

    -- Check if already unlocked
    SELECT COUNT(*) INTO v_already_unlocked FROM player_research
    WHERE user_id = v_user_id AND node_id = p_node_id
      AND (expires_at IS NULL OR expires_at > now());
    IF v_already_unlocked > 0 THEN
        RAISE EXCEPTION 'Already researched: %', p_node_id;
    END IF;

    -- Check prerequisite
    IF v_node.requires_node IS NOT NULL THEN
        SELECT EXISTS(
            SELECT 1 FROM player_research
            WHERE user_id = v_user_id AND node_id = v_node.requires_node
              AND (expires_at IS NULL OR expires_at > now())
        ) INTO v_prereq_met;
        IF NOT v_prereq_met THEN
            RAISE EXCEPTION 'Prerequisite not met: %', v_node.requires_node;
        END IF;
    END IF;

    -- Check currency and deduct
    IF v_node.alignment = 'light' THEN
        SELECT dogma INTO v_user_dogma FROM profiles WHERE id = v_user_id;
        IF v_user_dogma < v_node.cost THEN
            RAISE EXCEPTION 'Insufficient Dogma. Need %, have %.', v_node.cost, v_user_dogma;
        END IF;
        UPDATE profiles SET dogma = dogma - v_node.cost, updated_at = now() WHERE id = v_user_id;
    ELSIF v_node.alignment = 'dark' THEN
        SELECT heresy INTO v_user_heresy FROM profiles WHERE id = v_user_id;
        IF v_user_heresy < v_node.cost THEN
            RAISE EXCEPTION 'Insufficient Heresy. Need %, have %.', v_node.cost, v_user_heresy;
        END IF;
        UPDATE profiles SET heresy = heresy - v_node.cost, updated_at = now() WHERE id = v_user_id;
    END IF;

    -- Set expiry for timed effects
    IF v_node.effect_type = 'tithe_intercept' THEN
        v_expiry := now() + (COALESCE((v_node.effect_data->>'duration_hours')::NUMERIC, 12) * interval '1 hour');
    ELSIF v_node.effect_type = 'inquisition_immunity' THEN
        v_expiry := now() + (COALESCE((v_node.effect_data->>'duration_hours')::NUMERIC, 24) * interval '1 hour');
    ELSE
        v_expiry := NULL;
    END IF;

    -- Insert research unlock
    INSERT INTO player_research (user_id, node_id, expires_at)
    VALUES (v_user_id, p_node_id, v_expiry);

    -- Apply immediate effects (like acres bonus)
    IF v_node.effect_type = 'acres_bonus' THEN
        UPDATE profiles SET sacred_acres = sacred_acres + COALESCE((v_node.effect_data->>'acres_bonus')::INT, 10), updated_at = now()
        WHERE id = v_user_id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'node_id', p_node_id,
        'alignment', v_node.alignment,
        'cost', v_node.cost,
        'effect_type', v_node.effect_type,
        'effect_data', v_node.effect_data,
        'expires_at', v_expiry
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 7g. RPC: create_synod(p_name TEXT)
-- ============================================

CREATE OR REPLACE FUNCTION public.create_synod(p_name TEXT)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_user_gold INT;
    v_creation_cost NUMERIC;
    v_existing_synod UUID;
    v_new_synod_id UUID;
BEGIN
    -- Check name length
    IF LENGTH(p_name) < 3 OR LENGTH(p_name) > 30 THEN
        RAISE EXCEPTION 'Synod name must be between 3 and 30 characters';
    END IF;

    -- Check user not already in a synod
    SELECT synod_id INTO v_existing_synod FROM profiles WHERE id = v_user_id;
    IF v_existing_synod IS NOT NULL THEN
        RAISE EXCEPTION 'You are already in a Synod. Leave your current Synod first.';
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

    -- Create synod
    INSERT INTO synods (name, leader_id, tax_rate)
    VALUES (p_name, v_user_id, 0.05)
    RETURNING id INTO v_new_synod_id;

    -- Set user's synod_id
    UPDATE profiles SET synod_id = v_new_synod_id, updated_at = now() WHERE id = v_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'synod_id', v_new_synod_id,
        'name', p_name,
        'gold_spent', v_creation_cost
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 7h. RPC: join_synod(p_synod_id UUID)
-- ============================================

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

    -- Join
    UPDATE profiles SET synod_id = p_synod_id, updated_at = now() WHERE id = v_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'synod_id', p_synod_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 7i. RPC: leave_synod()
-- ============================================

CREATE OR REPLACE FUNCTION public.leave_synod()
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_synod_id UUID;
    v_is_leader BOOLEAN;
    v_member_count INT;
    v_oldest_member_id UUID;
BEGIN
    SELECT synod_id INTO v_synod_id FROM profiles WHERE id = v_user_id;
    IF v_synod_id IS NULL THEN
        RAISE EXCEPTION 'You are not in a Synod';
    END IF;

    -- Check if leader
    SELECT (leader_id = v_user_id), id INTO v_is_leader, v_synod_id
    FROM synods WHERE id = v_synod_id;

    -- Remove user from synod
    UPDATE profiles SET synod_id = NULL, updated_at = now() WHERE id = v_user_id;

    IF v_is_leader THEN
        -- Find oldest member to promote
        SELECT id INTO v_oldest_member_id
        FROM profiles
        WHERE synod_id = v_synod_id AND id != v_user_id
        ORDER BY created_at ASC
        LIMIT 1;

        IF v_oldest_member_id IS NOT NULL THEN
            -- Promote new leader
            UPDATE synods SET leader_id = v_oldest_member_id WHERE id = v_synod_id;
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
-- 7j. RPC: declare_holy_war(p_target_synod_id UUID)
-- ============================================

CREATE OR REPLACE FUNCTION public.declare_holy_war(p_target_synod_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_attacker_synod_id UUID;
    v_is_leader BOOLEAN;
    v_duration_hours NUMERIC;
    v_already_at_war INT;
BEGIN
    -- Get user's synod
    SELECT synod_id INTO v_attacker_synod_id FROM profiles WHERE id = v_user_id;
    IF v_attacker_synod_id IS NULL THEN
        RAISE EXCEPTION 'You are not in a Synod';
    END IF;

    -- Check user is leader
    SELECT (leader_id = v_user_id) INTO v_is_leader FROM synods WHERE id = v_attacker_synod_id;
    IF NOT v_is_leader THEN
        RAISE EXCEPTION 'Only the Synod leader can declare Holy War';
    END IF;

    -- Can't declare war on yourself
    IF p_target_synod_id = v_attacker_synod_id THEN
        RAISE EXCEPTION 'Cannot declare Holy War on your own Synod';
    END IF;

    -- Check target synod exists
    IF NOT EXISTS (SELECT 1 FROM synods WHERE id = p_target_synod_id) THEN
        RAISE EXCEPTION 'Target Synod not found';
    END IF;

    -- Check not already at war
    SELECT COUNT(*) INTO v_already_at_war FROM synod_wars
    WHERE attacker_synod_id = v_attacker_synod_id
      AND defender_synod_id = p_target_synod_id
      AND is_active = true;

    IF v_already_at_war > 0 THEN
        RAISE EXCEPTION 'Already at war with this Synod';
    END IF;

    -- Get duration
    SELECT value INTO v_duration_hours FROM game_config WHERE key = 'synod.holy_war_duration_hours';
    IF v_duration_hours IS NULL THEN v_duration_hours := 48; END IF;

    -- Create war
    INSERT INTO synod_wars (attacker_synod_id, defender_synod_id, expires_at)
    VALUES (v_attacker_synod_id, p_target_synod_id, now() + (v_duration_hours * interval '1 hour'));

    RETURN jsonb_build_object(
        'success', true,
        'attacker_synod_id', v_attacker_synod_id,
        'defender_synod_id', p_target_synod_id,
        'duration_hours', v_duration_hours
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 7k. RPC: attempt_relic_steal(p_relic_id UUID)
-- ============================================

CREATE OR REPLACE FUNCTION public.attempt_relic_steal(p_relic_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_relic RECORD;
    v_user_synod_id UUID;
    v_required_crusades INT;
    v_window_hours NUMERIC;
    v_stolen BOOLEAN := false;
BEGIN
    -- Get user's synod
    SELECT synod_id INTO v_user_synod_id FROM profiles WHERE id = v_user_id;
    IF v_user_synod_id IS NULL THEN
        RAISE EXCEPTION 'You must be in a Synod to steal a relic';
    END IF;

    -- Get relic
    SELECT * INTO v_relic FROM relics WHERE id = p_relic_id AND is_active = true;
    IF NOT FOUND THEN RAISE EXCEPTION 'Relic not found'; END IF;

    -- Can't steal from yourself
    IF v_relic.holder_id = v_user_id THEN
        RAISE EXCEPTION 'You already hold this relic';
    END IF;

    -- Can't steal unowned relics (claim directly)
    IF v_relic.holder_id IS NULL THEN
        UPDATE relics SET holder_id = v_user_id, last_stolen_at = now(), steal_progress = 0, steal_window_start = NULL
        WHERE id = p_relic_id;
        RETURN jsonb_build_object('success', true, 'action', 'claimed', 'relic_id', p_relic_id);
    END IF;

    -- Get config
    SELECT value INTO v_required_crusades FROM game_config WHERE key = 'synod.relic_steal_crusades_required';
    IF v_required_crusades IS NULL THEN v_required_crusades := 5; END IF;

    SELECT value INTO v_window_hours FROM game_config WHERE key = 'synod.relic_steal_window_hours';
    IF v_window_hours IS NULL THEN v_window_hours := 1; END IF;

    -- Check if window has expired, reset if so
    IF v_relic.steal_window_start IS NOT NULL AND v_relic.steal_window_start < (now() - (v_window_hours * interval '1 hour')) THEN
        UPDATE relics SET steal_progress = 0, steal_window_start = NULL WHERE id = p_relic_id;
        v_relic.steal_progress := 0;
        v_relic.steal_window_start := NULL;
    END IF;

    -- Start new window if needed
    IF v_relic.steal_window_start IS NULL THEN
        UPDATE relics SET steal_window_start = now(), steal_progress = 0 WHERE id = p_relic_id;
        v_relic.steal_window_start := now();
        v_relic.steal_progress := 0;
    END IF;

    -- Increment steal progress
    UPDATE relics SET steal_progress = steal_progress + 1 WHERE id = p_relic_id;

    -- Check if threshold met
    SELECT steal_progress INTO v_relic.steal_progress FROM relics WHERE id = p_relic_id;

    IF v_relic.steal_progress >= v_required_crusades THEN
        UPDATE relics SET holder_id = v_user_id, last_stolen_at = now(), steal_progress = 0, steal_window_start = NULL
        WHERE id = p_relic_id;
        v_stolen := true;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'relic_id', p_relic_id,
        'steal_progress', LEAST(v_relic.steal_progress + 1, v_required_crusades),
        'required_progress', v_required_crusades,
        'stolen', v_stolen
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 7l. RPC: consume_indulgence(p_action_type TEXT)
-- ============================================

CREATE OR REPLACE FUNCTION public.consume_indulgence(p_action_type TEXT)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_user_indulgences INT;
    v_user_synod_id UUID;
    v_cost INT;
    v_duration_hours NUMERIC;
    v_at_war BOOLEAN;
    v_queue_limit INT;
    v_current_queue INT;
    v_papal_bull_cost NUMERIC;
    v_architect_cost NUMERIC;
BEGIN
    -- Get user indulgences
    SELECT indulgences, synod_id INTO v_user_indulgences, v_user_synod_id
    FROM profiles WHERE id = v_user_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found'; END IF;

    CASE p_action_type
        WHEN 'papal_bull' THEN
            -- Get cost
            SELECT value INTO v_papal_bull_cost FROM game_config WHERE key = 'indulgence.papal_bull_cost';
            IF v_papal_bull_cost IS NULL THEN v_papal_bull_cost := 500; END IF;
            v_cost := v_papal_bull_cost::INT;

            -- Get duration
            SELECT value INTO v_duration_hours FROM game_config WHERE key = 'indulgence.papal_bull_duration_hours';
            IF v_duration_hours IS NULL THEN v_duration_hours := 12; END IF;

            -- Check if in active Holy War
            IF v_user_synod_id IS NOT NULL THEN
                SELECT EXISTS(
                    SELECT 1 FROM synod_wars
                    WHERE (attacker_synod_id = v_user_synod_id OR defender_synod_id = v_user_synod_id)
                      AND is_active = true
                ) INTO v_at_war;
                IF v_at_war THEN
                    RAISE EXCEPTION 'Cannot activate Papal Bull during an active Holy War';
                END IF;
            END IF;

            -- Check balance
            IF v_user_indulgences < v_cost THEN
                RAISE EXCEPTION 'Insufficient Indulgences. Need %, have %.', v_cost, v_user_indulgences;
            END IF;

            -- Deduct and activate
            UPDATE profiles SET
                indulgences = indulgences - v_cost,
                papal_bull_until = now() + (v_duration_hours * interval '1 hour'),
                updated_at = now()
            WHERE id = v_user_id;

            -- Create active_miracles record
            INSERT INTO active_miracles (user_id, miracle_type, effect_data, expires_at)
            VALUES (v_user_id, 'papal_bull', '{"immunity": true}'::jsonb, now() + (v_duration_hours * interval '1 hour'));

            RETURN jsonb_build_object(
                'success', true,
                'action', 'papal_bull',
                'indulgences_spent', v_cost,
                'expires_at', now() + (v_duration_hours * interval '1 hour')
            );

        WHEN 'divine_architect' THEN
            -- Get cost
            SELECT value INTO v_architect_cost FROM game_config WHERE key = 'indulgence.divine_architect_cost';
            IF v_architect_cost IS NULL THEN v_architect_cost := 200; END IF;
            v_cost := v_architect_cost::INT;

            -- Get queue limit
            SELECT value INTO v_queue_limit FROM game_config WHERE key = 'indulgence.divine_architect_queue_limit';
            IF v_queue_limit IS NULL THEN v_queue_limit := 5; END IF;

            -- Check current queue
            SELECT COUNT(*) INTO v_current_queue FROM build_queue
            WHERE user_id = v_user_id AND executed_at IS NULL;

            IF v_current_queue >= v_queue_limit THEN
                RAISE EXCEPTION 'Build queue is full. Maximum % items.', v_queue_limit;
            END IF;

            -- Check balance
            IF v_user_indulgences < v_cost THEN
                RAISE EXCEPTION 'Insufficient Indulgences. Need %, have %.', v_cost, v_user_indulgences;
            END IF;

            -- Deduct
            UPDATE profiles SET indulgences = indulgences - v_cost, updated_at = now() WHERE id = v_user_id;

            -- Create active_miracles record for tracking
            INSERT INTO active_miracles (user_id, miracle_type, effect_data, expires_at)
            VALUES (v_user_id, 'divine_architect', jsonb_build_object('queue_limit', v_queue_limit), now() + interval '7 days');

            RETURN jsonb_build_object(
                'success', true,
                'action', 'divine_architect',
                'indulgences_spent', v_cost,
                'queue_limit', v_queue_limit
            );

        ELSE
            RAISE EXCEPTION 'Unknown indulgence action: %', p_action_type;
    END CASE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 7m. RPC: get_synod_info()
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

    -- Get members
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', p.id,
        'username', p.username,
        'faith', p.faith,
        'sect_type', p.sect_type
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

    RETURN jsonb_build_object(
        'in_synod', true,
        'synod', v_synod,
        'members', v_members,
        'member_count', v_member_count,
        'wars', v_wars
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 7n. RPC: get_relics()
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
        'emoji_icon', r.emoji_icon,
        'effect_type', r.effect_type,
        'effect_data', r.effect_data,
        'holder_id', r.holder_id,
        'holder_username', p.username,
        'steal_progress', r.steal_progress,
        'last_stolen_at', r.last_stolen_at
    )), '[]'::jsonb) INTO v_result
    FROM relics r
    LEFT JOIN profiles p ON p.id = r.holder_id
    WHERE r.is_active = true;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 7o. RPC: get_research_tree()
-- ============================================

CREATE OR REPLACE FUNCTION public.get_research_tree()
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_nodes JSONB;
    v_unlocks JSONB;
BEGIN
    -- Get all research nodes
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', rn.id,
        'name', rn.name,
        'description', rn.description,
        'emoji_icon', rn.emoji_icon,
        'alignment', rn.alignment,
        'cost', rn.cost,
        'effect_type', rn.effect_type,
        'effect_data', rn.effect_data,
        'requires_node', rn.requires_node,
        'sort_order', rn.sort_order
    )), '[]'::jsonb) INTO v_nodes
    FROM research_nodes rn WHERE rn.is_active = true;

    -- Get user's unlocked research
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'node_id', pr.node_id,
        'unlocked_at', pr.unlocked_at,
        'expires_at', pr.expires_at
    )), '[]'::jsonb) INTO v_unlocks
    FROM player_research pr
    WHERE pr.user_id = v_user_id
      AND (pr.expires_at IS NULL OR pr.expires_at > now());

    RETURN jsonb_build_object(
        'nodes', v_nodes,
        'unlocks', v_unlocks
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 7p. RPC: get_sect_info()
-- ============================================

CREATE OR REPLACE FUNCTION public.get_sect_info()
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_sect_type TEXT;
    v_modifiers JSONB;
BEGIN
    SELECT sect_type INTO v_sect_type FROM profiles WHERE id = v_user_id;

    IF v_sect_type IS NULL THEN
        RETURN jsonb_build_object('sect_type', NULL, 'modifiers', '[]'::jsonb);
    END IF;

    -- Get all modifiers for this sect
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'key', gc.key,
        'value', gc.value,
        'description', gc.description
    )), '[]'::jsonb) INTO v_modifiers
    FROM game_config gc
    WHERE gc.key LIKE 'sect.' || v_sect_type || '.%';

    RETURN jsonb_build_object(
        'sect_type', v_sect_type,
        'modifiers', v_modifiers
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 7q. RPC: launch_crusade(p_target_id UUID) — v2 with Acre Theft, LIFO Ruin, Sect/Relic/War Bonuses
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

    -- Check target is not shielded (Divine Shield from Schism)
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

    -- Apply Doomsday Preppers defense bonus
    IF v_target_sect = 'doomsday_preppers' THEN
        SELECT COALESCE(value, 0.5) INTO v_sect_defense_bonus FROM game_config WHERE key = 'sect.doomsday_preppers.crusade_defense_bonus';
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

        -- LIFO Ruin Check: Deactivate buildings if defender's used acres exceed remaining acres
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

-- ============================================
-- 7r. RPC: declare_schism()
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
-- 7s. RPC: cast_plague(p_target_id UUID)
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
-- 7t. RPC: purchase_shop_item(p_item_id TEXT) — v3 with Acre Validation + Sect Restrictions
-- ============================================

CREATE OR REPLACE FUNCTION public.purchase_shop_item(p_item_id TEXT)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_item RECORD;
    v_user_karma INT;
    v_user_gold INT;
    v_user_heresy INT;
    v_user_acres INT;
    v_user_used_acres INT;
    v_user_sect TEXT;
    v_actual_karma_cost INT;
    v_actual_gold_cost INT;
    v_actual_heresy_cost INT;
    v_owned_count INT;
    v_effect_building_type TEXT;
    v_building_count INT;
    v_scaling_multiplier NUMERIC;
    v_acre_reduction NUMERIC;
    v_effective_acre_cost INT;
BEGIN
    -- Look up the shop item
    SELECT * INTO v_item FROM shop_items WHERE id = p_item_id AND is_active = true;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Shop item not found or inactive';
    END IF;

    -- Get user info
    SELECT karma, gold, heresy, sacred_acres, sect_type
    INTO v_user_karma, v_user_gold, v_user_heresy, v_user_acres, v_user_sect
    FROM profiles WHERE id = v_user_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found'; END IF;

    -- Check sect exclusion
    IF v_item.sect_exclusion IS NOT NULL AND v_item.sect_exclusion = v_user_sect THEN
        RAISE EXCEPTION 'Your sect (%) cannot purchase this item.', v_user_sect;
    END IF;

    -- Check sect restriction
    IF v_item.sect_restriction IS NOT NULL AND v_item.sect_restriction != v_user_sect THEN
        RAISE EXCEPTION 'Only members of the % sect can purchase this item.', v_item.sect_restriction;
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

    -- Check sacred acres availability for buildings
    IF v_item.effect_type = 'add_building' AND v_item.acre_cost > 0 THEN
        v_effect_building_type := v_item.effect_data->>'building_type';

        -- Calculate effective acre cost (with Divine Architecture research reduction)
        v_effective_acre_cost := v_item.acre_cost;
        IF EXISTS (
            SELECT 1 FROM player_research pr
            JOIN research_nodes rn ON rn.id = pr.node_id
            WHERE pr.user_id = v_user_id AND rn.effect_type = 'acre_cost_reduction'
              AND (pr.expires_at IS NULL OR pr.expires_at > now())
        ) THEN
            SELECT COALESCE(value, 20) INTO v_acre_reduction FROM game_config WHERE key = 'sect.prosperity_gospel.cathedral_upkeep_multiplier';
            -- Use the research effect data directly
            v_effective_acre_cost := GREATEST(1, FLOOR(v_item.acre_cost * (1 - 0.20)));
        END IF;

        -- Calculate currently used acres
        SELECT COALESCE(SUM(COALESCE((SELECT value FROM game_config WHERE key = 'building.' || pb.building_type || '.acre_cost'), 0)), 0)::INT
        INTO v_user_used_acres
        FROM player_buildings pb
        WHERE pb.user_id = v_user_id AND pb.is_active = true;

        IF (v_user_used_acres + v_effective_acre_cost) > v_user_acres THEN
            RAISE EXCEPTION 'Insufficient Sacred Acres. You have % total, % used, and need % more. Free: %.',
                v_user_acres, v_user_used_acres, v_effective_acre_cost, v_user_acres - v_user_used_acres;
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
        'new_max_slots', (SELECT max_prayer_slots FROM profiles WHERE id = v_user_id),
        'new_sacred_acres', (SELECT sacred_acres FROM profiles WHERE id = v_user_id)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 7u. RPC: get_leaderboard(p_offset INT, p_limit INT)
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
            p.max_prayer_slots,
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
-- 7v. RPC: get_player_economy() — v3 with all new fields
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
        'synod', v_synod_info
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 7w. RPC: get_vassalage_info()
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
-- 7x. RPC: get_akashic_logs(p_limit INT, p_offset INT)
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
-- 7y. RPC: grant_blessing(p_prayer_id UUID, p_blessing_type_id TEXT)
-- ============================================

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
BEGIN
  -- Get blessing type details
  SELECT karma_cost, karma_to_giver, karma_to_receiver
  INTO v_cost, v_giver_karma, v_receiver_karma
  FROM blessing_types
  WHERE id = p_blessing_type_id AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Blessing type not found or inactive';
  END IF;

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

  -- Insert blessing record
  INSERT INTO prayer_blessings (prayer_id, blessing_type_id, giver_id, receiver_id)
  VALUES (p_prayer_id, p_blessing_type_id, v_user_id, v_prayer_owner)
  RETURNING id INTO v_blessing_id;

  RETURN jsonb_build_object(
    'id', v_blessing_id,
    'blessing_type_id', p_blessing_type_id,
    'karma_spent', v_cost,
    'karma_to_giver', v_giver_karma,
    'karma_to_receiver', v_receiver_karma
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 7z. RPC: get_prayer_blessings(p_prayer_ids UUID[])
-- ============================================

CREATE OR REPLACE FUNCTION get_prayer_blessings(p_prayer_ids UUID[])
RETURNS JSONB AS $$
DECLARE
  v_result JSONB;
BEGIN
  SELECT jsonb_agg(jsonb_build_object(
    'prayer_id', agg.prayer_id,
    'blessing_type_id', agg.blessing_type_id,
    'emoji', bt.emoji,
    'name', bt.name,
    'count', agg.cnt
  )) INTO v_result
  FROM (
    SELECT prayer_id, blessing_type_id, COUNT(*) as cnt
    FROM prayer_blessings
    WHERE prayer_id = ANY(p_prayer_ids)
    GROUP BY prayer_id, blessing_type_id
  ) agg
  JOIN blessing_types bt ON agg.blessing_type_id = bt.id;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 7aa. RPC: get_public_prayers (with blessings) — final version
-- ============================================

CREATE OR REPLACE FUNCTION get_public_prayers(
  p_offset INT DEFAULT 0,
  p_limit INT DEFAULT 20,
  p_sort_by TEXT DEFAULT 'newest'
)
RETURNS JSONB AS $$
DECLARE
  v_result JSONB;
  v_order_clause TEXT;
BEGIN
  IF p_sort_by = 'most_prayed' THEN
    v_order_clause := 'prayer_count DESC, created_at DESC';
  ELSE
    v_order_clause := 'created_at DESC';
  END IF;

  EXECUTE format(
    'SELECT jsonb_agg(row_to_json(t)) FROM (
      SELECT p.id, p.user_id, p.response_content, p.prayer_count,
             p.created_at, p.prayer_type,
             pr.username, pr.faith,
             COALESCE(
               (SELECT jsonb_agg(jsonb_build_object(
                   ''blessing_type_id'', pb.blessing_type_id,
                   ''emoji'', bt.emoji,
                   ''name'', bt.name,
                   ''count'', pb.cnt
                 ) ORDER BY bt.sort_order)
                 FROM (
                   SELECT blessing_type_id, COUNT(*) as cnt
                   FROM prayer_blessings
                   WHERE prayer_id = p.id
                   GROUP BY blessing_type_id
                 ) pb
                 JOIN blessing_types bt ON pb.blessing_type_id = bt.id
               ),
               ''[]''::jsonb
              ) as blessings
      FROM prayers p
      LEFT JOIN profiles pr ON p.user_id = pr.id
      WHERE p.is_rejected = false
        AND p.is_archived = false
        AND p.status = ''completed''
        AND p.prayer_type = ''own''
      ORDER BY %s
      LIMIT %s OFFSET %s
    ) t',
    v_order_clause, p_limit, p_offset
  ) INTO v_result;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- END OF GENESIS PART 2 (RPC Functions)
-- Continue with genesis_3.sql for calculate_automated_karma
-- ============================================