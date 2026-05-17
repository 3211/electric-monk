# PRAYER APP - COMPLETE DATABASE SCHEMA

**Authority Source:** `src/lib/supabase-schema.sql`
**Last Updated:** 2026-05-17

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
    SELECT id, COALESCE(response_content, content) AS cycle_text, activated_at, last_counted_at, prayer_count
    INTO v_current
    FROM prayers
    WHERE user_id = v_user_id AND is_praying = true AND id != p_prayer_id;

    -- If there's an active prayer, calculate and save its final count
    -- Cycle time based on monk's response length: ~200ms per char, clamped 15s–3min
    IF FOUND THEN
        v_cycle_ms := GREATEST(15000, LEAST(length(v_current.cycle_text) * 200, 180000));
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

-- Enable RLS (FORCE ensures service_role RLS bypass is still tracked)
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles FORCE ROW LEVEL SECURITY;
ALTER TABLE prayers ENABLE ROW LEVEL SECURITY;
ALTER TABLE indulgences ENABLE ROW LEVEL SECURITY;

-- Profile policies
CREATE POLICY "Users can view own profile" ON profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can insert own profile" ON profiles FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "Users can update own profile" ON profiles FOR UPDATE USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

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

-- =====================================================
-- 8. INDEXES
-- =====================================================

CREATE INDEX IF NOT EXISTS idx_prayers_user_status ON prayers(user_id, status);
```

---

## 9. AKASHIC RECORDS EXTENSIONS (v3.0)

The Akashic Records feature adds a new tab showing all public prayers and users in purgatory, with the ability to pray altruistically for others.

### New Columns on `prayers` Table

```sql
-- Track karma milestones already awarded (prevents double-awarding)
karma_awarded INT DEFAULT 0

-- Link altruistic prayer back to the original prayer being prayed for
source_prayer_id UUID REFERENCES prayers(id) ON DELETE SET NULL

-- Link intercessory prayer to the sinner being prayed for
source_sinner_id UUID REFERENCES profiles(id) ON DELETE SET NULL

-- Distinguish prayer types: own, altruistic, intercessory
prayer_type TEXT DEFAULT 'own' CHECK (prayer_type IN ('own', 'altruistic', 'intercessory'))
```

### Prayer Types

| Type | Description | Karma Rate |
|------|-------------|------------|
| `own` | User's own prayer (default) | +1 karma per 100 prays |
| `altruistic` | Praying for someone else's prayer | +2 karma per 100 prays |
| `intercessory` | Praying for a sinner in purgatory | +1 karma per 100 prays |

### New Indexes

```sql
CREATE INDEX idx_prayers_public_feed
  ON prayers(is_rejected, is_archived, created_at DESC)
  WHERE is_rejected = false AND is_archived = false;

CREATE INDEX idx_prayers_type_active
  ON prayers(user_id, prayer_type, is_praying)
  WHERE is_praying = true;

CREATE INDEX idx_prayers_most_prayed
  ON prayers(prayer_count DESC)
  WHERE is_rejected = false AND is_archived = false AND prayer_type = 'own';
```

### Updated RLS Policies

```sql
-- Users can view approved prayers from others (Akashic Records feed)
-- AND their own prayers (including rejected/archived)
CREATE POLICY "Users can view approved prayers"
  ON prayers FOR SELECT
  USING (
    auth.uid() = user_id
    OR (is_rejected = false AND is_archived = false AND status = 'completed')
  );

-- Users can view purgatory users' basic info (Sinners list)
-- AND their own profile
CREATE POLICY "Users can view profiles"
  ON profiles FOR SELECT
  USING (
    auth.uid() = id
    OR (ban_until IS NOT NULL AND ban_until > now())
  );
