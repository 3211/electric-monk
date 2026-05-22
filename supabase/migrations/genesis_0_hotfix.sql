-- ======================================================================================
-- GENESIS 0 HOTFIX: GRANT PERMISSIONS + FIX get_available_sects
-- ======================================================================================
-- FIXES:
-- 1. "permission denied for table players" — Edge functions use supabase_admin (service_role)
--    which lacked explicit GRANTs on the tables.
-- 2. "column s.name must appear in GROUP BY clause" — ORDER BY was outside jsonb_agg.
-- 3. Missing EXECUTE grants on SECURITY DEFINER functions for authenticated/anon roles.
-- ======================================================================================

BEGIN;

-- ==========================================
-- 1. GRANT TABLE PERMISSIONS
-- ==========================================
-- supabase_admin is the role used by SUPABASE_SERVICE_ROLE_KEY (edge functions).
-- Without these, edge functions get "permission denied for table players/sects".

-- Grant to all roles that the service key might map to
GRANT ALL ON TABLE public.players TO supabase_admin;
GRANT ALL ON TABLE public.sects TO supabase_admin;
GRANT ALL ON TABLE public.players TO postgres;
GRANT ALL ON TABLE public.sects TO postgres;
GRANT ALL ON TABLE public.players TO authenticator;
GRANT ALL ON TABLE public.sects TO authenticator;

-- authenticated role needs access via RLS policies (already defined, but explicit grants help)
GRANT SELECT ON TABLE public.players TO authenticated;
GRANT SELECT ON TABLE public.sects TO authenticated;
GRANT INSERT ON TABLE public.players TO authenticated;
GRANT UPDATE ON TABLE public.players TO authenticated;

-- anon role needs SELECT on sects for unauthenticated reads (if ever needed)
GRANT SELECT ON TABLE public.sects TO anon;

-- ==========================================
-- 2. GRANT FUNCTION EXECUTE PERMISSIONS
-- ==========================================
-- SECURITY DEFINER functions require explicit EXECUTE grants for RPC callers.

GRANT EXECUTE ON FUNCTION public.update_player_username(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.choose_player_sect(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_player_onboarding() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_player_status() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_available_sects() TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_player_on_signup() TO postgres;

-- Also grant to anon for functions that might be called before full auth
GRANT EXECUTE ON FUNCTION public.get_available_sects() TO anon;
GRANT EXECUTE ON FUNCTION public.get_player_status() TO anon;

-- ==========================================
-- 3. FIX get_available_sects() FUNCTION
-- ==========================================
-- The ORDER BY was outside jsonb_agg, causing:
-- "column s.name must appear in the GROUP BY clause or be used in an aggregate function"
-- Fix: move ORDER BY inside the aggregate call.

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
                'emoji', s.emoji,
                'description', s.description,
                'principles', s.principles,
                'tone_description', s.tone_description
            )
            ORDER BY s.name
        )
        FROM public.sects s
    );
END;
$$;

COMMIT;