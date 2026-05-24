// Supabase Edge Function: akashic-mining
// Handles Akashic Record mining lifecycle: start scans, validate pulses, credit scores.
//
// ACTIONS:
//   start   — Initializes a mining batch with explicit scan_mode (scan|verify).
//             For verify: reserves blocks upfront and stores reserved_blocks.
//             Calculates compute speed from VM hardware.
//   pulse   — Validates completion timing, processes results, credits initiator_ip (player).
//             Clears reserved_by on verified blocks.
//   cancel  — Cancels active scan: clears reservations, deletes pending record.
//   status  — Returns scan progress (uses get_akashic_scan_progress for rehydration).
//
// SCORE ATTRIBUTION: initiator_ip (player's holy IP) gets credit, NOT machine_ip.

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

// ── Helpers ──

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

function cleanIp(ip: string): string {
  return ip.replace(/\/\d+$/, '')
}

async function getPlayerIp(userId: string): Promise<string> {
  const rows = await sql`
    SELECT host(ip_address) as ip_address
    FROM public.players
    WHERE id = ${userId}
  `
  if (rows.length === 0) throw new Error("Player record not found")
  return rows[0].ip_address
}

interface VmHardware {
  cpu_cores: number
  cpu_mhz: number
  ram_mhz: number
  nic_mbps: number
  machine_ip: string
  owner_ip: string
}

async function getVmHardware(machineIp: string, ownerIp: string): Promise<VmHardware> {
  const cmIp = cleanIp(machineIp)
  const coIp = cleanIp(ownerIp)
  const rows = await sql`
    SELECT
      host(vm.ip_address) as machine_ip,
      host(vm.owner_identity) as owner_ip,
      cpu.cores as cpu_cores,
      cpu.clock_speed_mhz as cpu_mhz,
      ram.speed_mhz as ram_mhz,
      nic.bandwidth_mbps as nic_mbps
    FROM public.virtual_machines vm
    JOIN public.catalog_cpus cpu ON vm.cpu_id = cpu.id
    JOIN public.catalog_memory ram ON vm.memory_id = ram.id
    JOIN public.catalog_network_cards nic ON vm.network_card_id = nic.id
    WHERE vm.ip_address = ${cmIp}::inet
      AND vm.owner_identity = ${coIp}::inet
  `
  if (rows.length === 0) throw new Error(`Virtual machine ${machineIp} not found or not owned by you`)
  return rows[0]
}

function calculateComputeSpeed(hw: VmHardware): number {
  return Math.floor(
    (hw.cpu_cores * hw.cpu_mhz)
    + (hw.ram_mhz * 0.5)
    + (hw.nic_mbps * 10)
  )
}

function calculateBlockSpeedMs(computeSpeed: number): number {
  return Math.max(1000, Math.floor(120000000 / Math.max(computeSpeed, 100)))
}

function calculateExpectedCompletion(blockSpeedMs: number, targetBlocks: number): Date {
  const totalMs = blockSpeedMs * targetBlocks * 1.10
  return new Date(Date.now() + totalMs)
}

async function getFactionIp(userId: string): Promise<string | null> {
  const rows = await sql`
    SELECT host(s.ip_address) as faction_ip
    FROM public.players p
    JOIN public.sects s ON p.sect_id = s.id
    WHERE p.id = ${userId}
  `
  if (rows.length === 0) return null
  return rows[0].faction_ip
}

