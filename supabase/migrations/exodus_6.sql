-- ============================================================
-- Exodus 6: Social Messaging (Shouts & Town Crier)
-- ============================================================
-- Adds: shouts, shout_replies, shout_blessings tables
-- Adds: submit_shout, submit_shout_reply, get_shouts,
--        get_shout_replies, grant_shout_blessing, get_shout_blessings RPCs
-- Adds: game_config entries for shout pricing
-- ============================================================

BEGIN;

-- ============================================================
-- TABLES
-- ============================================================

-- Shouts: player messages filtered through the Town Crier
CREATE TABLE IF NOT EXISTS shouts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id),
  content TEXT NOT NULL,
  crier_content TEXT,
  context TEXT NOT NULL CHECK (context IN ('global', 'synod')),
  synod_id UUID REFERENCES synods(id),
  sect_type TEXT CHECK (sect_type IN ('gilded_path', 'holy_way', 'final_watch', 'black_tribunal')),
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'posted', 'failed')),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Shout replies: threaded responses to shouts
CREATE TABLE IF NOT EXISTS shout_replies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shout_id UUID NOT NULL REFERENCES shouts(id),
  user_id UUID NOT NULL REFERENCES profiles(id),
  content TEXT NOT NULL,
  crier_content TEXT,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'posted', 'failed')),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Shout blessings: karma gifts placed on shouts or replies
CREATE TABLE IF NOT EXISTS shout_blessings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shout_id UUID NOT NULL REFERENCES shouts(id),
  reply_id UUID REFERENCES shout_replies(id),
  blessing_type_id TEXT NOT NULL REFERENCES blessing_types(id),
  giver_id UUID NOT NULL REFERENCES profiles(id),
  receiver_id UUID NOT NULL REFERENCES profiles(id),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ============================================================
-- INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_shouts_user_id ON shouts(user_id);
CREATE INDEX IF NOT EXISTS idx_shouts_context ON shouts(context);
CREATE INDEX IF NOT EXISTS idx_shouts_synod_id ON shouts(synod_id);
CREATE INDEX IF NOT EXISTS idx_shouts_sect_type ON shouts(sect_type);
CREATE INDEX IF NOT EXISTS idx_shouts_created_at ON shouts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_shouts_status ON shouts(status);

CREATE INDEX IF NOT EXISTS idx_shout_replies_shout_id ON shout_replies(shout_id);
CREATE INDEX IF NOT EXISTS idx_shout_replies_user_id ON shout_replies(user_id);
CREATE INDEX IF NOT EXISTS idx_shout_replies_created_at ON shout_replies(created_at);

CREATE INDEX IF NOT EXISTS idx_shout_blessings_shout_id ON shout_blessings(shout_id);
CREATE INDEX IF NOT EXISTS idx_shout_blessings_giver_id ON shout_blessings(giver_id);

-- Enforce uniqueness with COALESCE to handle null reply_ids
CREATE UNIQUE INDEX IF NOT EXISTS idx_shout_blessings_unique 
  ON shout_blessings(shout_id, COALESCE(reply_id, '00000000-0000-0000-0000-000000000000'::uuid), blessing_type_id, giver_id);

-- ============================================================
-- RLS POLICIES
-- ============================================================

-- shouts: public read, authenticated insert, no update/delete (permanent record)
ALTER TABLE shouts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "shouts_select_public"
  ON shouts FOR SELECT
  USING (true);

CREATE POLICY "shouts_insert_own"
  ON shouts FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- shout_replies: public read, authenticated insert
ALTER TABLE shout_replies ENABLE ROW LEVEL SECURITY;

CREATE POLICY "shout_replies_select_public"
  ON shout_replies FOR SELECT
  USING (true);

CREATE POLICY "shout_replies_insert_own"
  ON shout_replies FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- shout_blessings: public read, authenticated insert
ALTER TABLE shout_blessings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "shout_blessings_select_public"
  ON shout_blessings FOR SELECT
  USING (true);

CREATE POLICY "shout_blessings_insert_own"
  ON shout_blessings FOR INSERT
  WITH CHECK (auth.uid() = giver_id);

-- ============================================================
-- GAME CONFIG ENTRIES
-- ============================================================

