BEGIN;
-- IMPORTANT... *THIS* IS HOW SERVICE ROLES WORK ON SUPABASE!
-- Grant table permissions to the actual service_role used by Edge Functions
GRANT ALL ON TABLE public.players TO service_role;
GRANT ALL ON TABLE public.sects TO service_role;

-- Ensure the service_role can also execute your helper functions if your Edge Functions ever need to call them
GRANT EXECUTE ON FUNCTION public.update_player_username(TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.choose_player_sect(TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.complete_player_onboarding() TO service_role;
GRANT EXECUTE ON FUNCTION public.get_player_status() TO service_role;
GRANT EXECUTE ON FUNCTION public.get_available_sects() TO service_role;

COMMIT;