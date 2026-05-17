-- =====================================================
-- HOTFIX: Missing GRANT SELECT on Rapture Update tables
-- Date: 2026-05-17
--
-- The rapture-update.sql migration created RLS policies
-- but forgot to GRANT SELECT to authenticated/anon roles
-- on 4 new tables. This caused 403 errors when clients
-- tried to query these tables directly.
--
-- Run this in Supabase SQL Editor to fix the live DB.
-- =====================================================

-- active_miracles: queried by useIndulgences.js (Reliquary page)
-- RLS policy: "Miracles are publicly readable" (USING true)
GRANT SELECT ON TABLE active_miracles TO authenticated;
GRANT SELECT ON TABLE active_miracles TO anon;
GRANT ALL ON TABLE active_miracles TO service_role;

-- player_research: queried via get_research_tree RPC
-- RLS policy: "Players can read own research" (USING auth.uid() = user_id)
GRANT SELECT ON TABLE player_research TO authenticated;
GRANT ALL ON TABLE player_research TO service_role;

-- synods: queried by useSynod.js (Synod Hall page)
-- RLS policy: "Synods are publicly readable" (USING true)
GRANT SELECT ON TABLE synods TO authenticated;
GRANT SELECT ON TABLE synods TO anon;
GRANT ALL ON TABLE synods TO service_role;

-- build_queue: queried by future build queue composable
-- RLS policy: "Players can read own build queue" (USING auth.uid() = user_id)
GRANT SELECT ON TABLE build_queue TO authenticated;
GRANT ALL ON TABLE build_queue TO service_role;