-- ======================================================================================
-- REVELATIONS 0: SECTS SEED DATA
-- ======================================================================================
-- SUPABASE AI / AGENT DIRECTIVE:
-- This is REVELATIONS_0. It populates the four core factions.
-- Designed to be idempotent (re-runnable) using ON CONFLICT patterns.
-- Run this AFTER genesis_0.sql to ensure tables exist.
-- ======================================================================================

BEGIN;

-- ==========================================
-- SEED DATA: CORE FOUR FACTIONS
-- ==========================================
-- This data drives AI generation and onboarding.
-- Add new sects here - they will automatically appear in the frontend.

INSERT INTO public.sects (id, name, emoji, description, principles, tone_description)
VALUES
    (
        'gilded_path',
        'The Gilded Path',
        '✨',
        'Seekers of divine prosperity who channel the wealth of the heavens toward mortal ambitions.',
        ARRAY['Wealth', 'Prosperity', 'Ambition', 'Capital', 'Grandeur'],
        'opulent and grand, speaking of divine wealth and golden destiny'
    ),
    (
        'holy_way',
        'The Holy Way',
        '🕊️',
        'Children of compassion who walk the path of divine light and healing.',
        ARRAY['Compassion', 'Charity', 'Devotion', 'Selflessness', 'Healing'],
        'serene and compassionate, speaking of divine light and healing'
    ),
    (
        'final_watch',
        'The Final Watch',
        '🛡️',
        'Sentinels of the faithful who stand vigil over the devoted with unwavering duty.',
        ARRAY['Vigilance', 'Protection', 'Endurance', 'Loyalty', 'Defense of the faithful'],
        'stoic and resolute, speaking of duty and unwavering vigilance'
    ),
    (
        'black_tribunal',
        'The Black Tribunal',
        '🗡️',
        'Seekers of dominion who channel will into power through conquest and eradicating heresy.',
        ARRAY['Conquest', 'Eradicating heresy', 'Ruthlessness', 'Selfishness', 'Personal gain'],
        'dark and commanding, speaking of power and dominion'
    )
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    emoji = EXCLUDED.emoji,
    description = EXCLUDED.description,
    principles = EXCLUDED.principles,
    tone_description = EXCLUDED.tone_description,
    updated_at = now();

COMMIT;
