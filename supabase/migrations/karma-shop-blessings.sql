-- ============================================
-- KARMA SHOP - BLESSINGS (idempotent migration)
-- Adds blessing_types table, prayer_blessings junction table,
-- RPC functions for granting and fetching blessings,
-- RLS policies, seed data, and permissions.
-- Paste this into Supabase SQL Editor to run.
-- ============================================

-- 1. Create blessing_types table (mirrors src/config/blessings.json)
CREATE TABLE IF NOT EXISTS blessing_types (
  id TEXT PRIMARY KEY,
  emoji TEXT NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  karma_cost INT NOT NULL DEFAULT 0,
  karma_to_giver INT NOT NULL DEFAULT 0,
  karma_to_receiver INT NOT NULL DEFAULT 0,
  sort_order INT DEFAULT 0,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Create prayer_blessings junction table
-- One user can give each blessing type ONCE per prayer (UNIQUE constraint)
CREATE TABLE IF NOT EXISTS prayer_blessings (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  prayer_id UUID REFERENCES prayers(id) ON DELETE CASCADE NOT NULL,
  blessing_type_id TEXT REFERENCES blessing_types(id) ON DELETE CASCADE NOT NULL,
  giver_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  receiver_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(prayer_id, blessing_type_id, giver_id)
);

-- 3. Indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_prayer_blessings_prayer ON prayer_blessings(prayer_id);
CREATE INDEX IF NOT EXISTS idx_prayer_blessings_giver ON prayer_blessings(giver_id);
CREATE INDEX IF NOT EXISTS idx_prayer_blessings_type ON prayer_blessings(blessing_type_id);
CREATE INDEX IF NOT EXISTS idx_prayer_blessings_receiver ON prayer_blessings(receiver_id);

-- 4. RLS Policies

-- blessing_types: anyone authenticated can read
ALTER TABLE blessing_types ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Blessing types are publicly readable" ON blessing_types;
CREATE POLICY "Blessing types are publicly readable" ON blessing_types
  FOR SELECT USING (true);

-- prayer_blessings: anyone authenticated can read, no direct INSERT
-- (all inserts go through grant_blessing RPC which runs as SECURITY DEFINER)
ALTER TABLE prayer_blessings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Prayer blessings are publicly readable" ON prayer_blessings;
CREATE POLICY "Prayer blessings are publicly readable" ON prayer_blessings
  FOR SELECT USING (true);

-- 5. RPC: grant_blessing
-- Atomically deduct karma from giver, award karma to giver and receiver, insert blessing row.
-- Prevents self-blessing and duplicate blessings.
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

-- 6. RPC: get_prayer_blessings
-- Fetches aggregated blessing counts for a batch of prayers.
-- Returns one row per (prayer_id, blessing_type_id) with count and emoji.
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

-- 7. Update get_public_prayers to include blessing summary
-- Modified version that also returns blessing aggregate data per prayer
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
      SELECT p.id, p.response_content, p.prayer_count,
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

-- 8. Seed data (idempotent upsert)
INSERT INTO blessing_types (id, emoji, name, description, karma_cost, karma_to_giver, karma_to_receiver, sort_order)
VALUES
  ('golden-light', '✨', 'Golden Light', 'A radiant blessing that illuminates the prayer with divine light.', 10, 1, 5, 1),
  ('holy-flame', '🔥', 'Holy Flame', 'The sacred fire that purifies and elevates the spirit.', 25, 2, 10, 2),
  ('dove-of-peace', '🕊️', 'Dove of Peace', 'A gentle blessing that brings tranquility and grace.', 50, 5, 20, 3),
  ('divine-crown', '👑', 'Divine Crown', 'The highest honor — a crown of divine recognition.', 100, 10, 50, 4)
ON CONFLICT (id) DO UPDATE SET
  emoji = EXCLUDED.emoji,
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  karma_cost = EXCLUDED.karma_cost,
  karma_to_giver = EXCLUDED.karma_to_giver,
  karma_to_receiver = EXCLUDED.karma_to_receiver,
  sort_order = EXCLUDED.sort_order,
  is_active = true;

-- 9. Permissions
GRANT EXECUTE ON FUNCTION grant_blessing(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_prayer_blessings(UUID[]) TO authenticated;
GRANT EXECUTE ON FUNCTION get_public_prayers(INT, INT, TEXT) TO authenticated;