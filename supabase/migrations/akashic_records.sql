-- ============================================
-- AKASHIC RECORDS - MIGRATION (idempotent)
-- Adds prayer_type, source links, karma milestones,
-- and RPC functions for the Akashic Records feature.
-- Paste this into Supabase SQL Editor to run.
-- ============================================

-- 1. Add new columns to prayers table
ALTER TABLE prayers ADD COLUMN IF NOT EXISTS karma_awarded INT DEFAULT 0;
ALTER TABLE prayers ADD COLUMN IF NOT EXISTS source_prayer_id UUID REFERENCES prayers(id) ON DELETE SET NULL;
ALTER TABLE prayers ADD COLUMN IF NOT EXISTS source_sinner_id UUID REFERENCES profiles(id) ON DELETE SET NULL;
ALTER TABLE prayers ADD COLUMN IF NOT EXISTS prayer_type TEXT DEFAULT 'own'
  CHECK (prayer_type IN ('own', 'altruistic', 'intercessory'));

-- 2. Indexes for efficient Akashic Records queries
CREATE INDEX IF NOT EXISTS idx_prayers_public_feed
  ON prayers(is_rejected, is_archived, created_at DESC)
  WHERE is_rejected = false AND is_archived = false;

CREATE INDEX IF NOT EXISTS idx_prayers_type_active
  ON prayers(user_id, prayer_type, is_praying)
  WHERE is_praying = true;

CREATE INDEX IF NOT EXISTS idx_prayers_most_prayed
  ON prayers(prayer_count DESC)
  WHERE is_rejected = false AND is_archived = false AND prayer_type = 'own';

-- 3. RLS Policies (idempotent — DROP IF EXISTS before CREATE)

-- Users can view approved, non-archived, completed prayers from others (Akashic Records feed)
-- Plus always see their own prayers
DROP POLICY IF EXISTS "Users can view own prayers" ON prayers;
DROP POLICY IF EXISTS "Users can view approved prayers" ON prayers;
CREATE POLICY "Users can view approved prayers"
  ON prayers FOR SELECT
  USING (
    auth.uid() = user_id  -- always see your own
    OR (is_rejected = false AND is_archived = false AND status = 'completed')  -- see others' approved
  );

-- Users can view purgatory users' basic info (for Sinners list)
-- Plus always see their own profile
DROP POLICY IF EXISTS "Users can view own profile" ON profiles;
DROP POLICY IF EXISTS "Users can view profiles" ON profiles;
CREATE POLICY "Users can view profiles"
  ON profiles FOR SELECT
  USING (
    auth.uid() = id  -- always see your own
    OR (ban_until IS NOT NULL AND ban_until > now())  -- see purgatory users
  );

-- Users can insert own prayers (including altruistic/intercessory)
DROP POLICY IF EXISTS "Users can insert own prayers" ON prayers;
CREATE POLICY "Users can insert own prayers"
  ON prayers FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Users can update own prayers (for activation/deactivation)
DROP POLICY IF EXISTS "Users can update own prayers" ON prayers;
CREATE POLICY "Users can update own prayers"
  ON prayers FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- 4. RPC: Get public prayers for Akashic Records feed
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
             pr.username, pr.faith
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

-- 5. RPC: Get sinners (users currently in purgatory)
-- Fixed: Moved WHERE/ORDER BY into subquery to avoid GROUP BY conflict with LATERAL join
CREATE OR REPLACE FUNCTION get_sinners()
RETURNS JSONB AS $$
DECLARE
  v_result JSONB;
