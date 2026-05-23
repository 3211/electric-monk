-- ======================================================================================
-- GENESIS 1: VIRTUAL COMPUTERS, HARDWARE LINKS, FILES, AND NETWORK ENCRYPTION
-- ======================================================================================
-- SUPABASE AI / AGENT DIRECTIVE:
-- This is GENESIS_1. It creates virtual machine infrastructure and encryption systems.
-- Designed to be strictly idempotent (re-runnable).
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
-- 4. NETWORK ENCRYPTION SYSTEM
-- ==========================================

-- Add encryption level column to network_addresses
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

-- Trigger: Update encryption level on VM hardware change
CREATE OR REPLACE FUNCTION public.update_vm_encryption_level()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_vm_ip inet;
    v_chip_id TEXT;
    v_encryption_bonus INT;
    v_new_encryption_level INT;
BEGIN
    SELECT ip_address INTO v_vm_ip
    FROM public.virtual_machines
    WHERE machine_id = NEW.machine_id;
    
    IF v_vm_ip IS NULL THEN
        RETURN NEW;
    END IF;
    
    IF NEW.hardware_type = 'security_chip' THEN
        v_chip_id := NEW.catalog_id;
        
        SELECT encryption_bonus INTO v_encryption_bonus
        FROM public.catalog_security_chips
        WHERE id = v_chip_id;
        
        IF v_encryption_bonus IS NOT NULL THEN
            v_new_encryption_level := 100 + v_encryption_bonus;
            
            UPDATE public.network_addresses
            SET encryption_level = v_new_encryption_level
            WHERE ip_address = v_vm_ip;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS update_vm_encryption_trigger ON public.virtual_machine_hardware;
CREATE TRIGGER update_vm_encryption_trigger
    AFTER INSERT OR UPDATE ON public.virtual_machine_hardware
    FOR EACH ROW
    EXECUTE FUNCTION public.update_vm_encryption_level();

-- Trigger: Update encryption level on VM IP assignment
CREATE OR REPLACE FUNCTION public.update_vm_encryption_on_ip_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_chip_id TEXT;
    v_encryption_bonus INT;
    v_new_encryption_level INT;
BEGIN
    IF NEW.ip_address IS NULL OR (TG_OP = 'UPDATE' AND OLD.ip_address = NEW.ip_address) THEN
        RETURN NEW;
    END IF;
    
    SELECT catalog_id INTO v_chip_id
    FROM public.virtual_machine_hardware
    WHERE machine_id = NEW.machine_id
      AND hardware_type = 'security_chip'
    LIMIT 1;
    
    IF v_chip_id IS NULL THEN
        RETURN NEW;
    END IF;
    
    SELECT encryption_bonus INTO v_encryption_bonus
    FROM public.catalog_security_chips
    WHERE id = v_chip_id;
    
    IF v_encryption_bonus IS NOT NULL THEN
        v_new_encryption_level := 100 + v_encryption_bonus;
        
        UPDATE public.network_addresses
        SET encryption_level = v_new_encryption_level
        WHERE ip_address = NEW.ip_address;
    END IF;
    
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS update_vm_encryption_on_ip_trigger ON public.virtual_machines;
CREATE TRIGGER update_vm_encryption_on_ip_trigger
    AFTER INSERT OR UPDATE ON public.virtual_machines
    FOR EACH ROW
    EXECUTE FUNCTION public.update_vm_encryption_on_ip_change();

-- ==========================================
-- 5. ENCRYPTION RPC FUNCTIONS
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
    SELECT ip_address INTO v_vm_ip
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
    
    SELECT catalog_id INTO v_chip_id
    FROM public.virtual_machine_hardware
    WHERE machine_id = p_machine_id
      AND hardware_type = 'security_chip'
    LIMIT 1;
    
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
-- 6. INDEXES
-- ==========================================

CREATE INDEX IF NOT EXISTS idx_vmh_machine ON public.virtual_machine_hardware(machine_id, hardware_type);
CREATE INDEX IF NOT EXISTS idx_vfiles_machine_path ON public.virtual_files(machine_id, file_path);

-- ==========================================
-- 7. RLS POLICIES
-- ==========================================

ALTER TABLE public.virtual_machines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.virtual_machine_hardware ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.virtual_files ENABLE ROW LEVEL SECURITY;

-- ==========================================
-- 8. PERMISSIONS & GRANTS
-- ==========================================

-- Table Access
GRANT ALL ON TABLE public.virtual_machines TO service_role, postgres;
GRANT ALL ON TABLE public.virtual_machine_hardware TO service_role, postgres;
GRANT ALL ON TABLE public.virtual_files TO service_role, postgres;

-- Function Execution
GRANT EXECUTE ON FUNCTION public.calculate_vm_encryption(UUID) TO service_role, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.calculate_encryption(inet, inet) TO service_role, authenticated, anon;

COMMIT;