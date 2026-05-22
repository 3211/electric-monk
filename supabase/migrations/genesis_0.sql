-- ======================================================================================
-- GENESIS 0: CORE PLAYER & SECTS FOUNDATION
-- ======================================================================================
-- SUPABASE AI / AGENT DIRECTIVE:
-- This is GENESIS_0. It creates the foundational tables for players and sects.
-- Designed to be idempotent (re-runnable) using IF NOT EXISTS and ON CONFLICT patterns.
-- ======================================================================================

BEGIN;

-- ==========================================
-- 1. SECTS TABLE
-- ==========================================
-- Stores faction metadata that drives AI generation and game rules.
-- Read-only for players, populated by seed data.

CREATE TABLE IF NOT EXISTS public.sects (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    emoji TEXT NOT NULL,
    description TEXT,
    principles TEXT[] NOT NULL DEFAULT '{}',
    tone_description TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Add comment for documentation
COMMENT ON TABLE public.sects IS 'Faction metadata that drives AI generation and game rules. Read-only for players.';
COMMENT ON COLUMN public.sects.id IS 'Slug identifier: gilded_path, holy_way, final_watch, black_tribunal';
COMMENT ON COLUMN public.sects.principles IS 'Array of faction principles used for AI prompts';
COMMENT ON COLUMN public.sects.tone_description IS 'Tone descriptor for AI generation (e.g., "opulent and grand")';

-- ==========================================
-- 2. PLAYERS TABLE
-- ==========================================
-- Core player data linked to auth.users.
-- Tracks username, sect affiliation, and onboarding state.

CREATE TABLE IF NOT EXISTS public.players (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    username TEXT UNIQUE,
    sect_id TEXT REFERENCES public.sects(id) ON DELETE SET NULL,
    onboarding_complete BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    CONSTRAINT players_username_check CHECK (
        username IS NULL OR (
            length(username) >= 3 AND 
            length(username) <= 16 AND 
            username ~ '^[a-zA-Z0-9_]+$'
        )
    )
);

-- Add comment for documentation
COMMENT ON TABLE public.players IS 'Core player data linked to auth.users. Tracks username, sect affiliation, and onboarding state.';
COMMENT ON COLUMN public.players.username IS 'Unique player name, 3-16 chars, alphanumeric and underscores only';
COMMENT ON COLUMN public.players.sect_id IS 'Foreign key to sects table, NULL until player chooses a faction';
COMMENT ON COLUMN public.players.onboarding_complete IS 'TRUE when player has completed name selection and sect choice';

-- ==========================================
-- 3. INDEXES
-- ==========================================
-- Optimize common queries for authentication and lookup.

CREATE INDEX IF NOT EXISTS idx_players_username ON public.players(username) WHERE username IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_players_sect_id ON public.players(sect_id);
CREATE INDEX IF NOT EXISTS idx_players_onboarding ON public.players(onboarding_complete) WHERE onboarding_complete = false;

-- ==========================================
-- 4. RLS POLICIES
-- ==========================================
-- Row Level Security: Players can only modify their own data.
-- Sects are read-only for everyone.

-- Enable RLS on both tables
ALTER TABLE public.sects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.players ENABLE ROW LEVEL SECURITY;

-- SECTS: Public read-only
DROP POLICY IF EXISTS "Sects are public read-only" ON public.sects;
CREATE POLICY "Sects are public read-only"
    ON public.sects FOR SELECT
    USING (true);

-- Only service role can modify sects
DROP POLICY IF EXISTS "Service role can modify sects" ON public.sects;
CREATE POLICY "Service role can modify sects"
    ON public.sects FOR ALL
    USING (auth.jwt()->>'role' = 'service_role')
    WITH CHECK (auth.jwt()->>'role' = 'service_role');

-- PLAYERS: Public read for authenticated users
DROP POLICY IF EXISTS "Players readable by authenticated users" ON public.players;
CREATE POLICY "Players readable by authenticated users"
    ON public.players FOR SELECT
    TO authenticated
    USING (true);

-- PLAYERS: Users can only update their own row
DROP POLICY IF EXISTS "Players can update own data" ON public.players;
CREATE POLICY "Players can update own data"
    ON public.players FOR UPDATE
    TO authenticated
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

-- PLAYERS: Users can insert their own row (for trigger-created rows)
DROP POLICY IF EXISTS "Players can insert own data" ON public.players;
CREATE POLICY "Players can insert own data"
    ON public.players FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = id);

-- ==========================================
-- 5. TRIGGER: Auto-create player on user signup
-- ==========================================
-- Creates a players row whenever a new auth.users row is inserted.

