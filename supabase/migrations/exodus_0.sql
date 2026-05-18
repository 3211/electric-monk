-- ============================================
-- Exodus 0: Factions View — Relationships & Overview
-- ============================================
--
-- Adds:
--   1. faction_relationships table (enemy/ally/neutral per sect)
--   2. Seed data for all four faction relationships
--   3. get_factions_overview() RPC (member counts, top-5, relationships, modifiers, missions)
--   4. RLS & permissions
--

-- ============================================
-- 1. FACTION RELATIONSHIPS TABLE
-- ============================================

CREATE TABLE IF NOT EXISTS faction_relationships (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  sect_key TEXT NOT NULL UNIQUE
    CHECK (sect_key IN ('gilded_path', 'holy_way', 'final_watch', 'black_tribunal')),
  enemy_sect TEXT NOT NULL
    CHECK (enemy_sect IN ('gilded_path', 'holy_way', 'final_watch', 'black_tribunal')),
  ally_sect TEXT NOT NULL
    CHECK (ally_sect IN ('gilded_path', 'holy_way', 'final_watch', 'black_tribunal')),
  neutral_sect TEXT NOT NULL
    CHECK (neutral_sect IN ('gilded_path', 'holy_way', 'final_watch', 'black_tribunal')),
  rationale_enemy TEXT,
  rationale_ally TEXT,
  rationale_neutral TEXT,
  CHECK (sect_key != enemy_sect),
  CHECK (sect_key != ally_sect),
  CHECK (sect_key != neutral_sect)
);

-- ============================================
-- 2. SEED DATA
-- ============================================

INSERT INTO faction_relationships (sect_key, enemy_sect, ally_sect, neutral_sect, rationale_enemy, rationale_ally, rationale_neutral) VALUES

('gilded_path', 'black_tribunal', 'holy_way', 'final_watch',
 'Needs Mana to fuel defenses; The Tribunal steals Gold.',
 'Mutual economic dependency — Gilded provides Gold, Holy provides Mana.',
 'Neither ally nor foe; pragmatic coexistence.'),

('holy_way', 'final_watch', 'gilded_path', 'black_tribunal',
 'The Watch blocks their ascension; physical stability clashes with pure Mana worship.',
 'Gilded Path funds their ascetic lifestyle with Gold.',
 'The Tribunal ignores pure monks; no economic overlap.'),

('final_watch', 'holy_way', 'black_tribunal', 'gilded_path',
 'Physical stability clashes with pure Mana worship; the Watch sees asceticism as weakness.',
 'The Tribunal serves as an aggressive police force the Watch respects.',
 'Pragmatic coexistence; no direct conflict or benefit.'),

('black_tribunal', 'gilded_path', 'final_watch', 'holy_way',
 'High Heresy attracts Gold hoarders; natural enemies.',
 'The Tribunal serves as an aggressive police force; the Watch is their enforcer.',
 'Pure monks are beneath the Tribunal''s notice.')
ON CONFLICT (sect_key) DO UPDATE SET
  enemy_sect = EXCLUDED.enemy_sect,
  ally_sect = EXCLUDED.ally_sect,
  neutral_sect = EXCLUDED.neutral_sect,
  rationale_enemy = EXCLUDED.rationale_enemy,
  rationale_ally = EXCLUDED.rationale_ally,
  rationale_neutral = EXCLUDED.rationale_neutral;

-- ============================================
-- 3. RLS & PERMISSIONS
-- ============================================

ALTER TABLE faction_relationships ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view faction relationships"
  ON faction_relationships FOR SELECT
  USING (true);

GRANT SELECT ON TABLE faction_relationships TO authenticated;
GRANT SELECT ON TABLE faction_relationships TO anon;
GRANT SELECT ON TABLE faction_relationships TO service_role;

-- ============================================
-- 4. RPC: get_factions_overview()
-- ============================================

CREATE OR REPLACE FUNCTION get_factions_overview()
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT jsonb_object_agg(f.sect_key, f.payload)
    INTO v_result
    FROM (
        SELECT
            p.sect_type AS sect_key,
            jsonb_build_object(
                'member_count', COUNT(*)::INT,
                'top_members', (
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'id', m.id,
                            'username', m.username,
                            'karma', COALESCE(m.karma, 0),
                            'faith', m.faith
                        )
                        ORDER BY COALESCE(m.karma, 0) DESC
                    )
                    FROM profiles m
                    WHERE m.sect_type = p.sect_type
                    LIMIT 5
                ),
                'enemy', fr.enemy_sect,
                'ally', fr.ally_sect,
                'neutral', fr.neutral_sect,
                'rationale_enemy', fr.rationale_enemy,
                'rationale_ally', fr.rationale_ally,
                'rationale_neutral', fr.rationale_neutral,
                'modifiers', (
                    SELECT jsonb_object_agg(
                        replace(gc.key, 'sect.' || p.sect_type || '.', ''),
                        gc.value
                    )
                    FROM game_config gc
                    WHERE gc.key LIKE 'sect.' || p.sect_type || '.%'
                ),
                'mission', CASE p.sect_type
                    WHEN 'gilded_path' THEN 'Prosperity through ambition. Wealth is the highest blessing, and grandeur is the proof of divine favor.'
                    WHEN 'holy_way' THEN 'Grace through selflessness. Compassion and devotion are the only true currencies.'
                    WHEN 'final_watch' THEN 'Strength through vigilance. The faithful must be defended at all costs — endure, protect, endure again.'
                    WHEN 'black_tribunal' THEN 'Power through conquest. Heresy must be eradicated; the weak exist only to serve the strong.'
                END
            ) AS payload
        FROM profiles p
        LEFT JOIN faction_relationships fr ON fr.sect_key = p.sect_type
        WHERE p.sect_type IS NOT NULL
        GROUP BY p.sect_type, fr.enemy_sect, fr.ally_sect, fr.neutral_sect,
                 fr.rationale_enemy, fr.rationale_ally, fr.rationale_neutral
    ) f;

    RETURN COALESCE(v_result, '{}'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION get_factions_overview() TO authenticated;
GRANT EXECUTE ON FUNCTION get_factions_overview() TO service_role;