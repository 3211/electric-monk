import { supabase } from '@/lib/supabase'
import { usePlayerState } from '@/composables/usePlayerState'
import { generateFibonacci } from '../fibonacci'

/**
 * Process Manager — /processes, /run, /kill
 * 
 * Requires connection to a machine (/connect <vm_ip>).
 * Anyone with access can view/cancel processes, but rewards always flow to machine_ip.
 * 
 * /run scan_records.exe → prompts for CPU %, checks resources, starts Akashic scan
 */

/**
 * Generate a deterministic API key from an IP address.
 * Used as the "seed" for scan attribution.
 */
function generateApiKeyFromIp(ip) {
  let hash = 0
  for (let i = 0; i < ip.length; i++) {
    const char = ip.charCodeAt(i)
    hash = ((hash << 5) - hash) + char
    hash = hash & hash // Convert to 32bit integer
  }
  return Math.abs(hash).toString(16).padStart(8, '0')
}

/**
 * Look up a program definition from the DB.
 */
async function getProgramDefinition(programName) {
  try {
    const { data } = await supabase
      .from('program_definitions')
      .select('*')
      .eq('program_name', programName)
      .single()
    return data
  } catch (_) {
    return null
  }
}

/**
 * Check if the connected machine has a specific program installed.
 */
async function machineHasProgram(machineId, programName) {
  try {
    const { data } = await supabase
      .from('virtual_programs')
      .select('program_id')
      .eq('machine_id', machineId)
      .eq('program_name', programName)
    return data && data.length > 0 ? data[0] : null
  } catch (_) {
    return null
  }
}

/**
 * Calculate expected duration based on CPU allocation and hardware compute speed.
 */
function calculateDuration(baseDurationSec, cpuAllocPct, computeSpeed) {
  if (cpuAllocPct <= 0) cpuAllocPct = 100
  // Duration scales inversely with CPU%: 50% CPU = 2x duration
  // Hardware compute speed provides a speedup factor
  const cpuFactor = 100 / Math.max(cpuAllocPct, 1)
  const hwFactor = Math.max(0.1, computeSpeed / 1000)
  return Math.ceil(baseDurationSec * cpuFactor / hwFactor)
}

/**
 * Heartbeat: update process_metadata in the DB with scan progress.
 * Called periodically during the scan loop.
 */
async function heartbeatProgress(processId, metadata) {
  try {
    await supabase
      .from('virtual_processes')
      .update({ process_metadata: metadata })
      .eq('process_id', processId)
  } catch (_) {
    // Heartbeat is non-fatal
  }
}

