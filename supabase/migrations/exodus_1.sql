-- =====================================================
-- ELECTRIC MONK — EXODUS 1: Faction & Combat Systems Overhaul
-- Date: 2026-05-18
--
-- Run AFTER exodus_0.sql.
-- This migration is IDEMPOTENT where possible.
--
-- Phases:
--   0.  Schema changes (synods ALTER, 4 new tables, RLS, indexes)
--   0b. Economy rebalance (10x production, 6x shop costs, remove caps)
--   1.  Synod RPCs (petitions, stewards, public browser, faction balancing)
--   2.  Holy War RPCs (text-input target, auto-conscript, tick combat)
--   3.  Direct PvP RPCs (no UI block, betrayal detection, tick combat)
--   4.  Vassalage RPCs (subjugation timer, tribute, rebellion)
--   5.  Heartbeat update (no caps, 10x scaling, combat/subjugation/tithe phases)
--   8.  Grants & permissions
--
-- DO NOT USE EMOJIS IN CODE OR DEBUG LOGS.
-- =====================================================

-- ============================================
-- PHASE 0: SCHEMA CHANGES
-- ============================================

-- 0a. ALTER synods — add privacy, custom_message, sect_key
ALTER TABLE public.synods
  ADD COLUMN IF NOT EXISTS privacy TEXT DEFAULT 'public'
  CHECK (privacy IN ('public', 'private'));

ALTER TABLE public.synods
  ADD COLUMN IF NOT EXISTS custom_message TEXT DEFAULT NULL;

ALTER TABLE public.synods
  ADD COLUMN IF NOT EXISTS sect_key TEXT DEFAULT NULL;

-- Backfill sect_key for existing synods from leader's sect_type
UPDATE synods s SET sect_key = p.sect_type
FROM profiles p
WHERE s.leader_id = p.id AND s.sect_key IS NULL AND p.sect_type IS NOT NULL;

COMMENT ON COLUMN public.synods.privacy IS 'public = visible in Synod browser; private = invite only';
COMMENT ON COLUMN public.synods.custom_message IS 'Leader-set welcome/rules message shown at top of Synod page';
COMMENT ON COLUMN public.synods.sect_key IS 'Faction of founding leader. Set once at creation.';

-- 0b. CREATE synod_applicants — petition queue
CREATE TABLE IF NOT EXISTS synod_applicants (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  synod_id UUID NOT NULL REFERENCES synods(id) ON DELETE CASCADE,
  applied_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, synod_id)
);

COMMENT ON TABLE synod_applicants IS 'Pending join requests for faction-gated petition system';

-- 0c. CREATE combat_sessions — tick-based PvP + Holy War combat
CREATE TABLE IF NOT EXISTS combat_sessions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  combat_type TEXT NOT NULL CHECK (combat_type IN ('pvp', 'holy_war')),
  attacker_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  defender_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  attacker_synod_id UUID REFERENCES synods(id) ON DELETE SET NULL,
  defender_synod_id UUID REFERENCES synods(id) ON DELETE SET NULL,
  ticks_total INT NOT NULL DEFAULT 30,
  ticks_remaining INT NOT NULL DEFAULT 30,
  attacker_mana INT NOT NULL DEFAULT 0,
  defender_mana INT NOT NULL DEFAULT 0,
  attacker_workers INT NOT NULL DEFAULT 0,
  defender_workers INT NOT NULL DEFAULT 0,
  gold_stolen INT DEFAULT 0,
  gold_spent INT DEFAULT 0,
  started_at TIMESTAMPTZ DEFAULT now(),
  last_tick_at TIMESTAMPTZ DEFAULT now(),
  is_active BOOLEAN DEFAULT true,
  result TEXT CHECK (result IN ('attacker_win', 'defender_win', 'stalemate') OR result IS NULL)
);

COMMENT ON TABLE combat_sessions IS 'Tick-based combat for PvP (1v1) and Holy Wars (synod vs synod)';
COMMENT ON COLUMN combat_sessions.attacker_mana IS 'HP pool: attacker loses when this reaches 0';
COMMENT ON COLUMN combat_sessions.defender_mana IS 'HP pool: defender loses when this reaches 0';
COMMENT ON COLUMN combat_sessions.attacker_workers IS 'Damage output per tick for attacker';
COMMENT ON COLUMN combat_sessions.defender_workers IS 'Damage output per tick for defender (always 0 for holy_war)';

-- 0d. CREATE subjugation_timers — 168-hour vassalage countdown
CREATE TABLE IF NOT EXISTS subjugation_timers (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  liege_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  vassal_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  accumulated_hours NUMERIC DEFAULT 0 CHECK (accumulated_hours >= 0),
  last_attack_at TIMESTAMPTZ DEFAULT now(),
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(liege_id, vassal_id)
);

COMMENT ON TABLE subjugation_timers IS 'Tracks 168-hour subjugation countdown per attacker/target pair';
COMMENT ON COLUMN subjugation_timers.accumulated_hours IS 'Hours accumulated toward vassalage. At 168, target becomes vassal.';

-- 0e. CREATE betrayal_punishments — ban/karma tracking for faction betrayal
CREATE TABLE IF NOT EXISTS betrayal_punishments (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  target_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  betrayal_type TEXT NOT NULL CHECK (betrayal_type IN ('ally', 'own_faction')),
  ban_until TIMESTAMPTZ NOT NULL,
  karma_penalty INT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

COMMENT ON TABLE betrayal_punishments IS 'Audit log for faction betrayal bans and karma penalties';

-- 0f. RLS on new tables
ALTER TABLE synod_applicants ENABLE ROW LEVEL SECURITY;
ALTER TABLE combat_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE subjugation_timers ENABLE ROW LEVEL SECURITY;
ALTER TABLE betrayal_punishments ENABLE ROW LEVEL SECURITY;

-- synod_applicants: users can see their own applications; synod leaders/stewards can see apps to their synod
DROP POLICY IF EXISTS "Users can view own applications" ON synod_applicants;
CREATE POLICY "Users can view own applications" ON synod_applicants
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Synod leaders can view applications" ON synod_applicants;
CREATE POLICY "Synod leaders can view applications" ON synod_applicants
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid()
        AND p.synod_id = synod_applicants.synod_id
        AND p.synod_role IN ('leader', 'officer')
    )
  );

DROP POLICY IF EXISTS "Users can insert own application" ON synod_applicants;
CREATE POLICY "Users can insert own application" ON synod_applicants
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Synod leaders can delete applications" ON synod_applicants;
CREATE POLICY "Synod leaders can delete applications" ON synod_applicants
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid()
        AND p.synod_id = synod_applicants.synod_id
        AND p.synod_role IN ('leader', 'officer')
    )
  );

-- combat_sessions: participants can view; public read for war spectator
DROP POLICY IF EXISTS "Participants can view combat" ON combat_sessions;
CREATE POLICY "Participants can view combat" ON combat_sessions
  FOR SELECT USING (
    auth.uid() = attacker_id OR auth.uid() = defender_id
    OR (
      combat_type = 'holy_war' AND EXISTS (
        SELECT 1 FROM profiles p WHERE p.id = auth.uid()
          AND (p.synod_id = combat_sessions.attacker_synod_id
               OR p.synod_id = combat_sessions.defender_synod_id)
      )
    )
  );

-- subjugation_timers: participants can view
DROP POLICY IF EXISTS "Participants can view subjugation timers" ON subjugation_timers;
CREATE POLICY "Participants can view subjugation timers" ON subjugation_timers
  FOR SELECT USING (auth.uid() = liege_id OR auth.uid() = vassal_id);

-- betrayal_punishments: public read for transparency
DROP POLICY IF EXISTS "Anyone can view betrayal punishments" ON betrayal_punishments;
CREATE POLICY "Anyone can view betrayal punishments" ON betrayal_punishments
  FOR SELECT USING (true);

