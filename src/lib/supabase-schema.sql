-- Electric Monk - Supabase Database Schema
-- Run this in your Supabase SQL Editor to set up tables, RLS, and functions
-- 
-- SCHEMA VERSION: 2.0 (Token-Based System)
-- Last Updated: 2026-05-15
--
-- KEY CHANGES IN v2.0:
-- - profiles.daily_prayers_count renamed to profiles.tokens_spent_today
-- - Added profiles.daily_token_limit column
-- - Added submit_prayer() RPC for secure, atomic prayer submission
-- - Added refill_tokens() RPC for ad-reward token refills
--
-- ENVIRONMENT VARIABLES (configure in .env.example and GitHub Pages):
-- - VITE_MAX_PRAYER_CHARS: Max characters per prayer (default: 1500)
-- - VITE_DAILY_TOKEN_LIMIT: Daily token budget (default: 1000)
-- - VITE_PRAYER_TOKEN_RATIO: Chars per token (default: 5)
-- - VITE_DEV_EMAIL: Developer contact email

-- ============================================
-- 1. TABLES
-- ============================================

-- Profiles: Extended user metadata
-- tokens_spent_today: Tracks tokens spent today (renamed from daily_prayers_count)
-- daily_token_limit: User's daily token budget (default 1000)
CREATE TABLE IF NOT EXISTS profiles (
  id UUID REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
  email TEXT,
  ban_until TIMESTAMPTZ,
  tokens_spent_today INT DEFAULT 0,
  daily_token_limit INT DEFAULT 1000,
  last_prayer_date DATE,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Prayers: User prayer requests and their status
CREATE TABLE IF NOT EXISTS prayers (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  content TEXT NOT NULL,
  is_rejected BOOLEAN DEFAULT false,
  rejection_reason TEXT,
  is_praying BOOLEAN DEFAULT false, -- True while being "prayed" in background
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Indulgences: Ad views that reduce ban time
CREATE TABLE IF NOT EXISTS indulgences (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  time_removed_seconds INT DEFAULT 900, -- 15 minutes
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ============================================
-- 2. TRIGGERS & FUNCTIONS
-- ============================================

-- Function: Create profile on user signup
CREATE OR REPLACE FUNCTION public.create_profile_on_signup()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, email)
    VALUES (NEW.id, NEW.email)
    ON CONFLICT (id) DO NOTHING; -- Prevents errors if profile somehow exists
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger: Auto-create profile when user signs up via Auth
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.create_profile_on_signup();

-- Function: Reset daily token count (called at midnight or on new day)
-- Resets tokens_spent_today to 0
CREATE OR REPLACE FUNCTION reset_daily_prayer_count(user_id UUID)
RETURNS VOID AS $$
BEGIN
  UPDATE profiles
  SET tokens_spent_today = 0, last_prayer_date = CURRENT_DATE
  WHERE id = user_id
    AND (last_prayer_date IS NULL OR last_prayer_date < CURRENT_DATE);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 3. SECURE RPC FUNCTIONS (Token System)
-- ============================================

-- submit_prayer: Secure, atomic prayer submission
-- Validates character limit (1500) and token budget server-side
-- Returns: JSONB with { id: uuid, cost: int }
-- 
-- Usage from frontend:
--   const { data, error } = await supabase.rpc('submit_prayer', { prayer_content: '...' })
CREATE OR REPLACE FUNCTION submit_prayer(prayer_content TEXT)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_char_limit INT := 1500; -- Hard-coded safety cap (match VITE_MAX_PRAYER_CHARS)
    v_token_ratio INT := 5;    -- 5 chars per token (match VITE_PRAYER_TOKEN_RATIO)
    v_cost INT;
    v_spent INT;
    v_limit INT;
    v_new_prayer_id UUID;
BEGIN
    -- 1. Get current stats
    SELECT tokens_spent_today, daily_token_limit 
    INTO v_spent, v_limit 
    FROM profiles WHERE id = v_user_id;

    -- 2. Validate Character Count
    IF length(prayer_content) > v_char_limit THEN
        RAISE EXCEPTION 'Prayer exceeds maximum length of % characters.', v_char_limit;
    END IF;

    -- 3. Calculate Cost
    v_cost := ceil(length(prayer_content)::float / v_token_ratio);

    -- 4. Check Budget
    IF (v_spent + v_cost) > v_limit THEN
        RAISE EXCEPTION 'Insufficient tokens. This prayer costs % tokens, but you only have % remaining.', v_cost, (v_limit - v_spent);
    END IF;

    -- 5. Atomic Transaction: Insert prayer and Update profile
    INSERT INTO prayers (user_id, content, is_praying)
    VALUES (v_user_id, prayer_content, true)
    RETURNING id INTO v_new_prayer_id;

    UPDATE profiles 
    SET tokens_spent_today = tokens_spent_today + v_cost,
        last_prayer_date = CURRENT_DATE
    WHERE id = v_user_id;

    RETURN jsonb_build_object('id', v_new_prayer_id, 'cost', v_cost);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- refill_tokens: Reduce tokens_spent_today (for ad rewards)
-- Returns: New tokens_spent_today value
--
-- Usage from frontend:
--   const { data: newSpent, error } = await supabase.rpc('refill_tokens', { p_amount: 100 })
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

-- Function: Reduce ban time by 15 minutes (called when ad is watched)
-- Note: This is separate from token refills - handles ban reduction only
CREATE OR REPLACE FUNCTION reduce_ban_time(p_user_id UUID)
RETURNS INTERVAL AS $$
DECLARE
  current_ban_end TIMESTAMPTZ;
  new_ban_end TIMESTAMPTZ;
  reduction INTERVAL := INTERVAL '15 minutes';
BEGIN
  SELECT ban_until INTO current_ban_end FROM profiles WHERE id = p_user_id;
  
  IF current_ban_end IS NULL OR current_ban_end < now() THEN
    RETURN INTERVAL '0';
  END IF;
  
  new_ban_end := current_ban_end - reduction;
  
  IF new_ban_end < now() THEN
    new_ban_end := now();
  END IF;
  
  UPDATE profiles SET ban_until = new_ban_end WHERE id = p_user_id;
  
  INSERT INTO indulgences (user_id, time_removed_seconds)
  VALUES (p_user_id, 900);
  
  RETURN reduction;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 4. ROW LEVEL SECURITY (RLS)
-- ============================================

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

-- Prayers Policies
CREATE POLICY "Users can view own prayers"
  ON prayers FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own prayers"
  ON prayers FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own prayers"
  ON prayers FOR UPDATE
  USING (auth.uid() = user_id);

-- Indulgences Policies
CREATE POLICY "Users can view own indulgences"
  ON indulgences FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own indulgences"
  ON indulgences FOR INSERT
  WITH CHECK (auth.uid() = user_id);

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
