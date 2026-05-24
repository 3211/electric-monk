import { supabase } from '@/lib/supabase'
import { getActiveScannerState } from '../akashicScannerCommand.js'
import { usePlayerState } from '@/composables/usePlayerState'
import { generateFibonacci } from '../fibonacci'

/**
 * Process Manager — /processes, /run, /kill, /programs
 * 
 * Connection state is read from usePlayerState() singleton — the single source of truth.
 * Any module (connection.js, onboarding_two.js) can setConnection() and these
 * commands will immediately see it.
 * 
 * /run scan_records.exe → prompts for CPU %, checks resources, starts Akashic scan
 */

/**
 * Generate a deterministic API key from an IP address.
 * Used as the "seed" for scan attribution.
 */
function generateApiKeyFromIp(ip) {
  let hash = 0
  const cleanIp = typeof ip === 'string' ? ip.replace(/\/\d+$/, '') : ip
  for (let i = 0; i < cleanIp.length; i++) {
    const char = cleanIp.charCodeAt(i)
    hash = ((hash << 5) - hash) + char
    hash = hash & hash
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
  const cpuFactor = 100 / Math.max(cpuAllocPct, 1)
  const hwFactor = Math.max(0.1, computeSpeed / 1000)
  return Math.ceil(baseDurationSec * cpuFactor / hwFactor)
}

/**
 * Heartbeat: update process_metadata in the DB with scan progress.
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

/** Helper: get connection details from the singleton state */
function getConnState() {
  const ps = usePlayerState()
  const connectedIp = ps.connectedIp.value
  const machineId = ps.machineId.value
  const machineAccess = ps.machineAccess.value
  const isConnectedToVM = ps.isConnectedToVM.value
  return { ps, connectedIp, machineId, machineAccess, isConnectedToVM }
}

const PAGE_SIZE = 10
const SPINNER_CHARS = ['|', '/', '-', '\\']

/** Lazy heartbeat: auto-complete overdue processes for this machine. */
async function lazyHeartbeat(machineId) {
  try {
    const { data } = await supabase.rpc('get_machine_processes', { p_machine_id: machineId })
    if (!data) return
    const overdue = data.filter(p =>
      p.status === 'running' && p.expected_end_time && new Date(p.expected_end_time) <= new Date()
    )
    for (const p of overdue) {
      await supabase.rpc('complete_process', { p_process_id: p.process_id, p_status: 'completed' })
    }
  } catch (_) {}
}

export function buildProcessCommands() {
  return {
    procmgr: {
      help: 'Active process manager — view, kill, or re-hydrate running processes.',
      usage: '/procmgr',
      async handler(args, ctx) {
        const { isConnectedToVM, machineId, connectedIp } = getConnState()
        if (!isConnectedToVM) {
          return [{ text: '  [ERR] Not connected to a machine with access. Use /connect <vm_ip> first.', class: 'term-enemy' }]
        }

        const { terminal, tab } = ctx
        let page = 0

        while (true) {
          await lazyHeartbeat(machineId)
          terminal.clear()
          terminal.write({ text: '  [SYS] Querying process list...', class: 'term-dim' })

          let allProcesses = []
          try {
            const { data, error } = await supabase.rpc('get_machine_processes', { p_machine_id: machineId })
            if (error) throw new Error(error.message)
            allProcesses = data || []
          } catch (e) {
            terminal.write({ text: `  [ERR] ${e.message}`, class: 'term-enemy' })
            return null
          }

          const running = allProcesses.filter(p => p.status === 'running')

          if (running.length === 0) {
            terminal.write({ text: '  [OK]  No active processes on this machine.', class: 'term-ally' })
            terminal.write({ text: '', class: '' })
            await terminal.readLine('  Press ENTER to return...')
            return null
          }

          const totalPages = Math.ceil(running.length / PAGE_SIZE)
          if (page >= totalPages) page = totalPages - 1
          if (page < 0) page = 0

          const startIdx = page * PAGE_SIZE
          const pageProcesses = running.slice(startIdx, startIdx + PAGE_SIZE)

          const bar = '─'.repeat(70)
          terminal.write({ text: `  ${bar}`, class: 'term-dim' })
          terminal.write({ text: `  ACTIVE PROCESS MANAGER  (Page ${page + 1}/${totalPages})`, class: 'term-brass term-bold' })
          terminal.write({ text: `  ${bar}`, class: 'term-dim' })
          terminal.write({ text: '', class: '' })

          const options = [{ label: 'Back (exit)', value: '__back__' }]
          const now = Date.now()
          const spinChar = SPINNER_CHARS[Math.floor(now / 300) % 4]

          for (let i = 0; i < pageProcesses.length; i++) {
            const proc = pageProcesses[i]
            const idx = startIdx + i + 1
            const cpuStr = proc.cpu_alloc_pct > 0 ? `${proc.cpu_alloc_pct}%` : 'flex'
            const meta = proc.process_metadata || {}
            const progType = meta.type ? ` [${meta.type}]` : ''
            const pidShort = proc.process_id.substring(0, 8)

            if (proc.expected_end_time) {
              const remaining = Math.max(0, Math.round((new Date(proc.expected_end_time) - new Date()) / 1000))
              if (remaining <= 0) {
                terminal.write({
                  text: `  ${idx}. ${proc.program_name}${progType}  (CPU: ${cpuStr} | Mem: ${proc.memory_alloc_mb}MB) | ${spinChar} [COMPLETE]`,
                  class: 'term-success term-bold'
                })
                terminal.write({ text: `     PID: ${pidShort}... | Awaiting finalization...`, class: 'term-dim' })
              } else {
                terminal.write({
                  text: `  ${idx}. ${proc.program_name}${progType}  (CPU: ${cpuStr} | Mem: ${proc.memory_alloc_mb}MB) | ${spinChar}`,
                  class: 'term-brass'
                })
                terminal.write({ text: `     PID: ${pidShort}... | ETA: ${remaining}s`, class: 'term-dim' })
              }
            } else {
              terminal.write({
                text: `  ${idx}. ${proc.program_name}${progType}  (CPU: ${cpuStr} | Mem: ${proc.memory_alloc_mb}MB)`,
                class: 'term-brass'
              })
              terminal.write({ text: `     PID: ${pidShort}...`, class: 'term-dim' })
            }

            options.push({ label: `Process ${idx}: ${proc.program_name}`, value: proc.process_id })
          }

          if (totalPages > 1) {
            if (page > 0) options.push({ label: '← Previous Page', value: '__prev__' })
            if (page < totalPages - 1) options.push({ label: 'Next Page →', value: '__next__' })
          }

          const selection = await terminal.readMenu('  Select a process:', options)

          if (!selection) continue
          if (selection === '__back__') return null
          if (selection === '__next__') { page++; continue }
          if (selection === '__prev__') { page--; continue }

          const selectedProc = running.find(p => p.process_id === selection)
          if (!selectedProc) continue

          const meta = selectedProc.process_metadata || {}
          const subOptions = [{ label: 'Back', value: '__back__' }]

          if (meta.type === 'akashic_scan') {
            subOptions.push({ label: 'View (re-hydrate scanner UI)', value: '__view__' })
          }
          subOptions.push({ label: 'Kill (terminate process)', value: '__kill__' })

          const subSelection = await terminal.readMenu(
            `  Action for ${selectedProc.program_name} (PID: ${selectedProc.process_id.substring(0, 8)}...):`,
            subOptions
          )

          if (!subSelection || subSelection === '__back__') continue

          if (subSelection === '__view__') {
            const scannerState = getActiveScannerState()
            if (scannerState.running) {
              terminal.write({ text: `  [ERR] Scanner is already active from another tab. Use /stop first or close the scanner tab.`, class: 'term-enemy' })
              await terminal.readLine('  Press ENTER to continue...')
              continue
            }

            terminal.clear()
            terminal.write({ text: `  [SYS] Re-hydrating Akashic scanner...`, class: 'term-dim' })

            // Reset the shared state for this rehydration
            Object.keys(scannerState).forEach(k => delete scannerState[k])
            scannerState.running = true
            scannerState.processId = selectedProc.process_id
            scannerState.machineIp = meta.machine_ip || connectedIp
            scannerState.machineId = machineId
            scannerState.initiatorIp = meta.initiator_ip || null
            scannerState.scanMode = meta.scan_mode || 'scan'
            scannerState.totalSegments = meta.target_blocks || meta.total_blocks || 5
            scannerState.rehydrateFrom = 'procmgr'
            scannerState.startOffset = meta.start_offset || null
            scannerState.blocksCompleted = 0 // DB will tell us actual progress

            const { runScanner } = await import('../akashicScannerCommand.js')
            runScanner({ terminal, tab, registry: ctx.registry }, scannerState).catch(e => {
              terminal.write({ text: `  [ERR] Scanner crashed: ${e.message}`, class: 'term-enemy' })
            })
            return null
          }

          if (subSelection === '__kill__') {
            try {
              // Cancel any akashic reservations before terminating
              if (meta.type === 'akashic_scan' && meta.machine_ip) {
                await supabase.functions.invoke('akashic-mining', {
                  body: { action: 'cancel', process_id: selectedProc.process_id, machine_ip: meta.machine_ip }
                }).catch(() => {})
              }
              const { data: result } = await supabase.rpc('complete_process', {
                p_process_id: selectedProc.process_id,
                p_status: 'terminated'
              })
              if (result?.success) {
                // Reset the shared scanner state so a new scan can start
                const scannerState = getActiveScannerState()
                if (scannerState.processId === selectedProc.process_id) {
                  scannerState.running = false
                  scannerState.processId = null
                }
                terminal.write({ text: `  [OK]  Process terminated. CPU ${result.resources_freed?.cpu_pct || 0}%, ${result.resources_freed?.memory_mb || 0}MB RAM freed.`, class: 'term-ally' })
                await new Promise(r => setTimeout(r, 1200))
              } else {
                terminal.write({ text: `  [ERR] ${result?.error || 'Unknown error'}`, class: 'term-enemy' })
                await terminal.readLine('  Press ENTER to continue...')
              }
            } catch (e) {
              terminal.write({ text: `  [ERR] ${e.message}`, class: 'term-enemy' })
              await terminal.readLine('  Press ENTER to continue...')
            }
            continue
          }
        }
      }
    },

    // ── Hidden legacy commands (kept for scriptability, not shown in /help) ──
    processes: {
      help: 'List active processes (legacy). Use /procmgr for the interactive manager.',
      usage: '/processes',
      hidden: true,
      async handler(args, ctx) { return ctx.registry.procmgr.handler(args, ctx) }
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

        const { isConnectedToVM, machineId } = getConnState()
        if (!isConnectedToVM) {
          return [{ text: '  [ERR] Not connected to a machine with admin access. Use /connect <vm_ip> first.', class: 'term-enemy' }]
        }

        // Check program definition exists
        const progDef = await getProgramDefinition(programName)
        if (!progDef) {
          return [{ text: `  [ERR] Unknown program: ${programName}`, class: 'term-enemy' }]
        }

        // Check machine has the program installed
        const installed = await machineHasProgram(machineId, programName)
        if (!installed) {
          return [
            { text: `  [ERR] Program "${programName}" is not installed on this machine.`, class: 'term-enemy' },
            { text: `  [SYS] Install it first or use a machine that has it.`, class: 'term-dim' }
          ]
        }

        // ── NEW: Ask scan_mode first (for akashic scan) ──
        let scanMode = 'scan'
        let totalSegments = 5
        if (programName === 'scan_records.exe') {
          // Check if there are unverified blocks available
          let hasUnverified = false
          try {
            const { data: unverified } = await supabase.rpc('get_unverified_blocks', { p_limit: 1 })
            hasUnverified = unverified && unverified.length > 0
          } catch (_) { hasUnverified = false }

          const modeOptions = [
            { label: 'Scan (discover new blocks — full payout)', value: 'scan' }
          ]
          if (hasUnverified) {
            modeOptions.push({ label: 'Verify (confirm existing blocks — 25% payout)', value: 'verify' })
          }
          terminal.write({ text: '  [SYS] Select scan mode:', class: 'term-steel' })
          scanMode = await terminal.readMenu('  >', modeOptions)
          if (!scanMode) return [{ text: '  [ERR] No mode selected.', class: 'term-enemy' }]

          // Ask how many segments
          terminal.write({ text: `  [SYS] How many segments to scan? (1-10)`, class: 'term-steel' })
          const segInput = await terminal.readLine('  > ')
          const segParsed = parseInt(segInput, 10)
          if (isNaN(segParsed) || segParsed < 1 || segParsed > 10) {
            return [{ text: '  [ERR] Must be 1-10 segments.', class: 'term-enemy' }]
          }
          totalSegments = segParsed
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
            p_machine_id: machineId,
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
          return runAkashicScan(ctx, progDef, installed, cpuAllocPct, scanMode, totalSegments)
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
        const { isConnectedToVM, machineId } = getConnState()
        if (!isConnectedToVM) {
          return [{ text: '  [ERR] Not connected to a machine with access. Use /connect <vm_ip> first.', class: 'term-enemy' }]
        }

        const { terminal } = ctx
        terminal.write({ text: '  [SYS] Querying installed programs...', class: 'term-dim' })

        try {
          const { data: programs, error } = await supabase
            .from('virtual_programs')
            .select('program_id, program_name, installed_at')
            .eq('machine_id', machineId)
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
            const version = '1.0.0'
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
          return lines
        } catch (e) {
          return [{ text: `  [ERR] ${e.message}`, class: 'term-enemy' }]
        }
      }
    },

    kill: {
      help: 'Terminate a running process by process ID. Use /procmgr instead.',
      usage: '/kill <pid_prefix>',
      hidden: true,
      async handler(args, ctx) {
        const { isConnectedToVM, machineId } = getConnState()
        if (!isConnectedToVM) {
          return [{ text: '  [ERR] Not connected to a machine with access.', class: 'term-enemy' }]
        }

        const pidPrefix = args[0]
        if (!pidPrefix) {
          return [{ text: '  [SYS] Usage: /kill <pid_prefix> (first 8 chars of process ID shown in /processes)', class: 'term-dim' }]
        }

        try {
          const { data: processes } = await supabase.rpc('get_machine_processes', {
            p_machine_id: machineId
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
    },

    view: {
      help: 'Re-hydrate a running process UI. Use /procmgr instead.',
      usage: '/view <pid_prefix>',
      hidden: true,
      async handler(args, ctx) {
        const { isConnectedToVM, machineId } = getConnState()
        if (!isConnectedToVM) {
          return [{ text: '  [ERR] Not connected to a machine with access.', class: 'term-enemy' }]
        }

        const pidPrefix = args[0]
        if (!pidPrefix) {
          return [{ text: '  [SYS] Usage: /view <pid_prefix> (first 8 chars of process ID from /processes)', class: 'term-dim' }]
        }

        const { terminal } = ctx

        try {
          const { data: processes } = await supabase.rpc('get_machine_processes', {
            p_machine_id: machineId
          })

          const match = processes?.find(p =>
            p.process_id.startsWith(pidPrefix) &&
            p.status === 'running'
          )

          if (!match) {
            return [{ text: `  [ERR] No running process found with PID prefix: ${pidPrefix}`, class: 'term-enemy' }]
          }

          const meta = match.process_metadata || {}
          if (meta.type !== 'akashic_scan') {
            return [{ text: `  [ERR] Process ${pidPrefix} is not an Akashic scan (type: ${meta.type || 'unknown'}). Only akashic_scan processes support /view.`, class: 'term-enemy' }]
          }

          // Check if scanner is already running in another tab
          const scannerState = getActiveScannerState()
          if (scannerState.running) {
            return [{ text: `  [ERR] Scanner is already active from another tab. Use /stop first or close the scanner tab.`, class: 'term-enemy' }]
          }

          // Re-hydrate the scanner UI
          terminal.write({ text: `  [SYS] Re-hydrating Akashic scanner for PID ${pidPrefix}...`, class: 'term-dim' })

          // Reset the shared state for this rehydration
          Object.keys(scannerState).forEach(k => delete scannerState[k])
          scannerState.running = true
          scannerState.processId = match.process_id
          scannerState.machineIp = meta.machine_ip || connectedIp
          scannerState.machineId = machineId
          scannerState.initiatorIp = meta.initiator_ip || null
          scannerState.scanMode = meta.scan_mode || 'scan'
          scannerState.totalSegments = meta.target_blocks || meta.total_blocks || 5
          scannerState.rehydrateFrom = 'view'
          scannerState.startOffset = meta.start_offset || null
          scannerState.blocksCompleted = 0 // DB will tell us actual progress

          const { runScanner } = await import('../akashicScannerCommand.js')
          runScanner({ terminal, tab: ctx.tab, registry: ctx.registry }, scannerState).catch(e => {
            terminal.write({ text: `  [ERR] Scanner crashed: ${e.message}`, class: 'term-enemy' })
          })

          return null
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
async function runAkashicScan(ctx, progDef, installedProgram, cpuAllocPct, scanMode, totalSegments) {
  const { terminal, tab } = ctx
  const { connectedIp, machineId } = getConnState()
  const playerState = usePlayerState()
  const machineIp = connectedIp
  const playerIp = playerState.get('ip_address', 'unknown')

  tab.setTitle('Akashic Scanner')

  terminal.write({ text: '  [SYS] Initializing Akashic Record Scanner...', class: 'term-dim' })
  terminal.write({ text: `  [SYS] Mode: ${scanMode.toUpperCase()} | Segments: ${totalSegments}`, class: 'term-steel' })
  terminal.write({ text: `  [SYS] CPU Allocation: ${cpuAllocPct > 0 ? cpuAllocPct + '%' : 'Flex (auto)'}`, class: 'term-steel' })
  terminal.write({ text: `  [NET] Machine IP: ${machineIp}`, class: 'term-dim' })
  terminal.write({ text: `  [SYS] Rewards attributed to your holy IP: ${playerIp}`, class: 'term-brass' })

  const startOffset = Math.floor(Math.random() * 666999111) + 1

  // Estimate completion: each segment roughly base_duration_seconds
  const estimatedDurationSec = calculateDuration(progDef.base_duration_seconds * totalSegments, cpuAllocPct, 1000)
  const expectedEndTime = new Date(Date.now() + estimatedDurationSec * 1000)

  terminal.write({ text: '  [SYS] Registering process...', class: 'term-dim' })
  let processId
  try {
    const { data: procData, error } = await supabase
      .from('virtual_processes')
      .insert({
        machine_id: machineId,
        program_id: installedProgram.program_id,
        cpu_alloc_pct: cpuAllocPct,
        memory_alloc_mb: progDef.base_memory_mb,
        storage_alloc_mb: progDef.base_storage_mb,
        status: 'running',
        expected_end_time: expectedEndTime.toISOString(),
        process_metadata: {
          type: 'akashic_scan',
          scan_mode: scanMode,
          target_blocks: totalSegments,
          start_offset: startOffset,
          total_blocks: totalSegments,
          block_speed_ms: 0,
          cpu_alloc_pct: cpuAllocPct,
          machine_ip: machineIp,
          initiator_ip: playerIp,
          blocks_completed: 0,
          start_time: new Date().toISOString(),
          is_verification: scanMode === 'verify'
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
    processId = null
  }

  terminal.write({ text: `  [SYS] Estimated completion: ${expectedEndTime.toLocaleTimeString()}`, class: 'term-dim' })
  terminal.write({ text: `  [SYS] The scan will complete even if you disconnect.`, class: 'term-steel' })
  terminal.write({ text: `  [SYS] Use /stop to abort the scan prematurely.`, class: 'term-ally' })
  terminal.write({ text: '  ' + '─'.repeat(50), class: 'term-dim' })

  // Use shared module-level scanner state so /stop and /end work
  const scannerState = getActiveScannerState()
  scannerState.running = true
  scannerState.processId = processId
  scannerState.machineIp = machineIp
  scannerState.machineId = machineId
  scannerState.initiatorIp = playerIp
  scannerState.scanMode = scanMode
  scannerState.totalSegments = totalSegments
  scannerState.startOffset = startOffset

  let blockIndex = 0

  const heartbeatInterval = setInterval(async () => {
    if (!processId || !scannerState.running) return
    await heartbeatProgress(processId, {
      type: 'akashic_scan',
      scan_mode: scanMode,
      target_blocks: totalSegments,
      start_offset: startOffset,
      total_blocks: totalSegments,
      block_speed_ms: scannerState.blockSpeedMs || 0,
      cpu_alloc_pct: cpuAllocPct,
      machine_ip: machineIp,
      initiator_ip: playerIp,
      blocks_completed: blockIndex,
      start_time: new Date().toISOString(),
      is_verification: scanMode === 'verify'
    })
  }, 10000)

  // Set heartbeat callback on scanner so it can update blockIndex
  scannerState.onHeartbeat = (completed, total) => {
    blockIndex = completed
  }

  try {
    const { runScanner } = await import('../akashicScannerCommand.js')
    // Fire-and-forget: do NOT await the full scan — this unblocks terminal input
    runScanner({ terminal, tab, registry: ctx.registry }, scannerState).catch(e => {
      terminal.write({ text: `  [ERR] Scanner crashed: ${e.message}`, class: 'term-enemy' })
    })
    // Return immediately so the terminal stays responsive.
    // The scanner loops check scannerState.running on every tick.
    // Heartbeat and cleanup are handled by the scanner's finally block.
  } catch (e) {
    terminal.write({ text: `  [ERR] Scanner launch failed: ${e.message}`, class: 'term-enemy' })
    clearInterval(heartbeatInterval)
    if (processId) {
      try {
        await supabase.rpc('complete_process', { p_process_id: processId, p_status: 'failed' })
      } catch (_) {}
    }
  }

  // Scanner is now running in background.
  // heartbeatInterval stays alive; scannerState.running check gates heartbeats.
  // runScanner handles its own cleanup of the virtual_processes row on completion/stop.
  return null
}