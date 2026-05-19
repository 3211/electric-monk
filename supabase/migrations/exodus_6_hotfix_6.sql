-- ============================================================
-- Exodus 6 Hotfix 6: Grant service_role privileges for Town Crier
-- ============================================================
-- The town-crier edge function uses SUPABASE_SERVICE_ROLE_KEY to
-- update shouts/shout_replies (crier_content, status) and profiles
-- (ban_until). The service_role bypasses RLS but still needs
-- explicit table-level GRANTs to SELECT/UPDATE these tables.
-- Error 42501: permission denied for table shouts
-- ============================================================

BEGIN;

-- Grant service_role access to shouts (read + update crier_content/status)
GRANT SELECT, UPDATE ON public.shouts TO service_role;

-- Grant service_role access to shout_replies (read + update crier_content/status)
GRANT SELECT, UPDATE ON public.shout_replies TO service_role;

-- Grant service_role access to profiles (already likely granted via genesis, but ensure)
GRANT SELECT, UPDATE ON public.profiles TO service_role;

-- Grant service_role execute on update_karma RPC (used for -1 karma on rejection)
GRANT EXECUTE ON FUNCTION public.update_karma(UUID, INT) TO service_role;

COMMIT;