-- 0g. Indexes
CREATE INDEX IF NOT EXISTS idx_synod_applicants_synod ON synod_applicants(synod_id);
CREATE INDEX IF NOT EXISTS idx_synod_applicants_user ON synod_applicants(user_id);
CREATE INDEX IF NOT EXISTS idx_combat_sessions_active ON combat_sessions(is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_combat_sessions_attacker ON combat_sessions(attacker_id);
CREATE INDEX IF NOT EXISTS idx_combat_sessions_defender ON combat_sessions(defender_id);
CREATE INDEX IF NOT EXISTS idx_subjugation_timers_liege ON subjugation_timers(liege_id);
CREATE INDEX IF NOT EXISTS idx_subjugation_timers_vassal ON subjugation_timers(vassal_id);

-- ============================================
-- PHASE 0b: ECONOMY REBALANCE
-- ============================================

-- Multiply all production values by 10x for faster minute-tick feel
UPDATE game_config SET value = value * 10
WHERE key LIKE 'building.%.mana_per_day'
   OR key LIKE 'building.%.gold_per_day'
   OR key LIKE 'building.%.food_per_day'
   OR key LIKE 'building.%.heresy_per_day'
   OR key LIKE 'building.%.dogma_per_day'
   OR key LIKE 'building.%.gold_upkeep_per_day'
   OR key LIKE 'building.%.food_consumption_per_day';

-- Multiply shop item costs by 6x
UPDATE shop_items SET
  karma_cost = karma_cost * 6,
  gold_cost = gold_cost * 6,
  heresy_cost = heresy_cost * 6
WHERE karma_cost > 0 OR gold_cost > 0 OR heresy_cost > 0;

-- Multiply research node costs by 6x
UPDATE research_nodes SET cost = cost * 6 WHERE cost > 0;

-- Delete resource cap config keys (no more caps)
DELETE FROM game_config WHERE key IN (
  'cap.mana_multiplier',
  'cap.gold_multiplier',
  'cap.food_multiplier',
  'cap.dogma_multiplier',
  'cap.heresy_base',
  'cap.heresy_multiplier'
);

-- Insert/update combat tuning values
INSERT INTO game_config (key, value, description, category) VALUES
  ('combat.pvp_initiation_gold', 50, 'Gold cost to start PvP combat', 'combat'),
  ('combat.pvp_gold_per_tick', 10, 'Gold cost per PvP tick', 'combat'),
  ('combat.pvp_max_ticks', 30, 'Max ticks for PvP combat', 'combat'),
  ('combat.pvp_leech_pct', 0.02, 'Gold leech percent per tick (PvP)', 'combat'),
  ('combat.pvp_attrition_pct', 0.10, 'Worker attrition percent per tick', 'combat'),
  ('combat.pvp_exertion_pct', 0.05, 'Mana exertion percent per tick', 'combat'),
  ('combat.holy_war_initiation_gold', 200, 'Gold cost to start Holy War', 'combat'),
  ('combat.holy_war_gold_per_tick', 100, 'Gold cost per tick (Holy War)', 'combat'),
  ('combat.holy_war_max_ticks', 60, 'Max ticks for Holy War', 'combat'),
  ('combat.holy_war_leech_pct', 0.01, 'Gold leech percent per tick (Holy War)', 'combat'),
  ('combat.holy_war_victory_pct', 0.20, 'Defender gold percent taken on Holy War victory', 'combat'),
  ('combat.betrayal_ally_ban_minutes', 15, 'Ban minutes for attacking ally faction', 'combat'),
  ('combat.betrayal_own_ban_minutes', 30, 'Ban minutes for attacking own faction', 'combat'),
  ('combat.betrayal_ally_karma', -5, 'Karma penalty for ally betrayal', 'combat'),
  ('combat.betrayal_own_karma', -10, 'Karma penalty for own faction betrayal', 'combat'),
  ('combat.kill_neutral_karma', 1, 'Karma reward for defeating neutral faction enemy', 'combat'),
  ('combat.kill_enemy_karma', 5, 'Karma reward for defeating faction enemy', 'combat'),
  ('vassalage.subjugation_hours', 168, 'Hours required to subjugate a target', 'vassalage'),
  ('vassalage.tribute_gold_cost', 1000, 'Gold cost to reset 24 hours of subjugation', 'vassalage'),
  ('vassalage.rebellion_idle_days', 3, 'Days without attacks needed for rebellion', 'vassalage'),
  ('vassalage.tithe_pct', 0.10, 'Fraction of gold income paid to liege', 'vassalage'),
  ('vassalage.liege_karma_per_day', 5, 'Daily karma awarded per vassal', 'vassalage'),
  ('tick.production_divisor', 144, 'Divisor for per-day to per-minute tick conversion (was 1440, now 144 for 10x speed)', 'production')
ON CONFLICT (key) DO UPDATE SET
  value = EXCLUDED.value,
  description = EXCLUDED.description,
  category = EXCLUDED.category;

-- ============================================
-- PHASE 1: SYNOD RPCs
-- ============================================

-- 1a. Helper: check if two factions can associate
CREATE OR REPLACE FUNCTION public.can_associate_factions(p_user_sect TEXT, p_synod_sect TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    v_ally TEXT;
BEGIN
    IF p_user_sect = p_synod_sect THEN RETURN true; END IF;
    SELECT ally_sect INTO v_ally FROM faction_relationships WHERE sect_key = p_user_sect;
    RETURN v_ally = p_synod_sect;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- 1b. Replace create_synod: sets sect_key from founder's faction, supports privacy + custom_message
CREATE OR REPLACE FUNCTION public.create_synod(p_name TEXT, p_privacy TEXT DEFAULT 'public', p_custom_message TEXT DEFAULT NULL)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_user_gold INT;
    v_user_sect TEXT;
    v_creation_cost NUMERIC;
    v_existing_synod UUID;
    v_new_synod_id UUID;
    v_name_key TEXT;
BEGIN
    IF LENGTH(p_name) < 3 OR LENGTH(p_name) > 30 THEN
        RAISE EXCEPTION 'Synod name must be between 3 and 30 characters';
    END IF;

    IF p_privacy NOT IN ('public', 'private') THEN
        RAISE EXCEPTION 'Privacy must be public or private';
    END IF;

    SELECT synod_id, sect_type INTO v_existing_synod, v_user_sect FROM profiles WHERE id = v_user_id;
    IF v_existing_synod IS NOT NULL THEN
        RAISE EXCEPTION 'You are already in a Synod. Leave your current Synod first.';
    END IF;

    IF v_user_sect IS NULL THEN
        RAISE EXCEPTION 'You must choose a faction before founding a Synod.';
    END IF;

    v_name_key := LOWER(p_name);
    IF EXISTS (SELECT 1 FROM synods WHERE name_key = v_name_key) THEN
        RAISE EXCEPTION 'A Synod with that name already exists (case-insensitive).';
    END IF;

    SELECT value INTO v_creation_cost FROM game_config WHERE key = 'synod.creation_cost_gold';
    IF v_creation_cost IS NULL THEN v_creation_cost := 500; END IF;

    SELECT gold INTO v_user_gold FROM profiles WHERE id = v_user_id;
    IF v_user_gold < v_creation_cost THEN
        RAISE EXCEPTION 'Insufficient Gold. Need %, have %.', v_creation_cost, v_user_gold;
    END IF;

    UPDATE profiles SET gold = gold - v_creation_cost, updated_at = now() WHERE id = v_user_id;

    INSERT INTO synods (name, name_key, leader_id, tax_rate, privacy, custom_message, sect_key)
    VALUES (p_name, v_name_key, v_user_id, 0.05, p_privacy, p_custom_message, v_user_sect)
    RETURNING id INTO v_new_synod_id;

    UPDATE profiles SET synod_role = 'leader', synod_id = v_new_synod_id, updated_at = now() WHERE id = v_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'synod_id', v_new_synod_id,
        'name', p_name,
        'gold_spent', v_creation_cost
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 1c. Petition to join a Synod (replaces direct join_synod)
CREATE OR REPLACE FUNCTION public.petition_synod(p_synod_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_user_sect TEXT;
    v_synod_sect TEXT;
    v_existing_synod UUID;
    v_member_count INT;
    v_max_members NUMERIC;
BEGIN
    SELECT synod_id, sect_type INTO v_existing_synod, v_user_sect FROM profiles WHERE id = v_user_id;
    IF v_existing_synod IS NOT NULL THEN
        RAISE EXCEPTION 'You are already in a Synod. Leave your current Synod first.';
    END IF;

    SELECT sect_key INTO v_synod_sect FROM synods WHERE id = p_synod_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Synod not found';
    END IF;

    -- Faction check
    IF NOT public.can_associate_factions(v_user_sect, v_synod_sect) THEN
        RAISE EXCEPTION 'Your sect forbids association with heretics.';
    END IF;

    SELECT value INTO v_max_members FROM game_config WHERE key = 'synod.max_members';
    IF v_max_members IS NULL THEN v_max_members := 20; END IF;

    SELECT COUNT(*) INTO v_member_count FROM profiles WHERE synod_id = p_synod_id;
    IF v_member_count >= v_max_members THEN
        RAISE EXCEPTION 'Synod is full. Maximum % members.', v_max_members;
    END IF;

    -- Check if already applied
    IF EXISTS (SELECT 1 FROM synod_applicants WHERE user_id = v_user_id AND synod_id = p_synod_id) THEN
        RAISE EXCEPTION 'You have already petitioned this Synod.';
    END IF;

    -- Remove any prior applications to other synods
    DELETE FROM synod_applicants WHERE user_id = v_user_id;

    INSERT INTO synod_applicants (user_id, synod_id) VALUES (v_user_id, p_synod_id);

    RETURN jsonb_build_object('success', true, 'synod_id', p_synod_id, 'status', 'petitioned');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 1d. Replace leave_synod: clear synod_role, handle succession
CREATE OR REPLACE FUNCTION public.leave_synod()
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_synod_id UUID;
    v_is_leader BOOLEAN;
    v_oldest_member_id UUID;
BEGIN
    SELECT synod_id INTO v_synod_id FROM profiles WHERE id = v_user_id;
    IF v_synod_id IS NULL THEN
        RAISE EXCEPTION 'You are not in a Synod';
    END IF;

    SELECT (leader_id = v_user_id), id INTO v_is_leader, v_synod_id
    FROM synods WHERE id = v_synod_id;

    UPDATE profiles SET synod_id = NULL, synod_role = NULL, updated_at = now() WHERE id = v_user_id;

    -- Remove pending applications
    DELETE FROM synod_applicants WHERE user_id = v_user_id;

    IF v_is_leader THEN
        SELECT id INTO v_oldest_member_id
        FROM profiles
        WHERE synod_id = v_synod_id
        ORDER BY
            CASE synod_role WHEN 'officer' THEN 0 WHEN 'member' THEN 1 ELSE 2 END ASC,
            created_at ASC
        LIMIT 1;

        IF v_oldest_member_id IS NOT NULL THEN
            UPDATE synods SET leader_id = v_oldest_member_id WHERE id = v_synod_id;
            UPDATE profiles SET synod_role = 'leader', updated_at = now() WHERE id = v_oldest_member_id;
        ELSE
            -- No members left, dissolve synod
            DELETE FROM synod_applicants WHERE synod_id = v_synod_id;
            DELETE FROM synods WHERE id = v_synod_id;
        END IF;
    END IF;

    RETURN jsonb_build_object('success', true, 'former_synod_id', v_synod_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 1e. Get public Synods matching player's faction or ally (for Synod Browser)
CREATE OR REPLACE FUNCTION public.get_public_synods()
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_user_sect TEXT;
    v_ally_sect TEXT;
    v_result JSONB;
BEGIN
    SELECT sect_type INTO v_user_sect FROM profiles WHERE id = v_user_id;

    IF v_user_sect IS NULL THEN
        RETURN '[]'::jsonb;
    END IF;

    SELECT ally_sect INTO v_ally_sect FROM faction_relationships WHERE sect_key = v_user_sect;

    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', s.id,
            'name', s.name,
            'leader_name', pl.username,
            'sect_key', s.sect_key,
            'member_count', (SELECT COUNT(*) FROM profiles WHERE synod_id = s.id),
            'privacy', s.privacy,
            'created_at', s.created_at
        ) ORDER BY (SELECT COUNT(*) FROM profiles WHERE synod_id = s.id) DESC
    ), '[]'::jsonb) INTO v_result
    FROM synods s
    LEFT JOIN profiles pl ON pl.id = s.leader_id
    WHERE s.privacy = 'public'
      AND (s.sect_key = v_user_sect OR s.sect_key = v_ally_sect);

    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 1f. Approve a pending applicant (leader or officer only)
CREATE OR REPLACE FUNCTION public.approve_synod_applicant(p_applicant_user_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_user_synod_id UUID;
    v_user_role TEXT;
    v_app_synod_id UUID;
    v_app_user_synod UUID;
    v_member_count INT;
    v_max_members NUMERIC;
BEGIN
    SELECT synod_id, synod_role INTO v_user_synod_id, v_user_role FROM profiles WHERE id = v_user_id;
    IF v_user_synod_id IS NULL OR v_user_role NOT IN ('leader', 'officer') THEN
        RAISE EXCEPTION 'Only the Synod leader or stewards can approve applicants.';
    END IF;

    SELECT sa.synod_id, p.synod_id INTO v_app_synod_id, v_app_user_synod
    FROM synod_applicants sa
    JOIN profiles p ON p.id = sa.user_id
    WHERE sa.user_id = p_applicant_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Applicant not found in pending queue.';
    END IF;

    IF v_app_synod_id != v_user_synod_id THEN
        RAISE EXCEPTION 'This applicant did not petition your Synod.';
    END IF;

    IF v_app_user_synod IS NOT NULL THEN
        RAISE EXCEPTION 'Applicant is already in a Synod.';
    END IF;

    SELECT value INTO v_max_members FROM game_config WHERE key = 'synod.max_members';
    IF v_max_members IS NULL THEN v_max_members := 20; END IF;

    SELECT COUNT(*) INTO v_member_count FROM profiles WHERE synod_id = v_user_synod_id;
    IF v_member_count >= v_max_members THEN
        RAISE EXCEPTION 'Synod is full. Maximum % members.', v_max_members;
    END IF;

    -- Add to synod
    UPDATE profiles SET synod_id = v_user_synod_id, synod_role = 'member', updated_at = now()
    WHERE id = p_applicant_user_id;

    -- Remove from applicants
    DELETE FROM synod_applicants WHERE user_id = p_applicant_user_id;

    RETURN jsonb_build_object('success', true, 'approved_user_id', p_applicant_user_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 1g. Reject a pending applicant
CREATE OR REPLACE FUNCTION public.reject_synod_applicant(p_applicant_user_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_user_synod_id UUID;
    v_user_role TEXT;
    v_app_synod_id UUID;
BEGIN
    SELECT synod_id, synod_role INTO v_user_synod_id, v_user_role FROM profiles WHERE id = v_user_id;
    IF v_user_synod_id IS NULL OR v_user_role NOT IN ('leader', 'officer') THEN
        RAISE EXCEPTION 'Only the Synod leader or stewards can reject applicants.';
    END IF;

    SELECT sa.synod_id INTO v_app_synod_id
    FROM synod_applicants sa WHERE sa.user_id = p_applicant_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Applicant not found in pending queue.';
    END IF;

    IF v_app_synod_id != v_user_synod_id THEN
        RAISE EXCEPTION 'This applicant did not petition your Synod.';
    END IF;

    DELETE FROM synod_applicants WHERE user_id = p_applicant_user_id;

    RETURN jsonb_build_object('success', true, 'rejected_user_id', p_applicant_user_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 1h. Update synod privacy (leader only)
CREATE OR REPLACE FUNCTION public.update_synod_privacy(p_privacy TEXT)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_synod_id UUID;
BEGIN
    SELECT synod_id INTO v_synod_id FROM profiles WHERE id = v_user_id;
    IF v_synod_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM synods WHERE id = v_synod_id AND leader_id = v_user_id
    ) THEN
        RAISE EXCEPTION 'Only the Synod leader can change privacy settings.';
    END IF;

    IF p_privacy NOT IN ('public', 'private') THEN
        RAISE EXCEPTION 'Privacy must be public or private.';
    END IF;

    UPDATE synods SET privacy = p_privacy WHERE id = v_synod_id;

    RETURN jsonb_build_object('success', true, 'privacy', p_privacy);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 1i. Update synod custom message (leader only)
CREATE OR REPLACE FUNCTION public.update_synod_message(p_message TEXT)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_synod_id UUID;
BEGIN
    SELECT synod_id INTO v_synod_id FROM profiles WHERE id = v_user_id;
    IF v_synod_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM synods WHERE id = v_synod_id AND leader_id = v_user_id
    ) THEN
        RAISE EXCEPTION 'Only the Synod leader can change the message.';
    END IF;

    UPDATE synods SET custom_message = p_message WHERE id = v_synod_id;

    RETURN jsonb_build_object('success', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 1j. Get available factions for balanced onboarding (lowest member count)
CREATE OR REPLACE FUNCTION public.get_available_factions()
RETURNS JSONB AS $$
DECLARE
    v_result JSONB;
    v_min_count BIGINT;
BEGIN
    -- Find minimum member count across all factions
    SELECT MIN(cnt) INTO v_min_count FROM (
        SELECT COUNT(*) AS cnt FROM profiles WHERE sect_type = 'gilded_path'
        UNION ALL
        SELECT COUNT(*) FROM profiles WHERE sect_type = 'holy_way'
        UNION ALL
        SELECT COUNT(*) FROM profiles WHERE sect_type = 'final_watch'
        UNION ALL
        SELECT COUNT(*) FROM profiles WHERE sect_type = 'black_tribunal'
    ) sub;

    -- Return all factions that match the minimum
    SELECT jsonb_agg(faction_data) INTO v_result FROM (
        SELECT jsonb_build_object(
            'sect_key', 'gilded_path',
            'member_count', (SELECT COUNT(*) FROM profiles WHERE sect_type = 'gilded_path')
        ) AS faction_data
        WHERE (SELECT COUNT(*) FROM profiles WHERE sect_type = 'gilded_path') <= v_min_count

        UNION ALL

        SELECT jsonb_build_object(
            'sect_key', 'holy_way',
            'member_count', (SELECT COUNT(*) FROM profiles WHERE sect_type = 'holy_way')
        ) AS faction_data
        WHERE (SELECT COUNT(*) FROM profiles WHERE sect_type = 'holy_way') <= v_min_count

        UNION ALL

        SELECT jsonb_build_object(
            'sect_key', 'final_watch',
            'member_count', (SELECT COUNT(*) FROM profiles WHERE sect_type = 'final_watch')
        ) AS faction_data
        WHERE (SELECT COUNT(*) FROM profiles WHERE sect_type = 'final_watch') <= v_min_count

        UNION ALL

        SELECT jsonb_build_object(
            'sect_key', 'black_tribunal',
            'member_count', (SELECT COUNT(*) FROM profiles WHERE sect_type = 'black_tribunal')
        ) AS faction_data
        WHERE (SELECT COUNT(*) FROM profiles WHERE sect_type = 'black_tribunal') <= v_min_count
    ) t;

    RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 1k. Update get_synod_info to include privacy, custom_message, sect_key, and applicant queue
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
    v_applicants JSONB;
    v_user_role TEXT;
BEGIN
    SELECT synod_id, synod_role INTO v_synod_id, v_user_role FROM profiles WHERE id = v_user_id;
    IF v_synod_id IS NULL THEN
        RETURN jsonb_build_object('in_synod', false);
    END IF;

    SELECT jsonb_build_object(
        'id', s.id,
        'name', s.name,
        'leader_id', s.leader_id,
        'leader_name', pl.username,
        'tax_rate', s.tax_rate,
        'vault_gold', s.vault_gold,
        'vault_mana', s.vault_mana,
        'privacy', s.privacy,
        'custom_message', s.custom_message,
        'sect_key', s.sect_key,
        'created_at', s.created_at
    ) INTO v_synod
    FROM synods s
    LEFT JOIN profiles pl ON pl.id = s.leader_id
    WHERE s.id = v_synod_id;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'user_id', p.id,
        'username', p.username,
        'faith', p.faith,
        'sect_type', p.sect_type,
        'role', COALESCE(p.synod_role, 'member'),
        'joined_at', p.created_at
    ) ORDER BY CASE p.synod_role WHEN 'leader' THEN 0 WHEN 'officer' THEN 1 ELSE 2 END, p.created_at ASC
    ), '[]'::jsonb), COUNT(*)::INT INTO v_members, v_member_count
    FROM profiles p WHERE p.synod_id = v_synod_id;

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

    v_synod_relics := public.get_synod_relics(v_user_id);

    -- Applicants: only visible to leader and officers
    IF v_user_role IN ('leader', 'officer') THEN
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'user_id', p.id,
            'username', p.username,
            'sect_type', p.sect_type,
            'applied_at', sa.applied_at
        ) ORDER BY sa.applied_at ASC), '[]'::jsonb) INTO v_applicants
        FROM synod_applicants sa
        JOIN profiles p ON p.id = sa.user_id
        WHERE sa.synod_id = v_synod_id;
    ELSE
        v_applicants := '[]'::jsonb;
    END IF;

    RETURN jsonb_build_object(
        'in_synod', true,
        'synod', v_synod,
        'members', v_members,
        'member_count', v_member_count,
        'wars', v_wars,
        'synod_relics', v_synod_relics,
        'applicants', v_applicants,
        'my_role', v_user_role
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 1l. Helper: get player's faction relationships (used by combat RPCs)
CREATE OR REPLACE FUNCTION public.get_player_faction_relationships()
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_sect TEXT;
    v_result JSONB;
BEGIN
    SELECT sect_type INTO v_sect FROM profiles WHERE id = v_user_id;
    IF v_sect IS NULL THEN RETURN '{}'::jsonb; END IF;

    SELECT jsonb_build_object(
        'my_sect', fr.sect_key,
        'enemy', fr.enemy_sect,
        'ally', fr.ally_sect,
        'neutral', fr.neutral_sect
    ) INTO v_result
    FROM faction_relationships fr WHERE fr.sect_key = v_sect;

    RETURN COALESCE(v_result, '{}'::jsonb);
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- ============================================
-- PHASE 2: HOLY WAR RPCs
-- ============================================

-- 2a. Find synod by exact name (text input for Holy War target)
CREATE OR REPLACE FUNCTION public.find_synod_by_name(p_name TEXT)
RETURNS JSONB AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'id', s.id,
        'name', s.name,
        'sect_key', s.sect_key,
        'leader_name', p.username,
        'member_count', (SELECT COUNT(*) FROM profiles WHERE synod_id = s.id)
    ) INTO v_result
    FROM synods s
    LEFT JOIN profiles p ON p.id = s.leader_id
    WHERE LOWER(s.name) = LOWER(p_name);

    IF v_result IS NULL THEN
        RETURN jsonb_build_object('found', false);
    END IF;

    RETURN v_result || jsonb_build_object('found', true);
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- 2b. Initiate Holy War (leader only, auto-conscripts all members)
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
    v_already_active INT;