INSERT INTO game_config (key, value, description, category)
VALUES
  ('shout.global_cost', 100, 'Gold cost to post a global shout', 'social'),
  ('shout.reply_cost', 50, 'Gold cost to reply to a shout', 'social'),
  ('shout.synod_leader_cost', 50, 'Gold cost for synod leader/officer to post (billed to vault)', 'social'),
  ('shout.synod_member_cost', 100, 'Gold cost for synod member to post (personal gold)', 'social')
ON CONFLICT (key) DO UPDATE SET
  value = EXCLUDED.value,
  description = EXCLUDED.description,
  category = EXCLUDED.category,
  updated_at = now();

-- ============================================================
-- RPC: submit_shout
-- ============================================================

CREATE OR REPLACE FUNCTION submit_shout(
  p_content TEXT,
  p_context TEXT DEFAULT 'global'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id UUID;
  v_synod_id UUID;
  v_synod_role TEXT;
  v_sect_type TEXT;
  v_global_cost INT;
  v_reply_cost INT;
  v_synod_leader_cost INT;
  v_synod_member_cost INT;
  v_cost INT;
  v_shout_id UUID;
  v_result JSONB;
BEGIN
  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  IF p_content IS NULL OR length(trim(p_content)) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Shout content cannot be empty');
  END IF;

  SELECT p.synod_id, p.synod_role, p.sect_type
  INTO v_synod_id, v_synod_role, v_sect_type
  FROM profiles p
  WHERE p.id = v_user_id;

  SELECT COALESCE((SELECT value::INT FROM game_config WHERE key = 'shout.global_cost'), 100) INTO v_global_cost;
  SELECT COALESCE((SELECT value::INT FROM game_config WHERE key = 'shout.reply_cost'), 50) INTO v_reply_cost;
  SELECT COALESCE((SELECT value::INT FROM game_config WHERE key = 'shout.synod_leader_cost'), 50) INTO v_synod_leader_cost;
  SELECT COALESCE((SELECT value::INT FROM game_config WHERE key = 'shout.synod_member_cost'), 100) INTO v_synod_member_cost;

  IF p_context = 'synod' THEN
    IF v_synod_id IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'You must be in a synod to post to the forum');
    END IF;

    IF v_synod_role IN ('leader', 'officer') THEN
      v_cost := v_synod_leader_cost;
      IF (SELECT vault_gold FROM synods WHERE id = v_synod_id) < v_cost THEN
        RETURN jsonb_build_object('success', false, 'error', 'Synod vault has insufficient gold');
      END IF;
      UPDATE synods SET vault_gold = vault_gold - v_cost WHERE id = v_synod_id;
    ELSE
      v_cost := v_synod_member_cost;
      IF (SELECT gold FROM profiles WHERE id = v_user_id) < v_cost THEN
        RETURN jsonb_build_object('success', false, 'error', 'Insufficient gold');
      END IF;
      UPDATE profiles SET gold = gold - v_cost WHERE id = v_user_id;
    END IF;
  ELSE
    v_cost := v_global_cost;
    IF (SELECT gold FROM profiles WHERE id = v_user_id) < v_cost THEN
      RETURN jsonb_build_object('success', false, 'error', 'Insufficient gold');
    END IF;
    UPDATE profiles SET gold = gold - v_cost WHERE id = v_user_id;
  END IF;

  INSERT INTO shouts (user_id, content, context, synod_id, sect_type, status)
  VALUES (
    v_user_id,
    p_content,
    p_context,
    CASE WHEN p_context = 'synod' THEN v_synod_id ELSE NULL END,
    CASE WHEN p_context = 'global' THEN v_sect_type ELSE NULL END,
    'pending'
  )
  RETURNING id INTO v_shout_id;

  RETURN jsonb_build_object(
    'success', true,
    'shout_id', v_shout_id,
    'cost', v_cost,
    'context', p_context
  );
END;
$$;

-- ============================================================
-- RPC: submit_shout_reply
-- ============================================================

