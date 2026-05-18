-- =====================================================
-- ELECTRIC MONK — EXODUS 2: Siege Combat, Vanquish & Ban System
-- Date: 2026-05-18
--
-- Run AFTER exodus_1.sql.  Patches (CREATE OR REPLACE) all
-- combat/synod/relic functions with siege mechanics.
--
-- Key changes:
--   A. Schema: ALTER synods (+active_war_id), ALTER profiles
--      (+active_combat_target_id), CREATE pending_bans,
--      game_config keys (balance_tolerance, siege lengths)
--   B. Relic steal: leader-only; triggers auto-Holy-War
--   C. PvP: 7-day siege, 1-at-a-time, dual betrayal bans,
--      win = vassaldom
--   D. Holy War: 30-day siege, 1-at-a-time, member-level
--      damage, vanquish = scatter + spoils + relics + ban
--   E. Pending bans: apply on login/periodic check
--   F. Heartbeat: live member stats, vanquish resolution
-- =====================================================

-- ============================================
-- PHASE A: SCHEMA PATCHES
-- ============================================

-- A1. synods: track the ONE war this synod is currently attacking
ALTER TABLE public.synods
  ADD COLUMN IF NOT EXISTS active_war_id UUID DEFAULT NULL;

COMMENT ON COLUMN public.synods.active_war_id IS
  'The single Holy War this synod is currently waging as attacker. NULL = not attacking.';

-- A2. profiles: track the ONE PvP target this player is attacking
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS active_combat_target_id UUID DEFAULT NULL;

COMMENT ON COLUMN public.profiles.active_combat_target_id IS
  'The single player this user is currently attacking in PvP. NULL = not attacking.';