BEGIN
    -- Get caller's synod, role, and faction
    SELECT synod_id, synod_role, sect_type INTO v_attacker_synod_id, v_user_role, v_user_sect
    FROM profiles WHERE id = v_user_id;

    IF v_attacker_synod_id IS NULL THEN
        RAISE EXCEPTION 'You are not in a Synod';
    END IF;

    IF v_user_role != 'leader' THEN
        RAISE EXCEPTION 'Only the Synod leader can declare Holy War';
    END IF;

    IF p_target_synod_id = v_attacker_synod_id THEN
        RAISE EXCEPTION 'Cannot declare Holy War on your own Synod';
    END IF;

    -- Check target synod exists and get faction
    SELECT s.sect_key INTO v_target_sect FROM synods s WHERE s.id = p_target_synod_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Target Synod not found';
    END IF;

    -- Faction check: can only attack enemy or neutral factions
    IF public.can_associate_factions(v_user_sect, v_target_sect) THEN
        RAISE EXCEPTION 'You cannot wage Holy War on your own faction or allies.';
    END IF;

    -- Check not already in active combat
    SELECT COUNT(*) INTO v_already_active FROM combat_sessions
    WHERE combat_type = 'holy_war'
      AND attacker_synod_id = v_attacker_synod_id
      AND defender_synod_id = p_target_synod_id
      AND is_active = true;

    IF v_already_active > 0 THEN
        RAISE EXCEPTION 'Already in an active Holy War with this Synod.';
    END IF;

    -- Load config
    SELECT value INTO v_initiation_cost FROM game_config WHERE key = 'combat.holy_war_initiation_gold';
    IF v_initiation_cost IS NULL THEN v_initiation_cost := 200; END IF;

    SELECT value INTO v_max_ticks FROM game_config WHERE key = 'combat.holy_war_max_ticks';
    IF v_max_ticks IS NULL THEN v_max_ticks := 60; END IF;

    -- Check leader has gold
    IF (SELECT gold FROM profiles WHERE id = v_user_id) < v_initiation_cost THEN
        RAISE EXCEPTION 'Insufficient Gold. Need % to initiate Holy War.', v_initiation_cost;
    END IF;

    -- Deduct initiation cost from leader
    UPDATE profiles SET gold = gold - v_initiation_cost, updated_at = now() WHERE id = v_user_id;

    -- Sum all members' mana and worker buildings
    SELECT
        COALESCE(SUM(p.mana), 0)::INT,
        COALESCE(SUM(
            (SELECT COUNT(*) FROM player_buildings WHERE user_id = p.id AND is_active = true
             AND building_type IN ('novice', 'monk', 'cleric', 'bishop', 'cardinal', 'cultist'))
        ), 0)::INT
    INTO v_attacker_mana, v_attacker_workers
    FROM profiles p WHERE p.synod_id = v_attacker_synod_id;

    -- Defender mana = sum of all defender synod members' mana
    SELECT COALESCE(SUM(p.mana), 0)::INT INTO v_defender_mana
    FROM profiles p WHERE p.synod_id = p_target_synod_id;

    -- Create combat session
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

    -- Also create legacy synod_wars row for backward compatibility
    INSERT INTO synod_wars (attacker_synod_id, defender_synod_id, expires_at)
    VALUES (v_attacker_synod_id, p_target_synod_id, now() + (v_max_ticks * interval '1 minute'));

    RETURN jsonb_build_object(
        'success', true,
        'session_id', v_session_id,
        'attacker_mana', v_attacker_mana,
        'attacker_workers', v_attacker_workers,
        'defender_mana', v_defender_mana,
        'gold_spent', v_initiation_cost
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2c. Get active Holy Wars for player's synod
CREATE OR REPLACE FUNCTION public.get_active_holy_wars()
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_synod_id UUID;
    v_result JSONB;
BEGIN
    SELECT synod_id INTO v_synod_id FROM profiles WHERE id = v_user_id;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'session_id', cs.id,
        'combat_type', cs.combat_type,
        'attacker_synod_name', asyn.name,
        'defender_synod_name', dsyn.name,
        'attacker_mana', cs.attacker_mana,
        'defender_mana', cs.defender_mana,
        'attacker_workers', cs.attacker_workers,
        'defender_workers', cs.defender_workers,
        'ticks_total', cs.ticks_total,
        'ticks_remaining', cs.ticks_remaining,
        'gold_stolen', cs.gold_stolen,
        'gold_spent', cs.gold_spent,
        'started_at', cs.started_at,
        'last_tick_at', cs.last_tick_at,
        'is_attacker', cs.attacker_synod_id = v_synod_id
    ) ORDER BY cs.started_at DESC), '[]'::jsonb) INTO v_result
    FROM combat_sessions cs
    LEFT JOIN synods asyn ON asyn.id = cs.attacker_synod_id
    LEFT JOIN synods dsyn ON dsyn.id = cs.defender_synod_id
    WHERE cs.combat_type = 'holy_war'
      AND cs.is_active = true
      AND (cs.attacker_synod_id = v_synod_id OR cs.defender_synod_id = v_synod_id);

    RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- 2d. Process single Holy War tick (called by heartbeat)
