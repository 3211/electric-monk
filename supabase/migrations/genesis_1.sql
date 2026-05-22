-- ======================================================================================
-- GENESIS 1: VIRTUAL COMPUTERS, HARDWARE LINKS, FILES, AND LOGS
-- ======================================================================================

BEGIN;

-- ==========================================
-- 1. VIRTUAL MACHINES
-- ==========================================

CREATE TABLE IF NOT EXISTS public.virtual_machines (
    machine_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_identity_id UUID REFERENCES public.players(id) ON DELETE SET NULL,
    ip_address inet UNIQUE DEFAULT public.allocate_network_address('virtual_machines'),
    machine_name VARCHAR NOT NULL,
    case_id TEXT NOT NULL, 
    power_supply_id TEXT NOT NULL, 
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ==========================================
-- 2. VIRTUAL MACHINE HARDWARE LINKS
-- ==========================================

CREATE TABLE IF NOT EXISTS public.virtual_machine_hardware (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    machine_id UUID NOT NULL REFERENCES public.virtual_machines(machine_id) ON DELETE CASCADE,
    hardware_type VARCHAR NOT NULL,
    catalog_id TEXT NOT NULL, 
    slot_index INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ==========================================
-- 3. VIRTUAL FILES
-- ==========================================

CREATE TABLE IF NOT EXISTS public.virtual_files (
    file_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    machine_id UUID NOT NULL REFERENCES public.virtual_machines(machine_id) ON DELETE CASCADE,
    file_path VARCHAR NOT NULL,
    file_name VARCHAR NOT NULL,
    file_size_mb INT NOT NULL DEFAULT 0,
    file_content TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ==========================================
-- 4. VIRTUAL LOGS
-- ==========================================

CREATE TABLE IF NOT EXISTS public.virtual_logs (
    log_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    machine_id UUID NOT NULL REFERENCES public.virtual_machines(machine_id) ON DELETE CASCADE,
    timestamp TIMESTAMPTZ DEFAULT now(),
    source_ip inet NOT NULL,
    action_type VARCHAR NOT NULL,
    details TEXT,
    is_spoofed BOOLEAN DEFAULT false,
    trace_resistance_applied INT DEFAULT 0
);

-- ==========================================
-- 5. INDEXES
-- ==========================================

CREATE INDEX IF NOT EXISTS idx_vmh_machine ON public.virtual_machine_hardware(machine_id, hardware_type);
CREATE INDEX IF NOT EXISTS idx_vfiles_machine_path ON public.virtual_files(machine_id, file_path);
CREATE INDEX IF NOT EXISTS idx_vlogs_machine_time ON public.virtual_logs(machine_id, timestamp DESC);

-- ==========================================
-- 6. PERMISSIONS & GRANTS
-- ==========================================

ALTER TABLE public.virtual_machines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.virtual_machine_hardware ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.virtual_files ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.virtual_logs ENABLE ROW LEVEL SECURITY;

GRANT ALL ON TABLE public.virtual_machines TO service_role, postgres;
GRANT ALL ON TABLE public.virtual_machine_hardware TO service_role, postgres;
GRANT ALL ON TABLE public.virtual_files TO service_role, postgres;
GRANT ALL ON TABLE public.virtual_logs TO service_role, postgres;

COMMIT;