const BASE_MINING_SCORE = 100
const VERIFICATION_SCORE_MULTIPLIER = 0.25

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {
    if (req.method !== "POST") {
      throw new Error("Method not allowed. Use POST.")
    }

    const userId = extractUserIdFromAuthHeader(req)
    const body = await req.json()
    const action = body.action

    if (!action) throw new Error("Missing 'action' field in request body")

    // ────────────────────────────────────────
    // ACTION: start
    // ────────────────────────────────────────
    if (action === "start") {
      const rawMachineIp: string = body.machine_ip
      const machineIp = cleanIp(rawMachineIp)
      const scanMode: string = body.scan_mode || 'scan'  // 'scan' | 'verify'
      const targetBlocks: number = Math.min(10, Math.max(1, body.target_blocks || 5))
      const startBlockId: number = body.start_block_id || 0
      const virtualProcessId: string | null = body.virtual_process_id || null  // Links to virtual_processes for re-hydration

      if (!machineIp) throw new Error("Missing 'machine_ip'")
      if (!['scan', 'verify'].includes(scanMode)) {
        throw new Error("scan_mode must be 'scan' or 'verify'")
      }

      const playerIp = await getPlayerIp(userId)       // player's holy IP (initiator)
      const hw = await getVmHardware(machineIp, playerIp)
      const factionIp = await getFactionIp(userId)

      const computeSpeed = calculateComputeSpeed(hw)
      const blockSpeedMs = calculateBlockSpeedMs(computeSpeed)
      const expectedCompletion = calculateExpectedCompletion(blockSpeedMs, targetBlocks)

      let isVerification = false
      let reservedBlockIds: number[] = []

      if (scanMode === 'verify') {
        // Verify mode: reserve blocks upfront
        isVerification = true

        // Get available unverified blocks
        const unverified = await sql`
          SELECT block_id FROM public.akashic_sectors
          WHERE verified_count < 2
            AND reserved_by IS NULL
            AND (pending_verifications + verified_count) < 2
          ORDER BY discovery_time ASC
          LIMIT ${targetBlocks}
        `

        if (unverified.length === 0) {
          throw new Error("No unverified blocks available. Try scanning instead.")
        }

        // Reserve each block
        reservedBlockIds = []
        for (const block of unverified) {
          try {
            await sql`
              UPDATE public.akashic_sectors
              SET pending_verifications = pending_verifications + 1,
                  reserved_by = ${machineIp}::inet
              WHERE block_id = ${block.block_id}
                AND reserved_by IS NULL
                AND (pending_verifications + verified_count) < 2
            `
            reservedBlockIds.push(block.block_id)
          } catch (_) {
            // Block may have been taken by concurrent request
          }
        }

        if (reservedBlockIds.length === 0) {
          throw new Error("Failed to reserve any blocks. They may have been taken.")
        }
      }

      // Create pending scan
      const [pending] = await sql`
        INSERT INTO public.akashic_scans_pending (
          machine_ip,
          initiator_ip,
          faction_ip,
          start_block_id,
          target_blocks,
          expected_completion_time,
          block_speed_ms,
          is_verification,
          scan_mode,
          reserved_blocks,
          compute_speed_score,
          virtual_process_id
        ) VALUES (
          ${machineIp}::inet,
          ${playerIp}::inet,
          ${factionIp ? sql`${factionIp}::inet` : null},
          ${startBlockId},
          ${reservedBlockIds.length > 0 ? reservedBlockIds.length : targetBlocks},
          ${expectedCompletion.toISOString()},
          ${blockSpeedMs},
          ${isVerification},
          ${scanMode},
          ${reservedBlockIds.length > 0 ? reservedBlockIds : null},
          ${computeSpeed},
          ${virtualProcessId ? sql`${virtualProcessId}::uuid` : null}
        )
        RETURNING process_id, start_time
      `

      return new Response(JSON.stringify({
        success: true,
        action: "start",
        process_id: pending.process_id,
        start_time: pending.start_time,
        expected_completion_time: expectedCompletion.toISOString(),
        block_speed_ms: blockSpeedMs,
        compute_speed_score: computeSpeed,
        scan_mode: scanMode,
        is_verification: isVerification,
        target_blocks: reservedBlockIds.length > 0 ? reservedBlockIds.length : targetBlocks,
        reserved_blocks: reservedBlockIds.length > 0 ? reservedBlockIds : undefined,
        faction_ip: factionIp,
        initiator_ip: playerIp,
        machine_ip: machineIp,
        hardware: {
          cpu_cores: hw.cpu_cores,
          cpu_mhz: hw.cpu_mhz,
          ram_mhz: hw.ram_mhz,
          nic_mbps: hw.nic_mbps,
        },
      }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    // ────────────────────────────────────────
    // ACTION: pulse
    // ────────────────────────────────────────
    else if (action === "pulse") {
      const processId: string = body.process_id
      const blockScores: Array<{ block_id: number; score: number; matches_count: number }> = body.block_scores || []

      if (!processId) throw new Error("Missing 'process_id'")

      const pendingRows = await sql`
        SELECT * FROM public.akashic_scans_pending
        WHERE process_id = ${processId}
      `
      if (pendingRows.length === 0) {
        throw new Error(`Pending scan ${processId} not found. It may have already been processed or expired.`)
      }

      const pending = pendingRows[0]
      const pendingMachineIp = cleanIp(String(pending.machine_ip))
      const pendingInitiatorIp = pending.initiator_ip ? cleanIp(String(pending.initiator_ip)) : null
      const pendingFactionIp = pending.faction_ip ? cleanIp(String(pending.faction_ip)) : null

      const now = new Date()
      const expectedEnd = new Date(pending.expected_completion_time)
      const totalDurationMs = expectedEnd.getTime() - new Date(pending.start_time).getTime()
      const bufferMs = totalDurationMs * 0.05
      const earliestAcceptable = new Date(expectedEnd.getTime() - bufferMs)

      if (now < earliestAcceptable) {
        return new Response(JSON.stringify({
          success: false,
          action: "pulse",
          error: "Too early. Pulse rejected.",
          retry_after_ms: earliestAcceptable.getTime() - now.getTime(),
          earliest_acceptable: earliestAcceptable.toISOString(),
        }), { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } })
      }

      let totalScoreAwarded = 0
      const processedBlockIds: number[] = []
      const verificationResults: Array<{ block_id: number; is_new: boolean; score: number; note?: string; slots?: string }> = []

      for (const block of blockScores) {
        const existing = await sql`
          SELECT block_id, discovered_by_ip, verified_count, pending_verifications
          FROM public.akashic_sectors
          WHERE block_id = ${block.block_id}
        `

        if (existing.length === 0) {
          // New discovery — credit to initiator_ip
          const score = block.score > 0 ? block.score : BASE_MINING_SCORE

          await sql`
            INSERT INTO public.akashic_sectors (
              block_id,
              discovered_by_ip,
              discovered_by_faction_ip,
              score_value,
              verified_count,
              pending_verifications
            ) VALUES (
              ${block.block_id},
              ${pendingInitiatorIp ? sql`${pendingInitiatorIp}::inet` : sql`${pendingMachineIp}::inet`},
              ${pendingFactionIp ? sql`${pendingFactionIp}::inet` : null},
              ${score},
              0,
              0
            )
          `

          // Credit initiator_ip (player)
          if (pendingInitiatorIp) {
            await sql`
              UPDATE public.network_addresses
              SET akashic_score = akashic_score + ${score}
              WHERE ip_address = ${pendingInitiatorIp}::inet
            `
          }

          if (pendingFactionIp) {
            await sql`
              UPDATE public.network_addresses
              SET akashic_score = akashic_score + ${score}
              WHERE ip_address = ${pendingFactionIp}::inet
            `
          }

          totalScoreAwarded += score
          verificationResults.push({ block_id: block.block_id, is_new: true, score })
          processedBlockIds.push(block.block_id)
        } else {
          const sector = existing[0]

          if ((sector.verified_count + sector.pending_verifications) >= 2) {
            const score = 0
            verificationResults.push({ block_id: block.block_id, is_new: false, score, note: 'fully verified' })
            continue
          }

          const score = Math.floor((block.score > 0 ? block.score : BASE_MINING_SCORE) * VERIFICATION_SCORE_MULTIPLIER)

          await sql`
            UPDATE public.akashic_sectors
            SET
              verification_count = verification_count + 1,
              verified_count = verified_count + 1,
              pending_verifications = GREATEST(0, pending_verifications - 1),
              reserved_by = NULL,
              last_verified_at = now(),
              last_verified_by_ip = ${pendingInitiatorIp ? sql`${pendingInitiatorIp}::inet` : sql`${pendingMachineIp}::inet`}
            WHERE block_id = ${block.block_id}
          `

          // Credit initiator_ip (player)
          if (pendingInitiatorIp) {
            await sql`
              UPDATE public.network_addresses
              SET akashic_score = akashic_score + ${score}
              WHERE ip_address = ${pendingInitiatorIp}::inet
            `
          }

          if (pendingFactionIp) {
            await sql`
              UPDATE public.network_addresses
              SET akashic_score = akashic_score + ${score}
              WHERE ip_address = ${pendingFactionIp}::inet
            `
          }

          totalScoreAwarded += score
          verificationResults.push({ block_id: block.block_id, is_new: false, score, slots: `${sector.verified_count + 1}/2` })
          processedBlockIds.push(block.block_id)
        }
      }

      await sql`
        INSERT INTO public.akashic_scans_completed (
          process_id,
          machine_ip,
          initiator_ip,
          faction_ip,
          start_time,
          end_time,
          start_block_id,
          blocks_processed,
          score_awarded,
          is_verification
        ) VALUES (
          ${pending.process_id},
          ${pendingMachineIp}::inet,
          ${pendingInitiatorIp ? sql`${pendingInitiatorIp}::inet` : null},
          ${pendingFactionIp ? sql`${pendingFactionIp}::inet` : null},
          ${pending.start_time},
          now(),
          ${pending.start_block_id},
          ${processedBlockIds.length},
          ${totalScoreAwarded},
          ${pending.is_verification}
        )
      `

      await sql`
        DELETE FROM public.akashic_scans_pending
        WHERE process_id = ${processId}
      `

      return new Response(JSON.stringify({
        success: true,
        action: "pulse",
        process_id: processId,
        blocks_processed: processedBlockIds.length,
        total_score_awarded: totalScoreAwarded,
        initiator_ip: pendingInitiatorIp,
        verification_results: verificationResults,
        was_verification_batch: pending.is_verification,
      }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    // ────────────────────────────────────────
    // ACTION: cancel
    // ────────────────────────────────────────
    else if (action === "cancel") {
      const processId: string = body.process_id
      const rawMachineIp: string = body.machine_ip
      const machineIp = cleanIp(rawMachineIp)

      if (!processId) throw new Error("Missing 'process_id'")
      if (!machineIp) throw new Error("Missing 'machine_ip'")

      const playerIp = await getPlayerIp(userId)

      // Verify VM ownership before allowing cancel
      await getVmHardware(machineIp, playerIp)

      // Use the cancel_akashic_scan function which clears reservations
      const [result] = await sql`
        SELECT public.cancel_akashic_scan(${processId}::UUID, ${machineIp}::inet) as result
      `

      if (result?.result?.success) {
        return new Response(JSON.stringify({
          success: true,
          action: "cancel",
          process_id: processId,
          reservations_cleared: result.result.reservations_cleared,
        }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
      } else {
        throw new Error(result?.result?.error || "Cancel failed")
      }
    }

    // ────────────────────────────────────────
    // ACTION: status (recovery/rehydration)
    // ────────────────────────────────────────
    else if (action === "status") {
      const processId: string = body.process_id
      const rawMachineIp: string = body.machine_ip
      const machineIp = rawMachineIp ? cleanIp(rawMachineIp) : null
      const playerIp = await getPlayerIp(userId)

      if (processId) {
        // Use get_akashic_scan_progress for DB-ground-truth progress
        const [result] = await sql`
          SELECT public.get_akashic_scan_progress(${processId}::UUID) as progress
        `
        if (result?.progress?.success) {
          return new Response(JSON.stringify({
            success: true,
            action: "status",
            found: true,
            scan: result.progress,
          }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
        } else {
          // Fall back to direct query if function not available
          let rows = await sql`
            SELECT * FROM public.akashic_scans_pending
            WHERE process_id = ${processId}
          `
          // Second-chance lookup via virtual_process_id
          if (rows.length === 0) {
            rows = await sql`
              SELECT * FROM public.akashic_scans_pending
              WHERE virtual_process_id = ${processId}::uuid
            `
          }
          if (rows.length === 0) {
            return new Response(JSON.stringify({
              success: true,
              action: "status",
              found: false,
              message: "No active scan found with that process_id.",
            }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
          }

          const scan = rows[0]
          const now = new Date()
          const expectedEnd = new Date(scan.expected_completion_time)
          const totalDurationMs = expectedEnd.getTime() - new Date(scan.start_time).getTime()
          const elapsedMs = now.getTime() - new Date(scan.start_time).getTime()
          const progress = Math.min(1, Math.max(0, elapsedMs / totalDurationMs))

          return new Response(JSON.stringify({
            success: true,
            action: "status",
            found: true,
            scan: {
              process_id: scan.process_id,
              start_block_id: scan.start_block_id,
              target_blocks: scan.target_blocks,
              start_time: scan.start_time,
              expected_completion_time: scan.expected_completion_time,
              block_speed_ms: scan.block_speed_ms,
              is_verification: scan.is_verification,
              scan_mode: scan.scan_mode,
              reserved_blocks: scan.reserved_blocks,
              initiator_ip: scan.initiator_ip,
              progress,
              elapsed_ms: elapsedMs,
              remaining_ms: Math.max(0, totalDurationMs - elapsedMs),
            },
          }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
        }
      }

      // No process_id — return all active scans for player's machines
      if (machineIp) {
        await getVmHardware(machineIp, playerIp)
      }

      const ownerRows = await sql`
        SELECT host(vm.ip_address) as machine_ip
        FROM public.virtual_machines vm
        WHERE vm.owner_identity = ${playerIp}::inet
      `
      const machineIps: string[] = ownerRows.map((r: { machine_ip: string }) => r.machine_ip)

      if (machineIps.length === 0) {
        return new Response(JSON.stringify({
          success: true,
          action: "status",
          scans: [],
        }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
      }

      const pendingScans = await sql`
        SELECT * FROM public.akashic_scans_pending
        WHERE machine_ip = ANY(${machineIps}::inet[])
        ORDER BY start_time DESC
      `

      return new Response(JSON.stringify({
        success: true,
        action: "status",
        scans: pendingScans.map((scan: Record<string, unknown>) => {
          const now = new Date()
          const expectedEnd = new Date(scan.expected_completion_time)
          const totalDurationMs = expectedEnd.getTime() - new Date(scan.start_time).getTime()
          const elapsedMs = now.getTime() - new Date(scan.start_time).getTime()
          const progress = Math.min(1, Math.max(0, elapsedMs / totalDurationMs))

          return {
            process_id: scan.process_id,
            machine_ip: scan.machine_ip,
            initiator_ip: scan.initiator_ip,
            start_block_id: scan.start_block_id,
            target_blocks: scan.target_blocks,
            start_time: scan.start_time,
            expected_completion_time: scan.expected_completion_time,
            block_speed_ms: scan.block_speed_ms,
            is_verification: scan.is_verification,
            scan_mode: scan.scan_mode,
            reserved_blocks: scan.reserved_blocks,
            progress,
            elapsed_ms: elapsedMs,
            remaining_ms: Math.max(0, totalDurationMs - elapsedMs),
          }
        }),
      }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    else {
      throw new Error(`Unknown action: '${action}'. Valid actions: start, pulse, cancel, status`)
    }

  } catch (error) {
    console.error("[akashic-mining] Error:", error)
    return new Response(JSON.stringify({
      success: false,
      error: error instanceof Error ? error.message : "Unknown error occurred",
    }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } })
  }
})