CREATE OR REPLACE FUNCTION public.process_holy_war_tick(p_session_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_session RECORD;
    v_leech_pct NUMERIC;
    v_gold_per_tick NUMERIC;
    v_attrition_pct NUMERIC;
    v_exertion_pct NUMERIC;
    v_victory_pct NUMERIC;
    v_defender_gold INT;
    v_leech_gold INT;
    v_attacker_gold INT;
    v_result TEXT;
BEGIN
    SELECT * INTO v_session FROM combat_sessions WHERE id = p_session_id AND is_active = true;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('processed', false, 'reason', 'not_found_or_inactive');
    END IF;

    -- Load config values
    SELECT value INTO v_leech_pct FROM game_config WHERE key = 'combat.holy_war_leech_pct';
    IF v_leech_pct IS NULL THEN v_leech_pct := 0.01; END IF;

    SELECT value INTO v_gold_per_tick FROM game_config WHERE key = 'combat.holy_war_gold_per_tick';
    IF v_gold_per_tick IS NULL THEN v_gold_per_tick := 100; END IF;

    SELECT value INTO v_attrition_pct FROM game_config WHERE key = 'combat.pvp_attrition_pct';
    IF v_attrition_pct IS NULL THEN v_attrition_pct := 0.10; END IF;

    SELECT value INTO v_exertion_pct FROM game_config WHERE key = 'combat.pvp_exertion_pct';
    IF v_exertion_pct IS NULL THEN v_exertion_pct := 0.05; END IF;

    SELECT value INTO v_victory_pct FROM game_config WHERE key = 'combat.holy_war_victory_pct';
    IF v_victory_pct IS NULL THEN v_victory_pct := 0.20; END IF;

    -- Re-sum attacker workers and mana from current synod state
    SELECT
        COALESCE(SUM(p.mana), 0)::INT,
        COALESCE(SUM((SELECT COUNT(*) FROM player_buildings WHERE user_id = p.id AND is_active = true
            AND building_type IN ('novice', 'monk', 'cleric', 'bishop', 'cardinal', 'cultist'))), 0)::INT
    INTO v_session.attacker_mana, v_session.attacker_workers
    FROM profiles p WHERE p.synod_id = v_session.attacker_synod_id;

    -- Re-sum defender mana
    SELECT COALESCE(SUM(p.mana), 0)::INT INTO v_session.defender_mana
    FROM profiles p WHERE p.synod_id = v_session.defender_synod_id;

    -- Get defender's total gold
    SELECT COALESCE(SUM(p.gold), 0)::INT INTO v_defender_gold
    FROM profiles p WHERE p.synod_id = v_session.defender_synod_id;

    -- Get attacker leader's gold for tick cost
    SELECT gold INTO v_attacker_gold FROM profiles WHERE id = v_session.attacker_id;

    -- Calculate damage
    v_session.defender_mana := GREATEST(0, v_session.defender_mana - v_session.attacker_workers);

    -- Attrition and exertion on attacker
    v_session.attacker_workers := GREATEST(0, v_session.attacker_workers - FLOOR(v_session.attacker_workers * v_attrition_pct));
    v_session.attacker_mana := GREATEST(0, v_session.attacker_mana - FLOOR(v_session.attacker_mana * v_exertion_pct));

    -- Leech gold from defender
    v_leech_gold := FLOOR(v_defender_gold * v_leech_pct);

    -- Deduct gold tick cost from attacker
    v_session.gold_spent := v_session.gold_spent + v_gold_per_tick;
    v_session.gold_stolen := v_session.gold_stolen + v_leech_gold;

    -- Decrement tick
    v_session.ticks_remaining := v_session.ticks_remaining - 1;

    -- Check victory conditions
    IF v_session.defender_mana <= 0 THEN
        v_result := 'attacker_win';
    ELSIF v_session.attacker_mana <= 0 OR v_attacker_gold < v_gold_per_tick THEN
        v_result := 'defender_win';
    ELSIF v_session.ticks_remaining <= 0 THEN
        v_result := 'stalemate';
    ELSE
        v_result := NULL;
    END IF;

    -- Apply gold changes
    IF v_leech_gold > 0 THEN
        -- Distribute leeched gold from defender synod members proportionally
        UPDATE profiles SET gold = GREATEST(0, gold - FLOOR(gold * v_leech_pct))
        WHERE synod_id = v_session.defender_synod_id AND gold > 0;
    END IF;

    IF v_attacker_gold >= v_gold_per_tick THEN
        UPDATE profiles SET gold = gold - v_gold_per_tick, updated_at = now()
        WHERE id = v_session.attacker_id;
    END IF;

    -- Handle outcome
    IF v_result = 'attacker_win' THEN
        -- Attacker wins: gain 20% of defender synod gold
        DECLARE
            v_win_gold INT;
        BEGIN
            SELECT COALESCE(SUM(gold), 0)::INT * v_victory_pct INTO v_win_gold
            FROM profiles WHERE synod_id = v_session.defender_synod_id;

            -- Deduct from defenders
            UPDATE profiles SET gold = GREATEST(0, gold - FLOOR(gold * v_victory_pct))
            WHERE synod_id = v_session.defender_synod_id;

            -- Award to attacker leader
            UPDATE profiles SET gold = gold + v_win_gold, updated_at = now()
            WHERE id = v_session.attacker_id;

            -- Log to akashic
            INSERT INTO akashic_logs (target_id, actor_id, action_type, result_data)
            VALUES (v_session.defender_id, v_session.attacker_id, 'crusade',
                jsonb_build_object('type', 'holy_war_victory', 'session_id', v_session.id,
                    'gold_won', v_win_gold, 'ticks_remaining', v_session.ticks_remaining));
        END;

    ELSIF v_result = 'defender_win' THEN
        -- Attacker retreats: -10 karma
        UPDATE profiles SET karma = karma - 10, updated_at = now() WHERE id = v_session.attacker_id;

        INSERT INTO akashic_logs (target_id, actor_id, action_type, result_data)
        VALUES (v_session.defender_id, v_session.attacker_id, 'crusade',
            jsonb_build_object('type', 'holy_war_retreat', 'session_id', v_session.id,
                'karma_penalty', -10, 'ticks_remaining', v_session.ticks_remaining));

    ELSIF v_result = 'stalemate' THEN
        INSERT INTO akashic_logs (target_id, actor_id, action_type, result_data)
        VALUES (v_session.defender_id, v_session.attacker_id, 'crusade',
            jsonb_build_object('type', 'holy_war_stalemate', 'session_id', v_session.id));
    END IF;

    -- Update session
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
-- PHASE 3: DIRECT PvP RPCs
-- ============================================

-- 3a. Initiate PvP combat (NO faction block — always allowed; betrayal detected at API level)
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
    v_active_count INT;
    v_relation TEXT;
    v_ban_minutes NUMERIC;
    v_karma_penalty NUMERIC;
BEGIN
    IF p_target_id = v_user_id THEN
        RAISE EXCEPTION 'Cannot attack yourself';
    END IF;

    -- Get both players' factions
    SELECT sect_type, gold, mana INTO v_user_sect, v_user_gold, v_user_mana
    FROM profiles WHERE id = v_user_id;

    SELECT sect_type, mana INTO v_target_sect, v_target_mana
    FROM profiles WHERE id = p_target_id;

    IF NOT FOUND OR v_user_sect IS NULL OR v_target_sect IS NULL THEN
        RAISE EXCEPTION 'Both players must have chosen a faction.';
    END IF;

    -- Check target is not shielded
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

    -- Load config
    SELECT value INTO v_initiation_cost FROM game_config WHERE key = 'combat.pvp_initiation_gold';
    IF v_initiation_cost IS NULL THEN v_initiation_cost := 50; END IF;

    SELECT value INTO v_gold_per_tick FROM game_config WHERE key = 'combat.pvp_gold_per_tick';
    IF v_gold_per_tick IS NULL THEN v_gold_per_tick := 10; END IF;

    SELECT value INTO v_max_ticks FROM game_config WHERE key = 'combat.pvp_max_ticks';
    IF v_max_ticks IS NULL THEN v_max_ticks := 30; END IF;

    IF v_user_gold < v_initiation_cost THEN
        RAISE EXCEPTION 'Insufficient Gold. Need % to initiate combat.', v_initiation_cost;
    END IF;

    -- Check for active combat between these two
    SELECT COUNT(*) INTO v_active_count FROM combat_sessions
    WHERE combat_type = 'pvp' AND is_active = true
      AND ((attacker_id = v_user_id AND defender_id = p_target_id)
           OR (attacker_id = p_target_id AND defender_id = v_user_id));

    IF v_active_count > 0 THEN
        RAISE EXCEPTION 'Already in active combat with this target.';
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

    -- Betrayal detection: ally or own faction
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

        -- Apply ban (using existing ban_until pattern)
        UPDATE profiles SET ban_until = now() + (v_ban_minutes * interval '1 minute'), updated_at = now()
        WHERE id = v_user_id;

        -- Apply karma penalty
        UPDATE profiles SET karma = karma + v_karma_penalty, updated_at = now() WHERE id = v_user_id;

        -- Log betrayal
        INSERT INTO betrayal_punishments (user_id, target_id, betrayal_type, ban_until, karma_penalty)
        VALUES (v_user_id, p_target_id, v_relation, now() + (v_ban_minutes * interval '1 minute'), v_karma_penalty);
    END IF;

    -- Deduct initiation cost
    UPDATE profiles SET gold = gold - v_initiation_cost, updated_at = now() WHERE id = v_user_id;

    -- Count worker buildings for attacker
    SELECT COUNT(*)::INT INTO v_user_workers
    FROM player_buildings WHERE user_id = v_user_id AND is_active = true
      AND building_type IN ('novice', 'monk', 'cleric', 'bishop', 'cardinal', 'cultist');

    -- Count worker buildings for defender
    SELECT COUNT(*)::INT INTO v_target_workers
    FROM player_buildings WHERE user_id = p_target_id AND is_active = true
      AND building_type IN ('novice', 'monk', 'cleric', 'bishop', 'cardinal', 'cultist');

    -- Create combat session
    INSERT INTO combat_sessions (
        combat_type, attacker_id, defender_id,
        ticks_total, ticks_remaining,
        attacker_mana, defender_mana,
        attacker_workers, defender_workers
    ) VALUES (
        'pvp', v_user_id, p_target_id,
        v_max_ticks, v_max_ticks,
        v_user_mana, v_target_mana,
        GREATER(1, v_user_workers), GREATEST(0, v_target_workers)
    ) RETURNING id INTO v_session_id;

    RETURN jsonb_build_object(
        'success', true,
        'session_id', v_session_id,
        'faction_relation', v_relation,
        'betrayal', (v_relation IN ('ally', 'own_faction')),
        'ban_minutes', CASE WHEN v_relation IN ('ally', 'own_faction') THEN v_ban_minutes ELSE 0 END,
        'karma_penalty', CASE WHEN v_relation IN ('ally', 'own_faction') THEN v_karma_penalty ELSE 0 END
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3b. Get active PvP combats for player
CREATE OR REPLACE FUNCTION public.get_active_combats()
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_result JSONB;
BEGIN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'session_id', cs.id,
        'attacker_id', cs.attacker_id,
        'attacker_name', pa.username,
        'defender_id', cs.defender_id,
        'defender_name', pd.username,
        'attacker_mana', cs.attacker_mana,
        'defender_mana', cs.defender_mana,
        'attacker_workers', cs.attacker_workers,
        'defender_workers', cs.defender_workers,
        'ticks_total', cs.ticks_total,
        'ticks_remaining', cs.ticks_remaining,
        'gold_stolen', cs.gold_stolen,
        'gold_spent', cs.gold_spent,
        'started_at', cs.started_at,
        'last_tick_at', cs.last_tick_at,
        'is_attacker', cs.attacker_id = v_user_id,
        'result', cs.result
    ) ORDER BY cs.started_at DESC), '[]'::jsonb) INTO v_result
    FROM combat_sessions cs
    LEFT JOIN profiles pa ON pa.id = cs.attacker_id
    LEFT JOIN profiles pd ON pd.id = cs.defender_id
    WHERE cs.combat_type = 'pvp'
      AND cs.is_active = true
      AND (cs.attacker_id = v_user_id OR cs.defender_id = v_user_id);

    RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- ============================================
