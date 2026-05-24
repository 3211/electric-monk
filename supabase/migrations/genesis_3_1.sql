-- ======================================================================================
-- GENESIS 3.1: AKASHIC QUEUED PROCESS SYSTEM HOTFIX
-- ======================================================================================
-- SUPABASE AI / AGENT DIRECTIVE:
-- This is GENESIS_3_1. It overhauls the Akashic scanner to support:
--   - Explicit scan_mode (scan vs verify) — scanning NEVER verifies
--   - reserved_by on akashic_sectors for verification slot tracking (VM IP)
--   - initiator_ip on pending/completed scans — player's holy IP gets credit, NOT VM IP
--   - reserved_blocks on akashic_scans_pending for precise cancel cleanup
--   - cancel_akashic_scan() to clear reservations on process termination
--   - get_unverified_blocks() to find blocks eligible for verification
--   - Updated reserve_akashic_verification() to set reserved_by
--   - Updated process_akashic_rewards() to clear reserved_by + credit initiator_ip
--
-- SCORE ATTRIBUTION RULES:
--   - initiator_ip (player's holy IP) gets the akashic_score points
--   - faction_ip gets faction credit
--   - machine_ip (VM) does NOT get points — only operational tracking
--   - reserved_by on sectors = VM IP (doing the processing)
--   - discovered_by_ip on sectors = initiator_ip (player who found it)
--
-- Designed to be strictly idempotent (re-runnable).
-- ======================================================================================

BEGIN;

-- ==========================================
-- 1. AKASHIC SECTORS — Add reserved_by
-- ==========================================
-- Tracks which VM IP has reserved this block for verification.
-- NULL = not reserved. Only one verifier at a time per block.
-- Cleared on verification completion or process cancellation.

ALTER TABLE public.akashic_sectors
ADD COLUMN IF NOT EXISTS reserved_by inet;

COMMENT ON COLUMN public.akashic_sectors.reserved_by IS 'IP of the VM that has reserved this block for verification. NULL if not reserved. Cleared on verification completion or process cancellation.';

-- ==========================================
-- 2. AKASHIC SCANS PENDING — Add scan_mode, reserved_blocks, initiator_ip
-- ==========================================
-- scan_mode: Explicit user choice — 'scan' (discover new) or 'verify' (confirm existing).
-- Scanning NEVER auto-converts to verification.
-- reserved_blocks: Array of block_ids reserved by this verify scan (for precise cancel cleanup).
-- initiator_ip: The player's holy IP who initiated the scan — gets the credit/points.

ALTER TABLE public.akashic_scans_pending
ADD COLUMN IF NOT EXISTS scan_mode VARCHAR(10) NOT NULL DEFAULT 'scan'
  CHECK (scan_mode IN ('scan', 'verify'));

ALTER TABLE public.akashic_scans_pending
ADD COLUMN IF NOT EXISTS reserved_blocks BIGINT[] DEFAULT '{}';

ALTER TABLE public.akashic_scans_pending
ADD COLUMN IF NOT EXISTS initiator_ip inet;

COMMENT ON COLUMN public.akashic_scans_pending.scan_mode IS 'Explicit scan mode: scan (discover new blocks) or verify (confirm existing blocks). Scanning never auto-converts to verification.';
COMMENT ON COLUMN public.akashic_scans_pending.reserved_blocks IS 'For verify scans: the block_ids reserved by this scan. Used by cancel_akashic_scan to precisely clear reservations.';
COMMENT ON COLUMN public.akashic_scans_pending.initiator_ip IS 'The holy IP of the player who initiated the scan. This IP receives the akashic_score credit, NOT the machine_ip.';

-- ==========================================
-- 3. AKASHIC SCANS COMPLETED — Add initiator_ip
-- ==========================================

ALTER TABLE public.akashic_scans_completed
ADD COLUMN IF NOT EXISTS initiator_ip inet;

COMMENT ON COLUMN public.akashic_scans_completed.initiator_ip IS 'The holy IP of the player who initiated the scan. Receives the akashic_score credit.';

-- ==========================================
-- 4. HELPER: get_unverified_blocks
-- ==========================================
-- Returns blocks that are discovered but not fully verified and not currently reserved.
-- Used by the client to offer the "verify" option and by the edge function to select blocks.

CREATE OR REPLACE FUNCTION public.get_unverified_blocks(
    p_limit INT DEFAULT 10
)
RETURNS TABLE (block_id BIGINT, verified_count INT, pending_verifications INT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    RETURN QUERY
    SELECT s.block_id, s.verified_count, s.pending_verifications
    FROM public.akashic_sectors s
    WHERE s.verified_count < 2
      AND s.reserved_by IS NULL
      AND (s.pending_verifications + s.verified_count) < 2
    ORDER BY s.discovery_time ASC
    LIMIT p_limit;
END;
$$;

COMMENT ON FUNCTION public.get_unverified_blocks(INT) IS 'Returns unverified blocks available for verification. Excludes blocks already reserved. Ordered by discovery time (oldest first).';

-- ==========================================
-- 5. HELPER: cancel_akashic_scan
-- ==========================================
-- Cancels an active scan: clears verification reservations and deletes the pending scan.
-- For verify scans, uses reserved_blocks to precisely clear the right reservations.

CREATE OR REPLACE FUNCTION public.cancel_akashic_scan(
    p_process_id UUID,
    p_machine_ip inet
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_pending RECORD;
    v_cleared_count INT := 0;
BEGIN
    -- Find the pending scan
    SELECT * INTO v_pending
    FROM public.akashic_scans_pending
    WHERE process_id = p_process_id
      AND machine_ip = p_machine_ip;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Pending scan not found');
    END IF;

    -- If this was a verification scan, clear reserved_by on those blocks
    IF v_pending.scan_mode = 'verify' AND v_pending.reserved_blocks IS NOT NULL THEN
        UPDATE public.akashic_sectors
        SET reserved_by = NULL,
            pending_verifications = GREATEST(0, pending_verifications - 1)
        WHERE block_id = ANY(v_pending.reserved_blocks)
          AND reserved_by = p_machine_ip;

        GET DIAGNOSTICS v_cleared_count = ROW_COUNT;
    END IF;

    -- Delete the pending scan
    DELETE FROM public.akashic_scans_pending
    WHERE process_id = p_process_id;

    RETURN json_build_object(
        'success', true,
        'process_id', p_process_id,
        'reservations_cleared', v_cleared_count
    );
END;
$$;

COMMENT ON FUNCTION public.cancel_akashic_scan(UUID, inet) IS 'Cancels an akashic scan: clears verification reservations (using reserved_blocks for precision) and deletes the pending scan record.';

-- ==========================================
-- 6. UPDATE: reserve_akashic_verification (add reserved_by)
-- ==========================================
-- Updated to accept p_machine_ip and set reserved_by when reserving.
-- Must drop old signature first (was: p_block_id BIGINT, p_attempts INT DEFAULT 3).

DROP FUNCTION IF EXISTS public.reserve_akashic_verification(BIGINT, INT);

CREATE OR REPLACE FUNCTION public.reserve_akashic_verification(
    p_block_id BIGINT,
    p_machine_ip inet,
    p_attempts INT DEFAULT 3
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_sector RECORD;
BEGIN
    SELECT * INTO v_sector
    FROM public.akashic_sectors
    WHERE block_id = p_block_id
    FOR UPDATE SKIP LOCKED;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Block not found, eligible for discovery instead');
    END IF;

    IF v_sector.verified_count >= 2 THEN
        RETURN json_build_object('success', false, 'error', 'Block fully verified (2/2 verifications complete)');
    END IF;

    IF (v_sector.pending_verifications + v_sector.verified_count) >= 2 THEN
        RETURN json_build_object(
            'success', false,
            'error', 'All verification slots taken',
            'pending', v_sector.pending_verifications,
            'verified', v_sector.verified_count
        );
    END IF;

    -- Reserve a slot and set reserved_by (VM IP doing the processing)
    UPDATE public.akashic_sectors
    SET pending_verifications = pending_verifications + 1,
        reserved_by = p_machine_ip
    WHERE block_id = p_block_id;

    RETURN json_build_object(
        'success', true,
        'block_id', p_block_id,
        'pending_now', v_sector.pending_verifications + 1,
        'verified_count', v_sector.verified_count
    );
END;
$$;

COMMENT ON FUNCTION public.reserve_akashic_verification(BIGINT, inet, INT) IS 'Reserves a verification slot for a block and sets reserved_by (VM IP). Prevents more than 2 concurrent verifiers per block.';

-- ==========================================
-- 7. UPDATE: process_akashic_rewards
-- ==========================================
-- KEY CHANGE: Credits initiator_ip (player), NOT machine_ip (VM).
-- discovered_by_ip = initiator_ip (player who found it).
-- reserved_by cleared on verification completion.

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
    v_initiator_ip inet;
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

    -- Use initiator_ip from metadata if available (player's holy IP)
    -- Fall back to owner_ip for backwards compatibility
    IF p_process_metadata->>'initiator_ip' IS NOT NULL THEN
        v_initiator_ip := (p_process_metadata->>'initiator_ip')::inet;
    ELSE
        v_initiator_ip := v_owner_ip;
    END IF;

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
                -- Verification: release pending verification slot and clear reserved_by
                UPDATE public.akashic_sectors
                SET verified_count = verified_count + 1,
                    pending_verifications = GREATEST(0, pending_verifications - 1),
                    reserved_by = NULL,
                    last_verified_at = now(),
                    last_verified_by_ip = v_initiator_ip,
                    verification_count = verification_count + 1
                WHERE block_id = v_block.block_id
                  AND pending_verifications > 0;

                -- Verification pays 25% per verified block
                v_total_reward := v_total_reward + (v_block.score * 0.25)::INT;
            ELSE
                -- Discovery: insert new sector — initiator_ip gets discovery credit
                INSERT INTO public.akashic_sectors (
                    block_id,
                    discovered_by_ip,
                    discovered_by_faction_ip,
                    score_value,
                    verified_count,
                    pending_verifications
                ) VALUES (
                    v_block.block_id,
                    v_initiator_ip,
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

    -- Credit scores to INITIATOR IP (player), NOT machine IP (VM)
    IF v_total_reward > 0 THEN
        UPDATE public.network_addresses
        SET akashic_score = COALESCE(akashic_score, 0) + v_total_reward
        WHERE ip_address = v_initiator_ip;

        -- Credit faction IP (if applicable)
        IF v_faction_ip IS NOT NULL THEN
            UPDATE public.network_addresses
            SET akashic_score = COALESCE(akashic_score, 0) + v_total_reward
            WHERE ip_address = v_faction_ip;
        END IF;
    END IF;

    -- Insert completed scan record — include initiator_ip
    INSERT INTO public.akashic_scans_completed (
        process_id,
        machine_ip,
        faction_ip,
        start_time,
        end_time,
        start_block_id,
        blocks_processed,
        score_awarded,
        is_verification,
        initiator_ip
    ) VALUES (
        p_process_id,
        v_machine_ip,
        v_faction_ip,
        (p_process_metadata->>'start_time')::TIMESTAMPTZ,
        now(),
        (p_process_metadata->>'start_block_id')::BIGINT,
        v_blocks_processed,
        v_total_reward,
        COALESCE((p_process_metadata->>'is_verification')::BOOLEAN, false),
        v_initiator_ip
    );

    -- Clean up pending scan record
    DELETE FROM public.akashic_scans_pending
    WHERE process_id = p_process_id;

    RETURN json_build_object(
        'success', true,
        'process_id', p_process_id,
        'initiator_ip', v_initiator_ip,
        'total_reward', v_total_reward,
        'blocks_processed', v_blocks_processed
    );
END;
$$;

COMMENT ON FUNCTION public.process_akashic_rewards(UUID, UUID, JSONB, JSONB) IS 'Processes Akashic mining rewards on process completion. Credits initiator_ip (player), NOT machine_ip (VM). Clears reserved_by on verification completion.';

-- ==========================================
-- 8. HELPER: get_akashic_scan_progress
-- ==========================================
-- Returns the actual progress of a scan by checking DB state.
-- Used for rehydration instead of relying on a client-side counter.

CREATE OR REPLACE FUNCTION public.get_akashic_scan_progress(
    p_process_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_pending RECORD;
    v_blocks_completed INT := 0;
BEGIN
    SELECT * INTO v_pending
    FROM public.akashic_scans_pending
    WHERE process_id = p_process_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Pending scan not found');
    END IF;

    -- For verify scans, check how many reserved blocks have been verified
    IF v_pending.scan_mode = 'verify' AND v_pending.reserved_blocks IS NOT NULL THEN
        SELECT COUNT(*) INTO v_blocks_completed
        FROM public.akashic_sectors
        WHERE block_id = ANY(v_pending.reserved_blocks)
          AND last_verified_at >= v_pending.start_time;
    ELSE
        -- For scan mode, check how many blocks in the range are now discovered
        SELECT COUNT(*) INTO v_blocks_completed
        FROM public.akashic_sectors
        WHERE discovery_time >= v_pending.start_time
          AND discovered_by_ip = v_pending.initiator_ip;
    END IF;

    RETURN json_build_object(
        'success', true,
        'process_id', p_process_id,
        'scan_mode', v_pending.scan_mode,
        'target_blocks', v_pending.target_blocks,
        'blocks_completed', v_blocks_completed,
        'start_block_id', v_pending.start_block_id,
        'block_speed_ms', v_pending.block_speed_ms,
        'is_verification', v_pending.is_verification,
        'reserved_blocks', v_pending.reserved_blocks,
        'initiator_ip', v_pending.initiator_ip,
        'machine_ip', v_pending.machine_ip,
        'start_time', v_pending.start_time,
        'expected_completion_time', v_pending.expected_completion_time
    );
END;
$$;

COMMENT ON FUNCTION public.get_akashic_scan_progress(UUID) IS 'Returns actual progress of an Akashic scan by checking DB state. Used for rehydration instead of relying on a client-side counter.';

-- ==========================================
-- 9. INDEXES
-- ==========================================

CREATE INDEX IF NOT EXISTS idx_akashic_sectors_reserved_by ON public.akashic_sectors(reserved_by) WHERE reserved_by IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_akashic_sectors_unverified ON public.akashic_sectors(verified_count, reserved_by) WHERE verified_count < 2 AND reserved_by IS NULL;
CREATE INDEX IF NOT EXISTS idx_akashic_pending_initiator ON public.akashic_scans_pending(initiator_ip);
CREATE INDEX IF NOT EXISTS idx_akashic_completed_initiator ON public.akashic_scans_completed(initiator_ip);

-- ==========================================
-- 10. GRANTS
-- ==========================================

GRANT EXECUTE ON FUNCTION public.get_unverified_blocks(INT) TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_akashic_scan(UUID, inet) TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_akashic_verification(BIGINT, inet, INT) TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION public.process_akashic_rewards(UUID, UUID, JSONB, JSONB) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_akashic_scan_progress(UUID) TO service_role, authenticated;

COMMIT;