```

### New RPC Functions

#### `get_public_prayers(p_offset INT, p_limit INT, p_sort_by TEXT)`

Fetches the Akashic Records prayer feed with author usernames.

- `p_sort_by = 'newest'`: Orders by `created_at DESC`
- `p_sort_by = 'most_prayed'`: Orders by `prayer_count DESC, created_at DESC`
- Only returns `prayer_type = 'own'` (not altruistic/intercessory prayers)
- Only returns approved, completed, non-archived prayers
- Returns JSONB array with: `id, response_content, prayer_count, created_at, prayer_type, username, faith`

#### `get_sinners()`

Fetches users currently in purgatory with their most recent rejection reason.

- Returns JSONB array with: `id, username, faith, ban_until, rejection_reason, rejected_content`
- Only includes users where `ban_until > now()`

#### `start_altruistic_prayer(p_target_prayer_id UUID, p_response_content TEXT)`

Creates or resumes an altruistic prayer session for someone else's prayer.

- Deactivates any currently active prayer for the user
- If an existing altruistic prayer for the same target exists, reactivates it
- Otherwise creates a new prayer row with `prayer_type = 'altruistic'`
- Returns: `{ id, type, target_prayer_id }`

#### `start_intercessory_prayer(p_target_sinner_id UUID, p_response_content TEXT)`

Creates or resumes an intercessory prayer session for a sinner.

- Deactivates any currently active prayer for the user
- If an existing intercessory prayer for the same sinner exists, reactivates it
- Otherwise creates a new prayer row with `prayer_type = 'intercessory'`
- Returns: `{ id, type, target_sinner_id }`

### Modified RPC Function: `sync_prayer_count`

Now includes karma milestone checking. Every 100 prays triggers a karma award:

- `prayer_type = 'own'`: +1 karma per milestone
- `prayer_type = 'altruistic'`: +2 karma per milestone
- `prayer_type = 'intercessory'`: +1 karma per milestone

The `karma_awarded` column tracks how many milestones have been awarded to prevent double-awarding. The response now includes a `karma_change` field.

### Modified RPC Function: `deactivate_prayer`

Now includes karma milestone checking on final sync. When a prayer is deactivated, any milestone crossed during the final count sync triggers a karma award (same rates as `sync_prayer_count`). The response now includes a `karma_change` field, allowing the frontend to show a karma toast notification when stopping a prayer.

### New Edge Function: `pray-for-sinner`

Located at `supabase/functions/pray-for-sinner/index.ts`.

- Receives `{ sinner_id, user_id }`
- Fetches sinner's profile and most recent rejected prayer
- Generates an intercessory prayer via Venice AI
- Returns `{ success, response, sinner_username, faith, rejection_reason }`

### Frontend Components

| File | Purpose |
|------|---------|
| `src/views/AkashicRecordsView.vue` | Main view with Prayers/Sinners sub-tabs |
| `src/composables/useAkashicRecords.js` | Fetch public prayers, sinners, manage altruistic sessions |
| `src/components/organisms/AkashicPrayerCard.vue` | Prayer card for the public feed |
| `src/components/organisms/SinnerCard.vue` | Sinner card with live countdown |
| `src/components/molecules/KarmaToast.vue` | Toast notification for karma milestones |
| `supabase/functions/pray-for-sinner/index.ts` | Edge function for AI-generated intercessory prayers |

---

## Karma Shop — Blessings (v4.0)

**Migration:** `supabase/migrations/karma-shop-blessings.sql`
**Config:** `src/config/blessings.json`

### New Tables

#### `blessing_types`

Blessing definitions mirrored from the config file. Server-side source of truth for costs and karma values.

| Column | Type | Description |
|--------|------|-------------|
| `id` | TEXT PK | Slug identifier (e.g. `golden-light`) |
| `emoji` | TEXT | Emoji displayed as badge |
| `name` | TEXT | Human-readable name |
| `description` | TEXT | Flavor text |
| `karma_cost` | INT | Karma deducted from giver |
| `karma_to_giver` | INT | Karma rebated to giver |
| `karma_to_receiver` | INT | Karma awarded to prayer owner |
| `sort_order` | INT | Display order in shop |
| `is_active` | BOOLEAN | Whether available for purchase |
| `created_at` | TIMESTAMPTZ | Creation timestamp |

#### `prayer_blessings`

Junction table tracking who blessed which prayer. UNIQUE constraint prevents duplicate blessings (same user + same type per prayer).

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID PK | Auto-generated |
| `prayer_id` | UUID FK → prayers | The blessed prayer |
| `blessing_type_id` | TEXT FK → blessing_types | Which blessing |
| `giver_id` | UUID FK → profiles | Who gave the blessing |
| `receiver_id` | UUID FK → profiles | Prayer owner (denormalized for karma) |
| `created_at` | TIMESTAMPTZ | When blessed |

**UNIQUE constraint:** `(prayer_id, blessing_type_id, giver_id)` — one user can give each blessing type once per prayer.

### New RPC Functions

#### `grant_blessing(p_prayer_id UUID, p_blessing_type_id TEXT) → JSONB`

Atomically:
1. Validates blessing type is active
2. Prevents self-blessing (cannot bless own prayer)
3. Prevents duplicate blessings
4. Checks giver has enough karma
5. Deducts `karma_cost` from giver
6. Awards `karma_to_giver` rebate to giver
7. Awards `karma_to_receiver` to prayer owner
8. Inserts `prayer_blessings` row

Returns: `{ id, blessing_type_id, karma_spent, karma_to_giver, karma_to_receiver }`

#### `get_prayer_blessings(p_prayer_ids UUID[]) → JSONB`

Fetches aggregated blessing counts for a batch of prayers. Returns one row per `(prayer_id, blessing_type_id)` with count, emoji, and name.

### Updated RPC: `get_public_prayers`

Now includes a `blessings` JSONB array per prayer with aggregated blessing data (emoji, name, count), sorted by blessing sort_order.

### RLS Policies

- `blessing_types`: Publicly readable (SELECT for all)
- `prayer_blessings`: Publicly readable (SELECT for all)
- No direct INSERT policy — all inserts go through `grant_blessing` RPC (SECURITY DEFINER)

### Blessing Economics

| Blessing | Cost | Giver Gets | Receiver Gets | Net Cost |
|----------|------|------------|---------------|----------|
| ✨ Golden Light | 10 | 1 | 5 | 9 |
| 🔥 Holy Flame | 25 | 2 | 10 | 23 |
| 🕊️ Dove of Peace | 50 | 5 | 20 | 45 |
| 👑 Divine Crown | 100 | 10 | 50 | 90 |

### Frontend Components

| File | Purpose |
|------|---------|
| `src/config/blessings.json` | Blessing definitions (source of truth for display) |
| `src/composables/useBlessings.js` | Fetch blessing types & prayer blessing aggregates |
| `src/composables/useKarmaShop.js` | Shop tab state & blessing purchase flow |
| `src/views/KarmaShopView.vue` | Karma Shop page with Blessings tab |
| `src/components/organisms/BlessingPicker.vue` | Modal to pick a blessing to grant |
| `src/components/molecules/BlessingBadgeBar.vue` | Emoji badge bar with overflow handling |
| `src/components/organisms/BlessingDetailModal.vue` | Full blessing breakdown popup |
