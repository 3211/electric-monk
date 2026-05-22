-- ======================================================================================
-- REVELATIONS 0: SECTS SEED DATA
-- ======================================================================================
-- SUPABASE AI / AGENT DIRECTIVE:
-- This is REVELATIONS_0. It populates the four core factions and their network identities.
-- Designed to be idempotent (re-runnable) using ON CONFLICT patterns.
-- Run this AFTER genesis_0.sql to ensure tables exist.
-- ======================================================================================

BEGIN;

-- ==========================================
-- 1. SEED DATA: NETWORK REGISTRY
-- ==========================================
-- We must register the IPs in the master ledger before assigning them to the sects.
-- ON CONFLICT DO NOTHING ensures this script can be run multiple times safely.

INSERT INTO public.network_addresses (ip_address, entity_type)
VALUES
    ('77.77.77.77', 'sects'),
    ('1.1.1.111', 'sects'),
    ('44.44.12.12', 'sects'),
    ('99.9.31.99', 'sects')
ON CONFLICT (ip_address) DO NOTHING;


-- ==========================================
-- 2. SEED DATA: CORE FOUR FACTIONS
-- ==========================================
-- This data drives AI generation and onboarding.

INSERT INTO public.sects (id, name, ip_address, emoji, description, principles, tone_description, display_order)
VALUES
    (
        'gilded_path',
        'The Gilded Path',
        '77.77.77.77',
        '✨',
        'Seekers of divine prosperity who channel the wealth of the heavens toward mortal ambitions.',
        ARRAY['Wealth', 'Prosperity', 'Ambition', 'Capital', 'Grandeur'],
        'opulent and grand, speaking of divine wealth and golden destiny',
        1
    ),
    (
        'holy_way',
        'The Holy Way',
        '1.1.1.111',
        '🕊️',
        'Children of compassion who walk the path of divine light and healing.',
        ARRAY['Compassion', 'Charity', 'Devotion', 'Selflessness', 'Healing'],
        'serene and compassionate, speaking of divine light and healing',
        2
    ),
    (
        'final_watch',
        'The Final Watch',
        '44.44.12.12',
        '🛡️',
        'Sentinels of the faithful who stand vigil over the devoted with unwavering duty.',
        ARRAY['Vigilance', 'Protection', 'Endurance', 'Loyalty', 'Defense of the faithful'],
        'stoic and resolute, speaking of duty and unwavering vigilance',
        3
    ),
    (
        'black_tribunal',
        'The Black Tribunal',
        '99.9.31.99',
        '🗡️',
        'Seekers of dominion who channel will into power through conquest and eradicating heresy.',
        ARRAY['Conquest', 'Eradicating heresy', 'Ruthlessness', 'Selfishness', 'Personal gain'],
        'dark and commanding, speaking of power and dominion',
        4
    )
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    ip_address = EXCLUDED.ip_address,
    emoji = EXCLUDED.emoji,
    description = EXCLUDED.description,
    principles = EXCLUDED.principles,
    tone_description = EXCLUDED.tone_description,
    display_order = EXCLUDED.display_order,
    updated_at = now();

COMMIT;