BEGIN
  SELECT jsonb_agg(jsonb_build_object(
    'id', p.id,
    'username', p.username,
    'faith', p.faith,
    'ban_until', p.ban_until,
    'rejection_reason', pr.rejection_reason,
    'rejected_content', pr.content
  ))
  INTO v_result
  FROM (
    SELECT p.id, p.username, p.faith, p.ban_until
    FROM profiles p
    WHERE p.ban_until IS NOT NULL
      AND p.ban_until > now()
    ORDER BY p.ban_until ASC
  ) p
  LEFT JOIN LATERAL (
    SELECT content, rejection_reason
    FROM prayers
    WHERE prayers.user_id = p.id
      AND prayers.is_rejected = true
    ORDER BY created_at DESC
    LIMIT 1
  ) pr ON true;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. RPC: Start altruistic prayer (praying for someone else's prayer)
CREATE OR REPLACE FUNCTION start_altruistic_prayer(
  p_target_prayer_id UUID,
  p_response_content TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_existing RECORD;
  v_new_id UUID;
  v_target RECORD;
BEGIN
  -- Get the target prayer's response_content if not provided
  IF p_response_content IS NULL THEN
    SELECT response_content, content INTO v_target
    FROM prayers WHERE id = p_target_prayer_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'Target prayer not found'; END IF;

    -- Use the monk's response for cycle time calculation
    p_response_content := COALESCE(v_target.response_content, v_target.content);
  END IF;

  -- Deactivate any currently active prayer for this user (own or altruistic)
  UPDATE prayers SET is_praying = false, activated_at = NULL
  WHERE user_id = v_user_id AND is_praying = true;

  -- Check if an existing altruistic prayer for this target exists
  SELECT id, prayer_count, karma_awarded INTO v_existing
  FROM prayers
  WHERE user_id = v_user_id
    AND source_prayer_id = p_target_prayer_id
    AND prayer_type = 'altruistic'
    AND is_archived = false
  LIMIT 1;

  IF FOUND THEN
    -- Reactivate existing record
    UPDATE prayers
    SET is_praying = true, activated_at = now(), last_counted_at = now()
    WHERE id = v_existing.id
    RETURNING id INTO v_new_id;
  ELSE
    -- Create new altruistic prayer
    INSERT INTO prayers (user_id, content, response_content, prayer_type, source_prayer_id, is_praying, activated_at, last_counted_at, status)
    VALUES (
      v_user_id,
      'Altruistic prayer for another',
      p_response_content,
      'altruistic',
      p_target_prayer_id,
      true, now(), now(), 'completed'
    )
    RETURNING id INTO v_new_id;
  END IF;

  RETURN jsonb_build_object(
    'id', v_new_id,
    'type', 'altruistic',
    'target_prayer_id', p_target_prayer_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7. RPC: Start intercessory prayer (praying for a sinner)
CREATE OR REPLACE FUNCTION start_intercessory_prayer(
  p_target_sinner_id UUID,
  p_response_content TEXT
)
RETURNS JSONB AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_existing RECORD;
  v_new_id UUID;
BEGIN
  -- Deactivate any currently active prayer for this user
  UPDATE prayers SET is_praying = false, activated_at = NULL
  WHERE user_id = v_user_id AND is_praying = true;

  -- Check if an existing intercessory prayer for this sinner exists
  SELECT id, prayer_count, karma_awarded INTO v_existing
  FROM prayers
  WHERE user_id = v_user_id
    AND source_sinner_id = p_target_sinner_id
    AND prayer_type = 'intercessory'
    AND is_archived = false
  LIMIT 1;

  IF FOUND THEN
    -- Reactivate existing record
    UPDATE prayers
    SET is_praying = true, activated_at = now(), last_counted_at = now(),
        response_content = p_response_content
    WHERE id = v_existing.id
    RETURNING id INTO v_new_id;
  ELSE
    -- Create new intercessory prayer
    INSERT INTO prayers (user_id, content, response_content, prayer_type, source_sinner_id, is_praying, activated_at, last_counted_at, status)
    VALUES (
      v_user_id,
      'Intercessory prayer for a sinner',
      p_response_content,
      'intercessory',
      p_target_sinner_id,
      true, now(), now(), 'completed'
    )
    RETURNING id INTO v_new_id;
  END IF;

  RETURN jsonb_build_object(
    'id', v_new_id,
    'type', 'intercessory',
    'target_sinner_id', p_target_sinner_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 8. Modify sync_prayer_count to include karma milestone logic
CREATE OR REPLACE FUNCTION sync_prayer_count(p_prayer_id UUID, p_elapsed_counts INT)
RETURNS JSONB AS $$
DECLARE
  v_prayer RECORD;
  v_new_prayer_count INT;
  v_milestones INT;
  v_karma_change INT := 0;
BEGIN
  SELECT user_id, is_praying, prayer_type INTO v_prayer
  FROM prayers WHERE id = p_prayer_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'Prayer not found'; END IF;
  IF v_prayer.user_id != auth.uid() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF NOT v_prayer.is_praying THEN RAISE EXCEPTION 'Prayer is not active'; END IF;

  -- Update prayer count
  UPDATE prayers
  SET prayer_count = prayer_count + p_elapsed_counts,
      last_counted_at = now()
  WHERE id = p_prayer_id
  RETURNING prayer_count, last_counted_at, activated_at, karma_awarded INTO v_prayer;

  v_new_prayer_count := v_prayer.prayer_count;

  -- Check karma milestones (every 100 prays)
  v_milestones := floor(v_new_prayer_count / 100);

  IF v_milestones > v_prayer.karma_awarded THEN
    -- Determine karma rate based on prayer type
    IF v_prayer.prayer_type = 'altruistic' THEN
      v_karma_change := (v_milestones - v_prayer.karma_awarded) * 2;
    ELSE
      v_karma_change := (v_milestones - v_prayer.karma_awarded) * 1;
    END IF;

    -- Award karma to the praying user
    PERFORM update_karma(v_prayer.user_id, v_karma_change);

    -- Update karma_awarded tracker
    UPDATE prayers SET karma_awarded = v_milestones WHERE id = p_prayer_id;
  END IF;

  RETURN jsonb_build_object(
    'prayer_count', v_new_prayer_count,
    'last_counted_at', v_prayer.last_counted_at,
    'activated_at', v_prayer.activated_at,
    'karma_change', v_karma_change
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 8b. Modify deactivate_prayer to include karma milestone logic
-- This ensures final sync also awards karma if a milestone is crossed
CREATE OR REPLACE FUNCTION deactivate_prayer(
  p_prayer_id UUID,
  p_elapsed_counts INT
)
RETURNS JSONB AS $$
DECLARE
  v_user_id UUID;
  v_prayer RECORD;
  v_milestones INT;
  v_karma_change INT := 0;
BEGIN
  SELECT user_id INTO v_user_id
  FROM prayers WHERE id = p_prayer_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Prayer not found';
  END IF;

  IF v_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  -- Final count sync + deactivate
  UPDATE prayers
  SET prayer_count = prayer_count + p_elapsed_counts,
      last_counted_at = now(),
      is_praying = false,
      activated_at = NULL
  WHERE id = p_prayer_id
  RETURNING id, prayer_count, is_praying, activated_at, prayer_type, karma_awarded, user_id
  INTO v_prayer;

  -- Check karma milestones (every 100 prays)
  v_milestones := floor(v_prayer.prayer_count / 100);

  IF v_milestones > v_prayer.karma_awarded THEN
    -- Determine karma rate based on prayer type
    IF v_prayer.prayer_type = 'altruistic' THEN
      v_karma_change := (v_milestones - v_prayer.karma_awarded) * 2;
    ELSE
      v_karma_change := (v_milestones - v_prayer.karma_awarded) * 1;
    END IF;

    -- Award karma to the praying user
    PERFORM update_karma(v_prayer.user_id, v_karma_change);

    -- Update karma_awarded tracker
    UPDATE prayers SET karma_awarded = v_milestones WHERE id = p_prayer_id;
  END IF;

  RETURN jsonb_build_object(
    'id', v_prayer.id,
    'prayer_count', v_prayer.prayer_count,
    'is_praying', v_prayer.is_praying,
    'activated_at', v_prayer.activated_at,
    'karma_change', v_karma_change
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 9. Permissions
GRANT EXECUTE ON FUNCTION get_public_prayers(INT, INT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_sinners() TO authenticated;
GRANT EXECUTE ON FUNCTION start_altruistic_prayer(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION start_intercessory_prayer(UUID, TEXT) TO authenticated;