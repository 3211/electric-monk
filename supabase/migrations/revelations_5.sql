-- revelations_5.sql
-- Fix: Strip CIDR suffix from inet columns when returned via RPCs
-- The inet type stores IPs as e.g. 192.168.1.5/32 and json_build_object
-- preserves the netmask. Use host() to return bare IP strings.

BEGIN;

-- ==========================================
-- Fix get_player_status() — strip /32 from ip_address
-- ==========================================
CREATE OR REPLACE FUNCTION public.get_player_status()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_user_id UUID;
    v_result JSON;
BEGIN
    v_user_id := auth.uid();
    
    SELECT json_build_object(
        'id', p.id,
        'username', p.username,
        'ip_address', host(p.ip_address),  -- ← strip CIDR (e.g. /32)
        'sect_id', p.sect_id,
        'sect_name', s.name,
        'sect_emoji', s.emoji,
        'onboarding_complete', p.onboarding_complete
    ) INTO v_result
    FROM public.players p
    LEFT JOIN public.sects s ON p.sect_id = s.id
    WHERE p.id = v_user_id;
    
    RETURN COALESCE(v_result, json_build_object('error', 'Player not found'));
END;
$$;

-- ==========================================
-- Fix get_available_sects() — strip /32 from ip_address
-- ==========================================
CREATE OR REPLACE FUNCTION public.get_available_sects()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    RETURN (
        SELECT jsonb_agg(
            jsonb_build_object(
                'id', s.id,
                'name', s.name,
                'ip_address', host(s.ip_address),  -- ← strip CIDR
                'emoji', s.emoji,
                'description', s.description,
                'principles', s.principles,
                'tone_description', s.tone_description
            )
            ORDER BY s.display_order ASC
        )
        FROM public.sects s
    );
END;
$$;

-- Re-grant permissions (must re-grant after CREATE OR REPLACE)
GRANT EXECUTE ON FUNCTION public.get_player_status() TO service_role, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.get_available_sects() TO service_role, authenticated, anon;

COMMIT;