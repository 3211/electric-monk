// Supabase Edge Function: assign-starter-system
// Phase 2 Onboarding — checks if the authenticated player has a virtual computer.
// If not, provisions the lowest-tier hardware from the public catalogs
// and creates a starter machine for the player's faction.
//
// SECURITY: User identity derived from JWT Authorization header only.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import postgres from "https://deno.land/x/postgresjs@v3.3.4/mod.js"

const dbUrl = Deno.env.get("SUPABASE_DB_URL")
if (!dbUrl) throw new Error("SUPABASE_DB_URL is required")

const sql = postgres(dbUrl)

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

function extractUserIdFromAuthHeader(req: Request): string {
  const authHeader = req.headers.get("Authorization")
  if (!authHeader) throw new Error("Missing Authorization header")

  const parts = authHeader.split(" ")
  if (parts.length !== 2 || parts[0].toLowerCase() !== "bearer") {
    throw new Error("Invalid Authorization header format. Expected: Bearer <token>")
  }

  const token = parts[1]
  try {
    const payload = token.split(".")[1]
    const decoded = JSON.parse(atob(payload))
    const sub = decoded.sub
    if (!sub || typeof sub !== "string") throw new Error("JWT missing sub claim")
    return sub
  } catch (e) {
    if (e instanceof Error && e.message.startsWith("JWT missing")) throw e
    throw new Error("Failed to parse JWT token. Ensure you are authenticated.")
  }
}

// ── Types ──

interface CatalogHardware {
  id: string
  name: string
  base_price: number
}

interface ProvisionedSystem {
  machine_id: string
  machine_name: string
  ip_address: string
  cpu: CatalogHardware
  memory: CatalogHardware
  storage: CatalogHardware
  nic: CatalogHardware
  security_chip: CatalogHardware | null
  case: CatalogHardware
  psu: CatalogHardware
  total_power_draw: number
  was_newly_created: boolean
}

