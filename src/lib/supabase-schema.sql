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
-- - VITE_DAILY_TOKEN_LIMIT: Daily Mana budget (default: 1000)
-- - VITE_PRAYER_TOKEN_RATIO: Chars per Mana (default: 5)
-- - VITE_DEV_EMAIL: Developer contact email

-- ============================================
-- 1. TABLES
-- ============================================

-- Profiles: Extended user metadata
-- tokens_spent_today: Tracks Mana spent today (renamed from daily_prayers_count)
-- daily_token_limit: User's daily Mana budget (default 1000)
CREATE TABLE IF NOT EXISTS profiles (
  id UUID REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
  email TEXT,
  ban_until TIMESTAMPTZ,
  tokens_spent_today INT DEFAULT 0,
  daily_token_limit INT DEFAULT 100,
  last_prayer_date DATE,
  username TEXT,           -- User's chosen name (max 50 chars)
  faith TEXT,              -- User's faith/religion (max 100 chars)
  karma INT DEFAULT 0,     -- User's karma score
  max_prayer_slots INT DEFAULT 1,  -- Number of simultaneous prayer slots
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Prayers: User prayer requests and their status
CREATE TABLE IF NOT EXISTS prayers (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  content TEXT NOT NULL,
  response_content TEXT,              -- Monk's generated prayer/admonishment
  is_rejected BOOLEAN DEFAULT false,
  rejection_reason TEXT,
  is_praying BOOLEAN DEFAULT false, -- True while being "prayed" in background
  is_archived BOOLEAN DEFAULT false, -- True when user archives (hides) the prayer
  status TEXT DEFAULT 'pending',      -- Processing status: pending, completed, failed
  prayer_count INT DEFAULT 0,       -- Total times prayed (persisted at last sync)
  last_counted_at TIMESTAMPTZ,       -- Timestamp of last count sync
  activated_at TIMESTAMPTZ,          -- When prayer was last activated
  created_at TIMESTAMPTZ DEFAULT now(),
  -- Akashic Records columns (v3.0)
  karma_awarded INT DEFAULT 0,        -- How many 10-pray milestones have been awarded as karma
  source_prayer_id UUID REFERENCES prayers(id) ON DELETE SET NULL,  -- Links altruistic prayer to original
  source_sinner_id UUID REFERENCES profiles(id) ON DELETE SET NULL,  -- Links intercessory prayer to sinner
  prayer_type TEXT DEFAULT 'own' CHECK (prayer_type IN ('own', 'altruistic', 'intercessory'))
);

-- Migration: Add columns to existing tables (safe to run multiple times)
ALTER TABLE prayers ADD COLUMN IF NOT EXISTS response_content TEXT;
ALTER TABLE prayers ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'pending';

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
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
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
-- Validates character limit (1500) and Mana budget server-side
-- Deactivates any currently active prayer, then creates new prayer with activated_at set
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
        RAISE EXCEPTION 'Insufficient Mana. This prayer costs % Mana, but you only have % remaining.', v_cost, (v_limit - v_spent);
    END IF;

    -- 5. Deactivate any currently active prayer
    UPDATE prayers
    SET is_praying = false,
        activated_at = NULL
    WHERE user_id = v_user_id
      AND is_praying = true;

    -- 6. Insert new prayer with activated_at and last_counted_at set
    INSERT INTO prayers (user_id, content, is_praying, activated_at, last_counted_at)
    VALUES (v_user_id, prayer_content, true, now(), now())
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

-- Function: Update user karma (+1 for blessings, -1 for penance)
-- Called by the Edge Function after prayer classification
CREATE OR REPLACE FUNCTION update_karma(p_user_id UUID, p_karma_change INT)
RETURNS VOID AS $$
BEGIN
  UPDATE profiles
  SET karma = COALESCE(karma, 0) + p_karma_change,
      updated_at = now()
  WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Sync prayer count (called periodically while prayer is active)
-- Adds elapsed counts to prayer_count, updates last_counted_at, and awards karma for milestones
CREATE OR REPLACE FUNCTION sync_prayer_count(
  p_prayer_id UUID,
  p_elapsed_counts INT
)
RETURNS JSONB AS $$
DECLARE
  v_user_id UUID;
  v_prayer RECORD;
  v_milestones INT;
  v_karma_change INT := 0;
BEGIN
  SELECT user_id, is_praying INTO v_prayer
  FROM prayers WHERE id = p_prayer_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Prayer not found';
  END IF;

  IF v_prayer.user_id != auth.uid() THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  IF NOT v_prayer.is_praying THEN
    RAISE EXCEPTION 'Prayer is not active';
  END IF;

  UPDATE prayers
  SET prayer_count = prayer_count + p_elapsed_counts,
      last_counted_at = now()
  WHERE id = p_prayer_id
  RETURNING id, prayer_count, last_counted_at, activated_at, prayer_type, karma_awarded, user_id
  INTO v_prayer;

  -- Check karma milestones (every 10 prays)
  v_milestones := floor(v_prayer.prayer_count / 10);

  IF v_milestones > v_prayer.karma_awarded THEN
    -- Determine karma rate based on prayer type
    IF v_prayer.prayer_type = 'altruistic' THEN
      v_karma_change := (v_milestones - v_prayer.karma_awarded) * 2;
    ELSE
      v_karma_change := (v_milestones - v_prayer.karma_awarded) * 1;
    END IF;

    -- Award karma to the praying user
    PERFORM update_karma(v_prayer.user_id, v_karma_change);

    -- Update karma_awarded tracker
    UPDATE prayers SET karma_awarded = v_milestones WHERE id = p_prayer_id;
  END IF;

  RETURN jsonb_build_object(
    'prayer_count', v_prayer.prayer_count,
    'last_counted_at', v_prayer.last_counted_at,
    'activated_at', v_prayer.activated_at,
    'karma_change', v_karma_change
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Deactivate a prayer (final sync + set inactive + karma milestone)
-- Performs final count sync, sets is_praying = false, activated_at = null,
-- and awards karma if a milestone was crossed during the final sync
CREATE OR REPLACE FUNCTION deactivate_prayer(
  p_prayer_id UUID,
  p_elapsed_counts INT
)
RETURNS JSONB AS $$
DECLARE
  v_user_id UUID;
  v_prayer RECORD;
  v_milestones INT;
  v_karma_change INT := 0;
BEGIN
  SELECT user_id INTO v_user_id
  FROM prayers WHERE id = p_prayer_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Prayer not found';
  END IF;

  IF v_user_id != auth.uid() THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  -- Final count sync + deactivate
  UPDATE prayers
  SET prayer_count = prayer_count + p_elapsed_counts,
      last_counted_at = now(),
      is_praying = false,
      activated_at = NULL
  WHERE id = p_prayer_id
  RETURNING id, prayer_count, is_praying, activated_at, prayer_type, karma_awarded, user_id
  INTO v_prayer;

  -- Check karma milestones (every 10 prays)
  v_milestones := floor(v_prayer.prayer_count / 10);

  IF v_milestones > v_prayer.karma_awarded THEN
    -- Determine karma rate based on prayer type
    IF v_prayer.prayer_type = 'altruistic' THEN
      v_karma_change := (v_milestones - v_prayer.karma_awarded) * 2;
    ELSE
      v_karma_change := (v_milestones - v_prayer.karma_awarded) * 1;
    END IF;

    -- Award karma to the praying user
    PERFORM update_karma(v_prayer.user_id, v_karma_change);

    -- Update karma_awarded tracker
    UPDATE prayers SET karma_awarded = v_milestones WHERE id = p_prayer_id;
  END IF;

  RETURN jsonb_build_object(
    'id', v_prayer.id,
    'prayer_count', v_prayer.prayer_count,
    'is_praying', v_prayer.is_praying,
    'activated_at', v_prayer.activated_at,
    'karma_change', v_karma_change
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Activate a prayer (swap with current active)
-- Deactivates any currently active prayer for this user first,
-- then activates the target prayer with fresh timestamps
CREATE OR REPLACE FUNCTION activate_prayer(
  p_prayer_id UUID
)
RETURNS JSONB AS $$
DECLARE
  v_user_id UUID;
  v_current_active RECORD;
  v_elapsed_counts INT;
  v_cycle_time_ms INT;
  v_new_activated RECORD;
BEGIN
  v_user_id := auth.uid();

  -- Deactivate any currently active prayer
  SELECT id, COALESCE(response_content, content) AS cycle_text, activated_at, last_counted_at, prayer_count
  INTO v_current_active
  FROM prayers
  WHERE user_id = v_user_id
    AND is_praying = true
    AND id != p_prayer_id;

  IF FOUND THEN
    -- Cycle time based on monk's response length: ~200ms per char, clamped 15s–3min
    v_cycle_time_ms := GREATEST(15000, LEAST(length(v_current_active.cycle_text) * 200, 180000));
    v_elapsed_counts := GREATEST(0, floor(
      EXTRACT(EPOCH FROM (now() - COALESCE(v_current_active.last_counted_at, v_current_active.activated_at)))
      * 1000.0 / v_cycle_time_ms
    ));

    UPDATE prayers
    SET prayer_count = prayer_count + v_elapsed_counts,
        last_counted_at = now(),
        is_praying = false,
        activated_at = NULL
    WHERE id = v_current_active.id;
  END IF;

  -- Activate the target prayer
  UPDATE prayers
  SET is_praying = true,
      activated_at = now(),
      last_counted_at = now()
  WHERE id = p_prayer_id
    AND user_id = v_user_id
  RETURNING id, prayer_count, is_praying, activated_at, last_counted_at
  INTO v_new_activated;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Prayer not found or not authorized';
  END IF;

  RETURN jsonb_build_object(
    'activated', jsonb_build_object(
      'id', v_new_activated.id,
      'prayer_count', v_new_activated.prayer_count,
      'is_praying', v_new_activated.is_praying,
      'activated_at', v_new_activated.activated_at,
      'last_counted_at', v_new_activated.last_counted_at
    ),
    'deactivated_id', CASE WHEN v_current_active.id IS NOT NULL THEN v_current_active.id ELSE NULL END
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 4. ROW LEVEL SECURITY (RLS)
-- ============================================

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

-- Grant permissions for anonymous users (if needed for login/signup checks)
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

-- Function: Purchase additional prayer slot
-- Cost: 25 karma * current number of slots
-- Effect: +1 max_prayer_slots, +100 daily_token_limit
CREATE OR REPLACE FUNCTION purchase_prayer_slot()
RETURNS JSONB AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_current_slots INT;
  v_current_karma INT;
  v_slot_cost INT;
BEGIN
  -- Get current slot count and karma
  SELECT max_prayer_slots, COALESCE(karma, 0)
  INTO v_current_slots, v_current_karma
  FROM profiles WHERE id = v_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profile not found';
  END IF;

  -- Calculate cost: 25 karma * current slots
  v_slot_cost := 25 * v_current_slots;

  -- Check if user has enough karma
  IF v_current_karma < v_slot_cost THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Insufficient karma',
      'cost', v_slot_cost,
      'current_karma', v_current_karma
    );
  END IF;

  -- Deduct karma and add slot + mana
  UPDATE profiles
  SET karma = karma - v_slot_cost,
      max_prayer_slots = max_prayer_slots + 1,
      daily_token_limit = daily_token_limit + 100,
      updated_at = now()
  WHERE id = v_user_id;

  RETURN jsonb_build_object(
    'success', true,
    'new_slots', v_current_slots + 1,
    'new_daily_limit', (SELECT daily_token_limit FROM profiles WHERE id = v_user_id),
    'new_karma', (SELECT karma FROM profiles WHERE id = v_user_id),
    'cost', v_slot_cost
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute on purchase_prayer_slot to authenticated users
GRANT EXECUTE ON FUNCTION purchase_prayer_slot() TO authenticated;
GRANT EXECUTE ON FUNCTION purchase_prayer_slot() TO service_role;

-- ============================================
-- 6. AKASHIC RECORDS (v3.0)
-- ============================================

-- Migration: Add Akashic Records columns to prayers table (safe to run multiple times)
ALTER TABLE prayers ADD COLUMN IF NOT EXISTS karma_awarded INT DEFAULT 0;
ALTER TABLE prayers ADD COLUMN IF NOT EXISTS source_prayer_id UUID REFERENCES prayers(id) ON DELETE SET NULL;
ALTER TABLE prayers ADD COLUMN IF NOT EXISTS source_sinner_id UUID REFERENCES profiles(id) ON DELETE SET NULL;
ALTER TABLE prayers ADD COLUMN IF NOT EXISTS prayer_type TEXT DEFAULT 'own'
  CHECK (prayer_type IN ('own', 'altruistic', 'intercessory'));

-- Indexes for efficient Akashic Records queries
CREATE INDEX IF NOT EXISTS idx_prayers_public_feed
  ON prayers(is_rejected, is_archived, created_at DESC)
  WHERE is_rejected = false AND is_archived = false;

CREATE INDEX IF NOT EXISTS idx_prayers_type_active
  ON prayers(user_id, prayer_type, is_praying)
  WHERE is_praying = true;

CREATE INDEX IF NOT EXISTS idx_prayers_most_prayed
  ON prayers(prayer_count DESC)
  WHERE is_rejected = false AND is_archived = false AND prayer_type = 'own';

-- ============================================
-- 7. AKASHIC RECORDS RLS POLICIES
-- ============================================

-- Replace the restrictive "own prayers" policy with a broader one for the Akashic Records feed
DROP POLICY IF EXISTS "Users can view own prayers" ON prayers;
CREATE POLICY "Users can view approved prayers"
  ON prayers FOR SELECT
  USING (
    auth.uid() = user_id  -- always see your own
    OR (is_rejected = false AND is_archived = false AND status = 'completed')  -- see others' approved
  );

-- Replace the restrictive "own profile" policy with one that also shows purgatory users
DROP POLICY IF EXISTS "Users can view own profile" ON profiles;
CREATE POLICY "Users can view profiles"
  ON profiles FOR SELECT
  USING (
    auth.uid() = id  -- always see your own
    OR (ban_until IS NOT NULL AND ban_until > now())  -- see purgatory users
  );

-- Additional INSERT/UPDATE policies for altruistic/intercessory prayers
DROP POLICY IF EXISTS "Users can insert own prayers" ON prayers;
CREATE POLICY "Users can insert own prayers"
  ON prayers FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own prayers" ON prayers;
CREATE POLICY "Users can update own prayers"
  ON prayers FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ============================================
-- 8. AKASHIC RECORDS RPC FUNCTIONS
-- ============================================

-- Get public prayers for the Akashic Records feed
CREATE OR REPLACE FUNCTION get_public_prayers(
  p_offset INT DEFAULT 0,
  p_limit INT DEFAULT 20,
  p_sort_by TEXT DEFAULT 'newest'
)
RETURNS JSONB AS $$
DECLARE
  v_result JSONB;
  v_order_clause TEXT;
BEGIN
  IF p_sort_by = 'most_prayed' THEN
    v_order_clause := 'prayer_count DESC, created_at DESC';
  ELSE
    v_order_clause := 'created_at DESC';
  END IF;

  EXECUTE format(
    'SELECT jsonb_agg(row_to_json(t)) FROM (
      SELECT p.id, p.response_content, p.prayer_count,
             p.created_at, p.prayer_type,
             pr.username, pr.faith
      FROM prayers p
      LEFT JOIN profiles pr ON p.user_id = pr.id
      WHERE p.is_rejected = false
        AND p.is_archived = false
        AND p.status = ''completed''
        AND p.prayer_type = ''own''
      ORDER BY %s
      LIMIT %s OFFSET %s
    ) t',
    v_order_clause, p_limit, p_offset
  ) INTO v_result;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get sinners (users currently in purgatory)
CREATE OR REPLACE FUNCTION get_sinners()
RETURNS JSONB AS $$
DECLARE
  v_result JSONB;
BEGIN
  SELECT jsonb_agg(jsonb_build_object(
    'id', p.id,
    'username', p.username,
    'faith', p.faith,
    'ban_until', p.ban_until,
    'rejection_reason', pr.rejection_reason,
    'rejected_content', pr.content
  ))
  INTO v_result
  FROM profiles p
  LEFT JOIN LATERAL (
    SELECT content, rejection_reason
    FROM prayers
    WHERE prayers.user_id = p.id
      AND prayers.is_rejected = true
    ORDER BY created_at DESC
    LIMIT 1
  ) pr ON true
  WHERE p.ban_until IS NOT NULL
    AND p.ban_until > now()
  ORDER BY p.ban_until ASC;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Start an altruistic prayer session (praying for someone else's prayer)
CREATE OR REPLACE FUNCTION start_altruistic_prayer(
  p_target_prayer_id UUID,
  p_response_content TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_existing RECORD;
  v_new_id UUID;
  v_target RECORD;
BEGIN
  -- Get the target prayer's response_content if not provided
  IF p_response_content IS NULL THEN
    SELECT response_content, content INTO v_target
    FROM prayers WHERE id = p_target_prayer_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'Target prayer not found'; END IF;

    p_response_content := COALESCE(v_target.response_content, v_target.content);
  END IF;

  -- Deactivate any currently active prayer for this user
  UPDATE prayers SET is_praying = false, activated_at = NULL
  WHERE user_id = v_user_id AND is_praying = true;

  -- Check if an existing altruistic prayer for this target exists
  SELECT id, prayer_count, karma_awarded INTO v_existing
  FROM prayers
  WHERE user_id = v_user_id
    AND source_prayer_id = p_target_prayer_id
    AND prayer_type = 'altruistic'
    AND is_archived = false
  LIMIT 1;

  IF FOUND THEN
    UPDATE prayers
    SET is_praying = true, activated_at = now(), last_counted_at = now()
    WHERE id = v_existing.id
    RETURNING id INTO v_new_id;
  ELSE
    INSERT INTO prayers (user_id, content, response_content, prayer_type, source_prayer_id, is_praying, activated_at, last_counted_at, status)
    VALUES (
      v_user_id,
      'Altruistic prayer for another',
      p_response_content,
      'altruistic',
      p_target_prayer_id,
      true, now(), now(), 'completed'
    )
    RETURNING id INTO v_new_id;
  END IF;

  RETURN jsonb_build_object(
    'id', v_new_id,
    'type', 'altruistic',
    'target_prayer_id', p_target_prayer_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Start an intercessory prayer session (praying for a sinner)
CREATE OR REPLACE FUNCTION start_intercessory_prayer(
  p_target_sinner_id UUID,
  p_response_content TEXT
)
RETURNS JSONB AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_existing RECORD;
  v_new_id UUID;
BEGIN
  -- Deactivate any currently active prayer for this user
  UPDATE prayers SET is_praying = false, activated_at = NULL
  WHERE user_id = v_user_id AND is_praying = true;

  -- Check if an existing intercessory prayer for this sinner exists
  SELECT id, prayer_count, karma_awarded INTO v_existing
  FROM prayers
  WHERE user_id = v_user_id
    AND source_sinner_id = p_target_sinner_id
    AND prayer_type = 'intercessory'
    AND is_archived = false
  LIMIT 1;

  IF FOUND THEN
    UPDATE prayers
    SET is_praying = true, activated_at = now(), last_counted_at = now(),
        response_content = p_response_content
    WHERE id = v_existing.id
    RETURNING id INTO v_new_id;
  ELSE
    INSERT INTO prayers (user_id, content, response_content, prayer_type, source_sinner_id, is_praying, activated_at, last_counted_at, status)
    VALUES (
      v_user_id,
      'Intercessory prayer for a sinner',
      p_response_content,
      'intercessory',
      p_target_sinner_id,
      true, now(), now(), 'completed'
    )
    RETURNING id INTO v_new_id;
  END IF;

  RETURN jsonb_build_object(
    'id', v_new_id,
    'type', 'intercessory',
    'target_sinner_id', p_target_sinner_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- 9. AKASHIC RECORDS PERMISSIONS
-- ============================================

GRANT EXECUTE ON FUNCTION get_public_prayers(INT, INT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_sinners() TO authenticated;
GRANT EXECUTE ON FUNCTION start_altruistic_prayer(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION start_intercessory_prayer(UUID, TEXT) TO authenticated;
