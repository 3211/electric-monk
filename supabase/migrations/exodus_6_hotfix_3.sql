BEGIN;

CREATE OR REPLACE FUNCTION public.get_shouts(
  p_page INT DEFAULT 1,
  p_page_size INT DEFAULT 20,
  p_filter TEXT DEFAULT 'global'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog  -- Safe path constraint that includes public tables
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
  FROM public.profiles p WHERE p.id = v_user_id;

  IF p_filter = 'sect' THEN
    SELECT COUNT(*) INTO v_total
    FROM public.shouts s
    WHERE s.status = 'posted'
      AND s.context = 'global'
      AND s.sect_type = v_sect_type;
  ELSIF p_filter = 'synod' THEN
    SELECT COUNT(*) INTO v_total
    FROM public.shouts s
    WHERE s.status = 'posted'
      AND s.context = 'synod'
      AND s.synod_id = v_synod_id;
  ELSE
    SELECT COUNT(*) INTO v_total
    FROM public.shouts s
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
            FROM public.shout_blessings
            WHERE shout_id = s.id AND reply_id IS NULL
            GROUP BY blessing_type_id
          ) sb
          JOIN public.blessing_types bt ON bt.id = sb.blessing_type_id),
          '[]'::JSONB
        ) AS blessings,
        COALESCE(
          (SELECT COUNT(*) FROM public.shout_blessings WHERE shout_id = s.id AND reply_id IS NULL),
          0
        ) AS blessing_count,
        COALESCE(
          (SELECT COUNT(*) FROM public.shout_replies WHERE shout_id = s.id AND status = 'posted'),
          0
        ) AS reply_count
      FROM public.shouts s
      JOIN public.profiles p ON p.id = s.user_id
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
            FROM public.shout_blessings
            WHERE shout_id = s.id AND reply_id IS NULL
            GROUP BY blessing_type_id
          ) sb
          JOIN public.blessing_types bt ON bt.id = sb.blessing_type_id),
          '[]'::JSONB
        ) AS blessings,
        COALESCE(
          (SELECT COUNT(*) FROM public.shout_blessings WHERE shout_id = s.id AND reply_id IS NULL),
          0
        ) AS blessing_count,
        COALESCE(
          (SELECT COUNT(*) FROM public.shout_replies WHERE shout_id = s.id AND status = 'posted'),
          0
        ) AS reply_count
      FROM public.shouts s
      JOIN public.profiles p ON p.id = s.user_id
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
            FROM public.shout_blessings
            WHERE shout_id = s.id AND reply_id IS NULL
            GROUP BY blessing_type_id
          ) sb
          JOIN public.blessing_types bt ON bt.id = sb.blessing_type_id),
          '[]'::JSONB
        ) AS blessings,
        COALESCE(
          (SELECT COUNT(*) FROM public.shout_blessings WHERE shout_id = s.id AND reply_id IS NULL),
          0
        ) AS blessing_count,
        COALESCE(
          (SELECT COUNT(*) FROM public.shout_replies WHERE shout_id = s.id AND status = 'posted'),
          0
        ) AS reply_count
      FROM public.shouts s
      JOIN public.profiles p ON p.id = s.user_id
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

COMMIT;