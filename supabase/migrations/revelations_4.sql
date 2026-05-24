-- ======================================================================================
-- REVELATIONS 4: PROGRAM DEFINITIONS & AKASHIC VERIFICATION OVERHAUL
-- ======================================================================================
-- SUPABASE AI / AGENT DIRECTIVE:
-- This is REVELATIONS_4. It creates the program_definitions table for game-content
-- program parameters, updates akashic_sectors to support the two-verification model,
-- sets up pg_cron for automated process completion, and adds reward processing helpers.
-- Designed to be strictly idempotent (re-runnable).
-- ======================================================================================

BEGIN;

-- ==========================================
-- 1. PROGRAM DEFINITIONS (Game Content)
-- ==========================================
-- Defines hard-coded and game programs, their resource requirements,
-- execution parameters, and reward calculation formulas.

CREATE TABLE IF NOT EXISTS public.program_definitions (
    program_name VARCHAR(255) PRIMARY KEY,
    display_name VARCHAR(255) NOT NULL,
    category VARCHAR(50) NOT NULL DEFAULT 'utility' CHECK (category IN ('mining', 'hacking', 'utility', 'defense', 'scanning')),
    description TEXT DEFAULT '',
    -- Resource requirements (0 = variable, determined by player/system)
    base_cpu_pct INT NOT NULL DEFAULT 0,
    base_memory_mb INT NOT NULL DEFAULT 0,
    base_storage_mb INT NOT NULL DEFAULT 0,
    -- Execution parameters
    base_duration_seconds INT NOT NULL DEFAULT 60,
    duration_scales_with_cpu BOOLEAN NOT NULL DEFAULT true,
    -- Reward parameters
    reward_formula VARCHAR(50) NOT NULL DEFAULT 'linear' CHECK (reward_formula IN ('linear', 'exponential', 'discovery', 'verification')),
    base_reward INT NOT NULL DEFAULT 100,
    -- Metadata
    is_available_to_players BOOLEAN NOT NULL DEFAULT true,
    min_cpu_required_pct INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.program_definitions IS 'Game-content definitions for programs. Defines resource requirements, execution parameters, and reward calculations.';
COMMENT ON COLUMN public.program_definitions.program_name IS 'Unique program identifier (e.g., scan_records.exe).';
COMMENT ON COLUMN public.program_definitions.display_name IS 'Human-readable program name for UI.';
COMMENT ON COLUMN public.program_definitions.base_cpu_pct IS 'Default CPU allocation (0 = player-variable).';
COMMENT ON COLUMN public.program_definitions.base_memory_mb IS 'Default memory allocation in MB.';
COMMENT ON COLUMN public.program_definitions.base_storage_mb IS 'Default storage allocation in MB.';
COMMENT ON COLUMN public.program_definitions.base_duration_seconds IS 'Base execution time at 100% CPU. Scales based on CPU allocation and hardware.';
COMMENT ON COLUMN public.program_definitions.duration_scales_with_cpu IS 'If true, lower CPU% = proportionally longer duration.';
COMMENT ON COLUMN public.program_definitions.reward_formula IS 'How rewards scale: linear (CPU%), exponential (bonus for over-allocating), discovery (new blocks), verification (confirming existing).';
COMMENT ON COLUMN public.program_definitions.base_reward IS 'Base reward amount before scaling.';

-- ==========================================
-- 2. SEED DATA: AKASHIC SCAN PROGRAM
-- ==========================================

INSERT INTO public.program_definitions (program_name, display_name, category, description, base_cpu_pct, base_memory_mb, base_storage_mb, base_duration_seconds, duration_scales_with_cpu, reward_formula, base_reward, min_cpu_required_pct)
VALUES (
    'scan_records.exe',
    'Akashic Record Scanner',
    'mining',
    'Scan the Akashic blockchain for divine text fragments. Discovers new blocks or verifies existing records. Higher CPU allocation increases scan speed proportionally.',
    0,       -- base_cpu_pct: 0 = player-variable
    16,     -- base_memory_mb
    16,     -- base_storage_mb
    64,      -- base_duration_seconds at 100% CPU (scales with hardware)
    true,    -- duration_scales_with_cpu
    'discovery',
    100,
    10       -- min_cpu_required_pct
) ON CONFLICT (program_name) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    category = EXCLUDED.category,
    description = EXCLUDED.description,
    base_cpu_pct = EXCLUDED.base_cpu_pct,
    base_memory_mb = EXCLUDED.base_memory_mb,
    base_storage_mb = EXCLUDED.base_storage_mb,
    base_duration_seconds = EXCLUDED.base_duration_seconds,
    duration_scales_with_cpu = EXCLUDED.duration_scales_with_cpu,
    reward_formula = EXCLUDED.reward_formula,
    base_reward = EXCLUDED.base_reward,
    min_cpu_required_pct = EXCLUDED.min_cpu_required_pct;

-- ==========================================
-- 3. AKASHIC SECTORS — VERIFICATION OVERHAUL
-- ==========================================
-- Add verification reservation columns. Each block requires exactly 2 verifications
-- before it's considered fully verified. pending_verifications prevents race conditions
-- by allowing verifiers to "reserve" a slot before completing the scan.

ALTER TABLE public.akashic_sectors
ADD COLUMN IF NOT EXISTS pending_verifications INT NOT NULL DEFAULT 0;

ALTER TABLE public.akashic_sectors
ADD COLUMN IF NOT EXISTS verified_count INT NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.akashic_sectors.pending_verifications IS 'Number of active verification reservations (in-progress scans reserving a verification slot). Max 2 total across pending + verified.';
COMMENT ON COLUMN public.akashic_sectors.verified_count IS 'Number of completed verifications for this block (max 2). Once 2 is reached, block is fully verified and ineligible for further verification.';

-- ==========================================
-- 4. PG_CRON: AUTOMATED PROCESS COMPLETION
-- ==========================================
-- Schedules a job that runs every 30 seconds to detect processes whose
-- expected_end_time has passed and marks them as completed, applying pre-calculated rewards.

-- Enable pg_cron extension if not already enabled
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

-- Remove existing job if re-running migration (safe on fresh installs)
DO $$
BEGIN
    PERFORM cron.unschedule('process-completion-checker');
EXCEPTION WHEN OTHERS THEN
    -- Job didn't exist yet, safe to continue
END;
$$;

-- Schedule the completion checker to run every 30 seconds
SELECT cron.schedule(
    'process-completion-checker',
    '30 seconds',
    $$
    SELECT public.process_completed_jobs();
    $$
);

-- ==========================================
-- 5. PROCESS COMPLETION JOB FUNCTION
-- ==========================================

CREATE OR REPLACE FUNCTION public.process_completed_jobs()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_job_count INT := 0;
    v_process RECORD;
    v_reward JSON;
BEGIN
    -- Find all running processes past their expected end time
    FOR v_process IN
        SELECT
            vp.process_id,
            vp.machine_id,
            vp.program_id,
            vp.cpu_alloc_pct,
            vp.pre_calc_rewards,
            vp.process_metadata,
            vpr.program_name,
            pd.reward_formula
        FROM public.virtual_processes vp
        JOIN public.virtual_programs vpr ON vpr.program_id = vp.program_id
        LEFT JOIN public.program_definitions pd ON pd.program_name = vpr.program_name
        WHERE vp.status = 'running'
          AND vp.expected_end_time IS NOT NULL
          AND vp.expected_end_time <= now()
    LOOP
        -- Process akashic mining rewards
        IF v_process.program_name = 'scan_records.exe' THEN
            v_reward := public.process_akashic_rewards(
                v_process.process_id,
                v_process.machine_id,
                v_process.pre_calc_rewards,
                v_process.process_metadata
            );
        END IF;

        -- Mark process as completed (releases resources)
        PERFORM public.complete_process(v_process.process_id, 'completed');
        v_job_count := v_job_count + 1;
    END LOOP;

    RETURN format('Processed %s completed jobs', v_job_count);
END;
$$;

COMMENT ON FUNCTION public.process_completed_jobs() IS 'Cron-invoked function that detects completed processes and applies pre-calculated rewards. Runs every 30 seconds.';

-- ==========================================
-- 6. AKASHIC REWARD PROCESSING
-- ==========================================

CREATE OR REPLACE FUNCTION public.process_akashic_rewards(
    p_process_id UUID,
    p_machine_id UUID,
    p_pre_calc_rewards JSONB,
    p_process_metadata JSONB
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_machine_ip inet;
    v_faction_ip inet;
    v_owner_ip inet;
    v_total_reward INT := 0;
    v_blocks_processed INT := 0;
    v_block RECORD;
    v_blocks_json JSONB;
BEGIN
    -- Get the machine's IP and owner
    SELECT vm.ip_address, vm.owner_identity
    INTO v_machine_ip, v_owner_ip
    FROM public.virtual_machines vm
    WHERE vm.machine_id = p_machine_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Machine not found');
    END IF;

    -- Get faction IP for the owner
    SELECT s.ip_address INTO v_faction_ip
    FROM public.players p
    JOIN public.sects s ON s.id = p.sect_id
    WHERE p.ip_address = v_owner_ip;

    -- Extract block scores from process metadata
    v_blocks_json := p_process_metadata->'block_scores';

    -- Process each block
    IF v_blocks_json IS NOT NULL AND jsonb_typeof(v_blocks_json) = 'array' THEN
        FOR v_block IN
            SELECT
                (value->>'block_id')::BIGINT AS block_id,
                (value->>'score')::INT AS score,
                (value->>'matches_count')::INT AS matches_count,
                COALESCE((value->>'is_verification')::BOOLEAN, false) AS is_verification
            FROM jsonb_array_elements(v_blocks_json)
        LOOP
            -- Check if block is already discovered
            IF EXISTS (SELECT 1 FROM public.akashic_sectors WHERE block_id = v_block.block_id) THEN
                -- Verification: release pending verification slot
                UPDATE public.akashic_sectors
                SET verified_count = verified_count + 1,
                    pending_verifications = GREATEST(0, pending_verifications - 1),
                    last_verified_at = now(),
                    last_verified_by_ip = v_machine_ip,
                    verification_count = verification_count + 1
                WHERE block_id = v_block.block_id
                  AND pending_verifications > 0;

                -- Verification pays 25% per verified block
                v_total_reward := v_total_reward + (v_block.score * 0.25)::INT;
            ELSE
                -- Discovery: insert new sector
                INSERT INTO public.akashic_sectors (
                    block_id,
                    discovered_by_ip,
                    discovered_by_faction_ip,
                    score_value,
                    verified_count,
                    pending_verifications
                ) VALUES (
                    v_block.block_id,
                    v_machine_ip,
                    v_faction_ip,
                    v_block.score,
                    0,
                    0
                ) ON CONFLICT (block_id) DO NOTHING;

                -- Full reward for discovery
                v_total_reward := v_total_reward + v_block.score;
            END IF;

            v_blocks_processed := v_blocks_processed + 1;
        END LOOP;
    END IF;

    -- Credit scores to IP addresses
    IF v_total_reward > 0 THEN
        -- Credit machine IP
        UPDATE public.network_addresses
        SET akashic_score = COALESCE(akashic_score, 0) + v_total_reward
        WHERE ip_address = v_machine_ip;

        -- Credit faction IP (if applicable)
        IF v_faction_ip IS NOT NULL THEN
            UPDATE public.network_addresses
            SET akashic_score = COALESCE(akashic_score, 0) + v_total_reward
            WHERE ip_address = v_faction_ip;
        END IF;
    END IF;

    -- Insert completed scan record
    INSERT INTO public.akashic_scans_completed (
        process_id,
        machine_ip,
        faction_ip,
        start_time,
        end_time,
        start_block_id,
        blocks_processed,
        score_awarded,
        is_verification
    ) VALUES (
        p_process_id,
        v_machine_ip,
        v_faction_ip,
        (p_process_metadata->>'start_time')::TIMESTAMPTZ,
        now(),
        (p_process_metadata->>'start_block_id')::BIGINT,
        v_blocks_processed,
        v_total_reward,
        COALESCE((p_process_metadata->>'is_verification')::BOOLEAN, false)
    );

    -- Clean up pending scan record (if from old system)
    DELETE FROM public.akashic_scans_pending
    WHERE process_id = p_process_id;

    RETURN json_build_object(
        'success', true,
        'process_id', p_process_id,
        'machine_ip', v_machine_ip,
        'total_reward', v_total_reward,
        'blocks_processed', v_blocks_processed
    );
END;
$$;

COMMENT ON FUNCTION public.process_akashic_rewards(UUID, UUID, JSONB, JSONB) IS 'Processes Akashic mining rewards on process completion. Handles discovery vs verification with two-verification model.';

-- ==========================================
-- 7. VERIFICATION RESERVATION HELPER
-- ==========================================
-- Reserve a verification slot before starting a verification scan.
-- Returns true if reservation was successful.

CREATE OR REPLACE FUNCTION public.reserve_akashic_verification(
    p_block_id BIGINT,
    p_attempts INT DEFAULT 3
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_sector RECORD;
    v_attempt INT := 0;
BEGIN
    LOOP
        SELECT * INTO v_sector
        FROM public.akashic_sectors
        WHERE block_id = p_block_id
        FOR UPDATE SKIP LOCKED;

        IF NOT FOUND THEN
            RETURN json_build_object('success', false, 'error', 'Block not found, eligible for discovery instead');
        END IF;

        -- Check if fully verified (2 or more)
        IF v_sector.verified_count >= 2 THEN
            RETURN json_build_object('success', false, 'error', 'Block fully verified (2/2 verifications complete)');
        END IF;

        -- Check if all verification slots are taken (pending + verified >= 2)
        IF (v_sector.pending_verifications + v_sector.verified_count) >= 2 THEN
            RETURN json_build_object(
                'success', false,
                'error', 'All verification slots taken',
                'pending', v_sector.pending_verifications,
                'verified', v_sector.verified_count
            );
        END IF;

        -- Reserve a slot
        UPDATE public.akashic_sectors
        SET pending_verifications = pending_verifications + 1
        WHERE block_id = p_block_id;

        RETURN json_build_object(
            'success', true,
            'block_id', p_block_id,
            'pending_now', v_sector.pending_verifications + 1,
            'verified_count', v_sector.verified_count
        );
    END LOOP;
END;
$$;

COMMENT ON FUNCTION public.reserve_akashic_verification(BIGINT, INT) IS 'Reserves a verification slot for a block. Prevents more than 2 concurrent verifiers per block. Returns success/failure with slot status.';

-- ==========================================
-- 8. INDEXES
-- ==========================================

-- Program definitions
CREATE INDEX IF NOT EXISTS idx_program_defs_category ON public.program_definitions(category);

-- Updated akashic sectors indexes
CREATE INDEX IF NOT EXISTS idx_akashic_sectors_pending_verifications ON public.akashic_sectors(pending_verifications) WHERE pending_verifications > 0;
CREATE INDEX IF NOT EXISTS idx_akashic_sectors_verified_count ON public.akashic_sectors(verified_count) WHERE verified_count < 2;
CREATE INDEX IF NOT EXISTS idx_akashic_sectors_needs_verification ON public.akashic_sectors(pending_verifications, verified_count) WHERE verified_count < 2;

-- ==========================================
-- 9. RLS POLICIES
-- ==========================================

ALTER TABLE public.program_definitions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Program definitions are public read" ON public.program_definitions;
CREATE POLICY "Program definitions are public read"
    ON public.program_definitions FOR SELECT
    USING (true);

DROP POLICY IF EXISTS "Service manages program definitions" ON public.program_definitions;
CREATE POLICY "Service manages program definitions"
    ON public.program_definitions FOR ALL
    USING (auth.jwt()->>'role' = 'service_role')
    WITH CHECK (auth.jwt()->>'role' = 'service_role');

-- ==========================================
-- 10. GRANTS
-- ==========================================

GRANT ALL ON TABLE public.program_definitions TO service_role, postgres;
GRANT SELECT ON TABLE public.program_definitions TO authenticated;

GRANT EXECUTE ON FUNCTION public.process_completed_jobs() TO service_role;
GRANT EXECUTE ON FUNCTION public.process_akashic_rewards(UUID, UUID, JSONB, JSONB) TO service_role;
GRANT EXECUTE ON FUNCTION public.reserve_akashic_verification(BIGINT, INT) TO service_role, authenticated;

COMMIT;