-- PHASE 4: VASSALAGE RPCs
-- ============================================

-- 4a. Start or advance subjugation timer
CREATE OR REPLACE FUNCTION public.start_subjugation(p_target_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_existing RECORD;
BEGIN
    IF p_target_id = v_user_id THEN
        RAISE EXCEPTION 'Cannot subjugate yourself';
    END IF;

    -- Check if target already has a liege
    IF EXISTS (SELECT 1 FROM profiles WHERE id = p_target_id AND suzerain_id IS NOT NULL) THEN
        RAISE EXCEPTION 'Target already has a liege. They must rebel first.';
    END IF;

    -- Check circular
    IF EXISTS (
        WITH RECURSIVE chain AS (
            SELECT id, suzerain_id FROM profiles WHERE id = v_user_id
            UNION ALL
            SELECT p.id, p.suzerain_id FROM profiles p JOIN chain c ON p.id = c.suzerain_id
        )
        SELECT 1 FROM chain WHERE id = p_target_id
    ) THEN
        RAISE EXCEPTION 'Cannot subjugate someone in your chain of command';
    END IF;

    SELECT * INTO v_existing FROM subjugation_timers
    WHERE liege_id = v_user_id AND vassal_id = p_target_id;

    IF FOUND THEN
        UPDATE subjugation_timers SET last_attack_at = now()
        WHERE id = v_existing.id;

        RETURN jsonb_build_object(
            'success', true,
            'accumulated_hours', v_existing.accumulated_hours,
            'remaining_hours', GREATEST(0, 168 - v_existing.accumulated_hours)
        );
    ELSE
        INSERT INTO subjugation_timers (liege_id, vassal_id)
        VALUES (v_user_id, p_target_id);

        RETURN jsonb_build_object(
            'success', true,
            'accumulated_hours', 0,
            'remaining_hours', 168
        );
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4b. Resist subjugation: pay 1000 Gold to reduce timer by 24 hours
CREATE OR REPLACE FUNCTION public.resist_subjugation(p_liege_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_user_gold INT;
    v_tribute_cost NUMERIC;
BEGIN
    SELECT gold INTO v_user_gold FROM profiles WHERE id = v_user_id;

    SELECT value INTO v_tribute_cost FROM game_config WHERE key = 'vassalage.tribute_gold_cost';
    IF v_tribute_cost IS NULL THEN v_tribute_cost := 1000; END IF;

    IF v_user_gold < v_tribute_cost THEN
        RAISE EXCEPTION 'Insufficient Gold. Need % to resist subjugation.', v_tribute_cost;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM subjugation_timers WHERE liege_id = p_liege_id AND vassal_id = v_user_id AND accumulated_hours > 0
    ) THEN
        RAISE EXCEPTION 'No active subjugation from this liege.';
    END IF;

    -- Deduct gold
    UPDATE profiles SET gold = gold - v_tribute_cost, updated_at = now() WHERE id = v_user_id;

    -- Reduce accumulated hours by 24
    UPDATE subjugation_timers
    SET accumulated_hours = GREATEST(0, accumulated_hours - 24)
    WHERE liege_id = p_liege_id AND vassal_id = v_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'gold_spent', v_tribute_cost,
        'new_accumulated_hours',
        (SELECT accumulated_hours FROM subjugation_timers WHERE liege_id = p_liege_id AND vassal_id = v_user_id)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4c. Attempt rebellion: break free if liege hasn't attacked for 3+ days
CREATE OR REPLACE FUNCTION public.attempt_rebellion()
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_liege_id UUID;
    v_idle_days NUMERIC;
    v_last_attack TIMESTAMPTZ;
BEGIN
    SELECT suzerain_id INTO v_liege_id FROM profiles WHERE id = v_user_id;
    IF v_liege_id IS NULL THEN
        RAISE EXCEPTION 'You are not a vassal.';
    END IF;

    SELECT value INTO v_idle_days FROM game_config WHERE key = 'vassalage.rebellion_idle_days';
    IF v_idle_days IS NULL THEN v_idle_days := 3; END IF;

    -- Check last attack from liege
    SELECT COALESCE(MAX(started_at), now() - interval '30 days') INTO v_last_attack
    FROM combat_sessions
    WHERE attacker_id = v_liege_id AND defender_id = v_user_id
      AND combat_type = 'pvp' AND is_active = false;

    IF (now() - v_last_attack) < (v_idle_days * interval '1 day') THEN
        RAISE EXCEPTION 'Your liege has attacked within the last % days. Rebellion not yet possible.', v_idle_days;
    END IF;

    -- Clear vassalage
    UPDATE profiles SET suzerain_id = NULL, updated_at = now() WHERE id = v_user_id;

    -- Clean up subjugation timer
    DELETE FROM subjugation_timers WHERE vassal_id = v_user_id;

    RETURN jsonb_build_object('success', true, 'freed_from', v_liege_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4d. Update get_vassalage_info to include subjugation timers
CREATE OR REPLACE FUNCTION public.get_vassalage_info()
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_suzerain JSONB;
    v_vassals JSONB;
    v_vassal_count INT;
    v_daily_tithes JSONB;
    v_is_protected BOOLEAN;
    v_chain_depth INT;
    v_subjugation_as_liege JSONB;
    v_subjugation_as_vassal JSONB;
    v_tithe_pct NUMERIC;
BEGIN
    SELECT value INTO v_tithe_pct FROM game_config WHERE key = 'tithe.percentage';
    IF v_tithe_pct IS NULL THEN v_tithe_pct := 0.10; END IF;

    -- Suzerain info
    SELECT jsonb_build_object(
        'id', p.id, 'username', p.username, 'faith', p.faith
    ) INTO v_suzerain
    FROM profiles p WHERE p.id = (SELECT suzerain_id FROM profiles WHERE id = v_user_id);

    -- Vassals
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', p.id, 'username', p.username, 'faith', p.faith
    )), '[]'::jsonb), COUNT(*)::INT INTO v_vassals, v_vassal_count
    FROM profiles p WHERE p.suzerain_id = v_user_id;

    -- Daily tithes from vassals
    SELECT jsonb_build_object(
        'mana_per_day', FLOOR(COALESCE(SUM(COALESCE((SELECT value FROM game_config WHERE key = 'building.' || vb.building_type || '.mana_per_day'), 0)), 0) * v_tithe_pct),
        'gold_per_day', FLOOR(COALESCE(SUM(COALESCE((SELECT value FROM game_config WHERE key = 'building.' || vb.building_type || '.gold_per_day'), 0)), 0) * v_tithe_pct),
        'food_per_day', FLOOR(COALESCE(SUM(COALESCE((SELECT value FROM game_config WHERE key = 'building.' || vb.building_type || '.food_per_day'), 0)), 0) * v_tithe_pct)
    ) INTO v_daily_tithes
    FROM profiles vp
    JOIN player_buildings vb ON vb.user_id = vp.id AND vb.is_active = true
    WHERE vp.suzerain_id = v_user_id;

    IF v_daily_tithes IS NULL THEN
        v_daily_tithes := jsonb_build_object('mana_per_day', 0, 'gold_per_day', 0, 'food_per_day', 0);
    END IF;

    -- Shield status
    SELECT (divine_shield_until IS NOT NULL AND divine_shield_until > now()) INTO v_is_protected
    FROM profiles WHERE id = v_user_id;

    -- Chain depth
    WITH RECURSIVE chain AS (
        SELECT id, suzerain_id, 0 AS depth FROM profiles WHERE id = v_user_id
        UNION ALL
        SELECT p.id, p.suzerain_id, c.depth + 1 FROM profiles p JOIN chain c ON p.id = c.suzerain_id
    )
    SELECT MAX(depth) INTO v_chain_depth FROM chain;

    -- Subjugation timers where I'm the liege
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'vassal_id', st.vassal_id,
        'vassal_name', p.username,
        'accumulated_hours', st.accumulated_hours,
        'remaining_hours', GREATEST(0, 168 - st.accumulated_hours),
        'last_attack_at', st.last_attack_at
    )), '[]'::jsonb) INTO v_subjugation_as_liege
    FROM subjugation_timers st
    JOIN profiles p ON p.id = st.vassal_id
    WHERE st.liege_id = v_user_id AND st.accumulated_hours < 168;

    -- Subjugation timers where I'm the target
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'liege_id', st.liege_id,
        'liege_name', p.username,
        'accumulated_hours', st.accumulated_hours,
        'remaining_hours', GREATEST(0, 168 - st.accumulated_hours),
        'last_attack_at', st.last_attack_at
    )), '[]'::jsonb) INTO v_subjugation_as_vassal
    FROM subjugation_timers st
    JOIN profiles p ON p.id = st.liege_id
    WHERE st.vassal_id = v_user_id AND st.accumulated_hours < 168;

    RETURN jsonb_build_object(
        'suzerain', v_suzerain,
        'vassals', v_vassals,
        'vassal_count', v_vassal_count,
        'daily_tithes', v_daily_tithes,
        'is_protected', v_is_protected,
        'chain_depth', v_chain_depth,
        'subjugation_as_liege', v_subjugation_as_liege,
        'subjugation_as_vassal', v_subjugation_as_vassal
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- PHASE 5: HEARTBEAT UPDATE
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
    -- PHASE 2: RESOURCE GENERATION (NO CAPS, 10x SCALING via tick_divisor=144)
    -- ========================================
    WITH user_production AS (
        SELECT
            pb.user_id,
            COALESCE(SUM(CASE WHEN gc_mana.value IS NOT NULL THEN gc_mana.value ELSE 0 END), 0)::NUMERIC AS gross_mana_per_day,
            COALESCE(SUM(CASE WHEN gc_gold.value IS NOT NULL THEN gc_gold.value ELSE 0 END), 0)::NUMERIC AS gross_gold_per_day,
            COALESCE(SUM(CASE WHEN gc_food.value IS NOT NULL THEN gc_food.value ELSE 0 END), 0)::NUMERIC AS gross_food_per_day,
            COALESCE(SUM(CASE WHEN gc_gold_upkeep.value IS NOT NULL THEN gc_gold_upkeep.value ELSE 0 END), 0)::NUMERIC AS total_gold_upkeep_per_day,
            COALESCE(SUM(CASE WHEN gc_food_consume.value IS NOT NULL THEN gc_food_consume.value ELSE 0 END), 0)::NUMERIC AS total_food_consumption_per_day,
            COALESCE(SUM(CASE WHEN gc_heresy.value IS NOT NULL THEN gc_heresy.value ELSE 0 END), 0)::NUMERIC AS gross_heresy_per_day,
            COALESCE(SUM(CASE WHEN gc_dogma.value IS NOT NULL THEN gc_dogma.value ELSE 0 END), 0)::NUMERIC AS gross_dogma_per_day,
            COALESCE(SUM(CASE WHEN pb.building_type = 'coven' THEN 1 ELSE 0 END), 0)::INT AS coven_count
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
            tp.suzerain_id,
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
    )
    -- NO LEAST caps — unbounded resource accumulation
    UPDATE profiles p SET
        mana = p.mana + tp.mana_tick - tp.mana_tithe_tick + COALESCE(ti.received_mana_tick, 0),
        gold = GREATEST(0, p.gold + tp.gold_tick - tp.gold_upkeep_tick - tp.gold_tithe_tick + COALESCE(ti.received_gold_tick, 0) - COALESCE(st.gold_synod_tax_tick, 0)),
        food = GREATEST(0, p.food + tp.food_tick - tp.food_consume_tick - tp.food_tithe_tick + COALESCE(ti.received_food_tick, 0)),
        heresy = p.heresy + tp.heresy_tick,
        dogma = p.dogma + tp.dogma_tick,
        updated_at = now()
    FROM tick_production tp
    LEFT JOIN tithe_inbound ti ON ti.suzerain_id = p.id
    LEFT JOIN synod_tax st ON st.user_id = p.id
    WHERE p.id = tp.user_id;

    -- ========================================
    -- PHASE 3: SYNOD VAULT DEPOSITS
    -- ========================================
    UPDATE synods s SET
        vault_gold = vault_gold + COALESCE((SELECT SUM(st.gold_synod_tax_tick) FROM synod_tax st WHERE st.synod_id = s.id GROUP BY st.synod_id), 0),
        vault_mana = vault_mana + COALESCE((SELECT SUM(st.mana_synod_tax_tick) FROM synod_tax st WHERE st.synod_id = s.id GROUP BY st.synod_id), 0)
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
        -- Process PvP combat ticks inline
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

            -- Damage: attacker workers hit defender mana, defender workers hit attacker mana
            v_s.defender_mana := GREATEST(0, v_s.defender_mana - v_s.attacker_workers);
            IF v_s.defender_workers > 0 THEN
                v_s.attacker_mana := GREATEST(0, v_s.attacker_mana - v_s.defender_workers);
            END IF;

            -- Attrition + exertion
            v_s.attacker_workers := GREATEST(0, v_s.attacker_workers - FLOOR(v_s.attacker_workers * v_attrition));
            v_s.attacker_mana := GREATEST(0, v_s.attacker_mana - FLOOR(v_s.attacker_mana * v_exertion));
            IF v_s.defender_workers > 0 THEN
                v_s.defender_workers := GREATEST(0, v_s.defender_workers - FLOOR(v_s.defender_workers * v_attrition));
            END IF;

            -- Leech
            v_leech := FLOOR(v_defender_gold * v_leech_pct);
            v_s.gold_stolen := v_s.gold_stolen + v_leech;
            v_s.gold_spent := v_s.gold_spent + v_gold_per_tick;
            v_s.ticks_remaining := v_s.ticks_remaining - 1;

            -- Victory conditions
            IF v_s.defender_mana <= 0 THEN v_result := 'attacker_win';
            ELSIF v_s.attacker_mana <= 0 OR v_attacker_gold < v_gold_per_tick THEN v_result := 'defender_win';
            ELSIF v_s.ticks_remaining <= 0 THEN v_result := 'stalemate';
            END IF;

            -- Apply gold changes
            IF v_leech > 0 THEN
                UPDATE profiles SET gold = GREATEST(0, gold - v_leech) WHERE id = v_s.defender_id;
            END IF;
            IF v_attacker_gold >= v_gold_per_tick THEN
                UPDATE profiles SET gold = gold - v_gold_per_tick, updated_at = now() WHERE id = v_s.attacker_id;
            END IF;

            -- Handle outcome
            IF v_result = 'attacker_win' THEN
                -- Determine faction relation for karma reward
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

    -- Process Holy War ticks
    FOR r IN SELECT id FROM combat_sessions WHERE is_active = true AND combat_type = 'holy_war' LOOP
        PERFORM process_holy_war_tick(r.id);
    END LOOP;

    -- ========================================
    -- PHASE 7: ADVANCE SUBJUGATION TIMERS
    -- ========================================
    -- For each active PvP combat, advance subjugation timer
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

        -- Check if subjugation complete
        IF EXISTS (
            SELECT 1 FROM subjugation_timers
            WHERE liege_id = r.attacker_id AND vassal_id = r.defender_id
              AND accumulated_hours >= 168
        ) THEN
            -- Set vassalage
            UPDATE profiles SET suzerain_id = r.attacker_id, updated_at = now()
            WHERE id = r.defender_id AND suzerain_id IS NULL;

            -- Log
            INSERT INTO akashic_logs (target_id, actor_id, action_type, result_data)
            VALUES (r.defender_id, r.attacker_id, 'crusade',
                jsonb_build_object('type', 'subjugation_complete', 'liege_id', r.attacker_id, 'vassal_id', r.defender_id));

            -- Clean up timer
            DELETE FROM subjugation_timers WHERE liege_id = r.attacker_id AND vassal_id = r.defender_id;
        END IF;
    END LOOP;

    -- ========================================
    -- PHASE 8: VASSAL TITHES + LIEGE KARMA
    -- ========================================
    -- Award liege karma and tithes per vassal (once per minute tick)
    FOR r IN
        SELECT p.id AS vassal_id, p.suzerain_id AS liege_id
        FROM profiles p WHERE p.suzerain_id IS NOT NULL
    LOOP
        -- Transfer gold tithe from vassal to liege
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

        -- Award daily karma (approximate: every 1440 ticks ~= daily)
        UPDATE profiles SET karma = karma + ROUND(v_liege_karma_per_day / 1440.0, 4)::NUMERIC
        WHERE id = r.liege_id;
    END LOOP;

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- PHASE 8: GRANTS & PERMISSIONS
-- ============================================

-- Grant table access
GRANT SELECT ON TABLE synod_applicants TO authenticated;
GRANT INSERT ON TABLE synod_applicants TO authenticated;
GRANT DELETE ON TABLE synod_applicants TO authenticated;
GRANT SELECT ON TABLE synod_applicants TO service_role;

GRANT SELECT ON TABLE combat_sessions TO authenticated;
GRANT SELECT ON TABLE combat_sessions TO service_role;

GRANT SELECT ON TABLE subjugation_timers TO authenticated;
GRANT SELECT ON TABLE subjugation_timers TO service_role;

GRANT SELECT ON TABLE betrayal_punishments TO authenticated;
GRANT SELECT ON TABLE betrayal_punishments TO anon;
GRANT SELECT ON TABLE betrayal_punishments TO service_role;

-- Grant execute on helper functions
GRANT EXECUTE ON FUNCTION can_associate_factions(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION can_associate_factions(TEXT, TEXT) TO service_role;

GRANT EXECUTE ON FUNCTION get_player_faction_relationships() TO authenticated;
GRANT EXECUTE ON FUNCTION get_player_faction_relationships() TO service_role;

-- Grant execute on Synod RPCs
GRANT EXECUTE ON FUNCTION create_synod(TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION create_synod(TEXT, TEXT, TEXT) TO service_role;

GRANT EXECUTE ON FUNCTION petition_synod(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION petition_synod(UUID) TO service_role;

GRANT EXECUTE ON FUNCTION leave_synod() TO authenticated;
GRANT EXECUTE ON FUNCTION leave_synod() TO service_role;

GRANT EXECUTE ON FUNCTION get_public_synods() TO authenticated;
GRANT EXECUTE ON FUNCTION get_public_synods() TO service_role;

GRANT EXECUTE ON FUNCTION approve_synod_applicant(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION approve_synod_applicant(UUID) TO service_role;

GRANT EXECUTE ON FUNCTION reject_synod_applicant(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION reject_synod_applicant(UUID) TO service_role;

GRANT EXECUTE ON FUNCTION update_synod_privacy(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION update_synod_privacy(TEXT) TO service_role;

GRANT EXECUTE ON FUNCTION update_synod_message(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION update_synod_message(TEXT) TO service_role;

GRANT EXECUTE ON FUNCTION get_synod_info() TO authenticated;
GRANT EXECUTE ON FUNCTION get_synod_info() TO service_role;

GRANT EXECUTE ON FUNCTION get_available_factions() TO authenticated;
GRANT EXECUTE ON FUNCTION get_available_factions() TO anon;
GRANT EXECUTE ON FUNCTION get_available_factions() TO service_role;

-- Grant execute on Holy War RPCs
GRANT EXECUTE ON FUNCTION find_synod_by_name(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION find_synod_by_name(TEXT) TO service_role;

GRANT EXECUTE ON FUNCTION initiate_holy_war(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION initiate_holy_war(UUID) TO service_role;

GRANT EXECUTE ON FUNCTION get_active_holy_wars() TO authenticated;
GRANT EXECUTE ON FUNCTION get_active_holy_wars() TO service_role;

GRANT EXECUTE ON FUNCTION process_holy_war_tick(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION process_holy_war_tick(UUID) TO service_role;

-- Grant execute on PvP RPCs
GRANT EXECUTE ON FUNCTION initiate_combat(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION initiate_combat(UUID) TO service_role;

GRANT EXECUTE ON FUNCTION get_active_combats() TO authenticated;
GRANT EXECUTE ON FUNCTION get_active_combats() TO service_role;

-- Grant execute on Vassalage RPCs
GRANT EXECUTE ON FUNCTION start_subjugation(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION start_subjugation(UUID) TO service_role;

GRANT EXECUTE ON FUNCTION resist_subjugation(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION resist_subjugation(UUID) TO service_role;

GRANT EXECUTE ON FUNCTION attempt_rebellion() TO authenticated;
GRANT EXECUTE ON FUNCTION attempt_rebellion() TO service_role;

GRANT EXECUTE ON FUNCTION get_vassalage_info() TO authenticated;
GRANT EXECUTE ON FUNCTION get_vassalage_info() TO service_role;

-- Grant execute on heartbeat
GRANT EXECUTE ON FUNCTION calculate_automated_karma() TO service_role;

-- Re-grant existing functions that may have been dropped/recreated
GRANT EXECUTE ON FUNCTION promote_synod_member(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION promote_synod_member(UUID) TO service_role;

GRANT EXECUTE ON FUNCTION demote_synod_member(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION demote_synod_member(UUID) TO service_role;

GRANT EXECUTE ON FUNCTION kick_synod_member(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION kick_synod_member(UUID) TO service_role;

-- ============================================
-- END OF EXODUS 1
-- =====================================================