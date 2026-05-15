# Fix: service_role Permissions for Edge Function

## Problem

The `process-prayer` Edge Function authenticates as `service_role` (using `SUPABASE_SERVICE_ROLE_KEY`), but this role has **no table-level GRANTs** on `prayers`, `profiles`, or `indulgences`. In Supabase, `service_role` bypasses RLS but still requires explicit `GRANT` permissions to perform SELECT/INSERT/UPDATE/DELETE on tables and EXECUTE on functions.

**Error:** `permission denied for table prayers` (SQL code 42501)

## Edge Function Operations That Fail

| Line | Operation | Table/Function | Required Permission |
|------|-----------|---------------|-------------------|
| 263 | `UPDATE prayers SET is_praying=false WHERE user_id=? AND is_praying=true` | `prayers` | UPDATE |
| 285 | `UPDATE prayers SET response_content=?, status='completed', ... WHERE id=?` | `prayers` | UPDATE |
| 300 | `supabase.rpc('update_karma', ...)` | `update_karma(UUID, INT)` | EXECUTE |
| 323 | `UPDATE profiles SET ban_until=? WHERE id=?` | `profiles` | UPDATE |

## Step 1: Run This SQL in Supabase SQL Editor (IMMEDIATE FIX)

```sql
-- =====================================================
-- GRANT service_role PERMISSIONS
-- Required for Edge Functions (process-prayer, etc.)
-- =====================================================
-- Run this in: Supabase Dashboard > SQL Editor

-- 1. Grant table access to service_role
GRANT ALL ON TABLE public.prayers TO service_role;
GRANT ALL ON TABLE public.profiles TO service_role;
GRANT ALL ON TABLE public.indulgences TO service_role;

-- 2. Grant sequence access (for gen_random_uuid defaults)
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;

-- 3. Grant function execution to service_role
-- NOTE: Only grant on functions that EXIST on the live database.
-- reset_daily_prayer_count(UUID) does NOT exist yet — do NOT grant on it.
GRANT EXECUTE ON FUNCTION public.create_profile_on_signup() TO service_role;
GRANT EXECUTE ON FUNCTION public.submit_prayer(TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.activate_prayer(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.sync_prayer_count(UUID, INT) TO service_role;
GRANT EXECUTE ON FUNCTION public.deactivate_prayer(UUID, INT) TO service_role;
GRANT EXECUTE ON FUNCTION public.reduce_ban_time(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.refill_tokens(INT) TO service_role;
GRANT EXECUTE ON FUNCTION public.update_karma(UUID, INT) TO service_role;
```

## Step 2: Update `src/lib/supabase-schema.sql`

### 2a. Add FORCE RLS + missing profiles policies (lines 377-389)

Replace:
```sql
-- Enable RLS on all tables
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE prayers ENABLE ROW LEVEL SECURITY;
ALTER TABLE indulgences ENABLE ROW LEVEL SECURITY;

-- Profiles Policies
CREATE POLICY "Users can view own profile"
  ON profiles FOR SELECT
  USING (auth.uid() = id);

CREATE POLICY "Users can update own profile"
  ON profiles FOR UPDATE
  USING (auth.uid() = id);
```

With:
```sql
-- Enable RLS on all tables (FORCE ensures service_role RLS bypass is still tracked)
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles FORCE ROW LEVEL SECURITY;
ALTER TABLE prayers ENABLE ROW LEVEL SECURITY;
ALTER TABLE indulgences ENABLE ROW LEVEL SECURITY;

-- Profiles Policies
CREATE POLICY "Users can view own profile"
  ON profiles FOR SELECT
  USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile"
  ON profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update own profile"
  ON profiles FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);
```

### 2b. Add service_role GRANTs (after line 439, end of file)

Replace the entire Section 5 (lines 413-440):
```sql
-- ============================================
-- 5. PERMISSIONS
-- ============================================

-- Ensure the public schema is accessible
GRANT USAGE ON SCHEMA public TO anon, authenticated;

-- Grant permissions on tables
GRANT ALL ON TABLE prayers TO authenticated;
GRANT ALL ON TABLE profiles TO authenticated;
GRANT ALL ON TABLE indulgences TO authenticated;

-- Grant permissions on sequences (for IDs)
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- Grant permissions for anonymous users (if needed for login/signup checks)
GRANT SELECT ON TABLE profiles TO anon;

-- Grant execute permissions on RPC functions
GRANT EXECUTE ON FUNCTION submit_prayer TO authenticated;
GRANT EXECUTE ON FUNCTION refill_tokens TO authenticated;
GRANT EXECUTE ON FUNCTION reset_daily_prayer_count TO authenticated;
GRANT EXECUTE ON FUNCTION reduce_ban_time TO authenticated;
GRANT EXECUTE ON FUNCTION sync_prayer_count TO authenticated;
GRANT EXECUTE ON FUNCTION deactivate_prayer TO authenticated;
GRANT EXECUTE ON FUNCTION activate_prayer TO authenticated;
GRANT EXECUTE ON FUNCTION update_karma TO authenticated;
```

