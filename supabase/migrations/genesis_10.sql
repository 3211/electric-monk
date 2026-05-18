-- =====================================================
-- ELECTRIC MONK -- GENESIS 10: Faith-Filtered Leaderboard RPCs
-- Date: 2026-05-18
--
-- Adds two new RPCs to support the overhauled Leaderboard view:
--   1. get_leaderboard_by_faith(p_faith, p_offset, p_limit)
--      Returns players filtered by faith, ranked within that faith
--      and globally. No resource columns -- just name, ranks, shield.
--
--   2. get_user_ranks()
--      Returns the current user's global_rank, faith_rank, and faith.
--
-- This script is idempotent (CREATE OR REPLACE).
-- DO NOT USE EMOJIS IN CODE OR DEBUG LOGS.
-- =====================================================

-- ============================================
-- RPC 1: get_leaderboard_by_faith
-- ============================================
CREATE OR REPLACE FUNCTION get_leaderboard_by_faith(
    p_faith TEXT,
    p_offset INT DEFAULT 0,
    p_limit INT DEFAULT 5
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
            p.divine_shield_until,
            ROW_NUMBER() OVER (ORDER BY p.karma DESC, p.mana DESC, p.created_at ASC) AS global_rank,
            ROW_NUMBER() OVER (PARTITION BY p.sect_type ORDER BY p.karma DESC, p.mana DESC, p.created_at ASC) AS faith_rank
        FROM profiles p
        WHERE p.username IS NOT NULL
          AND p.sect_type = p_faith
        ORDER BY p.karma DESC, p.mana DESC, p.created_at ASC
        LIMIT p_limit OFFSET p_offset
    ) t;

    RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- RPC 2: get_user_ranks
-- ============================================
CREATE OR REPLACE FUNCTION get_user_ranks()
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'global_rank', (
            SELECT COUNT(*) + 1
            FROM profiles p2
            WHERE p2.username IS NOT NULL
              AND (
                  p2.karma > p1.karma
                  OR (p2.karma = p1.karma AND p2.mana > p1.mana)
                  OR (p2.karma = p1.karma AND p2.mana = p1.mana AND p2.created_at < p1.created_at)
              )
        ),
        'faith_rank', (
            SELECT COUNT(*) + 1
            FROM profiles p2
            WHERE p2.username IS NOT NULL
              AND p2.sect_type = p1.sect_type
              AND (
                  p2.karma > p1.karma
                  OR (p2.karma = p1.karma AND p2.mana > p1.mana)
                  OR (p2.karma = p1.karma AND p2.mana = p1.mana AND p2.created_at < p1.created_at)
              )
        ),
        'faith', p1.sect_type
    ) INTO v_result
    FROM profiles p1
    WHERE p1.id = v_user_id;

    RETURN COALESCE(v_result, '{}'::jsonb);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- GRANT PERMISSIONS
-- ============================================
GRANT EXECUTE ON FUNCTION get_leaderboard_by_faith(TEXT, INT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_leaderboard_by_faith(TEXT, INT, INT) TO anon;

GRANT EXECUTE ON FUNCTION get_user_ranks() TO authenticated;
GRANT EXECUTE ON FUNCTION get_user_ranks() TO anon;