CREATE OR REPLACE FUNCTION submit_shout_reply(
  p_shout_id UUID,
  p_content TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id UUID;
  v_reply_cost INT;
  v_reply_id UUID;
  v_shout_exists BOOLEAN;
BEGIN
  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  SELECT EXISTS(SELECT 1 FROM shouts WHERE id = p_shout_id) INTO v_shout_exists;
  IF NOT v_shout_exists THEN
    RETURN jsonb_build_object('success', false, 'error', 'Shout not found');
  END IF;

  IF p_content IS NULL OR length(trim(p_content)) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Reply content cannot be empty');
  END IF;

  SELECT COALESCE((SELECT value::INT FROM game_config WHERE key = 'shout.reply_cost'), 50) INTO v_reply_cost;

  IF (SELECT gold FROM profiles WHERE id = v_user_id) < v_reply_cost THEN
    RETURN jsonb_build_object('success', false, 'error', 'Insufficient gold');
  END IF;

  UPDATE profiles SET gold = gold - v_reply_cost WHERE id = v_user_id;

  INSERT INTO shout_replies (shout_id, user_id, content, status)
  VALUES (p_shout_id, v_user_id, p_content, 'pending')
  RETURNING id INTO v_reply_id;

  RETURN jsonb_build_object(
    'success', true,
    'reply_id', v_reply_id,
    'shout_id', p_shout_id,
    'cost', v_reply_cost
  );
END;
$$;

-- ============================================================
-- RPC: get_shouts
-- ============================================================

CREATE OR REPLACE FUNCTION get_shouts(
  p_page INT DEFAULT 1,
  p_page_size INT DEFAULT 20,
  p_filter TEXT DEFAULT 'global'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id UUID;
  v_sect_type TEXT;
  v_synod_id UUID;
  v_offset INT;
  v_total INT;
  v_shouts JSONB;
BEGIN
  v_user_id := auth.uid();
  v_offset := (p_page - 1) * p_page_size;

  SELECT p.sect_type, p.synod_id INTO v_sect_type, v_synod_id
  FROM profiles p WHERE p.id = v_user_id;

  IF p_filter = 'sect' THEN
    SELECT COUNT(*) INTO v_total
    FROM shouts s
    WHERE s.status = 'posted'
      AND s.context = 'global'
      AND s.sect_type = v_sect_type;
  ELSIF p_filter = 'synod' THEN
    SELECT COUNT(*) INTO v_total
    FROM shouts s
    WHERE s.status = 'posted'
      AND s.context = 'synod'
      AND s.synod_id = v_synod_id;
  ELSE
    SELECT COUNT(*) INTO v_total
    FROM shouts s
    WHERE s.status = 'posted'
      AND s.context = 'global';
  END IF;

  IF p_filter = 'sect' THEN
    SELECT jsonb_agg(
      row_to_json(shout_data.*) ORDER BY shout_data.created_at DESC
    ) INTO v_shouts
    FROM (
      SELECT
        s.id,
        s.user_id,
        s.content,
        s.crier_content,
        s.context,
        s.synod_id,
        s.sect_type,
        s.status,
        s.created_at,
        p.username,
        p.sect_type AS author_sect_type,
        p.pfp_index,
        COALESCE(
          (SELECT jsonb_agg(
            jsonb_build_object(
              'blessing_type_id', sb.blessing_type_id,
              'emoji', bt.emoji,
              'name', bt.name,
              'count', sb.blessing_count
            )
          )
          FROM (
            SELECT blessing_type_id, COUNT(*) AS blessing_count
            FROM shout_blessings
            WHERE shout_id = s.id AND reply_id IS NULL
            GROUP BY blessing_type_id
          ) sb
          JOIN blessing_types bt ON bt.id = sb.blessing_type_id),
          '[]'::JSONB
        ) AS blessings,
        COALESCE(
          (SELECT COUNT(*) FROM shout_blessings WHERE shout_id = s.id AND reply_id IS NULL),
          0
        ) AS blessing_count,
        COALESCE(
          (SELECT COUNT(*) FROM shout_replies WHERE shout_id = s.id AND status = 'posted'),
          0
        ) AS reply_count
      FROM shouts s
      JOIN profiles p ON p.id = s.user_id
      WHERE s.status = 'posted'
        AND s.context = 'global'
        AND s.sect_type = v_sect_type
      ORDER BY s.created_at DESC
      LIMIT p_page_size OFFSET v_offset
    ) AS shout_data;
  ELSIF p_filter = 'synod' THEN
    SELECT jsonb_agg(
      row_to_json(shout_data.*) ORDER BY shout_data.created_at DESC
    ) INTO v_shouts
    FROM (
      SELECT
        s.id,
        s.user_id,
        s.content,
        s.crier_content,
        s.context,
        s.synod_id,
        s.sect_type,
        s.status,
        s.created_at,
        p.username,
        p.sect_type AS author_sect_type,
        p.pfp_index,
        COALESCE(
          (SELECT jsonb_agg(
            jsonb_build_object(
              'blessing_type_id', sb.blessing_type_id,
              'emoji', bt.emoji,
              'name', bt.name,
              'count', sb.blessing_count
            )
          )
          FROM (
            SELECT blessing_type_id, COUNT(*) AS blessing_count
            FROM shout_blessings
            WHERE shout_id = s.id AND reply_id IS NULL
            GROUP BY blessing_type_id
          ) sb
          JOIN blessing_types bt ON bt.id = sb.blessing_type_id),
          '[]'::JSONB
        ) AS blessings,
        COALESCE(
          (SELECT COUNT(*) FROM shout_blessings WHERE shout_id = s.id AND reply_id IS NULL),
          0
        ) AS blessing_count,
        COALESCE(
          (SELECT COUNT(*) FROM shout_replies WHERE shout_id = s.id AND status = 'posted'),
          0
        ) AS reply_count
      FROM shouts s
      JOIN profiles p ON p.id = s.user_id
      WHERE s.status = 'posted'
        AND s.context = 'synod'
        AND s.synod_id = v_synod_id
      ORDER BY s.created_at DESC
      LIMIT p_page_size OFFSET v_offset
    ) AS shout_data;
  ELSE
    SELECT jsonb_agg(
      row_to_json(shout_data.*) ORDER BY shout_data.created_at DESC
    ) INTO v_shouts
    FROM (
      SELECT
        s.id,
        s.user_id,
        s.content,
        s.crier_content,
        s.context,
        s.synod_id,
        s.sect_type,
        s.status,
        s.created_at,
        p.username,
        p.sect_type AS author_sect_type,
        p.pfp_index,
        COALESCE(
          (SELECT jsonb_agg(
            jsonb_build_object(
              'blessing_type_id', sb.blessing_type_id,
              'emoji', bt.emoji,
              'name', bt.name,
              'count', sb.blessing_count
            )
          )
          FROM (
            SELECT blessing_type_id, COUNT(*) AS blessing_count
            FROM shout_blessings
            WHERE shout_id = s.id AND reply_id IS NULL
            GROUP BY blessing_type_id
          ) sb
          JOIN blessing_types bt ON bt.id = sb.blessing_type_id),
          '[]'::JSONB
        ) AS blessings,
        COALESCE(
          (SELECT COUNT(*) FROM shout_blessings WHERE shout_id = s.id AND reply_id IS NULL),
          0
        ) AS blessing_count,
        COALESCE(
          (SELECT COUNT(*) FROM shout_replies WHERE shout_id = s.id AND status = 'posted'),
          0
        ) AS reply_count
      FROM shouts s
      JOIN profiles p ON p.id = s.user_id
      WHERE s.status = 'posted'
        AND s.context = 'global'
      ORDER BY s.created_at DESC
      LIMIT p_page_size OFFSET v_offset
    ) AS shout_data;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'shouts', COALESCE(v_shouts, '[]'::JSONB),
    'total', v_total,
    'page', p_page,
    'page_size', p_page_size,
    'has_more', (v_offset + p_page_size) < v_total
  );
END;
$$;

-- ============================================================
-- RPC: get_shout_replies
-- ============================================================

CREATE OR REPLACE FUNCTION get_shout_replies(
  p_shout_id UUID,
  p_page INT DEFAULT 1,
  p_page_size INT DEFAULT 50
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_offset INT;
  v_total INT;
  v_replies JSONB;
  v_shout JSONB;
BEGIN
  v_offset := (p_page - 1) * p_page_size;

  SELECT row_to_json(shout_data.*) INTO v_shout
  FROM (
    SELECT
      s.id,
      s.user_id,
      s.content,
      s.crier_content,
      s.context,
      s.synod_id,
      s.sect_type,
      s.status,
      s.created_at,
      p.username,
      p.sect_type AS author_sect_type,
      p.pfp_index,
      COALESCE(
        (SELECT jsonb_agg(
          jsonb_build_object(
            'blessing_type_id', sb.blessing_type_id,
            'emoji', bt.emoji,
            'name', bt.name,
            'count', sb.blessing_count
          )
        )
        FROM (
          SELECT blessing_type_id, COUNT(*) AS blessing_count
          FROM shout_blessings
          WHERE shout_id = s.id AND reply_id IS NULL
          GROUP BY blessing_type_id
        ) sb
        JOIN blessing_types bt ON bt.id = sb.blessing_type_id),
        '[]'::JSONB
      ) AS blessings,
      COALESCE(
        (SELECT COUNT(*) FROM shout_blessings WHERE shout_id = s.id AND reply_id IS NULL),
        0
      ) AS blessing_count
    FROM shouts s
    JOIN profiles p ON p.id = s.user_id
    WHERE s.id = p_shout_id
  ) AS shout_data;

  SELECT COUNT(*) INTO v_total
  FROM shout_replies
  WHERE shout_id = p_shout_id AND status = 'posted';

  SELECT jsonb_agg(
    row_to_json(reply_data.*) ORDER BY reply_data.created_at ASC
  ) INTO v_replies
  FROM (
    SELECT
      sr.id,
      sr.shout_id,
      sr.user_id,
      sr.content,
      sr.crier_content,
      sr.status,
      sr.created_at,
      p.username,
      p.sect_type AS author_sect_type,
      p.pfp_index,
      COALESCE(
        (SELECT jsonb_agg(
          jsonb_build_object(
            'blessing_type_id', sb.blessing_type_id,
            'emoji', bt.emoji,
            'name', bt.name,
            'count', sb.blessing_count
          )
        )
        FROM (
          SELECT blessing_type_id, COUNT(*) AS blessing_count
          FROM shout_blessings
          WHERE shout_id = sr.shout_id AND reply_id = sr.id
          GROUP BY blessing_type_id
        ) sb
        JOIN blessing_types bt ON bt.id = sb.blessing_type_id),
        '[]'::JSONB
      ) AS blessings,
      COALESCE(
        (SELECT COUNT(*) FROM shout_blessings WHERE shout_id = sr.shout_id AND reply_id = sr.id),
        0
      ) AS blessing_count
    FROM shout_replies sr
    JOIN profiles p ON p.id = sr.user_id
    WHERE sr.shout_id = p_shout_id AND sr.status = 'posted'
    ORDER BY sr.created_at ASC
    LIMIT p_page_size OFFSET v_offset
  ) AS reply_data;

  RETURN jsonb_build_object(
    'success', true,
    'shout', v_shout,
    'replies', COALESCE(v_replies, '[]'::JSONB),
    'total_replies', v_total,
    'page', p_page,
    'page_size', p_page_size,
    'has_more', (v_offset + p_page_size) < v_total
  );
END;
$$;

-- ============================================================
-- RPC: grant_shout_blessing
-- ============================================================

CREATE OR REPLACE FUNCTION grant_shout_blessing(
  p_shout_id UUID,
  p_blessing_type_id TEXT,
  p_reply_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_giver_id UUID;
  v_receiver_id UUID;
  v_blessing RECORD;
  v_giver_karma INT;
  v_shout_user_id UUID;
  v_shield_minutes INT;
  v_shield_until TIMESTAMPTZ;
  v_existing INT;
BEGIN
  v_giver_id := auth.uid();

  IF v_giver_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  SELECT * INTO v_blessing FROM blessing_types WHERE id = p_blessing_type_id AND is_active = true;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid or inactive blessing type');
  END IF;

  IF p_reply_id IS NOT NULL THEN
    SELECT user_id INTO v_receiver_id FROM shout_replies WHERE id = p_reply_id;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', 'Reply not found');
    END IF;
  ELSE
    SELECT user_id INTO v_receiver_id FROM shouts WHERE id = p_shout_id;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', 'Shout not found');
    END IF;
  END IF;

  IF v_giver_id = v_receiver_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Cannot bless your own shout');
  END IF;

  SELECT COUNT(*) INTO v_existing
  FROM shout_blessings
  WHERE shout_id = p_shout_id
    AND COALESCE(reply_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE(p_reply_id, '00000000-0000-0000-0000-000000000000'::uuid)
    AND blessing_type_id = p_blessing_type_id
    AND giver_id = v_giver_id;

  IF v_existing > 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'You have already given this blessing to this shout');
  END IF;

  SELECT karma INTO v_giver_karma FROM profiles WHERE id = v_giver_id;
  IF v_giver_karma < v_blessing.karma_cost THEN
    RETURN jsonb_build_object('success', false, 'error', 'Insufficient karma');
  END IF;

  UPDATE profiles SET karma = karma - v_blessing.karma_cost WHERE id = v_giver_id;

  IF v_blessing.karma_to_giver > 0 THEN
    UPDATE profiles SET karma = karma + v_blessing.karma_to_giver WHERE id = v_giver_id;
  END IF;

  IF v_blessing.karma_to_receiver > 0 THEN
    UPDATE profiles SET karma = karma + v_blessing.karma_to_receiver WHERE id = v_receiver_id;
  END IF;

  INSERT INTO shout_blessings (shout_id, reply_id, blessing_type_id, giver_id, receiver_id)
  VALUES (p_shout_id, p_reply_id, p_blessing_type_id, v_giver_id, v_receiver_id);

  IF v_blessing.shield_minutes > 0 THEN
    v_shield_minutes := v_blessing.shield_minutes;
    v_shield_until := now() + (v_shield_minutes || ' minutes')::INTERVAL;

    UPDATE profiles
    SET divine_shield_until = GREATEST(COALESCE(divine_shield_until, now()), v_shield_until)
    WHERE id = v_giver_id;

    UPDATE profiles
    SET divine_shield_until = GREATEST(COALESCE(divine_shield_until, now()), v_shield_until)
    WHERE id = v_receiver_id;

    INSERT INTO active_miracles (user_id, miracle_type, effect_data, expires_at)
    VALUES (v_giver_id, 'blessing_shield',
      jsonb_build_object('blessing_type', p_blessing_type_id, 'shield_minutes', v_shield_minutes),
      v_shield_until);

    INSERT INTO active_miracles (user_id, miracle_type, effect_data, expires_at)
    VALUES (v_receiver_id, 'blessing_shield',
      jsonb_build_object('blessing_type', p_blessing_type_id, 'shield_minutes', v_shield_minutes),
      v_shield_until);
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'blessing_type', p_blessing_type_id,
    'karma_cost', v_blessing.karma_cost,
    'karma_rebate', v_blessing.karma_to_giver,
    'receiver_id', v_receiver_id
  );
END;
$$;

-- ============================================================
-- RPC: get_shout_blessings
-- ============================================================

CREATE OR REPLACE FUNCTION get_shout_blessings(
  p_shout_ids UUID[]
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_result JSONB;
BEGIN
  SELECT jsonb_object_agg(shout_id, blessings)
  INTO v_result
  FROM (
    SELECT
      sb.shout_id,
      jsonb_agg(
        jsonb_build_object(
          'blessing_type_id', sb.blessing_type_id,
          'emoji', bt.emoji,
          'name', bt.name,
          'count', sb.blessing_count
        )
      ) AS blessings
    FROM (
      SELECT shout_id, blessing_type_id, COUNT(*) AS blessing_count
      FROM shout_blessings
      WHERE shout_id = ANY(p_shout_ids) AND reply_id IS NULL
      GROUP BY shout_id, blessing_type_id
    ) sb
    JOIN blessing_types bt ON bt.id = sb.blessing_type_id
    GROUP BY sb.shout_id
  ) sub;

  RETURN COALESCE(v_result, '{}'::JSONB);
END;
$$;

-- ============================================================
-- GRANTS
-- ============================================================

GRANT SELECT ON shouts TO authenticated, anon;
GRANT INSERT ON shouts TO authenticated;
GRANT SELECT ON shout_replies TO authenticated, anon;
GRANT INSERT ON shout_replies TO authenticated;
GRANT SELECT ON shout_blessings TO authenticated, anon;
GRANT INSERT ON shout_blessings TO authenticated;

GRANT EXECUTE ON FUNCTION submit_shout(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION submit_shout_reply(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_shouts(INT, INT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_shout_replies(UUID, INT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION grant_shout_blessing(UUID, TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_shout_blessings(UUID[]) TO authenticated;

COMMIT;