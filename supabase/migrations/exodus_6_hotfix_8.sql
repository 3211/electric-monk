-- ============================================================
-- Exodus 6 Hotfix 8: Fix search_path for shout RPCs
-- ============================================================
-- The hotfix 7 migration set `SET search_path = ''` on
-- submit_shout, get_shouts, and get_shout_replies.
-- An empty search_path prevents the SECURITY DEFINER functions
-- from resolving unqualified table references (profiles, shouts,
-- etc.) which live in the `public` schema.
-- This changes search_path to `public` — the standard Supabase
-- pattern that prevents search-path injection while still
-- allowing table resolution.
-- ============================================================

BEGIN;

-- ============================================================
-- RPC: submit_shout (fix search_path)
-- ============================================================

CREATE OR REPLACE FUNCTION submit_shout(
  p_content TEXT,
  p_context TEXT DEFAULT 'global',
  p_is_sect_only BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

  INSERT INTO shouts (user_id, content, context, synod_id, sect_type, is_sect_only, status)
  VALUES (
    v_user_id,
    p_content,
    p_context,
    CASE WHEN p_context = 'synod' THEN v_synod_id ELSE NULL END,
    CASE WHEN p_context = 'global' THEN v_sect_type ELSE NULL END,
    CASE WHEN p_context = 'global' THEN p_is_sect_only ELSE false END,
    'pending'
  )
  RETURNING id INTO v_shout_id;

  RETURN jsonb_build_object(
    'success', true,
    'shout_id', v_shout_id,
    'cost', v_cost,
    'context', p_context,
    'is_sect_only', CASE WHEN p_context = 'global' THEN p_is_sect_only ELSE false END
  );
END;
$$;

-- ============================================================
-- RPC: get_shouts (fix search_path)
-- ============================================================

CREATE OR REPLACE FUNCTION get_shouts(
  p_page INT DEFAULT 1,
  p_page_size INT DEFAULT 20,
  p_filter TEXT DEFAULT 'global'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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
    -- Global: visible if (not sect-only) OR (sect-only and same sect as viewer)
    SELECT COUNT(*) INTO v_total
    FROM shouts s
    WHERE s.status = 'posted'
      AND s.context = 'global'
      AND (s.is_sect_only = false OR s.sect_type = v_sect_type);
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
        s.is_sect_only,
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
        s.is_sect_only,
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
    -- Global: visible if (not sect-only) OR (sect-only and same sect as viewer)
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
        s.is_sect_only,
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
        AND (s.is_sect_only = false OR s.sect_type = v_sect_type)
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
-- RPC: get_shout_replies (fix search_path)
-- ============================================================

CREATE OR REPLACE FUNCTION get_shout_replies(
  p_shout_id UUID,
  p_page INT DEFAULT 1,
  p_page_size INT DEFAULT 50
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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
      s.is_sect_only,
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
-- GRANTS (re-grant for updated function definitions)
-- ============================================================

GRANT EXECUTE ON FUNCTION submit_shout(TEXT, TEXT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION get_shouts(INT, INT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_shout_replies(UUID, INT, INT) TO authenticated;

COMMIT;