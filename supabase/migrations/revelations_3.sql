-- ======================================================================================
-- REVELATIONS 3: AKASHIC RECORD MINING
-- ======================================================================================
-- SUPABASE AI / AGENT DIRECTIVE:
-- This is REVELATIONS_3. It creates the Akashic Record mining infrastructure:
-- sector discovery tracking, pending/completed scan tables, compute speed helpers,
-- and score attribution to IP addresses.
-- Designed to be strictly idempotent (re-runnable).
-- ======================================================================================

BEGIN;

-- ==========================================
-- 1. AKASHIC SECTORS (Global Block Registry)
-- ==========================================

CREATE TABLE IF NOT EXISTS public.akashic_sectors (
    block_id BIGINT PRIMARY KEY,
    discovered_by_ip inet NOT NULL,
    discovered_by_faction_ip inet,
    discovery_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    score_value INT NOT NULL DEFAULT 0,
    verification_count INT NOT NULL DEFAULT 0,
    last_verified_at TIMESTAMPTZ,
    last_verified_by_ip inet
);

COMMENT ON TABLE public.akashic_sectors IS 'Global registry of discovered Akashic blocks. Each block can only be mined once (initial discovery), but verified many times.';
COMMENT ON COLUMN public.akashic_sectors.block_id IS 'Fibonacci seed offset identifying the mined address.';
COMMENT ON COLUMN public.akashic_sectors.discovered_by_ip IS 'IP address of the virtual machine that first discovered this block.';
COMMENT ON COLUMN public.akashic_sectors.discovered_by_faction_ip IS 'IP address of the faction (sect) credited with the discovery. NULL if solo mining.';
COMMENT ON COLUMN public.akashic_sectors.score_value IS 'Score awarded for the initial discovery.';
COMMENT ON COLUMN public.akashic_sectors.verification_count IS 'Number of times this block has been verified by other machines.';
COMMENT ON COLUMN public.akashic_sectors.last_verified_at IS 'Timestamp of the most recent verification.';
COMMENT ON COLUMN public.akashic_sectors.last_verified_by_ip IS 'IP of the most recent verifier machine.';

-- ==========================================
-- 2. AKASHIC SCANS PENDING (Active Mining)
-- ==========================================

CREATE TABLE IF NOT EXISTS public.akashic_scans_pending (
    process_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    machine_ip inet NOT NULL,
    faction_ip inet,
    start_block_id BIGINT NOT NULL,
    target_blocks INT NOT NULL DEFAULT 5,
    start_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    expected_completion_time TIMESTAMPTZ NOT NULL,
    block_speed_ms INT NOT NULL,
    is_verification BOOLEAN NOT NULL DEFAULT false,
    compute_speed_score INT NOT NULL DEFAULT 0
);

COMMENT ON TABLE public.akashic_scans_pending IS 'Active mining operations. Each row represents a batch being processed by a virtual machine.';
COMMENT ON COLUMN public.akashic_scans_pending.process_id IS 'UUID used by the client to identify and resume/pulse the scan.';
COMMENT ON COLUMN public.akashic_scans_pending.machine_ip IS 'IP of the virtual machine performing the mining.';
COMMENT ON COLUMN public.akashic_scans_pending.faction_ip IS 'IP of the faction (sect) credited. NULL if solo mining.';
COMMENT ON COLUMN public.akashic_scans_pending.start_block_id IS 'First Fibonacci seed offset in the batch.';
COMMENT ON COLUMN public.akashic_scans_pending.target_blocks IS 'Number of blocks to mine in this batch (default 5).';
COMMENT ON COLUMN public.akashic_scans_pending.expected_completion_time IS 'Server-calculated time when the scan should finish. Client must not pulse before this minus 5% buffer.';
COMMENT ON COLUMN public.akashic_scans_pending.block_speed_ms IS 'Calculated time per block in milliseconds. Drives client animation timing.';
COMMENT ON COLUMN public.akashic_scans_pending.is_verification IS 'True if these blocks have already been discovered (faster processing, pays less).';
COMMENT ON COLUMN public.akashic_scans_pending.compute_speed_score IS 'Raw compute score calculated from VM hardware (CPU, RAM, Network).';

-- ==========================================
-- 3. AKASHIC SCANS COMPLETED (Archive)
-- ==========================================

