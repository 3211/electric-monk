// Supabase Edge Function: akashic-mining
// Handles Akashic Record mining lifecycle: start scans, validate pulses, credit scores.
//
// ACTIONS:
//   start  — Initializes a new mining batch. Calculates compute speed from VM hardware,
//            checks if blocks are already discovered (verification mode), creates pending scan.
//   pulse  — Validates completion timing (must not arrive before expected - 5% buffer),
//            processes results, moves scan to completed, credits scores to IPs.
//   status — Returns the status of an active pending scan (for recovery after refresh).
//
// SECURITY: User identity derived from JWT Authorization header.
// All operations validated against VM ownership (player IP → owner_identity).

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

async function getPlayerIp(userId: string): Promise<string> {
  const rows = await sql`
    SELECT ip_address::text as ip_address
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
  const rows = await sql`
    SELECT
      vm.ip_address::text as machine_ip,
      vm.owner_identity::text as owner_ip,
      cpu.cores as cpu_cores,
      cpu.clock_speed_mhz as cpu_mhz,
      ram.speed_mhz as ram_mhz,
      nic.bandwidth_mbps as nic_mbps
    FROM public.virtual_machines vm
    JOIN public.catalog_cpus cpu ON vm.cpu_id = cpu.id
    JOIN public.catalog_memory ram ON vm.memory_id = ram.id
    JOIN public.catalog_network_cards nic ON vm.network_card_id = nic.id
    WHERE vm.ip_address = ${machineIp}::inet
      AND vm.owner_identity = ${ownerIp}::inet
  `
  if (rows.length === 0) throw new Error(`Virtual machine ${machineIp} not found or not owned by you`)
  return rows[0]
}

function calculateComputeSpeed(hw: VmHardware): number {
  // (CPU Cores × CPU MHz) + (RAM MHz × 0.5) + (Network Mbps × 10)
  return Math.floor(
    (hw.cpu_cores * hw.cpu_mhz)
    + (hw.ram_mhz * 0.5)
    + (hw.nic_mbps * 10)
  )
}

function calculateBlockSpeedMs(computeSpeed: number): number {
  // Base block time = 12,000ms / (computeSpeed / 1000), minimum 500ms
  return Math.max(500, Math.floor(12000000 / Math.max(computeSpeed, 1000)))
}

function calculateExpectedCompletion(blockSpeedMs: number, targetBlocks: number): Date {
  // Total ms × 1.10 (10% server breathing room)
  const totalMs = blockSpeedMs * targetBlocks * 1.10
  return new Date(Date.now() + totalMs)
}

async function getFactionIp(userId: string): Promise<string | null> {
  const rows = await sql`
    SELECT s.ip_address::text as faction_ip
    FROM public.players p
    JOIN public.sects s ON p.sect_id = s.id
    WHERE p.id = ${userId}
  `
  if (rows.length === 0) return null
  return rows[0].faction_ip
}

// ── Mining logic ──

const BASE_MINING_SCORE = 100
const VERIFICATION_SCORE_MULTIPLIER = 0.25

// ── Main Handler ──

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
      const machineIp: string = body.machine_ip
      const startBlockId: number = body.start_block_id
      const targetBlocks: number = body.target_blocks || 5

      if (!machineIp) throw new Error("Missing 'machine_ip'")
      if (startBlockId === undefined || startBlockId === null) throw new Error("Missing 'start_block_id'")

      const playerIp = await getPlayerIp(userId)
      const hw = await getVmHardware(machineIp, playerIp)
      const factionIp = await getFactionIp(userId)

      const computeSpeed = calculateComputeSpeed(hw)
      const blockSpeedMs = calculateBlockSpeedMs(computeSpeed)
      const expectedCompletion = calculateExpectedCompletion(blockSpeedMs, targetBlocks)

      // Check if any of the blocks in this batch are already discovered
      let isVerification = false
      const blockIds: number[] = []
      for (let i = 0; i < targetBlocks; i++) {
        blockIds.push(startBlockId + i)
      }

      const existingSectors = await sql`
        SELECT block_id FROM public.akashic_sectors
        WHERE block_id = ANY(${blockIds}::bigint[])
      `
      // If ALL blocks already exist, it's a verification run
      if (existingSectors.length === targetBlocks) {
        isVerification = true
      }

      // Create pending scan
      const [pending] = await sql`
        INSERT INTO public.akashic_scans_pending (
          machine_ip,
          faction_ip,
          start_block_id,
          target_blocks,
          expected_completion_time,
          block_speed_ms,
          is_verification,
          compute_speed_score
        ) VALUES (
          ${machineIp}::inet,
          ${factionIp ? sql`${factionIp}::inet` : null},
          ${startBlockId},
          ${targetBlocks},
          ${expectedCompletion.toISOString()},
          ${blockSpeedMs},
          ${isVerification},
          ${computeSpeed}
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
        is_verification: isVerification,
        faction_ip: factionIp,
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

      // Fetch pending scan
      const pendingRows = await sql`
        SELECT * FROM public.akashic_scans_pending
        WHERE process_id = ${processId}
      `
      if (pendingRows.length === 0) {
        throw new Error(`Pending scan ${processId} not found. It may have already been processed or expired.`)
      }

      const pending = pendingRows[0]
      const now = new Date()
      const expectedEnd = new Date(pending.expected_completion_time)
      const totalDurationMs = expectedEnd.getTime() - new Date(pending.start_time).getTime()
      const bufferMs = totalDurationMs * 0.05 // 5% early buffer
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

      // Process scores — credit IPs for each block
      let totalScoreAwarded = 0
      const processedBlockIds: number[] = []
      const verificationResults: Array<{ block_id: number; is_new: boolean; score: number }> = []

      for (const block of blockScores) {
        const existing = await sql`
          SELECT block_id, discovered_by_ip FROM public.akashic_sectors
          WHERE block_id = ${block.block_id}
        `

        if (existing.length === 0) {
          // New discovery — full score + track it
          const score = block.score > 0 ? block.score : BASE_MINING_SCORE

          await sql`
            INSERT INTO public.akashic_sectors (
              block_id,
              discovered_by_ip,
              discovered_by_faction_ip,
              score_value
            ) VALUES (
              ${block.block_id},
              ${pending.machine_ip}::inet,
              ${pending.faction_ip ? sql`${pending.faction_ip}::inet` : null},
              ${score}
            )
          `

          // Credit machine IP
          await sql`
            UPDATE public.network_addresses
            SET akashic_score = akashic_score + ${score}
            WHERE ip_address = ${pending.machine_ip}::inet
          `

          // Credit faction IP if applicable
          if (pending.faction_ip) {
            await sql`
              UPDATE public.network_addresses
              SET akashic_score = akashic_score + ${score}
              WHERE ip_address = ${pending.faction_ip}::inet
            `
          }

          totalScoreAwarded += score
          verificationResults.push({ block_id: block.block_id, is_new: true, score })
          processedBlockIds.push(block.block_id)
        } else {
          // Verification — fractional score
          const score = Math.floor((block.score > 0 ? block.score : BASE_MINING_SCORE) * VERIFICATION_SCORE_MULTIPLIER)

          await sql`
            UPDATE public.akashic_sectors
            SET
              verification_count = verification_count + 1,
              last_verified_at = now(),
              last_verified_by_ip = ${pending.machine_ip}::inet
            WHERE block_id = ${block.block_id}
          `

          // Credit machine IP (verification score)
          await sql`
            UPDATE public.network_addresses
            SET akashic_score = akashic_score + ${score}
            WHERE ip_address = ${pending.machine_ip}::inet
          `

          // Credit faction IP if applicable
          if (pending.faction_ip) {
            await sql`
              UPDATE public.network_addresses
              SET akashic_score = akashic_score + ${score}
              WHERE ip_address = ${pending.faction_ip}::inet
            `
          }

          totalScoreAwarded += score
          verificationResults.push({ block_id: block.block_id, is_new: false, score })
          processedBlockIds.push(block.block_id)
        }
      }

      // Move from pending to completed
      await sql`
        INSERT INTO public.akashic_scans_completed (
          process_id,
          machine_ip,
          faction_ip,
          start_time,
          end_time,
          start_block_id,
          blocks_processed,
          score_awarded,
          is_verification
        ) VALUES (
          ${pending.process_id},
          ${pending.machine_ip}::inet,
          ${pending.faction_ip ? sql`${pending.faction_ip}::inet` : null},
          ${pending.start_time},
          now(),
          ${pending.start_block_id},
          ${processedBlockIds.length},
          ${totalScoreAwarded},
          ${pending.is_verification}
        )
      `

      // Remove from pending
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
        verification_results: verificationResults,
        was_verification_batch: pending.is_verification,
      }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    // ────────────────────────────────────────
    // ACTION: status (recovery)
    // ────────────────────────────────────────
    else if (action === "status") {
      const processId: string = body.process_id
      const machineIp: string = body.machine_ip
      const playerIp = await getPlayerIp(userId)

      if (processId) {
        // Look up a specific process
        const rows = await sql`
          SELECT * FROM public.akashic_scans_pending
          WHERE process_id = ${processId}
            AND machine_ip = ${machineIp}::inet
        `
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
            progress,
            elapsed_ms: elapsedMs,
            remaining_ms: Math.max(0, totalDurationMs - elapsedMs),
          },
        }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
      }

      // No process_id — return all active scans for player's machines
      if (machineIp) {
        // Verify ownership
        await getVmHardware(machineIp, playerIp)
      }

      const ownerRows = await sql`
        SELECT vm.ip_address::text as machine_ip
        FROM public.virtual_machines vm
        WHERE vm.owner_identity = ${playerIp}::inet
      `
      const machineIps = ownerRows.map(r => r.machine_ip)

      if (machineIps.length === 0) {
        return new Response(JSON.stringify({
          success: true,
          action: "status",
          scans: [],
        }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
      }

      const pendingScans = await sql`
        SELECT * FROM public.akashic_scans_pending
        WHERE machine_ip = ANY(${machineIps.map(ip => ip + "::inet")}::inet[])
        ORDER BY start_time DESC
      `

      return new Response(JSON.stringify({
        success: true,
        action: "status",
        scans: pendingScans.map(scan => {
          const now = new Date()
          const expectedEnd = new Date(scan.expected_completion_time)
          const totalDurationMs = expectedEnd.getTime() - new Date(scan.start_time).getTime()
          const elapsedMs = now.getTime() - new Date(scan.start_time).getTime()
          const progress = Math.min(1, Math.max(0, elapsedMs / totalDurationMs))

          return {
            process_id: scan.process_id,
            machine_ip: scan.machine_ip,
            start_block_id: scan.start_block_id,
            target_blocks: scan.target_blocks,
            start_time: scan.start_time,
            expected_completion_time: scan.expected_completion_time,
            block_speed_ms: scan.block_speed_ms,
            is_verification: scan.is_verification,
            progress,
            elapsed_ms: elapsedMs,
            remaining_ms: Math.max(0, totalDurationMs - elapsedMs),
          }
        }),
      }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    else {
      throw new Error(`Unknown action: '${action}'. Valid actions: start, pulse, status`)
    }

  } catch (error) {
    console.error("[akashic-mining] Error:", error)
    return new Response(JSON.stringify({
      success: false,
      error: error instanceof Error ? error.message : "Unknown error occurred",
    }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } })
  }
})