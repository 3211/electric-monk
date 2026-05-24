-- ======================================================================================
-- GENESIS 3: VIRTUAL PROGRAMS & PROCESS MANAGEMENT
-- ======================================================================================
-- SUPABASE AI / AGENT DIRECTIVE:
-- This is GENESIS_3. It creates the virtual_programs and virtual_processes tables,
-- resource tracking helpers, and RLS policies for the virtual computing layer.
-- Designed to be strictly idempotent (re-runnable).
-- ======================================================================================

BEGIN;

-- ==========================================
-- 1. VIRTUAL PROGRAMS
-- ==========================================
-- Installed software on virtual machines. Ownership is machine-scoped (not user-scoped).
-- Supports both hard-coded system programs and future user-created programs via config_data JSONB.

CREATE TABLE IF NOT EXISTS public.virtual_programs (
    program_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    machine_id UUID NOT NULL REFERENCES public.virtual_machines(machine_id) ON DELETE CASCADE,
    program_name VARCHAR(255) NOT NULL,
    program_type VARCHAR(50) NOT NULL DEFAULT 'system' CHECK (program_type IN ('system', 'user', 'game')),
    config_data JSONB DEFAULT '{}',
    installed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(machine_id, program_name)
);

COMMENT ON TABLE public.virtual_programs IS 'Installed programs on virtual machines. Ownership attributed to the machine IP, not the player.';
COMMENT ON COLUMN public.virtual_programs.program_id IS 'Unique identifier for this installation instance.';
COMMENT ON COLUMN public.virtual_programs.machine_id IS 'The virtual machine this program is installed on.';
COMMENT ON COLUMN public.virtual_programs.program_name IS 'Name of the program (references program_definitions.program_name).';
COMMENT ON COLUMN public.virtual_programs.program_type IS 'System (hard-coded), user (player-created), or game (gameplay feature).';
COMMENT ON COLUMN public.virtual_programs.config_data IS 'JSONB blob for user-defined program logic or configuration overrides.';
COMMENT ON COLUMN public.virtual_programs.installed_at IS 'When this program was installed on the machine.';

-- ==========================================
-- 2. VIRTUAL PROCESSES
-- ==========================================
-- Running instances of programs on virtual machines. Tracks CPU, memory, and storage allocation.
-- Processes have a lifecycle: running → completed/terminated/failed.
-- pre_calc_rewards stores JSONB with expected rewards computed at start time.

