-- ======================================================================================
-- REVELATIONS 6: AKASHIC SCANS — VIRTUAL PROCESS LINK HOTFIX
-- ======================================================================================
-- SUPABASE AI / AGENT DIRECTIVE:
-- This is REVELATIONS_6. It adds virtual_process_id to akashic_scans_pending to
-- bridge the two UUID systems. virtual_processes (from /run scan_records.exe) and
-- akashic_scans_pending (from akashic-mining edge function) previously had no link.
-- This column enables reverse-lookup from procmgr re-hydration.
--
-- Also updates get_akashic_scan_progress() to fall back to virtual_process_id lookup
-- when the direct process_id match fails.
-- Designed to be strictly idempotent (re-runnable).
-- ======================================================================================

BEGIN;

-- ==========================================
-- 1. AKASHIC SCANS PENDING — Add virtual_process_id
-- ==========================================

ALTER TABLE public.akashic_scans_pending
ADD COLUMN IF NOT EXISTS virtual_process_id UUID;

COMMENT ON COLUMN public.akashic_scans_pending.virtual_process_id IS 'Links to virtual_processes.process_id for re-hydration from procmgr. NULL for scans started via /decrypt-records (no virtual process row).';

CREATE INDEX IF NOT EXISTS idx_akashic_pending_vprocess
ON public.akashic_scans_pending(virtual_process_id)
WHERE virtual_process_id IS NOT NULL;

-- ==========================================
-- 2. AKASHIC SCANS COMPLETED — Add virtual_process_id (for history)
-- ==========================================

ALTER TABLE public.akashic_scans_completed
ADD COLUMN IF NOT EXISTS virtual_process_id UUID;

COMMENT ON COLUMN public.akashic_scans_completed.virtual_process_id IS 'Links to virtual_processes.process_id for historical tracking. NULL for scans started via /decrypt-records.';

-- ==========================================
-- 3. UPDATE get_akashic_scan_progress — Fallback lookup
-- ==========================================
-- When called with a virtual_processes UUID (not the akashic one),
-- try virtual_process_id as a fallback.

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
    -- Try direct match first (akashic process_id)
    SELECT * INTO v_pending
    FROM public.akashic_scans_pending
    WHERE process_id = p_process_id;

    -- Fall back to virtual_process_id lookup
    IF NOT FOUND THEN
        SELECT * INTO v_pending
        FROM public.akashic_scans_pending
        WHERE virtual_process_id = p_process_id;
    END IF;

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
        'process_id', v_pending.process_id,
        'virtual_process_id', v_pending.virtual_process_id,
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

COMMENT ON FUNCTION public.get_akashic_scan_progress(UUID) IS 'Returns actual progress of an Akashic scan by checking DB state. Falls back to virtual_process_id lookup if direct process_id match fails. Used for rehydration.';

-- ==========================================
-- 4. GRANTS
-- ==========================================

GRANT EXECUTE ON FUNCTION public.get_akashic_scan_progress(UUID) TO service_role, authenticated;

COMMIT;