With:
```sql
-- ============================================
-- 5. PERMISSIONS
-- ============================================

-- Ensure the public schema is accessible
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- Grant permissions on tables — authenticated (frontend users)
GRANT ALL ON TABLE prayers TO authenticated;
GRANT ALL ON TABLE profiles TO authenticated;
GRANT ALL ON TABLE indulgences TO authenticated;

-- Grant permissions on tables — service_role (Edge Functions)
GRANT ALL ON TABLE prayers TO service_role;
GRANT ALL ON TABLE profiles TO service_role;
GRANT ALL ON TABLE indulgences TO service_role;

-- Grant permissions on sequences (for IDs)
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;

-- Grant permissions for anonymous users (for login/signup checks)
GRANT SELECT ON TABLE profiles TO anon;

-- Grant execute permissions on RPC functions — authenticated (frontend users)
GRANT EXECUTE ON FUNCTION submit_prayer(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION refill_tokens(INT) TO authenticated;
GRANT EXECUTE ON FUNCTION reset_daily_prayer_count(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION reduce_ban_time(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION sync_prayer_count(UUID, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION deactivate_prayer(UUID, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION activate_prayer(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION update_karma(UUID, INT) TO authenticated;

-- Grant execute permissions on RPC functions — service_role (Edge Functions)
GRANT EXECUTE ON FUNCTION create_profile_on_signup() TO service_role;
GRANT EXECUTE ON FUNCTION submit_prayer(TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION activate_prayer(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION sync_prayer_count(UUID, INT) TO service_role;
GRANT EXECUTE ON FUNCTION deactivate_prayer(UUID, INT) TO service_role;
GRANT EXECUTE ON FUNCTION reduce_ban_time(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION refill_tokens(INT) TO service_role;
GRANT EXECUTE ON FUNCTION update_karma(UUID, INT) TO service_role;
GRANT EXECUTE ON FUNCTION reset_daily_prayer_count(UUID) TO service_role;
```

## Step 3: Update `docs/schema.md`

### 3a. Add FORCE RLS + missing profiles policies (around line 314-320)

Replace:
```sql
-- Enable RLS
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE prayers ENABLE ROW LEVEL SECURITY;
ALTER TABLE indulgences ENABLE ROW LEVEL SECURITY;

-- Profile policies
CREATE POLICY "Users can view own profile" ON profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update own profile" ON profiles FOR UPDATE USING (auth.uid() = id);
```

With:
```sql
-- Enable RLS (FORCE ensures service_role RLS bypass is still tracked)
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles FORCE ROW LEVEL SECURITY;
ALTER TABLE prayers ENABLE ROW LEVEL SECURITY;
ALTER TABLE indulgences ENABLE ROW LEVEL SECURITY;

-- Profile policies
CREATE POLICY "Users can view own profile" ON profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can insert own profile" ON profiles FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "Users can update own profile" ON profiles FOR UPDATE USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
```

### 3b. Add service_role GRANTs (around line 331-353)

Replace:
```sql
-- =====================================================
-- 7. PERMISSIONS
-- =====================================================

-- Schema access
GRANT USAGE ON SCHEMA public TO anon, authenticated;

-- Table access
GRANT ALL ON TABLE prayers TO authenticated;
GRANT ALL ON TABLE profiles TO authenticated;
GRANT ALL ON TABLE indulgences TO authenticated;

-- Sequence access (for UUIDs/IDs)
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- Anonymous can read profiles (for signup/login checks)
GRANT SELECT ON TABLE profiles TO anon;

-- Function permissions
GRANT EXECUTE ON FUNCTION update_karma(UUID, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION sync_prayer_count(UUID, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION deactivate_prayer(UUID, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION activate_prayer(UUID) TO authenticated;
```

With:
```sql
-- =====================================================
-- 7. PERMISSIONS
-- =====================================================

-- Schema access
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- Table access — authenticated (frontend users)
GRANT ALL ON TABLE prayers TO authenticated;
GRANT ALL ON TABLE profiles TO authenticated;
GRANT ALL ON TABLE indulgences TO authenticated;

-- Table access — service_role (Edge Functions)
GRANT ALL ON TABLE prayers TO service_role;
GRANT ALL ON TABLE profiles TO service_role;
GRANT ALL ON TABLE indulgences TO service_role;

-- Sequence access (for UUIDs/IDs)
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;

-- Anonymous can read profiles (for signup/login checks)
GRANT SELECT ON TABLE profiles TO anon;

-- Function permissions — authenticated (frontend users)
GRANT EXECUTE ON FUNCTION update_karma(UUID, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION sync_prayer_count(UUID, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION deactivate_prayer(UUID, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION activate_prayer(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION submit_prayer(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION refill_tokens(INT) TO authenticated;
GRANT EXECUTE ON FUNCTION reset_daily_prayer_count(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION reduce_ban_time(UUID) TO authenticated;

-- Function permissions — service_role (Edge Functions)
GRANT EXECUTE ON FUNCTION create_profile_on_signup() TO service_role;
GRANT EXECUTE ON FUNCTION submit_prayer(TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION activate_prayer(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION sync_prayer_count(UUID, INT) TO service_role;
GRANT EXECUTE ON FUNCTION deactivate_prayer(UUID, INT) TO service_role;
GRANT EXECUTE ON FUNCTION reduce_ban_time(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION refill_tokens(INT) TO service_role;
GRANT EXECUTE ON FUNCTION update_karma(UUID, INT) TO service_role;
GRANT EXECUTE ON FUNCTION reset_daily_prayer_count(UUID) TO service_role;
```

## Post-Fix Verification

After running the GRANT statements, verify in the SQL Editor:

```sql
-- Check table permissions for service_role
SELECT grantee, table_name, privilege_type 
FROM information_schema.role_table_grants 
WHERE grantee = 'service_role' 
  AND table_schema = 'public';

-- Check function permissions for service_role
SELECT routine_name, routine_type 
FROM information_schema.routine_privileges 
WHERE grantee = 'service_role' 
  AND routine_schema = 'public';
```

## Schema Drift Note

`reset_daily_prayer_count(UUID)` is defined in the source-of-truth files but does NOT exist on the live database. Two options:
1. **Create it on live DB** — run the function definition from `supabase-schema.sql` lines 93-101
2. **Remove it from source-of-truth** — if it's not needed

The Edge Function does NOT call this function, so it's not blocking the current fix. Recommend creating it on live DB to match the source of truth.