CREATE TABLE IF NOT EXISTS public.virtual_processes (
    process_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    machine_id UUID NOT NULL REFERENCES public.virtual_machines(machine_id) ON DELETE CASCADE,
    program_id UUID NOT NULL REFERENCES public.virtual_programs(program_id) ON DELETE CASCADE,
    cpu_alloc_pct INT NOT NULL DEFAULT 100 CHECK (cpu_alloc_pct >= 0 AND cpu_alloc_pct <= 100),
    memory_alloc_mb INT NOT NULL DEFAULT 0 CHECK (memory_alloc_mb >= 0),
    storage_alloc_mb INT NOT NULL DEFAULT 0 CHECK (storage_alloc_mb >= 0),
    status VARCHAR(50) NOT NULL DEFAULT 'running' CHECK (status IN ('running', 'completed', 'terminated', 'failed')),
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expected_end_time TIMESTAMPTZ,
    actual_end_time TIMESTAMPTZ,
    pre_calc_rewards JSONB DEFAULT '{}',
    process_metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.virtual_processes IS 'Active and historical process instances running on virtual machines.';
COMMENT ON COLUMN public.virtual_processes.process_id IS 'Unique process identifier. Used by client for status checks and recovery.';
COMMENT ON COLUMN public.virtual_processes.machine_id IS 'The virtual machine executing this process.';
COMMENT ON COLUMN public.virtual_processes.program_id IS 'The installed program being executed.';
COMMENT ON COLUMN public.virtual_processes.cpu_alloc_pct IS 'Percentage of total VM CPU allocated (0 = variable/flex, up to 100).';
COMMENT ON COLUMN public.virtual_processes.memory_alloc_mb IS 'Memory allocated to this process in MB.';
COMMENT ON COLUMN public.virtual_processes.storage_alloc_mb IS 'Storage allocated to this process in MB.';
COMMENT ON COLUMN public.virtual_processes.status IS 'Lifecycle state: running, completed, terminated (by user), or failed (error).';
COMMENT ON COLUMN public.virtual_processes.expected_end_time IS 'Server-calculated time when the process should finish. Drives cron-based completion.';
COMMENT ON COLUMN public.virtual_processes.actual_end_time IS 'When the process actually ended (set by cron or manual completion).';
COMMENT ON COLUMN public.virtual_processes.pre_calc_rewards IS 'JSONB blob with expected rewards computed when process started. Applied by cron on completion.';
COMMENT ON COLUMN public.virtual_processes.process_metadata IS 'Arbitrary JSONB for process-specific state (e.g., akashic scan progress, block IDs).';

-- ==========================================
-- 3. INDEXES
-- ==========================================

-- Virtual programs lookups
CREATE INDEX IF NOT EXISTS idx_vprograms_machine ON public.virtual_programs(machine_id);
CREATE INDEX IF NOT EXISTS idx_vprograms_name ON public.virtual_programs(program_name);
CREATE INDEX IF NOT EXISTS idx_vprograms_machine_name ON public.virtual_programs(machine_id, program_name);

-- Virtual processes lookups
CREATE INDEX IF NOT EXISTS idx_vprocesses_machine ON public.virtual_processes(machine_id);
CREATE INDEX IF NOT EXISTS idx_vprocesses_status ON public.virtual_processes(status);
CREATE INDEX IF NOT EXISTS idx_vprocesses_expected_end ON public.virtual_processes(expected_end_time) WHERE status = 'running';
CREATE INDEX IF NOT EXISTS idx_vprocesses_program ON public.virtual_processes(program_id);
CREATE INDEX IF NOT EXISTS idx_vprocesses_machine_status ON public.virtual_processes(machine_id, status);

-- ==========================================
-- 4. HELPER FUNCTIONS
-- ==========================================

-- 4.1: Calculate total resource usage for a VM's active (running) processes
CREATE OR REPLACE FUNCTION public.calculate_vm_resource_usage(p_machine_id UUID)
RETURNS TABLE (
    total_cpu_pct INT,
    total_memory_mb INT,
    total_storage_mb INT,
    active_process_count INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    RETURN QUERY
    SELECT
        COALESCE(SUM(vp.cpu_alloc_pct), 0)::INT,
        COALESCE(SUM(vp.memory_alloc_mb), 0)::INT,
        COALESCE(SUM(vp.storage_alloc_mb), 0)::INT,
        COUNT(vp.process_id)::INT
    FROM public.virtual_processes vp
    WHERE vp.machine_id = p_machine_id
      AND vp.status = 'running';
END;
$$;

COMMENT ON FUNCTION public.calculate_vm_resource_usage(UUID) IS 'Returns aggregate CPU%, memory MB, storage MB, and count of active processes for a given VM.';

-- 4.2: Check if a VM has enough free resources to start a new process
CREATE OR REPLACE FUNCTION public.can_start_process(
    p_machine_id UUID,
    p_cpu_pct INT DEFAULT 100,
    p_memory_mb INT DEFAULT 0,
    p_storage_mb INT DEFAULT 0
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_usage RECORD;
    v_vm RECORD;
    v_available_cpu_pct INT;
    v_available_ram_mb INT;
    v_available_storage_mb INT;
BEGIN
    -- Get VM hardware references
    SELECT vm.machine_id, vm.cpu_id, vm.memory_id, vm.storage_id
    INTO v_vm
    FROM public.virtual_machines vm
    WHERE vm.machine_id = p_machine_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Virtual machine not found');
    END IF;

    -- Get current usage
    SELECT * INTO v_usage FROM public.calculate_vm_resource_usage(p_machine_id);

    -- Derive total capacity from catalog hardware
    -- CPU: each core contributes 100 percentage points
    SELECT COALESCE(cc.cores * 100, 100) INTO v_available_cpu_pct
    FROM public.catalog_cpus cc WHERE cc.id = v_vm.cpu_id;

    -- RAM: capacity_gb converted to MB
    SELECT COALESCE(cm.capacity_gb * 1024, 1024) INTO v_available_ram_mb
    FROM public.catalog_memory cm WHERE cm.id = v_vm.memory_id;

    -- Storage: capacity_mb from catalog
    SELECT COALESCE(cs.capacity_mb, 10240) INTO v_available_storage_mb
    FROM public.catalog_storage cs WHERE cs.id = v_vm.storage_id;

    -- Check CPU (0 means variable/flex — always allowed)
    IF p_cpu_pct > 0 AND (v_usage.total_cpu_pct + p_cpu_pct) > v_available_cpu_pct THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Insufficient CPU resources',
            'available_pct', v_available_cpu_pct - v_usage.total_cpu_pct,
            'requested_pct', p_cpu_pct,
            'total_capacity_pct', v_available_cpu_pct
        );
    END IF;

    -- Check RAM
    IF (v_usage.total_memory_mb + p_memory_mb) > v_available_ram_mb THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Insufficient memory resources',
            'available_mb', v_available_ram_mb - v_usage.total_memory_mb,
            'requested_mb', p_memory_mb,
            'total_capacity_mb', v_available_ram_mb
        );
    END IF;

    -- Check Storage
    IF (v_usage.total_storage_mb + p_storage_mb) > v_available_storage_mb THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Insufficient storage resources',
            'available_mb', v_available_storage_mb - v_usage.total_storage_mb,
            'requested_mb', p_storage_mb,
            'total_capacity_mb', v_available_storage_mb
        );
    END IF;

    RETURN json_build_object(
        'success', true,
        'available_cpu_pct', v_available_cpu_pct - v_usage.total_cpu_pct,
        'available_ram_mb', v_available_ram_mb - v_usage.total_memory_mb,
        'available_storage_mb', v_available_storage_mb - v_usage.total_storage_mb,
        'active_processes', v_usage.active_process_count
    );
END;
$$;