CREATE TABLE IF NOT EXISTS public.akashic_scans_completed (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    process_id UUID NOT NULL,
    machine_ip inet NOT NULL,
    faction_ip inet,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    start_block_id BIGINT NOT NULL,
    blocks_processed INT NOT NULL,
    score_awarded INT NOT NULL DEFAULT 0,
    is_verification BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE public.akashic_scans_completed IS 'Archive of completed mining operations. Records scores awarded and processing metadata.';
COMMENT ON COLUMN public.akashic_scans_completed.process_id IS 'Matches the process_id from akashic_scans_pending.';
COMMENT ON COLUMN public.akashic_scans_completed.score_awarded IS 'Total score awarded for this batch (sum of all blocks processed).';
COMMENT ON COLUMN public.akashic_scans_completed.blocks_processed IS 'Number of blocks actually processed in this batch (up to target_blocks).';

-- ==========================================
-- 4. SCORE TRACKING (Extend network_addresses)
-- ==========================================

ALTER TABLE public.network_addresses
ADD COLUMN IF NOT EXISTS akashic_score INT NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.network_addresses.akashic_score IS 'Cumulative Akashic mining score earned by this IP address. Updated on each completed pulse.';

-- ==========================================
-- 5. INDEXES
-- ==========================================

-- Akashic sectors
CREATE INDEX IF NOT EXISTS idx_akashic_sectors_discovered_by ON public.akashic_sectors(discovered_by_ip);
CREATE INDEX IF NOT EXISTS idx_akashic_sectors_faction ON public.akashic_sectors(discovered_by_faction_ip);
CREATE INDEX IF NOT EXISTS idx_akashic_sectors_discovery_time ON public.akashic_sectors(discovery_time DESC);

-- Pending scans
CREATE INDEX IF NOT EXISTS idx_akashic_pending_machine ON public.akashic_scans_pending(machine_ip);
CREATE INDEX IF NOT EXISTS idx_akashic_pending_faction ON public.akashic_scans_pending(faction_ip);
CREATE INDEX IF NOT EXISTS idx_akashic_pending_expected ON public.akashic_scans_pending(expected_completion_time);

-- Completed scans
CREATE INDEX IF NOT EXISTS idx_akashic_completed_machine ON public.akashic_scans_completed(machine_ip);
CREATE INDEX IF NOT EXISTS idx_akashic_completed_faction ON public.akashic_scans_completed(faction_ip);
CREATE INDEX IF NOT EXISTS idx_akashic_completed_process ON public.akashic_scans_completed(process_id);
CREATE INDEX IF NOT EXISTS idx_akashic_completed_time ON public.akashic_scans_completed(end_time DESC);

-- Score leaderboard
CREATE INDEX IF NOT EXISTS idx_network_akashic_score ON public.network_addresses(akashic_score DESC) WHERE akashic_score > 0;

-- ==========================================
-- 6. HELPER FUNCTIONS
-- ==========================================

-- 6.1: Calculate compute speed from VM hardware
CREATE OR REPLACE FUNCTION public.calculate_compute_speed(p_machine_ip inet)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_cpu_id   TEXT;
    v_mem_id   TEXT;
    v_nic_id   TEXT;
    v_cpu_cores INT;
    v_cpu_mhz  INT;
    v_ram_mhz  INT;
    v_nic_mbps INT;
    v_compute_speed INT;
BEGIN
    SELECT cpu_id, memory_id, network_card_id
    INTO v_cpu_id, v_mem_id, v_nic_id
    FROM public.virtual_machines
    WHERE ip_address = p_machine_ip;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Virtual machine with IP % not found', p_machine_ip;
    END IF;

    SELECT cores, clock_speed_mhz INTO v_cpu_cores, v_cpu_mhz
    FROM public.catalog_cpus WHERE id = v_cpu_id;

    SELECT speed_mhz INTO v_ram_mhz
    FROM public.catalog_memory WHERE id = v_mem_id;

    SELECT bandwidth_mbps INTO v_nic_mbps
    FROM public.catalog_network_cards WHERE id = v_nic_id;

    -- Formula: (CPU Cores × CPU MHz) + (RAM MHz × 0.5) + (Network Mbps × 10)
    v_compute_speed := (COALESCE(v_cpu_cores, 1) * COALESCE(v_cpu_mhz, 1000))
                    + FLOOR(COALESCE(v_ram_mhz, 1333) * 0.5)
                    + (COALESCE(v_nic_mbps, 100) * 10);

    RETURN v_compute_speed;
END;
$$;

-- 6.2: Calculate block processing time in ms based on compute speed
CREATE OR REPLACE FUNCTION public.calculate_block_speed_ms(p_compute_speed INT)
RETURNS INT
LANGUAGE plpgsql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    -- Base block time = 12,000 ms. Faster compute = faster blocks.
    -- Divisor: compute_speed / 1000 (minimum 1)
    -- block_speed_ms = 12,000,000 / compute_speed, floor minimum 500ms
    RETURN GREATEST(500, 12000000 / GREATEST(p_compute_speed, 1000));
END;
$$;

-- 6.3: Calculate expected completion time for a batch
CREATE OR REPLACE FUNCTION public.calculate_expected_completion(
    p_block_speed_ms INT,
    p_target_blocks INT DEFAULT 5
)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
IMMUTABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    -- Total time in ms = block_speed_ms × target_blocks × 1.10 (10% server buffer)
    RETURN now() + (INTERVAL '1 millisecond' * (p_block_speed_ms * p_target_blocks * 1.10));
END;
$$;

-- 6.4: Look up faction IP for a player (auto-determined from sect membership)
CREATE OR REPLACE FUNCTION public.get_player_faction_ip(p_user_id UUID)
RETURNS inet
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_faction_ip inet;
BEGIN
    SELECT s.ip_address INTO v_faction_ip
    FROM public.players p
    JOIN public.sects s ON p.sect_id = s.id
    WHERE p.id = p_user_id;

    RETURN v_faction_ip; -- NULL if player has no sect
END;
$$;

-- 6.5: Get all pending scans for a player (for recovery after refresh)
CREATE OR REPLACE FUNCTION public.get_player_pending_scans(p_user_id UUID)
RETURNS TABLE (
    process_id UUID,
    machine_ip inet,
    faction_ip inet,
    start_block_id BIGINT,
    target_blocks INT,
    start_time TIMESTAMPTZ,
    expected_completion_time TIMESTAMPTZ,
    block_speed_ms INT,
    is_verification BOOLEAN,
    compute_speed_score INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    RETURN QUERY
    SELECT p.*
    FROM public.akashic_scans_pending p
    JOIN public.virtual_machines vm ON vm.ip_address = p.machine_ip
    JOIN public.players pl ON pl.ip_address = vm.owner_identity
    WHERE pl.id = p_user_id;
END;
$$;

-- ==========================================
-- 7. RLS POLICIES
-- ==========================================

ALTER TABLE public.akashic_sectors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.akashic_scans_pending ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.akashic_scans_completed ENABLE ROW LEVEL SECURITY;

-- 7.1: Akashic sectors — public read, service write
DROP POLICY IF EXISTS "Akashic sectors are public read-only" ON public.akashic_sectors;
CREATE POLICY "Akashic sectors are public read-only"
    ON public.akashic_sectors FOR SELECT
    USING (true);

DROP POLICY IF EXISTS "Service role manages sectors" ON public.akashic_sectors;
CREATE POLICY "Service role manages sectors"
    ON public.akashic_sectors FOR ALL
    USING (auth.jwt()->>'role' = 'service_role')
    WITH CHECK (auth.jwt()->>'role' = 'service_role');

-- 7.2: Pending scans — players view own (via machine ownership), service manages
DROP POLICY IF EXISTS "Players view own pending scans" ON public.akashic_scans_pending;
CREATE POLICY "Players view own pending scans"
    ON public.akashic_scans_pending FOR SELECT
    TO authenticated
    USING (
        machine_ip IN (
            SELECT ip_address FROM public.virtual_machines
            WHERE owner_identity = (
                SELECT ip_address FROM public.players WHERE id = auth.uid()
            )
        )
    );

DROP POLICY IF EXISTS "Service role manages pending" ON public.akashic_scans_pending;
CREATE POLICY "Service role manages pending"
    ON public.akashic_scans_pending FOR ALL
    USING (auth.jwt()->>'role' = 'service_role')
    WITH CHECK (auth.jwt()->>'role' = 'service_role');

-- 7.3: Completed scans — players view own, service manages
DROP POLICY IF EXISTS "Players view own completed scans" ON public.akashic_scans_completed;
CREATE POLICY "Players view own completed scans"
    ON public.akashic_scans_completed FOR SELECT
    TO authenticated
    USING (
        machine_ip IN (
            SELECT ip_address FROM public.virtual_machines
            WHERE owner_identity = (
                SELECT ip_address FROM public.players WHERE id = auth.uid()
            )
        )
    );

DROP POLICY IF EXISTS "Service role manages completed" ON public.akashic_scans_completed;
CREATE POLICY "Service role manages completed"
    ON public.akashic_scans_completed FOR ALL
    USING (auth.jwt()->>'role' = 'service_role')
    WITH CHECK (auth.jwt()->>'role' = 'service_role');

-- ==========================================
-- 8. PERMISSIONS & GRANTS
-- ==========================================

-- Table access
GRANT ALL ON TABLE public.akashic_sectors TO service_role, postgres;
GRANT ALL ON TABLE public.akashic_scans_pending TO service_role, postgres;
GRANT ALL ON TABLE public.akashic_scans_completed TO service_role, postgres;

GRANT SELECT ON TABLE public.akashic_sectors TO authenticated;
GRANT SELECT ON TABLE public.akashic_scans_pending TO authenticated;
GRANT SELECT ON TABLE public.akashic_scans_completed TO authenticated;

-- Function execution
GRANT EXECUTE ON FUNCTION public.calculate_compute_speed(inet) TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION public.calculate_block_speed_ms(INT) TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION public.calculate_expected_completion(INT, INT) TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION public.get_player_faction_ip(UUID) TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION public.get_player_pending_scans(UUID) TO service_role, authenticated;

COMMIT;