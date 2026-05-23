-- ======================================================================================
-- REVELATIONS 1: HARDWARE CATALOG & SHOPS SEED DATA
-- ======================================================================================

BEGIN;

-- ==========================================
-- 1. HARDWARE SHOPS
-- ==========================================

CREATE TABLE IF NOT EXISTS public.hardware_shops (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    description TEXT
);

INSERT INTO public.hardware_shops (id, name, description)
VALUES
    ('public_hub', 'The Public Hub', 'Standard commercial hardware accessible to anyone.'),
    ('gilded_market', 'Gilded Market', 'High-end, premium, and highly efficient hardware.'),
    ('shadow_node', 'Shadow Node', 'Black market tech focused on stealth and brute force.')
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description;

-- ==========================================
-- 2. HARDWARE: CPUS
-- ==========================================

CREATE TABLE IF NOT EXISTS public.catalog_cpus (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    base_price INT NOT NULL,
    cores INT NOT NULL,
    clock_speed_mhz INT NOT NULL,
    power_draw_watts INT NOT NULL,
    available_in_shops TEXT[] NOT NULL DEFAULT '{}'
);

INSERT INTO public.catalog_cpus (id, name, base_price, cores, clock_speed_mhz, power_draw_watts, available_in_shops)
VALUES
    ('cpu_basic', 'Generic Single-Core', 100, 1, 1000, 50, ARRAY['public_hub']),
    ('cpu_dual', 'Commercial Dual-Core', 350, 2, 2400, 90, ARRAY['public_hub', 'gilded_market']),
    ('cpu_quantum', 'Gilded Quantum Processor', 1500, 8, 5000, 200, ARRAY['gilded_market']),
    ('cpu_overclocked', 'Jury-rigged Hexa-Core', 800, 6, 4200, 300, ARRAY['shadow_node'])
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name, base_price = EXCLUDED.base_price, cores = EXCLUDED.cores, 
    clock_speed_mhz = EXCLUDED.clock_speed_mhz, power_draw_watts = EXCLUDED.power_draw_watts, 
    available_in_shops = EXCLUDED.available_in_shops;

-- ==========================================
-- 3. HARDWARE: MEMORY
-- ==========================================

CREATE TABLE IF NOT EXISTS public.catalog_memory (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    base_price INT NOT NULL,
    capacity_gb INT NOT NULL,
    speed_mhz INT NOT NULL,
    power_draw_watts INT NOT NULL,
    available_in_shops TEXT[] NOT NULL DEFAULT '{}'
);

INSERT INTO public.catalog_memory (id, name, base_price, capacity_gb, speed_mhz, power_draw_watts, available_in_shops)
VALUES
    ('ram_2gb', 'Budget 2GB Stick', 50, 2, 1333, 10, ARRAY['public_hub']),
    ('ram_8gb', 'Standard 8GB Module', 180, 8, 2400, 20, ARRAY['public_hub', 'gilded_market']),
    ('ram_32gb_stealth', 'Low-Emission 32GB', 900, 32, 3200, 15, ARRAY['shadow_node'])
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name, base_price = EXCLUDED.base_price, capacity_gb = EXCLUDED.capacity_gb, 
    speed_mhz = EXCLUDED.speed_mhz, power_draw_watts = EXCLUDED.power_draw_watts, 
    available_in_shops = EXCLUDED.available_in_shops;

-- ==========================================
-- 4. HARDWARE: STORAGE
-- ==========================================

CREATE TABLE IF NOT EXISTS public.catalog_storage (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    base_price INT NOT NULL,
    capacity_mb INT NOT NULL,
    read_speed_mbps INT NOT NULL,
    write_speed_mbps INT NOT NULL,
    power_draw_watts INT NOT NULL,
    available_in_shops TEXT[] NOT NULL DEFAULT '{}'
);

INSERT INTO public.catalog_storage (id, name, base_price, capacity_mb, read_speed_mbps, write_speed_mbps, power_draw_watts, available_in_shops)
VALUES
    ('hdd_500', 'Rusty 500MB Platter', 30, 500, 50, 30, 15, ARRAY['public_hub']),
    ('ssd_2000', 'Commercial 2GB SSD', 150, 2000, 500, 400, 5, ARRAY['public_hub', 'gilded_market']),
    ('nvme_10000', 'Gilded 10GB Crystal Matrix', 1200, 10000, 3500, 3000, 10, ARRAY['gilded_market'])
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name, base_price = EXCLUDED.base_price, capacity_mb = EXCLUDED.capacity_mb, 
    read_speed_mbps = EXCLUDED.read_speed_mbps, write_speed_mbps = EXCLUDED.write_speed_mbps, 
    power_draw_watts = EXCLUDED.power_draw_watts, available_in_shops = EXCLUDED.available_in_shops;

-- ==========================================
-- 5. HARDWARE: NETWORK CARDS
-- ==========================================

CREATE TABLE IF NOT EXISTS public.catalog_network_cards (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    base_price INT NOT NULL,
    bandwidth_mbps INT NOT NULL,
    trace_resistance INT NOT NULL,
    power_draw_watts INT NOT NULL,
    available_in_shops TEXT[] NOT NULL DEFAULT '{}'
);

