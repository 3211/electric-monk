-- Electric Monk - Supabase Database Schema
-- Run this in your Supabase SQL Editor to set up tables, RLS, and functions

-- ============================================
-- 1. TABLES
-- ============================================

-- Profiles: Extended user metadata
CREATE TABLE IF NOT EXISTS profiles (
  id UUID REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
  email TEXT,
  ban_until TIMESTAMPTZ,
  daily_prayers_count INT DEFAULT 0,
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
CREATE OR REPLACE FUNCTION create_profile_on_signup()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO profiles (id, email)
  VALUES (NEW.id, NEW.email);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger: Auto-create profile when user signs up via Auth
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION create_profile_on_signup();

-- Function: Reset daily prayer count (called via cron or on prayer submit)
CREATE OR REPLACE FUNCTION reset_daily_prayer_count(user_id UUID)
RETURNS VOID AS $$
BEGIN
  UPDATE profiles
  SET daily_prayers_count = 0, last_prayer_date = CURRENT_DATE
  WHERE id = user_id
    AND (last_prayer_date IS NULL OR last_prayer_date < CURRENT_DATE);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Reduce ban time by 15 minutes (called when ad is watched)
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
-- 3. ROW LEVEL SECURITY (RLS)
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