export function buildProcessCommands() {
  return {
    processes: {
      help: 'List active processes on the currently connected machine.',
      usage: '/processes',
      async handler(args, ctx) {
        if (!ctx.machine_id || ctx.machine_access !== 'admin') {
          return [{ text: '  [ERR] Not connected to a machine with access. Use /connect <vm_ip> first.', class: 'term-enemy' }]
        }

        const { terminal } = ctx
        terminal.write({ text: '  [SYS] Querying process list...', class: 'term-dim' })

        try {
          const { data: processes, error } = await supabase.rpc('get_machine_processes', {
            p_machine_id: ctx.machine_id
          })

          if (error) throw new Error(error.message)

          if (!processes || processes.length === 0) {
            return [{ text: '  [OK]  No active processes on this machine.', class: 'term-ally' }]
          }

          const bar = '─'.repeat(70)
          const lines = [
            { text: `  ${bar}`, class: 'term-dim' },
            { text: `  PROCESS LIST`, class: 'term-brass term-bold' },
            { text: `  ${bar}`, class: 'term-dim' },
            { text: '', class: '' }
          ]

          for (const proc of processes) {
            const pidShort = proc.process_id.substring(0, 8)
            const statusCls = proc.status === 'running' ? 'term-success' :
                              proc.status === 'completed' ? 'term-ally' :
                              proc.status === 'terminated' ? 'term-enemy' : 'term-dim'
            const cpuStr = proc.cpu_alloc_pct > 0 ? `${proc.cpu_alloc_pct}%` : 'flex'

            lines.push({
              text: `  PID: ${pidShort}... | ${proc.program_name}`,
              class: 'term-brass'
            })
            lines.push({
              text: `    Status: ${proc.status.toUpperCase()} | CPU: ${cpuStr} | Mem: ${proc.memory_alloc_mb}MB | Storage: ${proc.storage_alloc_mb}MB`,
              class: statusCls
            })

            if (proc.expected_end_time) {
              const eta = new Date(proc.expected_end_time)
              const now = new Date()
              const remaining = Math.max(0, Math.round((eta - now) / 1000))
              if (remaining > 0 && proc.status === 'running') {
                lines.push({ text: `    ETA: ${remaining}s remaining`, class: 'term-dim' })
              }
            }

            if (proc.status === 'running') {
              lines.push({ text: `    [/kill ${pidShort} to terminate]`, class: 'term-enemy' })
            }

            lines.push({ text: '', class: '' })
          }

          lines.push({ text: `  ${bar}`, class: 'term-dim' })
          return lines
        } catch (e) {
          return [{ text: `  [ERR] ${e.message}`, class: 'term-enemy' }]
        }
      }
    },

    run: {
      help: 'Execute a program on the connected machine. Usage: /run <program_name>',
      usage: '/run <program_name>',
      async handler(args, ctx) {
        const { terminal } = ctx
        const programName = args[0]

        if (!programName) {
          return [{ text: '  [SYS] Usage: /run <program_name>', class: 'term-dim' }]
        }

        // Must be connected to a machine with access
        if (!ctx.machine_id || ctx.machine_access !== 'admin') {
          return [{ text: '  [ERR] Not connected to a machine with admin access. Use /connect <vm_ip> first.', class: 'term-enemy' }]
        }

        // Check program definition exists
        const progDef = await getProgramDefinition(programName)
        if (!progDef) {
          return [{ text: `  [ERR] Unknown program: ${programName}`, class: 'term-enemy' }]
        }

        // Check machine has the program installed
        const installed = await machineHasProgram(ctx.machine_id, programName)
        if (!installed) {
          return [
            { text: `  [ERR] Program "${programName}" is not installed on this machine.`, class: 'term-enemy' },
            { text: `  [SYS] Install it first or use a machine that has it.`, class: 'term-dim' }
          ]
        }

        // If CPU is variable (base_cpu_pct = 0), prompt the user
        let cpuAllocPct = progDef.base_cpu_pct
        if (cpuAllocPct === 0) {
          terminal.write({ text: '  [SYS] This program supports variable CPU allocation.', class: 'term-steel' })
          terminal.write({ text: `  [SYS] Min: ${progDef.min_cpu_required_pct}% — Higher CPU = faster completion.`, class: 'term-steel' })
          terminal.write({ text: '  Enter CPU allocation % (10-100, or 0 for flex):', class: 'term-text' })
          const input = await terminal.readLine('  > ')
          const parsed = parseInt(input, 10)
          if (isNaN(parsed) || parsed < 0 || parsed > 100) {
            return [{ text: '  [ERR] Invalid CPU allocation. Must be 0-100.', class: 'term-enemy' }]
          }
          if (parsed > 0 && parsed < progDef.min_cpu_required_pct) {
            return [{ text: `  [ERR] Minimum CPU required: ${progDef.min_cpu_required_pct}%`, class: 'term-enemy' }]
          }
          cpuAllocPct = parsed
        }

        // Check resources
        terminal.write({ text: '  [SYS] Checking system resources...', class: 'term-dim' })
        try {
          const { data: resourceCheck } = await supabase.rpc('can_start_process', {
            p_machine_id: ctx.machine_id,
            p_cpu_pct: cpuAllocPct,
            p_memory_mb: progDef.base_memory_mb,
            p_storage_mb: progDef.base_storage_mb
          })

          if (!resourceCheck.success) {
            return [
              { text: `  [ERR] ${resourceCheck.error}`, class: 'term-enemy' },
              ...(resourceCheck.available_pct !== undefined ? [{ text: `  Available CPU: ${resourceCheck.available_pct}%`, class: 'term-dim' }] : []),
              ...(resourceCheck.available_mb !== undefined ? [{ text: `  Available RAM: ${resourceCheck.available_mb}MB`, class: 'term-dim' }] : []),
              ...(resourceCheck.available_storage_mb !== undefined ? [{ text: `  Available Storage: ${resourceCheck.available_storage_mb}MB`, class: 'term-dim' }] : [])
            ]
          }
        } catch (e) {
          return [{ text: `  [ERR] Resource check failed: ${e.message}`, class: 'term-enemy' }]
        }

        // ── Dispatch to program-specific handler ──
        if (programName === 'scan_records.exe') {
          return runAkashicScan(ctx, progDef, installed, cpuAllocPct)
        }

        // Generic stub for unknown programs
        return [
          { text: `  [SYS] Program "${programName}" launched.`, class: 'term-ally' },
          { text: `  [STUB] This program's execution logic is not yet implemented.`, class: 'term-dim' }
        ]
      }
    },

    programs: {
      help: 'List installed programs on the currently connected machine.',
      usage: '/programs',
      async handler(args, ctx) {
        if (!ctx.machine_id || ctx.machine_access !== 'admin') {
          return [{ text: '  [ERR] Not connected to a machine with access. Use /connect <vm_ip> first.', class: 'term-enemy' }]
        }

        const { terminal } = ctx
        terminal.write({ text: '  [SYS] Querying installed programs...', class: 'term-dim' })

        try {
          const { data: programs, error } = await supabase
            .from('virtual_programs')
            .select('program_id, program_name, version, installed_at')
            .eq('machine_id', ctx.machine_id)
            .order('program_name', { ascending: true })

          if (error) throw new Error(error.message)

          if (!programs || programs.length === 0) {
            return [{ text: '  [OK]  No programs installed on this machine.', class: 'term-ally' }]
          }

          const bar = '─'.repeat(58)
          const lines = [
            { text: `  ${bar}`, class: 'term-dim' },
            { text: `  INSTALLED PROGRAMS`, class: 'term-brass term-bold' },
            { text: `  ${bar}`, class: 'term-dim' },
            { text: '', class: '' }
          ]

          for (const prog of programs) {
            const shortId = prog.program_id.substring(0, 8)
            const version = prog.version || '1.0.0'
            const installed = prog.installed_at
              ? new Date(prog.installed_at).toLocaleDateString()
              : 'unknown'

            lines.push({
              text: `  ${prog.program_name}  (v${version})`,
              class: 'term-ally'
            })
            lines.push({
              text: `    Program ID: ${shortId}... | Installed: ${installed}`,
              class: 'term-dim'
            })
            lines.push({
              text: `    [/run ${prog.program_name} to execute]`,
              class: 'term-steel'
            })
            lines.push({ text: '', class: '' })
          }

          lines.push({ text: `  ${bar}`, class: 'term-dim' })
          lines.push({
            text: `  To execute a program: /run <program_name>  (requires /connect <vm_ip> first)`,
            class: 'term-muted'
          })
          return lines
        } catch (e) {
          return [{ text: `  [ERR] ${e.message}`, class: 'term-enemy' }]
        }
      }
    },

    kill: {
      help: 'Terminate a running process by process ID. Use /processes to see PIDs.',
      usage: '/kill <pid_prefix>',
      async handler(args, ctx) {
        if (!ctx.machine_id || ctx.machine_access !== 'admin') {
          return [{ text: '  [ERR] Not connected to a machine with access.', class: 'term-enemy' }]
        }

        const pidPrefix = args[0]
        if (!pidPrefix) {
          return [{ text: '  [SYS] Usage: /kill <pid_prefix> (first 8 chars of process ID shown in /processes)', class: 'term-dim' }]
        }

        try {
          // Find the full process ID from prefix
          const { data: processes } = await supabase.rpc('get_machine_processes', {
            p_machine_id: ctx.machine_id
          })

          const match = processes?.find(p =>
            p.process_id.startsWith(pidPrefix) &&
            p.status === 'running'
          )

          if (!match) {
            return [{ text: `  [ERR] No running process found with PID prefix: ${pidPrefix}`, class: 'term-enemy' }]
          }

          const { data: result } = await supabase.rpc('complete_process', {
            p_process_id: match.process_id,
            p_status: 'terminated'
          })

          if (!result?.success) {
            throw new Error(result?.error || 'Unknown error')
          }

          return [
            { text: `  [OK]  Process ${pidPrefix}... terminated.`, class: 'term-ally' },
            { text: `  Resources freed: CPU ${result.resources_freed?.cpu_pct || 0}%, ${result.resources_freed?.memory_mb || 0}MB RAM, ${result.resources_freed?.storage_mb || 0}MB Storage`, class: 'term-dim' }
          ]
        } catch (e) {
          return [{ text: `  [ERR] ${e.message}`, class: 'term-enemy' }]
        }
      }
    }
  }
}