COMMENT ON COLUMN public.catalog_network_cards.trace_resistance IS 'Reduces the speed at which hostile tracing algorithms lock onto the user IP.';

INSERT INTO public.catalog_network_cards (id, name, base_price, bandwidth_mbps, trace_resistance, power_draw_watts, available_in_shops)
VALUES
    ('nic_basic', 'Basic Ethernet Adapter', 40, 100, 0, 5, ARRAY['public_hub']),
    ('nic_gilded', 'Gilded Fiber Node', 400, 1000, 10, 15, ARRAY['gilded_market']),
    ('nic_ghost', 'Ghost Protocol Router', 850, 300, 50, 25, ARRAY['shadow_node'])
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name, base_price = EXCLUDED.base_price, bandwidth_mbps = EXCLUDED.bandwidth_mbps, 
    trace_resistance = EXCLUDED.trace_resistance, power_draw_watts = EXCLUDED.power_draw_watts, 
    available_in_shops = EXCLUDED.available_in_shops;

-- ==========================================
-- 5.5 HARDWARE: SECURITY CHIPS
-- ==========================================

CREATE TABLE IF NOT EXISTS public.catalog_security_chips (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    base_price INT NOT NULL,
    encryption_bonus INT NOT NULL,
    power_draw_watts INT NOT NULL,
    available_in_shops TEXT[] NOT NULL DEFAULT '{}'
);

INSERT INTO public.catalog_security_chips (id, name, base_price, encryption_bonus, power_draw_watts, available_in_shops)
VALUES
    ('chip_basic', 'Basic Encryption Module', 200, 50, 5, ARRAY['public_hub']),
    ('chip_gilded', 'Gilded Cipher Core', 1200, 250, 15, ARRAY['gilded_market']),
    ('chip_shadow', 'Shadow Decryption Barrier', 2500, 500, 30, ARRAY['shadow_node'])
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name, base_price = EXCLUDED.base_price, encryption_bonus = EXCLUDED.encryption_bonus, 
    power_draw_watts = EXCLUDED.power_draw_watts, available_in_shops = EXCLUDED.available_in_shops;


-- ==========================================
-- 6. HARDWARE: CASES / CHASSIS
-- ==========================================

CREATE TABLE IF NOT EXISTS public.catalog_cases (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    base_price INT NOT NULL,
    max_expansion_slots INT NOT NULL,
    available_in_shops TEXT[] NOT NULL DEFAULT '{}'
);

INSERT INTO public.catalog_cases (id, name, base_price, max_expansion_slots, available_in_shops)
VALUES
    ('case_tower', 'Old Beige Tower', 60, 2, ARRAY['public_hub']),
    ('case_server', 'Rackmount Server Chassis', 300, 6, ARRAY['public_hub', 'gilded_market']),
    ('case_mainframe', 'Gilded Monolith', 2500, 12, ARRAY['gilded_market'])
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name, base_price = EXCLUDED.base_price, max_expansion_slots = EXCLUDED.max_expansion_slots, 
    available_in_shops = EXCLUDED.available_in_shops;

-- ==========================================
-- 7. HARDWARE: POWER SUPPLIES
-- ==========================================

CREATE TABLE IF NOT EXISTS public.catalog_power_supplies (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    base_price INT NOT NULL,
    max_output_watts INT NOT NULL,
    available_in_shops TEXT[] NOT NULL DEFAULT '{}'
);

INSERT INTO public.catalog_power_supplies (id, name, base_price, max_output_watts, available_in_shops)
VALUES
    ('psu_budget', 'Budget 300W PSU', 40, 300, ARRAY['public_hub']),
    ('psu_standard', 'Standard 600W PSU', 90, 600, ARRAY['public_hub', 'gilded_market']),
    ('psu_industrial', 'Industrial 1200W PSU', 250, 1200, ARRAY['gilded_market', 'shadow_node'])
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name, base_price = EXCLUDED.base_price, max_output_watts = EXCLUDED.max_output_watts, 
    available_in_shops = EXCLUDED.available_in_shops;

-- ==========================================
-- 8. RLS POLICIES (All Catalogs are Read-Only for Players)
-- ==========================================

ALTER TABLE public.hardware_shops ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalog_cpus ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalog_memory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalog_storage ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalog_network_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalog_cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalog_power_supplies ENABLE ROW LEVEL SECURITY;

DO $$ 
DECLARE
    t_name text;
BEGIN
-- Update the array in step 8 to include the new table:
    FOR t_name IN 
        SELECT unnest(ARRAY['hardware_shops', 'catalog_cpus', 'catalog_memory', 'catalog_storage', 'catalog_network_cards', 'catalog_cases', 'catalog_power_supplies', 'catalog_security_chips']) 
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS "Public Read Access" ON public.%I;', t_name);
        EXECUTE format('CREATE POLICY "Public Read Access" ON public.%I FOR SELECT USING (true);', t_name);
        EXECUTE format('DROP POLICY IF EXISTS "Service Role Access" ON public.%I;', t_name);
        EXECUTE format('CREATE POLICY "Service Role Access" ON public.%I FOR ALL USING (auth.jwt()->>''role'' = ''service_role'');', t_name);
    END LOOP;
END $$;
-- yes run and enable rls if asked
COMMIT;