// ── Main Handler ──

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {
    if (req.method !== "POST") {
      throw new Error("Method not allowed")
    }

    const authenticatedUserId = extractUserIdFromAuthHeader(req)

    // ── Step 1: Check if player already has a virtual machine ──
    const existingVms = await sql`
      SELECT machine_id, machine_name, ip_address::text as ip_address
      FROM virtual_machines
      WHERE owner_identity_id = ${authenticatedUserId}
      ORDER BY created_at ASC
      LIMIT 1
    `

    if (existingVms.length > 0) {
      // Player already has a VM — fetch its hardware and return
      const vm = existingVms[0]

      const hardware = await sql`
        SELECT vmh.hardware_type, vmh.catalog_id
        FROM virtual_machine_hardware vmh
        WHERE vmh.machine_id = ${vm.machine_id}
      `

      // Map hardware types to catalog IDs
      const hwMap: Record<string, string> = {}
      for (const hw of hardware) {
        hwMap[hw.hardware_type] = hw.catalog_id
      }

      // Fetch names from catalogs
      const cpu = await sql`SELECT id, name, base_price FROM catalog_cpus WHERE id = ${hwMap["cpu"] || ""}`.then(r => r[0])
      const mem = await sql`SELECT id, name, base_price FROM catalog_memory WHERE id = ${hwMap["memory"] || ""}`.then(r => r[0])
      const sto = await sql`SELECT id, name, base_price FROM catalog_storage WHERE id = ${hwMap["storage"] || ""}`.then(r => r[0])
      const nic = await sql`SELECT id, name, base_price FROM catalog_network_cards WHERE id = ${hwMap["network"] || ""}`.then(r => r[0])
      const chip = hwMap["security_chip"]
        ? await sql`SELECT id, name, base_price FROM catalog_security_chips WHERE id = ${hwMap["security_chip"]}`.then(r => r[0])
        : null

      const vmRec = await sql`SELECT case_id, power_supply_id FROM virtual_machines WHERE machine_id = ${vm.machine_id}`.then(r => r[0])
      const caseHw = await sql`SELECT id, name, base_price FROM catalog_cases WHERE id = ${vmRec.case_id}`.then(r => r[0])
      const psu = await sql`SELECT id, name, base_price FROM catalog_power_supplies WHERE id = ${vmRec.power_supply_id}`.then(r => r[0])

      return new Response(JSON.stringify({
        success: true,
        was_newly_created: false,
        system: {
          machine_id: vm.machine_id,
          machine_name: vm.machine_name,
          ip_address: vm.ip_address,
          cpu: cpu || null,
          memory: mem || null,
          storage: sto || null,
          nic: nic || null,
          security_chip: chip || null,
          case: caseHw || null,
          psu: psu || null,
        },
      }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    // ── Step 2: No VM exists — provision the lowest-tier starter system ──

    // Fetch lowest-tier hardware from each catalog
    // Lowest = cheapest (sorted by base_price ASC, limit 1)

    const lowestCpu = await sql`
      SELECT id, name, base_price, cores, clock_speed_mhz, power_draw_watts
      FROM catalog_cpus
      WHERE 'public_hub' = ANY(available_in_shops)
      ORDER BY base_price ASC LIMIT 1
    `.then(r => r[0])

    const lowestMemory = await sql`
      SELECT id, name, base_price, capacity_gb, speed_mhz, power_draw_watts
      FROM catalog_memory
      WHERE 'public_hub' = ANY(available_in_shops)
      ORDER BY base_price ASC LIMIT 1
    `.then(r => r[0])

    const lowestStorage = await sql`
      SELECT id, name, base_price, capacity_mb, read_speed_mbps, write_speed_mbps, power_draw_watts
      FROM catalog_storage
      WHERE 'public_hub' = ANY(available_in_shops)
      ORDER BY base_price ASC LIMIT 1
    `.then(r => r[0])

    const lowestNic = await sql`
      SELECT id, name, base_price, bandwidth_mbps, trace_resistance, power_draw_watts
      FROM catalog_network_cards
      WHERE 'public_hub' = ANY(available_in_shops)
      ORDER BY base_price ASC LIMIT 1
    `.then(r => r[0])

    const lowestCase = await sql`
      SELECT id, name, base_price, max_expansion_slots
      FROM catalog_cases
      WHERE 'public_hub' = ANY(available_in_shops)
      ORDER BY base_price ASC LIMIT 1
    `.then(r => r[0])

    const lowestPsu = await sql`
      SELECT id, name, base_price, max_output_watts
      FROM catalog_power_supplies
      WHERE 'public_hub' = ANY(available_in_shops)
      ORDER BY base_price ASC LIMIT 1
    `.then(r => r[0])

    // Security chip is optional at starter tier — fetch cheapest for future reference
    // but only install if it fits within PSU budget
    const lowestChip = await sql`
      SELECT id, name, base_price, encryption_bonus, power_draw_watts
      FROM catalog_security_chips
      WHERE 'public_hub' = ANY(available_in_shops)
      ORDER BY base_price ASC LIMIT 1
    `.then(r => r[0])

    if (!lowestCpu || !lowestMemory || !lowestStorage || !lowestNic || !lowestCase || !lowestPsu) {
      throw new Error("Hardware catalog is incomplete — missing required starter components")
    }

    // Calculate total power draw
    const totalPowerDraw =
      (lowestCpu.power_draw_watts || 0) +
      (lowestMemory.power_draw_watts || 0) +
      (lowestStorage.power_draw_watts || 0) +
      (lowestNic.power_draw_watts || 0) +
      (lowestChip?.power_draw_watts || 0)

    if (totalPowerDraw > (lowestPsu.max_output_watts || 0)) {
      // Can't install security chip — skip it
      console.log("[assign-starter-system] Skipping security chip: total power draw exceeds PSU capacity")
    }

    const shouldInstallChip = totalPowerDraw <= (lowestPsu.max_output_watts || 0) && lowestChip

    // ── Step 3: Create the virtual machine in a transaction ──
    const machineName = "Novice Terminal"

    const result = await sql.begin(async (tx) => {
      // Create the VM
      const [newVm] = await tx`
        INSERT INTO virtual_machines (
          owner_identity_id,
          machine_name,
          case_id,
          power_supply_id
        ) VALUES (
          ${authenticatedUserId},
          ${machineName},
          ${lowestCase.id},
          ${lowestPsu.id}
        )
        RETURNING machine_id, ip_address::text as ip_address, created_at
      `

      // Insert hardware entries
      await tx`
        INSERT INTO virtual_machine_hardware (machine_id, hardware_type, catalog_id, slot_index)
        VALUES
          (${newVm.machine_id}, 'cpu', ${lowestCpu.id}, 0),
          (${newVm.machine_id}, 'memory', ${lowestMemory.id}, 0),
          (${newVm.machine_id}, 'storage', ${lowestStorage.id}, 0),
          (${newVm.machine_id}, 'network', ${lowestNic.id}, 0)
      `

      if (shouldInstallChip) {
        await tx`
          INSERT INTO virtual_machine_hardware (machine_id, hardware_type, catalog_id, slot_index)
          VALUES (${newVm.machine_id}, 'security_chip', ${lowestChip.id}, 0)
        `
      }

      return newVm
    })

    const system: ProvisionedSystem = {
      machine_id: result.machine_id,
      machine_name: machineName,
      ip_address: result.ip_address,
      cpu: { id: lowestCpu.id, name: lowestCpu.name, base_price: lowestCpu.base_price },
      memory: { id: lowestMemory.id, name: lowestMemory.name, base_price: lowestMemory.base_price },
      storage: { id: lowestStorage.id, name: lowestStorage.name, base_price: lowestStorage.base_price },
      nic: { id: lowestNic.id, name: lowestNic.name, base_price: lowestNic.base_price },
      security_chip: shouldInstallChip
        ? { id: lowestChip.id, name: lowestChip.name, base_price: lowestChip.base_price }
        : null,
      case: { id: lowestCase.id, name: lowestCase.name, base_price: lowestCase.base_price },
      psu: { id: lowestPsu.id, name: lowestPsu.name, base_price: lowestPsu.base_price },
      total_power_draw: totalPowerDraw,
      was_newly_created: true,
    }

    return new Response(JSON.stringify({
      success: true,
      was_newly_created: true,
      system,
    }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })

  } catch (error) {
    console.error("[assign-starter-system] Error:", error)
    return new Response(JSON.stringify({
      success: false,
      error: error instanceof Error ? error.message : "Unknown error occurred",
    }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } })
  }
})