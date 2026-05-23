-- ======================================================================================
-- GENESIS 1.1: NETWORK ENCRYPTION LEVEL
-- ======================================================================================
-- Adds encryption_level to network_addresses with hard-locks for players (100) and sects (1000).
-- Includes RPC to calculate combined encryption between two IPs.
-- Designed to be strictly idempotent (re-runnable).
-- ======================================================================================

BEGIN;

-- ==========================================
-- 1. ADD ENCRYPTION LEVEL COLUMN
-- ==========================================

ALTER TABLE public.network_addresses
ADD COLUMN IF NOT EXISTS encryption_level INT NOT NULL DEFAULT 3;

COMMENT ON COLUMN public.network_addresses.encryption_level IS 'Encryption strength of the network endpoint. Hard-locked at 100 for players, 1000 for sects. Other entity types are freely updatable.';

-- ==========================================
-- 2. BACKFILL EXISTING SECT RECORDS
-- ==========================================

UPDATE public.network_addresses
SET encryption_level = 1000
WHERE entity_type = 'sects' AND encryption_level != 1000;

-- ==========================================
-- 3. TRIGGER: HARD-LOCK ENCRYPTION FOR PLAYERS & SECTS
-- ==========================================

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

-- ==========================================
-- 4. TRIGGER: UPDATE ENCRYPTION LEVEL ON VM HARDWARE CHANGE
-- ==========================================

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
    -- Get the VM's IP address
    SELECT ip_address INTO v_vm_ip
    FROM public.virtual_machines
    WHERE machine_id = NEW.machine_id;
    
    -- If VM has no IP, skip
    IF v_vm_ip IS NULL THEN
        RETURN NEW;
    END IF;
    
    -- Only proceed if this is a security chip being inserted/updated
    IF NEW.hardware_type = 'security_chip' THEN
        v_chip_id := NEW.catalog_id;
        
        -- Look up the encryption bonus from catalog
        SELECT encryption_bonus INTO v_encryption_bonus
        FROM public.catalog_security_chips
        WHERE id = v_chip_id;
        
        -- If chip found in catalog, calculate new encryption level
        IF v_encryption_bonus IS NOT NULL THEN
            v_new_encryption_level := 100 + v_encryption_bonus;
            
            -- Update the network_addresses encryption_level
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

-- ==========================================
-- 5. TRIGGER: UPDATE ENCRYPTION LEVEL ON VM IP ASSIGNMENT
-- ==========================================

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
    -- Only proceed if IP is being set/changed and is not null
    IF NEW.ip_address IS NULL OR (TG_OP = 'UPDATE' AND OLD.ip_address = NEW.ip_address) THEN
        RETURN NEW;
    END IF;
    
    -- Look for equipped security chip
    SELECT catalog_id INTO v_chip_id
    FROM public.virtual_machine_hardware
    WHERE machine_id = NEW.machine_id
      AND hardware_type = 'security_chip'
    LIMIT 1;
    
    -- If no security chip equipped, skip (leave default 100)
    IF v_chip_id IS NULL THEN
        RETURN NEW;
    END IF;
    
    -- Look up the encryption bonus from catalog
    SELECT encryption_bonus INTO v_encryption_bonus
    FROM public.catalog_security_chips
    WHERE id = v_chip_id;
    
    -- If chip found in catalog, calculate and update encryption level
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
-- 6. RPC: CALCULATE VM ENCRYPTION
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
    -- Get the VM's IP address
    SELECT ip_address INTO v_vm_ip
    FROM public.virtual_machines
    WHERE machine_id = p_machine_id;
    
    IF NOT FOUND OR v_vm_ip IS NULL THEN
        RAISE EXCEPTION 'Virtual machine % not found or has no IP address', p_machine_id;
    END IF;
    
    -- Get base encryption level from network_addresses
    SELECT encryption_level INTO v_base_encryption
    FROM public.network_addresses
    WHERE ip_address = v_vm_ip;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Network address % not found in registry', v_vm_ip;
    END IF;
    
    -- Look for equipped security chip
    SELECT catalog_id INTO v_chip_id
    FROM public.virtual_machine_hardware
    WHERE machine_id = p_machine_id
      AND hardware_type = 'security_chip'
    LIMIT 1;
    
    -- If security chip equipped, get its bonus
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

-- ==========================================
-- 6. RPC: CALCULATE COMBINED ENCRYPTION
-- ==========================================

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
-- 7. PERMISSIONS & GRANTS
-- ==========================================
GRANT EXECUTE ON FUNCTION public.calculate_vm_encryption(UUID) TO service_role, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.calculate_encryption(inet, inet) TO service_role, authenticated, anon;

COMMIT;