CREATE OR REPLACE FUNCTION public.create_player_on_signup()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    INSERT INTO public.players (id, username, sect_id, onboarding_complete)
    VALUES (
        NEW.id,
        NULL,  -- username set during onboarding
        NULL,  -- sect_id set during onboarding
        false  -- onboarding_complete = false initially
    )
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$;

-- Drop existing trigger if it exists (for re-runnability)
DROP TRIGGER IF EXISTS create_player_on_signup_trigger ON auth.users;

CREATE TRIGGER create_player_on_signup_trigger
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.create_player_on_signup();

-- ==========================================
-- 6. HELPER FUNCTION: Update username
-- ==========================================
-- Safe way to update username with validation.

CREATE OR REPLACE FUNCTION public.update_player_username(p_new_username TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_user_id UUID;
    v_existing TEXT;
BEGIN
    v_user_id := auth.uid();
    
    -- Validate username format
    IF p_new_username IS NULL OR length(p_new_username) < 3 OR length(p_new_username) > 16 THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Username must be between 3 and 16 characters'
        );
    END IF;
    
    IF p_new_username !~ '^[a-zA-Z0-9_]+$' THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Username can only contain letters, numbers, and underscores'
        );
    END IF;
    
    -- Check if username already exists
    SELECT username INTO v_existing FROM public.players 
    WHERE username = p_new_username AND id != v_user_id;
    
    IF v_existing IS NOT NULL THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Username already taken'
        );
    END IF;
    
    -- Update username
    UPDATE public.players
    SET username = p_new_username, updated_at = now()
    WHERE id = v_user_id;
    
    RETURN json_build_object(
        'success', true,
        'username', p_new_username
    );
END;
$$;

-- ==========================================
-- 7. HELPER FUNCTION: Choose sect
-- ==========================================
-- Safe way to set sect affiliation.

CREATE OR REPLACE FUNCTION public.choose_player_sect(p_sect_id TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_user_id UUID;
    v_sect_exists BOOLEAN;
BEGIN
    v_user_id := auth.uid();
    
    -- Check if sect exists
    SELECT EXISTS(SELECT 1 FROM public.sects WHERE id = p_sect_id) INTO v_sect_exists;
    
    IF NOT v_sect_exists THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Invalid sect ID'
        );
    END IF;
    
    -- Update sect_id
    UPDATE public.players
    SET sect_id = p_sect_id, updated_at = now()
    WHERE id = v_user_id;
    
    RETURN json_build_object(
        'success', true,
        'sect_id', p_sect_id
    );
END;
$$;

-- ==========================================
-- 8. HELPER FUNCTION: Complete onboarding
-- ==========================================
-- Marks onboarding as complete after name and sect are set.

CREATE OR REPLACE FUNCTION public.complete_player_onboarding()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_user_id UUID;
    v_username TEXT;
    v_sect_id TEXT;
BEGIN
    v_user_id := auth.uid();
    
    -- Check that username and sect are set
    SELECT username, sect_id INTO v_username, v_sect_id 
    FROM public.players WHERE id = v_user_id;
    
    IF v_username IS NULL OR v_username = '' THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Username not set'
        );
    END IF;
    
    IF v_sect_id IS NULL OR v_sect_id = '' THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Sect not chosen'
        );
    END IF;
    
    -- Mark onboarding complete
    UPDATE public.players
    SET onboarding_complete = true, updated_at = now()
    WHERE id = v_user_id;
    
    RETURN json_build_object(
        'success', true,
        'onboarding_complete', true
    );
END;
$$;

-- ==========================================
-- 9. HELPER FUNCTION: Get player status
-- ==========================================
-- Returns player's onboarding status and profile data.

CREATE OR REPLACE FUNCTION public.get_player_status()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_user_id UUID;
    v_result JSON;
BEGIN
    v_user_id := auth.uid();
    
    SELECT json_build_object(
        'id', p.id,
        'username', p.username,
        'sect_id', p.sect_id,
        'sect_name', s.name,
        'sect_emoji', s.emoji,
        'onboarding_complete', p.onboarding_complete
    ) INTO v_result
    FROM public.players p
    LEFT JOIN public.sects s ON p.sect_id = s.id
    WHERE p.id = v_user_id;
    
    RETURN COALESCE(v_result, json_build_object('error', 'Player not found'));
END;
$$;

-- ==========================================
-- 10. HELPER FUNCTION: Get available sects
-- ==========================================
-- Returns all sects for selection during onboarding.

CREATE OR REPLACE FUNCTION public.get_available_sects()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    RETURN (
        SELECT jsonb_agg(
            jsonb_build_object(
                'id', s.id,
                'name', s.name,
                'emoji', s.emoji,
                'description', s.description,
                'principles', s.principles,
                'tone_description', s.tone_description
            )
        )
        FROM public.sects s
        ORDER BY s.name
    );
END;
$$;

COMMIT;
