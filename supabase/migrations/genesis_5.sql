-- =====================================================
-- ELECTRIC MONK — GENESIS 5: Permission Fix Patch
-- Date: 2026-05-17
--
-- Fixes 403 Forbidden errors on prayers, profiles, and
-- indulgences tables by adding missing GRANT statements
-- and RLS policies for the authenticated role.
--
-- Root Cause: genesis_4.sql defined RLS policies but
-- omitted the GRANT layer. PostgreSQL evaluates GRANT
-- permissions BEFORE RLS policies, so authenticated users
-- were blocked at the GRANT layer even though RLS was
-- correctly configured.
--
-- Run AFTER genesis_1 through genesis_4.
-- This script is idempotent and safe to re-run.
-- =====================================================

-- ============================================
-- PHASE 1: GRANT TABLE PERMISSIONS
-- ============================================

-- prayers: authenticated needs SELECT, INSERT, UPDATE
GRANT SELECT, INSERT, UPDATE ON TABLE prayers TO authenticated;
GRANT ALL ON TABLE prayers TO service_role;

-- profiles: authenticated needs SELECT, INSERT, UPDATE
-- (service_role already had ALL from genesis_4, but let's confirm)
GRANT SELECT, INSERT, UPDATE ON TABLE profiles TO authenticated;
GRANT ALL ON TABLE profiles TO service_role;

-- indulgences: authenticated needs SELECT, INSERT
-- (INSERT was only via RPC before, but direct access may be needed)
GRANT SELECT, INSERT ON TABLE indulgences TO authenticated;
GRANT ALL ON TABLE indulgences TO service_role;

-- ============================================
-- PHASE 2: MISSING RLS POLICIES
-- ============================================

-- profiles: users can insert their own row (needed for upsert on profile completion)
-- The trigger create_profile_on_signup creates a minimal row (id, email),
-- but the frontend does .upsert({id, username, faith}) which requires INSERT.
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can insert own profile" ON profiles;
CREATE POLICY "Users can insert own profile" ON profiles
  FOR INSERT WITH CHECK (auth.uid() = id);

-- profiles: users can update their own row
-- Frontend updates tokens_spent_today, last_prayer_date, ban_until, etc.
DROP POLICY IF EXISTS "Users can update own profile" ON profiles;
CREATE POLICY "Users can update own profile" ON profiles
  FOR UPDATE USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- indulgences: users can view their own indulgences
ALTER TABLE indulgences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own indulgences" ON indulgences;
CREATE POLICY "Users can view own indulgences" ON indulgences
  FOR SELECT USING (auth.uid() = user_id);

-- ============================================
-- END OF GENESIS 5
-- =====================================================