COMMENT ON FUNCTION public.can_start_process(UUID, INT, INT, INT) IS 'Validates whether a VM has sufficient CPU, RAM, and storage to start a new process. Returns JSON with success/error and available resources.';

-- 4.3: Complete a process (set status and actual_end_time)
CREATE OR REPLACE FUNCTION public.complete_process(
    p_process_id UUID,
    p_status VARCHAR DEFAULT 'completed'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_process RECORD;
BEGIN
    SELECT * INTO v_process
    FROM public.virtual_processes
    WHERE process_id = p_process_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Process not found');
    END IF;

    IF v_process.status != 'running' THEN
        RETURN json_build_object('success', false, 'error', 'Process is not in running state', 'current_status', v_process.status);
    END IF;

    UPDATE public.virtual_processes
    SET status = p_status,
        actual_end_time = now()
    WHERE process_id = p_process_id;

    RETURN json_build_object(
        'success', true,
        'process_id', p_process_id,
        'status', p_status,
        'machine_id', v_process.machine_id,
        'resources_freed', json_build_object(
            'cpu_pct', v_process.cpu_alloc_pct,
            'memory_mb', v_process.memory_alloc_mb,
            'storage_mb', v_process.storage_alloc_mb
        )
    );
END;
$$;

COMMENT ON FUNCTION public.complete_process(UUID, VARCHAR) IS 'Marks a running process as completed/terminated/failed and releases its resources.';

-- 4.4: Get all active processes for a machine
CREATE OR REPLACE FUNCTION public.get_machine_processes(p_machine_id UUID)
RETURNS TABLE (
    process_id UUID,
    program_name VARCHAR(255),
    program_type VARCHAR(50),
    cpu_alloc_pct INT,
    memory_alloc_mb INT,
    storage_alloc_mb INT,
    status VARCHAR(50),
    started_at TIMESTAMPTZ,
    expected_end_time TIMESTAMPTZ,
    actual_end_time TIMESTAMPTZ,
    process_metadata JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    RETURN QUERY
    SELECT
        vp.process_id,
        vpr.program_name,
        vpr.program_type,
        vp.cpu_alloc_pct,
        vp.memory_alloc_mb,
        vp.storage_alloc_mb,
        vp.status,
        vp.started_at,
        vp.expected_end_time,
        vp.actual_end_time,
        vp.process_metadata
    FROM public.virtual_processes vp
    JOIN public.virtual_programs vpr ON vpr.program_id = vp.program_id
    WHERE vp.machine_id = p_machine_id
    ORDER BY vp.started_at DESC;
END;
$$;

COMMENT ON FUNCTION public.get_machine_processes(UUID) IS 'Returns all processes (running and historical) for a given virtual machine.';

-- ==========================================
-- 5. RLS POLICIES
-- ==========================================

ALTER TABLE public.virtual_programs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.virtual_processes ENABLE ROW LEVEL SECURITY;

-- Service role full access
DROP POLICY IF EXISTS "service_manage_programs" ON public.virtual_programs;
CREATE POLICY "service_manage_programs"
    ON public.virtual_programs FOR ALL
    USING (auth.jwt()->>'role' = 'service_role')
    WITH CHECK (auth.jwt()->>'role' = 'service_role');

DROP POLICY IF EXISTS "service_manage_processes" ON public.virtual_processes;
CREATE POLICY "service_manage_processes"
    ON public.virtual_processes FOR ALL
    USING (auth.jwt()->>'role' = 'service_role')
    WITH CHECK (auth.jwt()->>'role' = 'service_role');

-- Players can view programs on machines they own
DROP POLICY IF EXISTS "players_view_own_programs" ON public.virtual_programs;
CREATE POLICY "players_view_own_programs"
    ON public.virtual_programs FOR SELECT
    TO authenticated
    USING (
        machine_id IN (
            SELECT vm.machine_id FROM public.virtual_machines vm
            WHERE vm.owner_identity = (
                SELECT ip_address FROM public.players WHERE id = auth.uid()
            )
        )
    );

-- Players can view processes on machines they own
DROP POLICY IF EXISTS "players_view_own_processes" ON public.virtual_processes;
CREATE POLICY "players_view_own_processes"
    ON public.virtual_processes FOR SELECT
    TO authenticated
    USING (
        machine_id IN (
            SELECT vm.machine_id FROM public.virtual_machines vm
            WHERE vm.owner_identity = (
                SELECT ip_address FROM public.players WHERE id = auth.uid()
            )
        )
    );

-- ==========================================
-- 6. GRANTS
-- ==========================================

GRANT ALL ON TABLE public.virtual_programs TO service_role, postgres;
GRANT ALL ON TABLE public.virtual_processes TO service_role, postgres;

GRANT SELECT ON TABLE public.virtual_programs TO authenticated;
GRANT SELECT ON TABLE public.virtual_processes TO authenticated;

GRANT EXECUTE ON FUNCTION public.calculate_vm_resource_usage(UUID) TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION public.can_start_process(UUID, INT, INT, INT) TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_process(UUID, VARCHAR) TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION public.get_machine_processes(UUID) TO service_role, authenticated;

COMMIT;