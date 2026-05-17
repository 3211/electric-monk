-- ============================================
-- Electric Monk - Intercessory Prayer Features
-- Migration for: prayer count display, ban reduction, sinner redemption
-- 
-- SCHEMA VERSION: 2.2
-- Date: 2026-05-16
--
-- CHANGES:
-- 1. New RPC: get_intercessory_prayer_count() - Count active prayers for a sinner
-- 2. Modified RPC: sync_prayer_count() - Ban reduction for intercessory prayers
--    - Reduces sinner ban_until by 1 minute per completed pray cycle
--    - Awards +5 karma bonus when sinner is redeemed
--    - Auto-deactivates intercessory prayer on redemption
--    - Returns new sinner_redeemed boolean field
--
-- ⚠️  COPY AND PASTE THIS ENTIRE SCRIPT INTO SUPABASE SQL EDITOR
-- ⚠️  Run it as a single transaction
-- ============================================

-- Drop existing functions first to avoid "cannot change return type" errors
DROP FUNCTION IF EXISTS sync_prayer_count(UUID, INT) CASCADE;
DROP FUNCTION IF EXISTS get_intercessory_prayer_count(UUID) CASCADE;

-- ============================================
-- 1. NEW RPC: get_intercessory_prayer_count
-- ============================================
-- Returns the count of active intercessory prayers targeting a specific sinner.
-- Used by PurgatoryView to show "X people are praying for your redemption"

CREATE OR REPLACE FUNCTION get_intercessory_prayer_count(p_sinner_id UUID)
RETURNS INT AS $$
  SELECT COUNT(*)::INT FROM prayers
  WHERE source_sinner_id = p_sinner_id
    AND is_praying = true
    AND prayer_type = 'intercessory';
$$ LANGUAGE sql SECURITY DEFINER;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION get_intercessory_prayer_count(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_intercessory_prayer_count(UUID) TO service_role;

-- ============================================
-- 2. MODIFIED RPC: sync_prayer_count
-- ============================================
-- Modified to add intercessory prayer ban reduction and sinner redemption.
-- 
-- Key additions:
-- - When prayer_type = 'intercessory' and source_sinner_id is set:
--   - Reduces sinner's ban_until by p_elapsed_counts * 1 minute
--   - If ban_until drops to now() or earlier: sinner is redeemed
--   - On redemption: clears ban, awards +5 karma to praying user, deactivates prayer
-- - Returns new sinner_redeemed boolean field

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
  v_ban_check TIMESTAMPTZ;
  v_sinner_redeemed BOOLEAN := false;
  v_ban_reduction INTERVAL;
  v_redemption_bonus INT := 5;
BEGIN
  SELECT user_id, is_praying, prayer_type, source_sinner_id, karma_awarded
  INTO v_prayer
  FROM prayers WHERE id = p_prayer_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Prayer not found';
  END IF;

  -- Allow sync even if prayer was deactivated (e.g., by redemption)
  -- but only if it was recently active (within last 60 seconds)
  IF v_prayer.is_praying = false AND v_prayer.prayer_type = 'intercessory' THEN
    -- For intercessory prayers that may have been auto-deactivated by redemption,
    -- we still process the final sync to credit karma to the praying user
    -- Check if prayer was recently active
    IF v_prayer.activated_at IS NULL OR (now() - v_prayer.activated_at) > INTERVAL '5 minutes' THEN
      RAISE EXCEPTION 'Prayer is not active and was not recently active';
    END IF;
  ELSIF v_prayer.is_praying = false THEN
    RAISE EXCEPTION 'Prayer is not active';
  END IF;

  IF v_prayer.user_id != auth.uid() THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  -- Update prayer count
  UPDATE prayers
  SET prayer_count = prayer_count + p_elapsed_counts,
      last_counted_at = now()
  WHERE id = p_prayer_id
  RETURNING id, prayer_count, last_counted_at, activated_at, prayer_type, karma_awarded, user_id, source_sinner_id
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

  -- INTERCESSORY PRAYER: Reduce sinner ban time
  -- 1 minute per completed pray cycle (p_elapsed_counts)
  IF v_prayer.prayer_type = 'intercessory' AND v_prayer.source_sinner_id IS NOT NULL THEN
    -- Calculate ban reduction: 1 minute per elapsed count
    v_ban_reduction := p_elapsed_counts * INTERVAL '1 minute';

    -- Reduce sinner's ban time, but not below now()
    UPDATE profiles
    SET ban_until = GREATEST(now(), ban_until - v_ban_reduction),
        updated_at = now()
    WHERE id = v_prayer.source_sinner_id
      AND ban_until IS NOT NULL
      AND ban_until > now();

    -- Check if sinner is now redeemed (ban_until <= now or NULL)
    SELECT ban_until INTO v_ban_check
    FROM profiles WHERE id = v_prayer.source_sinner_id;

    IF v_ban_check IS NULL OR v_ban_check <= now() THEN
      -- Sinner redeemed! Clear their ban completely
      UPDATE profiles SET ban_until = NULL, updated_at = now()
      WHERE id = v_prayer.source_sinner_id;

      -- Award +5 karma bonus to the praying user for redeeming a sinner
      PERFORM update_karma(v_prayer.user_id, v_redemption_bonus);
      v_karma_change := v_karma_change + v_redemption_bonus;

      -- Deactivate the intercessory prayer (it's done its job)
      UPDATE prayers
      SET is_praying = false, activated_at = NULL
      WHERE id = p_prayer_id;

      v_sinner_redeemed := true;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'prayer_count', v_prayer.prayer_count,
    'last_counted_at', v_prayer.last_counted_at,
    'activated_at', v_prayer.activated_at,
    'karma_change', v_karma_change,
    'sinner_redeemed', v_sinner_redeemed
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Ensure execute permissions are set
GRANT EXECUTE ON FUNCTION sync_prayer_count(UUID, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION sync_prayer_count(UUID, INT) TO service_role;

-- ============================================
-- 3. VERIFY update_karma FUNCTION EXISTS
-- ============================================
-- The sync_prayer_count function calls update_karma() which should already exist.
-- If it doesn't, create it:

CREATE OR REPLACE FUNCTION update_karma(p_user_id UUID, p_karma_change INT)
RETURNS VOID AS $$
BEGIN
  UPDATE profiles
  SET karma = COALESCE(karma, 0) + p_karma_change,
      updated_at = now()
  WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION update_karma(UUID, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION update_karma(UUID, INT) TO service_role;

-- ============================================
-- DONE! Verify the functions were created:
-- ============================================
-- Run this query to verify:
-- SELECT proname, prosrc FROM pg_proc WHERE proname IN ('get_intercessory_prayer_count', 'sync_prayer_count', 'update_karma');