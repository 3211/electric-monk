-- ======================================================================================
-- GENESIS 1: VIRTUAL COMPUTERS, HARDWARE (FLATTENED), FILES, AND NETWORK ENCRYPTION
-- ======================================================================================
-- SUPABASE AI / AGENT DIRECTIVE:
-- This is GENESIS_1. Rewritten to use IP-based ownership, flattened hardware columns,
-- access control arrays (admins/users), and auto-generated passwords.
-- Designed to be strictly idempotent (re-runnable).
-- ======================================================================================

BEGIN;

-- ==========================================
-- 1. DROP OBSOLETE TABLES (CLEAN SLATE)
-- ==========================================

DROP TABLE IF EXISTS public.virtual_machine_hardware CASCADE;

-- ==========================================
-- 2. PASSWORD GENERATION HELPER
-- ==========================================

CREATE OR REPLACE FUNCTION public.generate_secure_password()
RETURNS TEXT
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    chars TEXT := 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*';
    result TEXT := '';
    i INT;
BEGIN
    FOR i IN 1..16 LOOP
        result := result || substr(chars, floor(random() * length(chars) + 1)::INT, 1);
    END LOOP;
    RETURN result;
END;
$$;

-- ==========================================
-- 3. VIRTUAL MACHINES (FLATTENED HARDWARE)
-- ==========================================