-- A3. pending_bans: delayed bans applied on login or periodic sweep
CREATE TABLE IF NOT EXISTS pending_bans (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  ban_until TIMESTAMPTZ NOT NULL,
  ban_reason TEXT NOT NULL CHECK (ban_reason IN (
    'Attacked ally faction', 'Attacked own faction',
    'Synod attacked ally faction', 'Synod attacked own faction',
    'Synod vanquished'
  )),
  applied BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

COMMENT ON TABLE pending_bans IS 'Bans queued for application on next login or heartbeat sweep.';

ALTER TABLE pending_bans ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own pending bans" ON pending_bans;
CREATE POLICY "Users can view own pending bans" ON pending_bans
  FOR SELECT USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_pending_bans_user ON pending_bans(user_id, applied);

-- A4. Insert / update game_config keys
INSERT INTO game_config (key, value, description, category) VALUES
  ('faction.balance_tolerance', 2, 'Allowed difference from minimum member count for balanced onboarding', 'factions'),
  ('combat.pvp_max_ticks', 10080, 'Max PvP siege ticks (7 days of minutes)', 'combat'),
  ('combat.holy_war_max_ticks', 43200, 'Max Holy War siege ticks (30 days of minutes)', 'combat'),
  ('combat.vanquish_ban_minutes', 5, 'Ban minutes for members of a vanquished synod', 'combat')
ON CONFLICT (key) DO UPDATE SET
  value = EXCLUDED.value,
  description = EXCLUDED.description,
  category = EXCLUDED.category;

-- ============================================
-- PHASE B: RELIC STEAL (leader-only + auto Holy War)
-- ============================================

CREATE OR REPLACE FUNCTION public.attempt_relic_steal(p_relic_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_relic RECORD;
    v_user_synod_id UUID;
    v_user_role TEXT;
    v_prev_holder_synod UUID;
    v_prev_holder_id UUID;
    v_required_crusades INT;
    v_window_hours NUMERIC;
    v_stolen BOOLEAN := false;
    v_holy_war_initiated BOOLEAN := false;
BEGIN
    SELECT synod_id, synod_role INTO v_user_synod_id, v_user_role FROM profiles WHERE id = v_user_id;
    IF v_user_synod_id IS NULL THEN
        RAISE EXCEPTION 'You must be in a Synod to steal a relic';
    END IF;

    -- Leader-only check (Exodus 2)
    IF v_user_role != 'leader' THEN
        RAISE EXCEPTION 'Only the Synod leader can attempt to steal relics.';
    END IF;

    SELECT * INTO v_relic FROM relics WHERE id = p_relic_id AND is_active = true;
    IF NOT FOUND THEN RAISE EXCEPTION 'Relic not found'; END IF;

    IF v_relic.holder_id = v_user_id THEN
        RAISE EXCEPTION 'You already hold this relic';
    END IF;

    v_prev_holder_id := v_relic.holder_id;

    IF v_relic.holder_id IS NULL THEN
        UPDATE relics SET holder_id = v_user_id, last_stolen_at = now(), steal_progress = 0, steal_window_start = NULL
        WHERE id = p_relic_id;
        RETURN jsonb_build_object('success', true, 'action', 'claimed', 'relic_id', p_relic_id);
    END IF;

    SELECT value INTO v_required_crusades FROM game_config WHERE key = 'synod.relic_steal_crusades_required';
    IF v_required_crusades IS NULL THEN v_required_crusades := 5; END IF;

    SELECT value INTO v_window_hours FROM game_config WHERE key = 'synod.relic_steal_window_hours';
    IF v_window_hours IS NULL THEN v_window_hours := 1; END IF;

    IF v_relic.steal_window_start IS NOT NULL AND v_relic.steal_window_start < (now() - (v_window_hours * interval '1 hour')) THEN
        UPDATE relics SET steal_progress = 0, steal_window_start = NULL WHERE id = p_relic_id;
        v_relic.steal_progress := 0;
        v_relic.steal_window_start := NULL;
    END IF;

    IF v_relic.steal_window_start IS NULL THEN
        UPDATE relics SET steal_window_start = now(), steal_progress = 0 WHERE id = p_relic_id;
        v_relic.steal_window_start := now();
        v_relic.steal_progress := 0;
    END IF;

    UPDATE relics SET steal_progress = steal_progress + 1 WHERE id = p_relic_id;
    SELECT steal_progress INTO v_relic.steal_progress FROM relics WHERE id = p_relic_id;

    IF v_relic.steal_progress >= v_required_crusades THEN
        UPDATE relics SET holder_id = v_user_id, last_stolen_at = now(), steal_progress = 0, steal_window_start = NULL
        WHERE id = p_relic_id;
        v_stolen := true;

        -- Exodus 2: Auto-initiate Holy War against previous holder's synod
        IF v_prev_holder_id IS NOT NULL THEN
            SELECT synod_id INTO v_prev_holder_synod FROM profiles WHERE id = v_prev_holder_id;
            IF v_prev_holder_synod IS NOT NULL AND v_prev_holder_synod != v_user_synod_id THEN
                BEGIN
                    -- Initiate silently (ignore if already at war or attacking someone else)
                    PERFORM initiate_holy_war(v_prev_holder_synod);
                    v_holy_war_initiated := true;
                EXCEPTION WHEN OTHERS THEN
                    -- Holy War initiation may fail if already attacking; that's OK
                    NULL;
                END;
            END IF;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'relic_id', p_relic_id,
        'steal_progress', LEAST(v_relic.steal_progress, v_required_crusades),
        'required_progress', v_required_crusades,
        'stolen', v_stolen,
        'holy_war_initiated', v_holy_war_initiated
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- PHASE C: PvP SIEGE OVERHAUL
-- ============================================

CREATE OR REPLACE FUNCTION public.initiate_combat(p_target_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_user_sect TEXT;
    v_target_sect TEXT;
    v_initiation_cost NUMERIC;
    v_gold_per_tick NUMERIC;
    v_max_ticks NUMERIC;
    v_user_gold INT;
    v_user_mana INT;
    v_user_workers INT;
    v_target_mana INT;
    v_target_workers INT;
    v_session_id UUID;
    v_relation TEXT;
    v_ban_minutes NUMERIC;
    v_karma_penalty NUMERIC;
    v_user_existing_target UUID;
    v_target_existing_target UUID;
BEGIN
    IF p_target_id = v_user_id THEN
        RAISE EXCEPTION 'Cannot attack yourself';
    END IF;

    -- One-target-at-a-time check (Exodus 2)
    SELECT active_combat_target_id INTO v_user_existing_target FROM profiles WHERE id = v_user_id;
    IF v_user_existing_target IS NOT NULL THEN
        RAISE EXCEPTION 'You are already attacking someone. Withdraw or wait for the siege to end.';
    END IF;

    -- Check if target is already attacking someone else (doesn't block us attacking them)
    -- but we note it for the response

    SELECT sect_type, gold, mana INTO v_user_sect, v_user_gold, v_user_mana
    FROM profiles WHERE id = v_user_id;

    SELECT sect_type, mana, active_combat_target_id INTO v_target_sect, v_target_mana, v_target_existing_target
    FROM profiles WHERE id = p_target_id;

    IF NOT FOUND OR v_user_sect IS NULL OR v_target_sect IS NULL THEN
        RAISE EXCEPTION 'Both players must have chosen a faction.';
    END IF;

    -- Check target is not shielded (Exodus 2: enforce this strictly)
    IF EXISTS (
        SELECT 1 FROM profiles
        WHERE id = p_target_id AND divine_shield_until IS NOT NULL AND divine_shield_until > now()
    ) THEN
        RAISE EXCEPTION 'Target is protected by Divine Shield.';
    END IF;

    IF EXISTS (
        SELECT 1 FROM profiles
        WHERE id = p_target_id AND papal_bull_until IS NOT NULL AND papal_bull_until > now()
    ) THEN
        RAISE EXCEPTION 'Target is protected by Papal Bull.';
    END IF;

    SELECT value INTO v_initiation_cost FROM game_config WHERE key = 'combat.pvp_initiation_gold';
    IF v_initiation_cost IS NULL THEN v_initiation_cost := 50; END IF;

    SELECT value INTO v_gold_per_tick FROM game_config WHERE key = 'combat.pvp_gold_per_tick';
    IF v_gold_per_tick IS NULL THEN v_gold_per_tick := 10; END IF;

    SELECT value INTO v_max_ticks FROM game_config WHERE key = 'combat.pvp_max_ticks';
    IF v_max_ticks IS NULL THEN v_max_ticks := 10080; END IF;

    IF v_user_gold < v_initiation_cost THEN
        RAISE EXCEPTION 'Insufficient Gold. Need % to initiate combat.', v_initiation_cost;
    END IF;

    -- Determine faction relationship
    SELECT
        CASE
            WHEN v_user_sect = v_target_sect THEN 'own_faction'
            WHEN fr.ally_sect = v_target_sect THEN 'ally'
            WHEN fr.enemy_sect = v_target_sect THEN 'enemy'
            ELSE 'neutral'
        END
    INTO v_relation
    FROM faction_relationships fr WHERE fr.sect_key = v_user_sect;

    -- Exodus 2: Betrayal = ban BOTH attacker AND defender
    IF v_relation IN ('ally', 'own_faction') THEN
        IF v_relation = 'ally' THEN
            SELECT value INTO v_ban_minutes FROM game_config WHERE key = 'combat.betrayal_ally_ban_minutes';
            SELECT value INTO v_karma_penalty FROM game_config WHERE key = 'combat.betrayal_ally_karma';
            IF v_ban_minutes IS NULL THEN v_ban_minutes := 15; END IF;
            IF v_karma_penalty IS NULL THEN v_karma_penalty := -5; END IF;
        ELSE
            SELECT value INTO v_ban_minutes FROM game_config WHERE key = 'combat.betrayal_own_ban_minutes';
            SELECT value INTO v_karma_penalty FROM game_config WHERE key = 'combat.betrayal_own_karma';
            IF v_ban_minutes IS NULL THEN v_ban_minutes := 30; END IF;
            IF v_karma_penalty IS NULL THEN v_karma_penalty := -10; END IF;
        END IF;

        -- Ban attacker (extend if already banned)
        UPDATE profiles SET
            ban_until = GREATEST(COALESCE(ban_until, now()), now()) + (v_ban_minutes * interval '1 minute'),
            updated_at = now()
        WHERE id = v_user_id;

        UPDATE profiles SET karma = karma + v_karma_penalty, updated_at = now() WHERE id = v_user_id;

        INSERT INTO betrayal_punishments (user_id, target_id, betrayal_type, ban_until, karma_penalty)
        VALUES (v_user_id, p_target_id, v_relation,
            GREATEST(COALESCE((SELECT ban_until FROM profiles WHERE id = v_user_id), now()), now()) + (v_ban_minutes * interval '1 minute'),
            v_karma_penalty);

        -- ALSO ban defender (they participated in the betrayal too)
        UPDATE profiles SET
            ban_until = GREATEST(COALESCE(ban_until, now()), now()) + (v_ban_minutes * interval '1 minute'),
            updated_at = now()
        WHERE id = p_target_id;

        UPDATE profiles SET karma = karma + v_karma_penalty, updated_at = now() WHERE id = p_target_id;

        INSERT INTO betrayal_punishments (user_id, target_id, betrayal_type, ban_until, karma_penalty)
        VALUES (p_target_id, v_user_id, v_relation,
            GREATEST(COALESCE((SELECT ban_until FROM profiles WHERE id = p_target_id), now()), now()) + (v_ban_minutes * interval '1 minute'),
            v_karma_penalty);
    END IF;

    -- Deduct initiation cost
    UPDATE profiles SET gold = gold - v_initiation_cost, updated_at = now() WHERE id = v_user_id;

    -- Set active combat target (Exodus 2: one-at-a-time)
    UPDATE profiles SET active_combat_target_id = p_target_id, updated_at = now() WHERE id = v_user_id;

    SELECT COUNT(*)::INT INTO v_user_workers
    FROM player_buildings WHERE user_id = v_user_id AND is_active = true
      AND building_type IN ('novice', 'monk', 'cleric', 'bishop', 'cardinal', 'cultist');

    SELECT COUNT(*)::INT INTO v_target_workers
    FROM player_buildings WHERE user_id = p_target_id AND is_active = true
      AND building_type IN ('novice', 'monk', 'cleric', 'bishop', 'cardinal', 'cultist');

    INSERT INTO combat_sessions (
        combat_type, attacker_id, defender_id,
        ticks_total, ticks_remaining,
        attacker_mana, defender_mana,
        attacker_workers, defender_workers
    ) VALUES (
        'pvp', v_user_id, p_target_id,
        v_max_ticks, v_max_ticks,
        v_user_mana, v_target_mana,
        GREATEST(1, v_user_workers), GREATEST(0, v_target_workers)
    ) RETURNING id INTO v_session_id;

    RETURN jsonb_build_object(
        'success', true,
        'session_id', v_session_id,
        'faction_relation', v_relation,
        'betrayal', (v_relation IN ('ally', 'own_faction')),
        'ban_minutes', CASE WHEN v_relation IN ('ally', 'own_faction') THEN v_ban_minutes ELSE 0 END,
        'karma_penalty', CASE WHEN v_relation IN ('ally', 'own_faction') THEN v_karma_penalty ELSE 0 END,
        'max_ticks', v_max_ticks,
        'siege_days', ROUND(v_max_ticks / 1440.0, 1)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- PHASE D: HOLY WAR SIEGE OVERHAUL
-- ============================================

CREATE OR REPLACE FUNCTION public.initiate_holy_war(p_target_synod_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_attacker_synod_id UUID;
    v_user_role TEXT;
    v_user_sect TEXT;
    v_target_sect TEXT;
    v_initiation_cost NUMERIC;
    v_max_ticks NUMERIC;
    v_attacker_mana INT;
    v_attacker_workers INT;
    v_defender_mana INT;
    v_session_id UUID;
    v_existing_war UUID;
    v_relation TEXT;
    v_ban_minutes NUMERIC;
    v_karma_penalty NUMERIC;
BEGIN
    SELECT synod_id, synod_role, sect_type INTO v_attacker_synod_id, v_user_role, v_user_sect
    FROM profiles WHERE id = v_user_id;

    IF v_attacker_synod_id IS NULL THEN
        RAISE EXCEPTION 'You are not in a Synod';
    END IF;

    IF v_user_role != 'leader' THEN
        RAISE EXCEPTION 'Only the Synod leader can declare Holy War';
    END IF;

    -- One-war-at-a-time check (Exodus 2)
    SELECT active_war_id INTO v_existing_war FROM synods WHERE id = v_attacker_synod_id;
    IF v_existing_war IS NOT NULL THEN
        RAISE EXCEPTION 'Your Synod is already waging a Holy War. Finish it first.';
    END IF;

    IF p_target_synod_id = v_attacker_synod_id THEN
        RAISE EXCEPTION 'Cannot declare Holy War on your own Synod';
    END IF;

    SELECT s.sect_key INTO v_target_sect FROM synods s WHERE s.id = p_target_synod_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Target Synod not found';
    END IF;

    -- Faction check: can only attack enemy or neutral
    SELECT
        CASE
            WHEN v_user_sect = v_target_sect THEN 'own_faction'
            WHEN fr.ally_sect = v_target_sect THEN 'ally'
            WHEN fr.enemy_sect = v_target_sect THEN 'enemy'
            ELSE 'neutral'
        END
    INTO v_relation
    FROM faction_relationships fr WHERE fr.sect_key = v_user_sect;

    IF v_relation IN ('own_faction', 'ally') THEN
        -- Exodus 2: Ban both leaders for faction betrayal
        IF v_relation = 'own_faction' THEN
            v_ban_minutes := 30; v_karma_penalty := -10;
        ELSE
            v_ban_minutes := 15; v_karma_penalty := -5;
        END IF;

        -- Ban attacker leader
        UPDATE profiles SET
            ban_until = GREATEST(COALESCE(ban_until, now()), now()) + (v_ban_minutes * interval '1 minute'),
            karma = karma + v_karma_penalty,
            updated_at = now()
        WHERE id = v_user_id;

        -- Ban defender leader
        DECLARE
            v_def_leader UUID;
        BEGIN
            SELECT leader_id INTO v_def_leader FROM synods WHERE id = p_target_synod_id;
            IF v_def_leader IS NOT NULL THEN
                UPDATE profiles SET
                    ban_until = GREATEST(COALESCE(ban_until, now()), now()) + (v_ban_minutes * interval '1 minute'),
                    karma = karma + v_karma_penalty,
                    updated_at = now()
                WHERE id = v_def_leader;
            END IF;
        END;

        -- Store ban reasons
        INSERT INTO pending_bans (user_id, ban_until, ban_reason)
        VALUES (v_user_id,
            GREATEST(COALESCE((SELECT ban_until FROM profiles WHERE id = v_user_id), now()), now()) + (v_ban_minutes * interval '1 minute'),
            CASE WHEN v_relation = 'own_faction' THEN 'Synod attacked own faction' ELSE 'Synod attacked ally faction' END);
    END IF;

    SELECT value INTO v_initiation_cost FROM game_config WHERE key = 'combat.holy_war_initiation_gold';
    IF v_initiation_cost IS NULL THEN v_initiation_cost := 200; END IF;

    SELECT value INTO v_max_ticks FROM game_config WHERE key = 'combat.holy_war_max_ticks';
    IF v_max_ticks IS NULL THEN v_max_ticks := 43200; END IF;

    IF (SELECT gold FROM profiles WHERE id = v_user_id) < v_initiation_cost THEN
        RAISE EXCEPTION 'Insufficient Gold. Need % to initiate Holy War.', v_initiation_cost;
    END IF;

    UPDATE profiles SET gold = gold - v_initiation_cost, updated_at = now() WHERE id = v_user_id;

    -- Sum all members' mana and workers
    SELECT
        COALESCE(SUM(p.mana), 0)::INT,
        COALESCE(SUM((SELECT COUNT(*) FROM player_buildings WHERE user_id = p.id AND is_active = true
            AND building_type IN ('novice', 'monk', 'cleric', 'bishop', 'cardinal', 'cultist'))), 0)::INT
    INTO v_attacker_mana, v_attacker_workers
    FROM profiles p WHERE p.synod_id = v_attacker_synod_id;

    SELECT COALESCE(SUM(p.mana), 0)::INT INTO v_defender_mana
    FROM profiles p WHERE p.synod_id = p_target_synod_id;

    -- Set active war on attacker synod (Exodus 2)
    UPDATE synods SET active_war_id = p_target_synod_id WHERE id = v_attacker_synod_id;

    INSERT INTO combat_sessions (
        combat_type, attacker_id, defender_id,
        attacker_synod_id, defender_synod_id,
        ticks_total, ticks_remaining,
        attacker_mana, defender_mana,
        attacker_workers, defender_workers
    ) VALUES (
        'holy_war', v_user_id, (SELECT leader_id FROM synods WHERE id = p_target_synod_id),
        v_attacker_synod_id, p_target_synod_id,
        v_max_ticks, v_max_ticks,
        v_attacker_mana, v_defender_mana,
        v_attacker_workers, 0
    ) RETURNING id INTO v_session_id;

    -- Legacy synod_wars row
    INSERT INTO synod_wars (attacker_synod_id, defender_synod_id, expires_at)
    VALUES (v_attacker_synod_id, p_target_synod_id, now() + (v_max_ticks * interval '1 minute'));

    RETURN jsonb_build_object(
        'success', true,
        'session_id', v_session_id,
        'attacker_mana', v_attacker_mana,
        'attacker_workers', v_attacker_workers,
        'defender_mana', v_defender_mana,
        'gold_spent', v_initiation_cost,
        'max_ticks', v_max_ticks,
        'siege_days', ROUND(v_max_ticks / 1440.0, 1)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- PHASE D2: VANQUISH HELPER
-- ============================================

CREATE OR REPLACE FUNCTION public.vanquish_synod(p_defeated_synod_id UUID, p_victor_session_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_session RECORD;
    v_ban_minutes NUMERIC;
    v_total_workers INT;
    v_member RECORD;
    v_spoil_gold INT;
    v_spoil_mana INT;
    v_spoil_food INT;
BEGIN
    SELECT * INTO v_session FROM combat_sessions WHERE id = p_victor_session_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Session not found');
    END IF;

    SELECT value INTO v_ban_minutes FROM game_config WHERE key = 'combat.vanquish_ban_minutes';
    IF v_ban_minutes IS NULL THEN v_ban_minutes := 5; END IF;

    -- Calculate total attacker workers for weighted spoils
    SELECT COALESCE(SUM((SELECT COUNT(*) FROM player_buildings WHERE user_id = p.id AND is_active = true
        AND building_type IN ('novice', 'monk', 'cleric', 'bishop', 'cardinal', 'cultist'))), 0)::INT
    INTO v_total_workers
    FROM profiles p WHERE p.synod_id = v_session.attacker_synod_id;

    -- Collect all defender resources
    DECLARE
        v_total_gold INT;
        v_total_mana INT;
        v_total_food INT;
    BEGIN
        SELECT COALESCE(SUM(gold), 0)::INT, COALESCE(SUM(mana), 0)::INT, COALESCE(SUM(food), 0)::INT
        INTO v_total_gold, v_total_mana, v_total_food
        FROM profiles WHERE synod_id = p_defeated_synod_id;

        -- Zero out defender resources (they're scattered)
        UPDATE profiles SET gold = 0, mana = 0, food = 0 WHERE synod_id = p_defeated_synod_id;

        -- Distribute spoils to attacker members based on weighted worker contribution
        FOR v_member IN
            SELECT p.id, (SELECT COUNT(*) FROM player_buildings WHERE user_id = p.id AND is_active = true
                AND building_type IN ('novice', 'monk', 'cleric', 'bishop', 'cardinal', 'cultist')) AS workers
            FROM profiles p WHERE p.synod_id = v_session.attacker_synod_id
        LOOP
            IF v_total_workers > 0 AND v_member.workers > 0 THEN
                v_spoil_gold := FLOOR(v_total_gold * v_member.workers::NUMERIC / v_total_workers);
                v_spoil_mana := FLOOR(v_total_mana * v_member.workers::NUMERIC / v_total_workers);
                v_spoil_food := FLOOR(v_total_food * v_member.workers::NUMERIC / v_total_workers);

                UPDATE profiles SET
                    gold = gold + v_spoil_gold,
                    mana = mana + v_spoil_mana,
                    food = food + v_spoil_food,
                    updated_at = now()
                WHERE id = v_member.id;
            END IF;
        END LOOP;
    END;

    -- Transfer all relics from defeated synod members to attacker leader
    UPDATE relics r SET holder_id = v_session.attacker_id, last_stolen_at = now(), steal_progress = 0
    FROM profiles p
    WHERE r.holder_id = p.id AND p.synod_id = p_defeated_synod_id AND r.is_active = true;

    -- Scatter all members: remove from synod + apply 5-min ban
    UPDATE profiles SET
        synod_id = NULL,
        synod_role = NULL,
        ban_until = GREATEST(COALESCE(ban_until, now()), now()) + (v_ban_minutes * interval '1 minute'),
        updated_at = now()
    WHERE synod_id = p_defeated_synod_id;

    -- Queue pending bans with reason
    INSERT INTO pending_bans (user_id, ban_until, ban_reason)
    SELECT id, GREATEST(COALESCE(ban_until, now()), now()) + (v_ban_minutes * interval '1 minute'), 'Synod vanquished'
    FROM profiles WHERE synod_id IS NULL AND ban_until > now();

    -- Remove applicant queue
    DELETE FROM synod_applicants WHERE synod_id = p_defeated_synod_id;

    -- Destroy the synod
    DELETE FROM synods WHERE id = p_defeated_synod_id;

    -- Clear active_war_id on attacker synod
    UPDATE synods SET active_war_id = NULL WHERE id = v_session.attacker_synod_id;

    -- Log to akashic
    INSERT INTO akashic_logs (target_id, actor_id, action_type, result_data)
    VALUES (v_session.defender_id, v_session.attacker_id, 'crusade',
        jsonb_build_object('type', 'synod_vanquished', 'session_id', p_victor_session_id,
            'defeated_synod_id', p_defeated_synod_id));

    RETURN jsonb_build_object('success', true, 'vanquished_synod_id', p_defeated_synod_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- PHASE D3: HOLY WAR TICK (member-level + vanquish)
-- ============================================

CREATE OR REPLACE FUNCTION public.process_holy_war_tick(p_session_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_session RECORD;
    v_leech_pct NUMERIC;
    v_gold_per_tick NUMERIC;
    v_attrition_pct NUMERIC;
    v_exertion_pct NUMERIC;
    v_victory_pct NUMERIC;
    v_defender_total_gold INT;
    v_leech_gold INT;
    v_attacker_gold INT;
    v_result TEXT;
    v_defender_total_mana INT;
    v_damage_per_member INT;
    v_def_member RECORD;
BEGIN
    SELECT * INTO v_session FROM combat_sessions WHERE id = p_session_id AND is_active = true;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('processed', false, 'reason', 'not_found_or_inactive');
    END IF;

    SELECT COALESCE(value, 0.01) INTO v_leech_pct FROM game_config WHERE key = 'combat.holy_war_leech_pct';
    SELECT COALESCE(value, 100) INTO v_gold_per_tick FROM game_config WHERE key = 'combat.holy_war_gold_per_tick';
    SELECT COALESCE(value, 0.10) INTO v_attrition_pct FROM game_config WHERE key = 'combat.pvp_attrition_pct';
    SELECT COALESCE(value, 0.05) INTO v_exertion_pct FROM game_config WHERE key = 'combat.pvp_exertion_pct';
    SELECT COALESCE(value, 0.20) INTO v_victory_pct FROM game_config WHERE key = 'combat.holy_war_victory_pct';

    -- Re-sum live stats
    SELECT COALESCE(SUM(p.mana), 0)::INT,
           COALESCE(SUM((SELECT COUNT(*) FROM player_buildings WHERE user_id = p.id AND is_active = true
               AND building_type IN ('novice', 'monk', 'cleric', 'bishop', 'cardinal', 'cultist'))), 0)::INT
    INTO v_session.attacker_mana, v_session.attacker_workers
    FROM profiles p WHERE p.synod_id = v_session.attacker_synod_id;

    SELECT COALESCE(SUM(p.mana), 0)::INT INTO v_defender_total_mana
    FROM profiles p WHERE p.synod_id = v_session.defender_synod_id;

    SELECT COALESCE(SUM(p.gold), 0)::INT INTO v_defender_total_gold
    FROM profiles p WHERE p.synod_id = v_session.defender_synod_id;

    SELECT gold INTO v_attacker_gold FROM profiles WHERE id = v_session.attacker_id;

    -- Calculate damage and apply to each defending member proportionally
    v_damage_per_member := CASE WHEN v_defender_total_mana > 0
        THEN FLOOR(v_session.attacker_workers::NUMERIC / GREATEST(1, (SELECT COUNT(*) FROM profiles WHERE synod_id = v_session.defender_synod_id)))
        ELSE v_session.attacker_workers END;

    -- Hit each defender's mana directly
    UPDATE profiles SET mana = GREATEST(0, mana - v_damage_per_member), updated_at = now()
    WHERE synod_id = v_session.defender_synod_id AND mana > 0;

    -- Recalculate remaining defender mana
    SELECT COALESCE(SUM(p.mana), 0)::INT INTO v_session.defender_mana
    FROM profiles p WHERE p.synod_id = v_session.defender_synod_id;

    -- Attrition and exertion on attacker (virtual pools for tracking)
    v_session.attacker_workers := GREATEST(0, v_session.attacker_workers - FLOOR(v_session.attacker_workers * v_attrition_pct));
    v_session.attacker_mana := GREATEST(0, v_session.attacker_mana - FLOOR(v_session.attacker_mana * v_exertion_pct));

    -- Leech gold from each defender
    v_leech_gold := FLOOR(v_defender_total_gold * v_leech_pct);
    IF v_leech_gold > 0 THEN
        UPDATE profiles SET gold = GREATEST(0, gold - FLOOR(gold * v_leech_pct))
        WHERE synod_id = v_session.defender_synod_id AND gold > 0;
    END IF;

    v_session.gold_spent := v_session.gold_spent + v_gold_per_tick;
    v_session.gold_stolen := v_session.gold_stolen + v_leech_gold;
    v_session.ticks_remaining := v_session.ticks_remaining - 1;

    -- Victory conditions
    IF v_session.defender_mana <= 0 THEN
        v_result := 'attacker_win';
    ELSIF v_session.attacker_mana <= 0 OR v_attacker_gold < v_gold_per_tick THEN
        v_result := 'defender_win';
    ELSIF v_session.ticks_remaining <= 0 THEN
        v_result := 'stalemate';
    END IF;

    -- Gold tick cost from attacker leader
    IF v_attacker_gold >= v_gold_per_tick THEN
        UPDATE profiles SET gold = gold - v_gold_per_tick, updated_at = now()
        WHERE id = v_session.attacker_id;
    END IF;

    IF v_result = 'attacker_win' THEN
        -- Vanquish the defender synod (Exodus 2)
        PERFORM vanquish_synod(v_session.defender_synod_id, p_session_id);
    ELSIF v_result = 'defender_win' THEN
        UPDATE profiles SET karma = karma - 10, updated_at = now() WHERE id = v_session.attacker_id;
        UPDATE synods SET active_war_id = NULL WHERE id = v_session.attacker_synod_id;

        INSERT INTO akashic_logs (target_id, actor_id, action_type, result_data)
        VALUES (v_session.defender_id, v_session.attacker_id, 'crusade',
            jsonb_build_object('type', 'holy_war_retreat', 'session_id', p_session_id, 'karma_penalty', -10));
    ELSIF v_result = 'stalemate' THEN
        UPDATE synods SET active_war_id = NULL WHERE id = v_session.attacker_synod_id;

        INSERT INTO akashic_logs (target_id, actor_id, action_type, result_data)
        VALUES (v_session.defender_id, v_session.attacker_id, 'crusade',
            jsonb_build_object('type', 'holy_war_stalemate', 'session_id', p_session_id));
    END IF;

    UPDATE combat_sessions SET
        attacker_mana = v_session.attacker_mana,
        defender_mana = v_session.defender_mana,
        attacker_workers = v_session.attacker_workers,
        ticks_remaining = v_session.ticks_remaining,
        gold_stolen = v_session.gold_stolen,
        gold_spent = v_session.gold_spent,
        last_tick_at = now(),
        is_active = CASE WHEN v_result IS NOT NULL THEN false ELSE true END,
        result = CASE WHEN v_result IS NOT NULL THEN v_result ELSE NULL END
    WHERE id = p_session_id;

    RETURN jsonb_build_object('processed', true, 'result', v_result);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- PHASE E: PENDING BANS
-- ============================================

CREATE OR REPLACE FUNCTION public.apply_pending_bans()
RETURNS VOID AS $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT * FROM pending_bans WHERE applied = false LOOP
        UPDATE profiles SET
            ban_until = GREATEST(COALESCE(ban_until, now()), r.ban_until),
            updated_at = now()
        WHERE id = r.user_id;

        UPDATE pending_bans SET applied = true WHERE id = r.id;
    END LOOP;

    -- Clean up applied bans older than 7 days
    DELETE FROM pending_bans WHERE applied = true AND created_at < now() - interval '7 days';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- PHASE F: HEARTBEAT UPDATE
-- (replaces calculate_automated_karma with siege-aware version)
-- ============================================

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
    SELECT COALESCE(value, 50) INTO v_milestone_threshold FROM game_config WHERE key = 'karma.milestone_threshold';
    SELECT COALESCE(value, 5) INTO v_milestone_payout FROM game_config WHERE key = 'karma.milestone_payout';
    SELECT COALESCE(value, 2) INTO v_altruistic_multiplier FROM game_config WHERE key = 'karma.altruistic_multiplier';
    SELECT COALESCE(value, 0.10) INTO v_tithe_pct FROM game_config WHERE key = 'tithe.percentage';
    SELECT COALESCE(value, 144) INTO v_tick_divisor FROM game_config WHERE key = 'tick.production_divisor';
    SELECT COALESCE(value, 5) INTO v_liege_karma_per_day FROM game_config WHERE key = 'vassalage.liege_karma_per_day';

    -- PHASE 1: KARMA MILESTONES
    FOR r IN SELECT p.* FROM prayers p WHERE p.is_praying = true LOOP
        v_text := COALESCE(r.response_content, r.content);
        v_cycle_s := GREATEST(15, LEAST(length(v_text) * 0.2, 180))::INT;
        v_elapsed_s := EXTRACT(EPOCH FROM (now() - COALESCE(r.last_counted_at, r.activated_at)));
        v_new_cycles := floor(v_elapsed_s / v_cycle_s);

        IF v_new_cycles > 0 THEN
            UPDATE prayers SET prayer_count = prayer_count + v_new_cycles,
                last_counted_at = COALESCE(last_counted_at, activated_at) + (v_new_cycles * (v_cycle_s * interval '1 second')),
                updated_at = now() WHERE id = r.id;

            v_milestones_total := floor((r.prayer_count + v_new_cycles) / v_milestone_threshold);
            IF v_milestones_total > r.karma_awarded THEN
                v_karma_to_award := (v_milestones_total - r.karma_awarded) * v_milestone_payout *
                    (CASE WHEN r.prayer_type = 'altruistic' THEN v_altruistic_multiplier ELSE 1 END);
                UPDATE profiles SET karma = karma + v_karma_to_award, updated_at = now() WHERE id = r.user_id;
                UPDATE prayers SET karma_awarded = v_milestones_total WHERE id = r.id;
            END IF;
        END IF;

        IF r.prayer_type = 'intercessory' AND r.source_sinner_id IS NOT NULL THEN
            SELECT (ban_until IS NULL OR ban_until <= now()) INTO v_sinner_redeemed FROM profiles WHERE id = r.source_sinner_id;
            IF v_sinner_redeemed THEN
                UPDATE prayers SET is_praying = false, last_counted_at = now(), updated_at = now() WHERE id = r.id;
                UPDATE profiles SET karma = karma + 10, updated_at = now() WHERE id = r.user_id;
            END IF;
        END IF;
    END LOOP;

    -- PHASE 2: RESOURCE GENERATION (no caps)
    WITH user_production AS (
        SELECT pb.user_id,
            COALESCE(SUM(CASE WHEN gc_mana.value IS NOT NULL THEN gc_mana.value ELSE 0 END), 0)::NUMERIC AS gross_mana,
            COALESCE(SUM(CASE WHEN gc_gold.value IS NOT NULL THEN gc_gold.value ELSE 0 END), 0)::NUMERIC AS gross_gold,
            COALESCE(SUM(CASE WHEN gc_food.value IS NOT NULL THEN gc_food.value ELSE 0 END), 0)::NUMERIC AS gross_food,
            COALESCE(SUM(CASE WHEN gc_gold_upkeep.value IS NOT NULL THEN gc_gold_upkeep.value ELSE 0 END), 0)::NUMERIC AS gold_upkeep,
            COALESCE(SUM(CASE WHEN gc_food_consume.value IS NOT NULL THEN gc_food_consume.value ELSE 0 END), 0)::NUMERIC AS food_consume,
            COALESCE(SUM(CASE WHEN gc_heresy.value IS NOT NULL THEN gc_heresy.value ELSE 0 END), 0)::NUMERIC AS gross_heresy,
            COALESCE(SUM(CASE WHEN gc_dogma.value IS NOT NULL THEN gc_dogma.value ELSE 0 END), 0)::NUMERIC AS gross_dogma,
            COALESCE(SUM(CASE WHEN pb.building_type = 'coven' THEN 1 ELSE 0 END), 0)::INT AS coven_count
        FROM player_buildings pb
        LEFT JOIN game_config gc_mana ON gc_mana.key = 'building.' || pb.building_type || '.mana_per_day'
        LEFT JOIN game_config gc_gold ON gc_gold.key = 'building.' || pb.building_type || '.gold_per_day'
        LEFT JOIN game_config gc_food ON gc_food.key = 'building.' || pb.building_type || '.food_per_day'
        LEFT JOIN game_config gc_gold_upkeep ON gc_gold_upkeep.key = 'building.' || pb.building_type || '.gold_upkeep_per_day'
        LEFT JOIN game_config gc_food_consume ON gc_food_consume.key = 'building.' || pb.building_type || '.food_consumption_per_day'
        LEFT JOIN game_config gc_heresy ON gc_heresy.key = 'building.' || pb.building_type || '.heresy_per_day'
        LEFT JOIN game_config gc_dogma ON gc_dogma.key = 'building.' || pb.building_type || '.dogma_per_day'
        WHERE pb.is_active = true GROUP BY pb.user_id
    ),
    all_players AS (
        SELECT p.id AS user_id, p.sect_type, p.synod_id, p.suzerain_id,
            COALESCE(up.gross_mana, 0) AS gross_mana, COALESCE(up.gross_gold, 0) AS gross_gold,
            COALESCE(up.gross_food, 0) AS gross_food, COALESCE(up.gold_upkeep, 0) AS gold_upkeep,
            COALESCE(up.food_consume, 0) AS food_consume, COALESCE(up.gross_heresy, 0) AS gross_heresy,
            COALESCE(up.gross_dogma, 0) AS gross_dogma, COALESCE(up.coven_count, 0) AS coven_count
        FROM profiles p LEFT JOIN user_production up ON p.id = up.user_id
    ),
    sect_modified AS (
        SELECT ap.user_id, ap.synod_id, ap.suzerain_id,
            CASE WHEN ap.sect_type = 'gilded_path' THEN ap.gross_mana * COALESCE((SELECT value FROM game_config WHERE key = 'sect.gilded_path.mana_multiplier'), 0.8)
                 WHEN ap.sect_type = 'holy_way' THEN ap.gross_mana * COALESCE((SELECT value FROM game_config WHERE key = 'sect.holy_way.mana_multiplier'), 1.2)
                 WHEN ap.sect_type = 'black_tribunal' THEN ap.gross_mana * COALESCE((SELECT value FROM game_config WHERE key = 'sect.black_tribunal.mana_multiplier'), 0.7)
                 ELSE ap.gross_mana END AS mod_mana,
            CASE WHEN ap.sect_type = 'gilded_path' THEN ap.gross_gold * COALESCE((SELECT value FROM game_config WHERE key = 'sect.gilded_path.gold_multiplier'), 1.5)
                 WHEN ap.sect_type = 'final_watch' THEN ap.gross_gold * COALESCE((SELECT value FROM game_config WHERE key = 'sect.final_watch.gold_multiplier'), 0.75)
                 ELSE ap.gross_gold END AS mod_gold,
            CASE WHEN ap.sect_type = 'final_watch' THEN ap.gross_food * COALESCE((SELECT value FROM game_config WHERE key = 'sect.final_watch.food_multiplier'), 1.5)
                 ELSE ap.gross_food END AS mod_food,
            CASE WHEN ap.sect_type = 'gilded_path' THEN ap.gold_upkeep * COALESCE((SELECT value FROM game_config WHERE key = 'sect.gilded_path.cathedral_upkeep_multiplier'), 2.0)
                 ELSE ap.gold_upkeep END AS mod_gold_upkeep,
            CASE WHEN ap.sect_type = 'holy_way' THEN ap.food_consume * COALESCE((SELECT value FROM game_config WHERE key = 'sect.holy_way.food_consumption_multiplier'), 0.5)
                 ELSE ap.food_consume END AS mod_food_consume,
            CASE WHEN ap.sect_type = 'black_tribunal' THEN ap.gross_heresy * COALESCE((SELECT value FROM game_config WHERE key = 'sect.black_tribunal.heresy_multiplier'), 2.0)
                 ELSE ap.gross_heresy END AS mod_heresy,
            ap.gross_dogma, ap.coven_count
        FROM all_players ap
    ),
    tick_production AS (
        SELECT sm.user_id, sm.synod_id, sm.suzerain_id,
            GREATEST(0, FLOOR(sm.mod_mana / v_tick_divisor)) AS mana_tick,
            GREATEST(0, FLOOR(sm.mod_gold / v_tick_divisor)) AS gold_tick,
            GREATEST(0, FLOOR(sm.mod_food / v_tick_divisor)) AS food_tick,
            GREATEST(0, FLOOR(sm.mod_heresy / v_tick_divisor)) AS heresy_tick,
            GREATEST(0, FLOOR(sm.gross_dogma / v_tick_divisor)) AS dogma_tick,
            GREATEST(0, FLOOR(sm.mod_gold_upkeep / v_tick_divisor)) AS gold_upkeep_tick,
            GREATEST(0, FLOOR(sm.mod_food_consume / v_tick_divisor)) AS food_consume_tick,
            CASE WHEN sm.suzerain_id IS NOT NULL THEN FLOOR(sm.mod_mana / v_tick_divisor * v_tithe_pct) ELSE 0 END::INT AS mana_tithe,
            CASE WHEN sm.suzerain_id IS NOT NULL THEN FLOOR(sm.mod_gold / v_tick_divisor * v_tithe_pct) ELSE 0 END::INT AS gold_tithe,
            CASE WHEN sm.suzerain_id IS NOT NULL THEN FLOOR(sm.mod_food / v_tick_divisor * v_tithe_pct) ELSE 0 END::INT AS food_tithe
        FROM sect_modified sm
    ),
    tithe_inbound AS (
        SELECT tp.suzerain_id,
            COALESCE(SUM(tp.mana_tithe), 0)::INT AS recv_mana,
            COALESCE(SUM(tp.gold_tithe), 0)::INT AS recv_gold,
            COALESCE(SUM(tp.food_tithe), 0)::INT AS recv_food
        FROM tick_production tp WHERE tp.suzerain_id IS NOT NULL GROUP BY tp.suzerain_id
    ),
    synod_tax AS (
        SELECT tp.user_id, tp.synod_id,
            FLOOR(tp.gold_tick * COALESCE(s.tax_rate, 0.05))::INT AS gold_tax,
            FLOOR(tp.mana_tick * COALESCE(s.tax_rate, 0.05))::INT AS mana_tax
        FROM tick_production tp JOIN synods s ON s.id = tp.synod_id WHERE tp.synod_id IS NOT NULL
    )
    UPDATE profiles p SET
        mana = p.mana + tp.mana_tick - tp.mana_tithe + COALESCE(ti.recv_mana, 0),
        gold = GREATEST(0, p.gold + tp.gold_tick - tp.gold_upkeep_tick - tp.gold_tithe + COALESCE(ti.recv_gold, 0) - COALESCE(st.gold_tax, 0)),
        food = GREATEST(0, p.food + tp.food_tick - tp.food_consume_tick - tp.food_tithe + COALESCE(ti.recv_food, 0)),
        heresy = p.heresy + tp.heresy_tick,
        dogma = p.dogma + tp.dogma_tick,
        updated_at = now()
    FROM tick_production tp
    LEFT JOIN tithe_inbound ti ON ti.suzerain_id = p.id
    LEFT JOIN synod_tax st ON st.user_id = p.id
    WHERE p.id = tp.user_id;

    -- PHASE 3: SYNOD VAULT
    UPDATE synods s SET
        vault_gold = vault_gold + COALESCE((SELECT SUM(st.gold_tax) FROM synod_tax st WHERE st.synod_id = s.id GROUP BY st.synod_id), 0),
        vault_mana = vault_mana + COALESCE((SELECT SUM(st.mana_tax) FROM synod_tax st WHERE st.synod_id = s.id GROUP BY st.synod_id), 0)
    WHERE s.id IN (SELECT DISTINCT synod_id FROM synod_tax WHERE synod_id IS NOT NULL);

    -- PHASE 4: EXPIRE EFFECTS
    DELETE FROM active_miracles WHERE expires_at < now();
    DELETE FROM player_research WHERE expires_at IS NOT NULL AND expires_at < now();
    UPDATE synod_wars SET is_active = false WHERE is_active = true AND expires_at < now();
    UPDATE profiles SET papal_bull_until = NULL WHERE papal_bull_until IS NOT NULL AND papal_bull_until < now();
    UPDATE profiles SET divine_shield_until = NULL WHERE divine_shield_until IS NOT NULL AND divine_shield_until < now();

    -- PHASE 5: DIVINE ARCHITECT QUEUE
    FOR r IN SELECT bq.*, si.karma_cost, si.gold_cost, si.heresy_cost, si.effect_type, si.effect_data, si.acre_cost, si.cost_scaling
        FROM build_queue bq JOIN shop_items si ON si.id = bq.item_id
        WHERE bq.executed_at IS NULL AND bq.auto_execute = true
    LOOP
        DECLARE v_k INT; v_g INT; v_h INT;
        BEGIN
            SELECT karma, gold, heresy INTO v_k, v_g, v_h FROM profiles WHERE id = r.user_id;
            IF v_k >= r.karma_cost AND v_g >= r.gold_cost AND v_h >= r.heresy_cost THEN
                BEGIN
                    PERFORM purchase_shop_item(r.item_id);
                    UPDATE build_queue SET executed_at = now() WHERE id = r.id;
                EXCEPTION WHEN OTHERS THEN NULL; END;
            END IF;
        END;
    END LOOP;
    DELETE FROM build_queue WHERE executed_at IS NOT NULL AND executed_at < now() - interval '7 days';

    -- PHASE 6: COMBAT TICKS (Exodus 2: live mana reads, vassaldom on PvP win)
    FOR r IN SELECT id FROM combat_sessions WHERE is_active = true AND combat_type = 'pvp' LOOP
        DECLARE
            v_s RECORD; v_leech_pct NUMERIC; v_gold_per_tick NUMERIC;
            v_attrition NUMERIC; v_exertion NUMERIC;
            v_attacker_gold INT; v_defender_gold INT; v_leech INT;
            v_result TEXT; v_kill_karma INT;
            v_attacker_mana INT; v_defender_mana INT;
            v_attacker_workers INT; v_defender_workers INT;
        BEGIN
            SELECT * INTO v_s FROM combat_sessions WHERE id = r.id AND is_active = true;
            IF NOT FOUND THEN CONTINUE; END IF;

            SELECT COALESCE(value, 0.02) INTO v_leech_pct FROM game_config WHERE key = 'combat.pvp_leech_pct';
            SELECT COALESCE(value, 10) INTO v_gold_per_tick FROM game_config WHERE key = 'combat.pvp_gold_per_tick';
            SELECT COALESCE(value, 0.10) INTO v_attrition FROM game_config WHERE key = 'combat.pvp_attrition_pct';
            SELECT COALESCE(value, 0.05) INTO v_exertion FROM game_config WHERE key = 'combat.pvp_exertion_pct';

            -- Exodus 2: Read LIVE mana and worker counts from profiles each tick
            SELECT mana, gold, (SELECT COUNT(*)::INT FROM player_buildings WHERE user_id = v_s.attacker_id AND is_active = true
                AND building_type IN ('novice', 'monk', 'cleric', 'bishop', 'cardinal', 'cultist'))
            INTO v_attacker_mana, v_attacker_gold, v_attacker_workers FROM profiles WHERE id = v_s.attacker_id;

            SELECT mana, gold, (SELECT COUNT(*)::INT FROM player_buildings WHERE user_id = v_s.defender_id AND is_active = true
                AND building_type IN ('novice', 'monk', 'cleric', 'bishop', 'cardinal', 'cultist'))
            INTO v_defender_mana, v_defender_gold, v_defender_workers FROM profiles WHERE id = v_s.defender_id;

            -- Damage
            UPDATE profiles SET mana = GREATEST(0, mana - v_attacker_workers) WHERE id = v_s.defender_id;
            IF v_defender_workers > 0 THEN
                UPDATE profiles SET mana = GREATEST(0, mana - v_defender_workers) WHERE id = v_s.attacker_id;
            END IF;

            -- Leech gold from defender
            v_leech := FLOOR(v_defender_gold * v_leech_pct);
            IF v_leech > 0 THEN
                UPDATE profiles SET gold = GREATEST(0, gold - v_leech) WHERE id = v_s.defender_id;
                UPDATE profiles SET gold = gold + v_leech, updated_at = now() WHERE id = v_s.attacker_id;
            END IF;

            -- Tick cost from attacker
            IF v_attacker_gold >= v_gold_per_tick THEN
                UPDATE profiles SET gold = gold - v_gold_per_tick, updated_at = now() WHERE id = v_s.attacker_id;
            END IF;

            v_s.gold_stolen := COALESCE(v_s.gold_stolen, 0) + v_leech;
            v_s.gold_spent := COALESCE(v_s.gold_spent, 0) + v_gold_per_tick;
            v_s.ticks_remaining := v_s.ticks_remaining - 1;

            -- Re-read mana for victory check
            SELECT mana INTO v_attacker_mana FROM profiles WHERE id = v_s.attacker_id;
            SELECT mana INTO v_defender_mana FROM profiles WHERE id = v_s.defender_id;
            SELECT gold INTO v_attacker_gold FROM profiles WHERE id = v_s.attacker_id;

            IF v_defender_mana <= 0 THEN v_result := 'attacker_win';
            ELSIF v_attacker_mana <= 0 OR v_attacker_gold < v_gold_per_tick THEN v_result := 'defender_win';
            ELSIF v_s.ticks_remaining <= 0 THEN v_result := 'stalemate';
            END IF;

            IF v_result = 'attacker_win' THEN
                -- Exodus 2: PvP win = vassaldom
                DECLARE v_att_sect TEXT; v_def_sect TEXT; v_fr RECORD;
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

                -- Set vassaldom if not already a vassal
                IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = v_s.defender_id AND suzerain_id IS NOT NULL) THEN
                    UPDATE profiles SET suzerain_id = v_s.attacker_id, updated_at = now() WHERE id = v_s.defender_id;
                END IF;

                INSERT INTO akashic_logs (target_id, actor_id, action_type, result_data)
                VALUES (v_s.defender_id, v_s.attacker_id, 'crusade',
                    jsonb_build_object('type', 'pvp_victory', 'session_id', v_s.id, 'karma_gained', v_kill_karma, 'vassaldom', true));

            ELSIF v_result = 'defender_win' THEN
                INSERT INTO akashic_logs (target_id, actor_id, action_type, result_data)
                VALUES (v_s.defender_id, v_s.attacker_id, 'crusade',
                    jsonb_build_object('type', 'pvp_retreat', 'session_id', v_s.id));
            END IF;

            -- Clear active_combat_target_id on resolution
            IF v_result IS NOT NULL THEN
                UPDATE profiles SET active_combat_target_id = NULL WHERE id = v_s.attacker_id;
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
    FOR r IN SELECT id FROM combat_sessions WHERE is_active = true AND combat_type = 'holy_war' LOOP
        PERFORM process_holy_war_tick(r.id);
    END LOOP;

    -- PHASE 7: SUBJUGATION TIMERS
    FOR r IN SELECT cs.attacker_id, cs.defender_id
        FROM combat_sessions cs
        WHERE cs.combat_type = 'pvp' AND cs.is_active = true
          AND EXISTS (SELECT 1 FROM subjugation_timers st
                       WHERE st.liege_id = cs.attacker_id AND st.vassal_id = cs.defender_id AND st.accumulated_hours < 168)
    LOOP
        UPDATE subjugation_timers
        SET accumulated_hours = accumulated_hours + (1.0 / 60.0), last_attack_at = now()
        WHERE liege_id = r.attacker_id AND vassal_id = r.defender_id AND accumulated_hours < 168;

        IF EXISTS (SELECT 1 FROM subjugation_timers
                    WHERE liege_id = r.attacker_id AND vassal_id = r.defender_id AND accumulated_hours >= 168) THEN
            UPDATE profiles SET suzerain_id = r.attacker_id, updated_at = now()
            WHERE id = r.defender_id AND suzerain_id IS NULL;

            INSERT INTO akashic_logs (target_id, actor_id, action_type, result_data)
            VALUES (r.defender_id, r.attacker_id, 'crusade',
                jsonb_build_object('type', 'subjugation_complete', 'liege_id', r.attacker_id, 'vassal_id', r.defender_id));

            DELETE FROM subjugation_timers WHERE liege_id = r.attacker_id AND vassal_id = r.defender_id;
        END IF;
    END LOOP;

    -- PHASE 8: VASSAL TITHES + LIEGE KARMA
    FOR r IN SELECT p.id AS vassal_id, p.suzerain_id AS liege_id
        FROM profiles p WHERE p.suzerain_id IS NOT NULL
    LOOP
        DECLARE v_vassal_gold_tick INT;
        BEGIN
            SELECT COALESCE(FLOOR(SUM(COALESCE((SELECT value FROM game_config WHERE key = 'building.' || pb.building_type || '.gold_per_day'), 0)) / v_tick_divisor * v_tithe_pct), 0)
            INTO v_vassal_gold_tick FROM player_buildings pb WHERE pb.user_id = r.vassal_id AND pb.is_active = true;

            IF v_vassal_gold_tick > 0 THEN
                UPDATE profiles SET gold = GREATEST(0, gold - v_vassal_gold_tick), updated_at = now() WHERE id = r.vassal_id;
                UPDATE profiles SET gold = gold + v_vassal_gold_tick, updated_at = now() WHERE id = r.liege_id;
            END IF;
        END;

        UPDATE profiles SET karma = karma + ROUND(v_liege_karma_per_day / 1440.0, 4)::NUMERIC WHERE id = r.liege_id;
    END LOOP;

    -- PHASE 9: APPLY PENDING BANS (Exodus 2)
    PERFORM apply_pending_bans();

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- PHASE 8: GRANTS
-- ============================================

GRANT SELECT ON TABLE pending_bans TO authenticated;
GRANT SELECT ON TABLE pending_bans TO service_role;

GRANT EXECUTE ON FUNCTION attempt_relic_steal(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION attempt_relic_steal(UUID) TO service_role;

GRANT EXECUTE ON FUNCTION initiate_combat(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION initiate_combat(UUID) TO service_role;

GRANT EXECUTE ON FUNCTION initiate_holy_war(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION initiate_holy_war(UUID) TO service_role;

GRANT EXECUTE ON FUNCTION process_holy_war_tick(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION process_holy_war_tick(UUID) TO service_role;

GRANT EXECUTE ON FUNCTION vanquish_synod(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION vanquish_synod(UUID, UUID) TO service_role;

GRANT EXECUTE ON FUNCTION apply_pending_bans() TO authenticated;
GRANT EXECUTE ON FUNCTION apply_pending_bans() TO service_role;

GRANT EXECUTE ON FUNCTION calculate_automated_karma() TO service_role;

-- ============================================
-- END OF EXODUS 2
-- =====================================================