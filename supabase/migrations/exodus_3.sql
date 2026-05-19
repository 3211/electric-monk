-- ============================================
-- Exodus 3: Synod Rankings & War UI Integration
-- ============================================
--
-- Adds:
--   1. get_synod_rankings_by_sect RPC — synods ranked
--      by member_count, grouped by sect_key
--   2. get_synod_defense_status RPC — check if a
--      synod is currently being attacked (defender)

-- ============================================
-- RPC 1: get_synod_rankings_by_sect
-- ============================================
-- Returns all public synods, ranked by total power
-- (member_count + vault_gold/100), grouped by sect_key.
-- Visible to all authenticated users regardless of
-- synod membership.

CREATE OR REPLACE FUNCTION public.get_synod_rankings_by_sect()
RETURNS JSONB AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT jsonb_agg(
        jsonb_build_object(
            'sect_key', ranked.sect_key,
            'rank', ranked.rank,
            'synod_id', ranked.synod_id,
            'name', ranked.name,
            'leader_name', ranked.leader_name,
            'member_count', ranked.member_count,
            'vault_gold', ranked.vault_gold,
            'has_active_war', ranked.has_active_war,
            'privacy', ranked.privacy
        ) ORDER BY ranked.sect_key, ranked.rank
    ) INTO v_result
    FROM (
        SELECT
            s.sect_key,
            s.id AS synod_id,
            s.name,
            pl.username AS leader_name,
            (SELECT COUNT(*) FROM public.profiles WHERE synod_id = s.id)::INT AS member_count,
            s.vault_gold,
            (s.active_war_id IS NOT NULL) AS has_active_war,
            s.privacy,
            ROW_NUMBER() OVER (
                PARTITION BY s.sect_key
                ORDER BY
                    (SELECT COUNT(*) FROM public.profiles WHERE synod_id = s.id) DESC,
                    s.vault_gold DESC,
                    s.created_at ASC
            )::INT AS rank
        FROM public.synods s
        LEFT JOIN public.profiles pl ON pl.id = s.leader_id
        WHERE s.sect_key IS NOT NULL
          AND s.sect_key IN ('gilded_path', 'holy_way', 'final_watch', 'black_tribunal')
        ORDER BY s.sect_key, rank
    ) ranked;

    RETURN COALESCE(v_result, '[]'::JSONB);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- ============================================
-- RPC 2: get_synod_defense_status
-- ============================================
-- Returns whether the user's synod is currently
-- being attacked (defender in an active war).
-- Used to hide the "Declare War" button when
-- the synod must defend itself first.

CREATE OR REPLACE FUNCTION public.get_synod_defense_status()
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_synod_id UUID;
    v_under_attack BOOLEAN;
    v_attacker_name TEXT;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('under_attack', false);
    END IF;

    SELECT synod_id INTO v_synod_id FROM public.profiles WHERE id = v_user_id;
    IF v_synod_id IS NULL THEN
        RETURN jsonb_build_object('under_attack', false);
    END IF;

    SELECT EXISTS(
        SELECT 1 FROM public.synod_wars sw
        WHERE sw.defender_synod_id = v_synod_id
          AND sw.is_active = true
    ) INTO v_under_attack;

    IF v_under_attack THEN
        SELECT s.name INTO v_attacker_name
        FROM public.synod_wars sw
        JOIN public.synods s ON s.id = sw.attacker_synod_id
        WHERE sw.defender_synod_id = v_synod_id
          AND sw.is_active = true
        LIMIT 1;
    END IF;

    RETURN jsonb_build_object(
        'under_attack', v_under_attack,
        'attacker_name', v_attacker_name
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- ============================================
-- GRANTS
-- ============================================
GRANT EXECUTE ON FUNCTION get_synod_rankings_by_sect() TO authenticated;
GRANT EXECUTE ON FUNCTION get_synod_rankings_by_sect() TO service_role;
GRANT EXECUTE ON FUNCTION get_synod_defense_status() TO authenticated;
GRANT EXECUTE ON FUNCTION get_synod_defense_status() TO service_role;