CREATE TABLE IF NOT EXISTS public.virtual_machines (
    machine_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_identity inet NOT NULL,
    ip_address inet UNIQUE DEFAULT public.allocate_network_address('virtual_machines'),
    machine_name VARCHAR NOT NULL,

    -- Flattened hardware references (catalog IDs)
    cpu_id TEXT NOT NULL,
    memory_id TEXT NOT NULL,
    storage_id TEXT NOT NULL,
    network_card_id TEXT NOT NULL,
    case_id TEXT NOT NULL,
    power_supply_id TEXT NOT NULL,
    security_chip_id TEXT,

    -- Access control
    admins inet[] NOT NULL DEFAULT '{}',
    users inet[] NOT NULL DEFAULT '{}',

    -- Passwords (plaintext for gameplay)
    admin_password TEXT NOT NULL DEFAULT public.generate_secure_password(),
    user_password TEXT NOT NULL DEFAULT public.generate_secure_password(),

    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

COMMENT ON TABLE public.virtual_machines IS 'In-game virtual computers. Ownership, hardware, and access control are all stored flat on the row.';
COMMENT ON COLUMN public.virtual_machines.owner_identity IS 'IP address of the owning entity (player, sect, or another VM).';
COMMENT ON COLUMN public.virtual_machines.ip_address IS 'Unique public IP of this virtual computer (base encryption 100 + security chip bonus).';
COMMENT ON COLUMN public.virtual_machines.admins IS 'Array of IP addresses with admin-level access. Owner IP auto-added on creation.';
COMMENT ON COLUMN public.virtual_machines.users IS 'Array of IP addresses with user-level access. Owner IP auto-added on creation.';
COMMENT ON COLUMN public.virtual_machines.admin_password IS 'Auto-generated 16-char password for admin login (plaintext for gameplay).';
COMMENT ON COLUMN public.virtual_machines.user_password IS 'Auto-generated 16-char password for user login (plaintext for gameplay).';

-- ==========================================
-- 4. VIRTUAL FILES (IP-AWARE)
-- ==========================================

CREATE TABLE IF NOT EXISTS public.virtual_files (
    file_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    machine_id UUID NOT NULL REFERENCES public.virtual_machines(machine_id) ON DELETE CASCADE,
    owner_identity inet,
    file_path VARCHAR NOT NULL,
    file_name VARCHAR NOT NULL,
    file_size_mb INT NOT NULL DEFAULT 0,
    file_content TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT now()
);

COMMENT ON TABLE public.virtual_files IS 'Filesystem for virtual_machines. owner_identity tracks which IP created the file.';
COMMENT ON COLUMN public.virtual_files.owner_identity IS 'IP address of the entity that created/owns this file.';

-- ==========================================
-- 5. VIRTUAL LOGS
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

COMMENT ON TABLE public.virtual_logs IS 'Audit trail for actions performed on or by virtual machines.';

-- ==========================================
-- 6. NETWORK ENCRYPTION SYSTEM
-- ==========================================

-- Add encryption level column to network_addresses (if not already present)
ALTER TABLE public.network_addresses
ADD COLUMN IF NOT EXISTS encryption_level INT NOT NULL DEFAULT 3;

COMMENT ON COLUMN public.network_addresses.encryption_level IS 'Encryption strength of the network endpoint. Hard-locked at 100 for players, 1000 for sects. Other entity types are freely updatable.';

-- Backfill existing sect records
UPDATE public.network_addresses
SET encryption_level = 1000
WHERE entity_type = 'sects' AND encryption_level != 1000;

-- Trigger: Hard-lock encryption for players & sects
CREATE OR REPLACE FUNCTION public.enforce_encryption_level()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.entity_type = 'players' THEN
            NEW.encryption_level := 100;
        ELSIF NEW.entity_type = 'sects' THEN
            NEW.encryption_level := 1000;
        END IF;
    END IF;

    IF TG_OP = 'UPDATE' THEN
        IF NEW.entity_type = 'players' THEN
            NEW.encryption_level := 100;
        ELSIF NEW.entity_type = 'sects' THEN
            NEW.encryption_level := 1000;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_encryption_level_trigger ON public.network_addresses;
CREATE TRIGGER enforce_encryption_level_trigger
    BEFORE INSERT OR UPDATE ON public.network_addresses
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_encryption_level();

-- Trigger: Update encryption level when VM security chip changes or IP is assigned
CREATE OR REPLACE FUNCTION public.update_vm_encryption_level()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_encryption_bonus INT;
    v_new_encryption_level INT;
    v_chip_id TEXT;
BEGIN
    -- Determine which security_chip_id to use
    IF TG_OP = 'DELETE' THEN
        v_chip_id := NULL;
    ELSE
        v_chip_id := NEW.security_chip_id;
    END IF;

    -- Only proceed if IP is set
    IF (TG_OP = 'DELETE' AND OLD.ip_address IS NULL)
       OR (TG_OP != 'DELETE' AND NEW.ip_address IS NULL)
       OR (TG_OP = 'UPDATE' AND OLD.security_chip_id IS NOT DISTINCT FROM NEW.security_chip_id AND OLD.ip_address IS NOT DISTINCT FROM NEW.ip_address) THEN
        IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
    END IF;

    -- Get encryption bonus from security chip
    IF v_chip_id IS NOT NULL THEN
        SELECT encryption_bonus INTO v_encryption_bonus
        FROM public.catalog_security_chips
        WHERE id = v_chip_id;
    END IF;

    v_new_encryption_level := 100 + COALESCE(v_encryption_bonus, 0);

    -- Update network_addresses
    IF TG_OP = 'DELETE' THEN
        UPDATE public.network_addresses
        SET encryption_level = v_new_encryption_level
        WHERE ip_address = OLD.ip_address;
        RETURN OLD;
    ELSE
        UPDATE public.network_addresses
        SET encryption_level = v_new_encryption_level
        WHERE ip_address = NEW.ip_address;
        RETURN NEW;
    END IF;
END;
$$;

DROP TRIGGER IF EXISTS update_vm_encryption_trigger ON public.virtual_machines;
CREATE TRIGGER update_vm_encryption_trigger
    AFTER INSERT OR UPDATE OF security_chip_id, ip_address ON public.virtual_machines
    FOR EACH ROW
    EXECUTE FUNCTION public.update_vm_encryption_level();

-- ==========================================
-- 7. ENCRYPTION RPC FUNCTIONS
-- ==========================================

CREATE OR REPLACE FUNCTION public.calculate_vm_encryption(p_machine_id UUID)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_vm_ip inet;
    v_base_encryption INT;
    v_chip_id TEXT;
    v_encryption_bonus INT;
    v_total_encryption INT;
BEGIN
    SELECT ip_address, security_chip_id INTO v_vm_ip, v_chip_id
    FROM public.virtual_machines
    WHERE machine_id = p_machine_id;

    IF NOT FOUND OR v_vm_ip IS NULL THEN
        RAISE EXCEPTION 'Virtual machine % not found or has no IP address', p_machine_id;
    END IF;

    SELECT encryption_level INTO v_base_encryption
    FROM public.network_addresses
    WHERE ip_address = v_vm_ip;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Network address % not found in registry', v_vm_ip;
    END IF;

    IF v_chip_id IS NOT NULL THEN
        SELECT encryption_bonus INTO v_encryption_bonus
        FROM public.catalog_security_chips
        WHERE id = v_chip_id;

        IF v_encryption_bonus IS NOT NULL THEN
            v_total_encryption := v_base_encryption + v_encryption_bonus;
        ELSE
            v_total_encryption := v_base_encryption;
        END IF;
    ELSE
        v_total_encryption := v_base_encryption;
    END IF;

    RETURN v_total_encryption;
END;
$$;

CREATE OR REPLACE FUNCTION public.calculate_encryption(p_ip1 inet, p_ip2 inet)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_level1 INT;
    v_level2 INT;
BEGIN
    SELECT encryption_level INTO v_level1
    FROM public.network_addresses
    WHERE ip_address = p_ip1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'IP address % not found in network registry', p_ip1;
    END IF;

    SELECT encryption_level INTO v_level2
    FROM public.network_addresses
    WHERE ip_address = p_ip2;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'IP address % not found in network registry', p_ip2;
    END IF;

    RETURN v_level1 * v_level2;
END;
$$;

-- ==========================================
-- 8. INDEXES
-- ==========================================

CREATE INDEX IF NOT EXISTS idx_vm_owner ON public.virtual_machines(owner_identity);
CREATE INDEX IF NOT EXISTS idx_vm_ip ON public.virtual_machines(ip_address);
CREATE INDEX IF NOT EXISTS idx_vm_admins ON public.virtual_machines USING gin(admins);
CREATE INDEX IF NOT EXISTS idx_vm_users ON public.virtual_machines USING gin(users);
CREATE INDEX IF NOT EXISTS idx_vfiles_machine_path ON public.virtual_files(machine_id, file_path);
CREATE INDEX IF NOT EXISTS idx_vfiles_owner ON public.virtual_files(owner_identity);
CREATE INDEX IF NOT EXISTS idx_vlogs_machine_time ON public.virtual_logs(machine_id, timestamp DESC);

-- ==========================================
-- 9. RLS POLICIES
-- ==========================================

ALTER TABLE public.virtual_machines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.virtual_files ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.virtual_logs ENABLE ROW LEVEL SECURITY;

-- Virtual Machines: Service role manages all; players can view machines they own or have access to
DROP POLICY IF EXISTS "Service role manages VMs" ON public.virtual_machines;
CREATE POLICY "Service role manages VMs"
    ON public.virtual_machines FOR ALL
    USING (auth.jwt()->>'role' = 'service_role')
    WITH CHECK (auth.jwt()->>'role' = 'service_role');

DROP POLICY IF EXISTS "Players can view own VMs" ON public.virtual_machines;
CREATE POLICY "Players can view own VMs"
    ON public.virtual_machines FOR SELECT
    TO authenticated
    USING (
        owner_identity IN (
            SELECT ip_address FROM public.players WHERE id = auth.uid()
        )
        OR owner_identity::text IN (
            SELECT ip_address::text FROM public.players WHERE id = auth.uid()
        )
    );

-- Virtual Files: Service role manages all
DROP POLICY IF EXISTS "Service role manages files" ON public.virtual_files;
CREATE POLICY "Service role manages files"
    ON public.virtual_files FOR ALL
    USING (auth.jwt()->>'role' = 'service_role')
    WITH CHECK (auth.jwt()->>'role' = 'service_role');

-- Virtual Logs: Service role manages all
DROP POLICY IF EXISTS "Service role manages logs" ON public.virtual_logs;
CREATE POLICY "Service role manages logs"
    ON public.virtual_logs FOR ALL
    USING (auth.jwt()->>'role' = 'service_role')
    WITH CHECK (auth.jwt()->>'role' = 'service_role');

-- ==========================================
-- 10. PERMISSIONS & GRANTS
-- ==========================================

-- Table Access
GRANT ALL ON TABLE public.virtual_machines TO service_role, postgres;
GRANT ALL ON TABLE public.virtual_files TO service_role, postgres;
GRANT ALL ON TABLE public.virtual_logs TO service_role, postgres;

GRANT SELECT ON TABLE public.virtual_machines TO authenticated;
GRANT SELECT ON TABLE public.virtual_files TO authenticated;
GRANT SELECT ON TABLE public.virtual_logs TO authenticated;

-- Function Execution
GRANT EXECUTE ON FUNCTION public.generate_secure_password() TO service_role, postgres;
GRANT EXECUTE ON FUNCTION public.calculate_vm_encryption(UUID) TO service_role, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.calculate_encryption(inet, inet) TO service_role, authenticated, anon;

COMMIT;