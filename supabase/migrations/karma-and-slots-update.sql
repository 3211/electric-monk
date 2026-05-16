-- Electric Monk - Karma & Prayer Slots Update
-- Migration for: 10-pray karma milestones, purchasable prayer slots, 100 mana per slot
-- 
-- SCHEMA VERSION: 2.1
-- Date: 2026-05-16
--
-- CHANGES:
-- - Daily mana limit default reduced from 1000 to 100 (per slot)
-- - Karma milestones now awarded every 10 prays (was 100)
-- - New purchase_prayer_slot() RPC: Buy slots for 25 * current_slots karma
-- - Each purchased slot adds +100 daily mana limit
--
-- USAGE: Run this script in the Supabase SQL Editor

-- ============================================
-- 1. UPDATE PROFILES TABLE DEFAULTS
-- ============================================

-- Update the default daily_token_limit for new users (100 mana per slot, starting with 1 slot)
ALTER TABLE profiles ALTER COLUMN daily_token_limit SET DEFAULT 100;

-- Update comment for karma_awarded to reflect 10-pray milestones
COMMENT ON COLUMN prayers.karma_awarded IS 'How many 10-pray milestones have been awarded as karma';

-- ============================================
-- 2. UPDATE sync_prayer_count FUNCTION
-- ============================================
-- Modified to award karma every 10 prays instead of 100

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

-- ============================================
-- 3. CREATE purchase_prayer_slot FUNCTION
-- ============================================
-- Allows users to purchase additional prayer slots
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
-- 4. NOTES FOR EXISTING USERS
-- ============================================
-- 
-- Existing users will keep their current daily_token_limit values.
-- To reset existing users to the new 100 mana base:
--   UPDATE profiles SET daily_token_limit = 100 + (max_prayer_slots - 1) * 100;
--
-- This migration does NOT automatically adjust existing users' limits.
-- Run the above UPDATE if you want to normalize all users to the new system.