/**
 * Launch an Akashic scan via /run scan_records.exe.
 * Creates a virtual_processes row, runs the visual scanner, heartbeats progress.
 */
async function runAkashicScan(ctx, progDef, installedProgram, cpuAllocPct) {
  const { terminal, tab } = ctx
  const playerState = usePlayerState()
  const machineIp = ctx.connected_ip
  const playerIp = playerState.get('ip_address', 'unknown')

  tab.setTitle('Akashic Scanner')

  // Generate deterministic API key from machine IP
  const apiKey = generateApiKeyFromIp(machineIp)

  terminal.write({ text: '  [SYS] Initializing Akashic Record Scanner...', class: 'term-dim' })
  terminal.write({ text: `  [SYS] CPU Allocation: ${cpuAllocPct > 0 ? cpuAllocPct + '%' : 'Flex (auto)'}`, class: 'term-steel' })
  terminal.write({ text: `  [NET] Machine IP: ${machineIp}`, class: 'term-dim' })
  terminal.write({ text: `  [KEY] Deterministic API Key: ${apiKey}`, class: 'term-dim' })
  terminal.write({ text: `  [SYS] Rewards will be attributed to: ${machineIp}`, class: 'term-brass' })

  // Generate Fibonacci seeds (64 blocks total)
  const startOffset = Math.floor(Math.random() * 666999111) + 1
  const seeds = generateFibonacci(startOffset, 64)

  // Determine timing parameters
  // Get compute speed from edge function
  let blockSpeedMs = 25
  let computeSpeed = 1000
  try {
    const { data: startData } = await supabase.functions.invoke('akashic-mining', {
      body: {
        action: 'start',
        machine_ip: machineIp,
        start_block_id: Number(BigInt(seeds[0]) % BigInt(Number.MAX_SAFE_INTEGER)),
        target_blocks: 64
      }
    })
    if (startData?.success) {
      blockSpeedMs = startData.block_speed_ms
      computeSpeed = startData.compute_speed_score
    }
  } catch (_) {
    // Fall back to defaults
  }

  // Calculate expected duration
  const totalDurationSec = calculateDuration(progDef.base_duration_seconds * 64, cpuAllocPct, computeSpeed)
  const expectedEndTime = new Date(Date.now() + totalDurationSec * 1000)

  // Create virtual_processes row
  terminal.write({ text: '  [SYS] Registering process...', class: 'term-dim' })
  let processId
  try {
    const { data: procData, error } = await supabase
      .from('virtual_processes')
      .insert({
        machine_id: ctx.machine_id,
        program_id: installedProgram.program_id,
        cpu_alloc_pct: cpuAllocPct,
        memory_alloc_mb: progDef.base_memory_mb,
        storage_alloc_mb: progDef.base_storage_mb,
        status: 'running',
        expected_end_time: expectedEndTime.toISOString(),
        process_metadata: {
          type: 'akashic_scan',
          start_offset: startOffset,
          total_blocks: 64,
          block_speed_ms: blockSpeedMs,
          cpu_alloc_pct: cpuAllocPct,
          machine_ip: machineIp,
          api_key: apiKey,
          blocks_completed: 0,
          start_time: new Date().toISOString(),
          is_verification: false
        },
        pre_calc_rewards: {
          base_reward: progDef.base_reward,
          reward_formula: progDef.reward_formula,
          cpu_factor: cpuAllocPct > 0 ? cpuAllocPct / 100 : 1
        }
      })
      .select('process_id')
      .single()
    if (error) throw error
    processId = procData.process_id
    terminal.write({ text: `  [OK]  Process registered. PID: ${processId.substring(0, 8)}...`, class: 'term-ally' })
  } catch (e) {
    terminal.write({ text: `  [ERR] Failed to register process: ${e.message}`, class: 'term-enemy' })
    // Continue in offline mode
    processId = null
  }

  terminal.write({ text: `  [SYS] Estimated completion: ${expectedEndTime.toLocaleTimeString()}`, class: 'term-dim' })
  terminal.write({ text: `  [SYS] The scan will complete even if you disconnect.`, class: 'term-steel' })
  terminal.write({ text: `  [SYS] Use /stop to abort the scan prematurely.`, class: 'term-ally' })
  terminal.write({ text: '  ' + '─'.repeat(50), class: 'term-dim' })

  // ── Run the scanner ──
  // The scanner loop is the existing akashicScannerCommand.js logic
  // but now with heartbeat updates to virtual_processes.process_metadata
  const scannerState = { running: true, processId, machineIp }

  // Track progress for heartbeat
  let blockIndex = 0
  const totalBlocks = 64

  // Heartbeat interval: update DB every 5 blocks
  const heartbeatInterval = setInterval(async () => {
    if (!processId || !scannerState.running) return
    await heartbeatProgress(processId, {
      type: 'akashic_scan',
      start_offset: startOffset,
      total_blocks: totalBlocks,
      block_speed_ms: blockSpeedMs,
      cpu_alloc_pct: cpuAllocPct,
      machine_ip: machineIp,
      api_key: apiKey,
      blocks_completed: blockIndex,
      start_time: new Date().toISOString(),
      is_verification: false
    })
  }, 10000) // Every 10 seconds

  // Import and run the actual scanner
  try {
    const { runScanner } = await import('../akashicScannerCommand.js')
    await runScanner({ terminal, tab, registry: ctx.registry }, scannerState)
  } catch (e) {
    terminal.write({ text: `  [ERR] Scanner crashed: ${e.message}`, class: 'term-enemy' })
  } finally {
    clearInterval(heartbeatInterval)

    // Final heartbeat: mark completed
    if (processId) {
      await heartbeatProgress(processId, {
        type: 'akashic_scan',
        start_offset: startOffset,
        total_blocks: totalBlocks,
        block_speed_ms: blockSpeedMs,
        cpu_alloc_pct: cpuAllocPct,
        machine_ip: machineIp,
        api_key: apiKey,
        blocks_completed: blockIndex,
        start_time: new Date().toISOString(),
        is_verification: false,
        completed: true,
        completed_at: new Date().toISOString()
      })

      // Complete the process (triggers reward processing via cron)
      try {
        await supabase.rpc('complete_process', {
          p_process_id: processId,
          p_status: scannerState.running ? 'terminated' : 'completed'
        })
      } catch (_) {}
    }

    terminal.write({ text: '  [SYS] Scan process ended.', class: 'term-brass' })
  }

  return null
}