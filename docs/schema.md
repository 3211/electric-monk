# PRAYER APP - COMPLETE DATABASE SCHEMA

**Authority Source:** `src/lib/supabase-schema.sql`
**Last Updated:** 2026-05-15

This document serves as the primary reference for the database schema used in the Prayer App. It is designed for use by both human developers and AI agents.

## SQL Schema

```sql
-- =====================================================
-- PRAYER APP - COMPLETE DATABASE SCHEMA
-- =====================================================
-- For: Supabase/PostgreSQL
-- Purpose: User profiles, prayer tracking with counters, 
--          token economy, karma system, and indulgences

-- =====================================================
-- 1. TABLES
-- =====================================================

-- User profiles linked to Supabase Auth
CREATE TABLE IF NOT EXISTS profiles (
  id UUID REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
  email TEXT,
  username TEXT,
  faith TEXT,
  ban_until TIMESTAMPTZ,
  tokens_spent_today INT DEFAULT 0,
  daily_token_limit INT DEFAULT 1000,
  last_prayer_date DATE,
  karma INT DEFAULT 0,
  max_prayer_slots INT DEFAULT 1,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Prayers created by users
CREATE TABLE IF NOT EXISTS prayers (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  content TEXT NOT NULL,
  is_rejected BOOLEAN DEFAULT false,
  rejection_reason TEXT,
  is_praying BOOLEAN DEFAULT false,
  is_archived BOOLEAN DEFAULT false,
  response_content TEXT,
  status TEXT DEFAULT 'pending',
  prayer_count INT DEFAULT 0,
  last_counted_at TIMESTAMPTZ,
  activated_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Tracks ban time reductions (indulgences)
CREATE TABLE IF NOT EXISTS indulgences (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  time_removed_seconds INT DEFAULT 900,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- =====================================================
-- 2. AUTO-PROFILE CREATION (Supabase Auth hook)
-- =====================================================

CREATE OR REPLACE FUNCTION public.create_profile_on_signup()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, email)
    VALUES (NEW.id, NEW.email)
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.create_profile_on_signup();

-- =====================================================
-- 3. PRAYER MANAGEMENT FUNCTIONS
-- =====================================================

-- Submit a new prayer (costs tokens, auto-activates, deactivates current)
CREATE OR REPLACE FUNCTION submit_prayer(prayer_content TEXT)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_char_limit INT := 1500;
    v_token_ratio INT := 5;
    v_cost INT;
    v_spent INT;
    v_limit INT;
    v_new_prayer_id UUID;
BEGIN
    -- Load user's token stats
    SELECT tokens_spent_today, daily_token_limit 
    INTO v_spent, v_limit 
    FROM profiles WHERE id = v_user_id;

    -- Validate length
    IF length(prayer_content) > v_char_limit THEN
        RAISE EXCEPTION 'Prayer exceeds maximum length of % characters.', v_char_limit;
    END IF;

    -- Calculate token cost (5 chars = 1 token, rounded up)
    v_cost := ceil(length(prayer_content)::float / v_token_ratio);

    -- Check balance
    IF (v_spent + v_cost) > v_limit THEN
        RAISE EXCEPTION 'Insufficient Mana. This prayer costs % Mana, but you only have % remaining.', 
            v_cost, (v_limit - v_spent);
    END IF;

    -- Deactivate any currently active prayer
    UPDATE prayers
    SET is_praying = false, activated_at = NULL
    WHERE user_id = v_user_id AND is_praying = true;

    -- Create new prayer (starts active)
    INSERT INTO prayers (user_id, content, is_praying, activated_at, last_counted_at)
    VALUES (v_user_id, prayer_content, true, now(), now())
    RETURNING id INTO v_new_prayer_id;

    -- Deduct tokens
    UPDATE profiles 
    SET tokens_spent_today = tokens_spent_today + v_cost,
        last_prayer_date = CURRENT_DATE
    WHERE id = v_user_id;

    RETURN jsonb_build_object('id', v_new_prayer_id, 'cost', v_cost);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Activate a prayer (deactivates current one first, syncs final count)
CREATE OR REPLACE FUNCTION activate_prayer(p_prayer_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_current RECORD;
    v_elapsed INT;
    v_cycle_ms INT;
    v_result RECORD;
BEGIN
    -- Find currently active prayer (if different from target)
    SELECT id, content, activated_at, last_counted_at, prayer_count
    INTO v_current
    FROM prayers
    WHERE user_id = v_user_id AND is_praying = true AND id != p_prayer_id;

    -- If there's an active prayer, calculate and save its final count
    IF FOUND THEN
        v_cycle_ms := GREATEST(150, ceil(length(v_current.content) / 5.0) * 150);
        v_elapsed := GREATEST(0, floor(
            EXTRACT(EPOCH FROM (now() - COALESCE(v_current.last_counted_at, v_current.activated_at)))
            * 1000.0 / v_cycle_ms
        ));
        
        UPDATE prayers
        SET prayer_count = prayer_count + v_elapsed,
            last_counted_at = now(),
            is_praying = false,
            activated_at = NULL
        WHERE id = v_current.id;
    END IF;

    -- Activate the target prayer
    UPDATE prayers
    SET is_praying = true, activated_at = now(), last_counted_at = now()
    WHERE id = p_prayer_id AND user_id = v_user_id
    RETURNING id, prayer_count, is_praying, activated_at, last_counted_at INTO v_result;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Prayer not found or not authorized';
    END IF;

    RETURN jsonb_build_object(
        'activated', jsonb_build_object(
            'id', v_result.id,
            'prayer_count', v_result.prayer_count,
            'is_praying', v_result.is_praying,
            'activated_at', v_result.activated_at,
            'last_counted_at', v_result.last_counted_at
        ),
        'deactivated_id', v_current.id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Sync prayer count (called every ~10s while prayer is active)
CREATE OR REPLACE FUNCTION sync_prayer_count(p_prayer_id UUID, p_elapsed_counts INT)
RETURNS JSONB AS $$
DECLARE
    v_prayer RECORD;
BEGIN
    SELECT user_id, is_praying INTO v_prayer
    FROM prayers WHERE id = p_prayer_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'Prayer not found'; END IF;
    IF v_prayer.user_id != auth.uid() THEN RAISE EXCEPTION 'Not authorized'; END IF;
    IF NOT v_prayer.is_praying THEN RAISE EXCEPTION 'Prayer is not active'; END IF;

    UPDATE prayers
    SET prayer_count = prayer_count + p_elapsed_counts,
        last_counted_at = now()
    WHERE id = p_prayer_id
    RETURNING prayer_count, last_counted_at, activated_at INTO v_prayer;

    RETURN jsonb_build_object(
        'prayer_count', v_prayer.prayer_count,
        'last_counted_at', v_prayer.last_counted_at,
        'activated_at', v_prayer.activated_at
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Deactivate prayer (final sync, stops counting)
CREATE OR REPLACE FUNCTION deactivate_prayer(p_prayer_id UUID, p_elapsed_counts INT)
RETURNS JSONB AS $$
DECLARE
    v_prayer RECORD;
BEGIN
    SELECT user_id INTO v_prayer FROM prayers WHERE id = p_prayer_id;
    
    IF NOT FOUND THEN RAISE EXCEPTION 'Prayer not found'; END IF;
    IF v_prayer.user_id != auth.uid() THEN RAISE EXCEPTION 'Not authorized'; END IF;

    UPDATE prayers
    SET prayer_count = prayer_count + p_elapsed_counts,
        last_counted_at = now(),
        is_praying = false,
        activated_at = NULL
    WHERE id = p_prayer_id
    RETURNING id, prayer_count, is_praying, activated_at INTO v_prayer;

    RETURN jsonb_build_object(
        'id', v_prayer.id,
        'prayer_count', v_prayer.prayer_count,
        'is_praying', v_prayer.is_praying,
        'activated_at', v_prayer.activated_at
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- 4. INDULGENCE SYSTEM (Ban reduction)
-- =====================================================

-- Reduce ban time by 15 minutes
CREATE OR REPLACE FUNCTION reduce_ban_time(p_user_id UUID)
RETURNS INTERVAL AS $$
DECLARE
    current_ban TIMESTAMPTZ;
    new_ban TIMESTAMPTZ;
    reduction INTERVAL := INTERVAL '15 minutes';
BEGIN
    SELECT ban_until INTO current_ban FROM profiles WHERE id = p_user_id;
    
    IF current_ban IS NULL OR current_ban < now() THEN 
        RETURN INTERVAL '0'; 
    END IF;
    
    new_ban := GREATEST(now(), current_ban - reduction);
    
    UPDATE profiles SET ban_until = new_ban WHERE id = p_user_id;
    INSERT INTO indulgences (user_id, time_removed_seconds) VALUES (p_user_id, 900);
    
    RETURN reduction;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- 5. TOKEN & KARMA FUNCTIONS
-- =====================================================

-- Refill spent tokens
CREATE OR REPLACE FUNCTION refill_tokens(p_amount INT)
RETURNS INT AS $$
DECLARE
    v_new_spent INT;
BEGIN
    UPDATE profiles 
    SET tokens_spent_today = GREATEST(0, tokens_spent_today - p_amount)
    WHERE id = auth.uid()
    RETURNING tokens_spent_today INTO v_new_spent;
    
    RETURN v_new_spent;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update karma (called by Edge Functions)
CREATE OR REPLACE FUNCTION update_karma(p_user_id UUID, p_karma_change INT)
RETURNS INT AS $$
DECLARE
    v_new_karma INT;
BEGIN
    UPDATE profiles 
    SET karma = karma + p_karma_change
    WHERE id = p_user_id
    RETURNING karma INTO v_new_karma;
    
    RETURN v_new_karma;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- 6. SECURITY (RLS Policies)
-- =====================================================

-- Enable RLS
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE prayers ENABLE ROW LEVEL SECURITY;
ALTER TABLE indulgences ENABLE ROW LEVEL SECURITY;

-- Profile policies
CREATE POLICY "Users can view own profile" ON profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update own profile" ON profiles FOR UPDATE USING (auth.uid() = id);

-- Prayer policies
CREATE POLICY "Users can view own prayers" ON prayers FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own prayers" ON prayers FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can archive own prayers" ON prayers FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- Indulgence policies
CREATE POLICY "Users can view own indulgences" ON indulgences FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own indulgences" ON indulgences FOR INSERT WITH CHECK (auth.uid() = user_id);

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

-- =====================================================
-- 8. INDEXES
-- =====================================================

CREATE INDEX IF NOT EXISTS idx_prayers_user_status ON prayers(user_id, status);
```
