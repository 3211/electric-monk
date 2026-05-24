import { supabase } from '@/lib/supabase'
import { usePlayerState } from '@/composables/usePlayerState'

/**
 * Virtual File System Manager — /files, /delete, /cd, /rmdir, /listdir, /rmfile, /mkdir, /cat, /encrypt, /storage
 *
 * Integrates with the manage-files edge function for all DB-backed operations.
 * Files are NEVER actually deleted — soft-delete via deletion_level.
 * Akashic records have encryption_level = 0 (decrypted).
 *
 * Supports full path-based navigation with /cd, directory trees with /files,
 * and the complete standard CLI file management toolkit.
 */

// ── Helpers ──

function getConnState() {
  const ps = usePlayerState()
  return {
    ps,
    connectedIp: ps.connectedIp.value,
    machineId: ps.machineId.value,
    machineAccess: ps.machineAccess.value,
    isConnectedToVM: ps.isConnectedToVM.value,
  }
}

/** Wraps manage-files edge function call */
async function callManageFiles(action, body = {}) {
  const { data, error } = await supabase.functions.invoke('manage-files', {
    body: { action, ...body },
  })
  if (error) throw new Error(error.message || 'Edge function error')
  if (!data.success) throw new Error(data.error || 'Unknown error')
  return data
}

/**
 * Normalize a user-provided path like "foo/bar/" or "/foo/bar" into
 * our internal representation (no leading/trailing slashes, null = root).
 */
function normalizeInputPath(raw) {
  if (!raw || raw === '/' || raw === '') return null
  let p = raw.replace(/\/{2,}/g, '/')
  if (p.startsWith('/')) p = p.substring(1)
  if (p.endsWith('/')) p = p.substring(0, p.length - 1)
  return p || null
}

/**
 * Join a current directory and a target path.
 * Supports relative paths and ".."
 */
function resolvePath(currentDir, target) {
  if (!target || target === '/') return null
  if (target.startsWith('/')) return normalizeInputPath(target)

  const parts = (currentDir ? currentDir.split('/') : [])
  const targetParts = target.split('/')

  for (const part of targetParts) {
    if (part === '..') {
      parts.pop()
    } else if (part !== '.' && part !== '') {
      parts.push(part)
    }
  }

  if (parts.length === 0) return null
  return parts.join('/')
}

// ── ASCII Tree Renderer ──

/** File/folder emoji mapping */
const FILE_ICONS = {
  directory: '📁',
  record: '📜',
  text: '📄',
  encrypted: '🔒',
  hidden: '👻',
  default: '📄',
}

function getFileIcon(node) {
  if (node.is_directory) return FILE_ICONS.directory
  if (node.deletion_level > 0) return FILE_ICONS.hidden
  if (node.encryption_level > 0) return FILE_ICONS.encrypted
  if (node.file_name?.endsWith('.record')) return FILE_ICONS.record
  return FILE_ICONS.default
}

function formatFileSize(bytes) {
  if (bytes < 1024) return `${bytes}B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)}KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)}MB`
}

/**
 * Build an ASCII tree from flat nodes array (sorted by sort_path).
 * Each node: { file_id, file_name, is_directory, file_size_bytes, encryption_level, deletion_level, depth, ... }
 */
function buildAsciiTree(nodes) {
  if (!nodes || nodes.length === 0) return [{ text: '  (empty)', class: 'term-dim' }]

  const lines = []

  for (let i = 0; i < nodes.length; i++) {
    const node = nodes[i]
    const depth = node.depth || 0
    const isLast = (() => {
      // A node is "last" at its depth if no subsequent sibling at same depth
      for (let j = i + 1; j < nodes.length; j++) {
        if (nodes[j].depth < depth) return true
        if (nodes[j].depth === depth) return false
      }
      return true
    })()

    // Build connector prefix
    let prefix = '  '
    if (depth > 0) {
      // Need to walk ancestors to determine vertical bars
      const ancestorStack = []
      for (let j = i - 1; j >= 0; j--) {
        if (nodes[j].depth < depth) {
          ancestorStack.unshift(nodes[j])
          if (ancestorStack.length === depth) break
        }
      }
      // For each ancestor depth, check if there's a future sibling at that depth
      for (let d = 0; d < depth; d++) {
        let hasFutureSibling = false
        for (let k = i + 1; k < nodes.length; k++) {
          if (nodes[k].depth < d + 1) break
          if (nodes[k].depth === d + 1) {
            hasFutureSibling = true
            break
          }
        }
        prefix += hasFutureSibling ? '│ ' : '  '
      }
      prefix += isLast ? '└─' : '├─'
    }

    const icon = getFileIcon(node)
    const name = node.file_name || '(unnamed)'
    const size = node.is_directory ? '' : ` ${formatFileSize(node.file_size_bytes)}`
    const badges = []
    if (node.encryption_level > 0) badges.push(`🔒L${node.encryption_level}`)
    if (node.deletion_level > 0) badges.push('🗑')
    const badgeStr = badges.length > 0 ? ` [${badges.join('')}]` : ''

    const cls = node.deletion_level > 0 ? 'term-dim'
              : node.encryption_level > 0 ? 'term-amber'
              : node.is_directory ? 'term-brass'
              : node.file_name?.endsWith('.record') ? 'term-holy'
              : 'term-text'

    lines.push({ text: `${prefix}${icon} ${name}${size}${badgeStr}`, class: cls })
  }

  return lines
}

// ── Command Builders ──

export function buildFileCommands() {
  return {
    files: {
      help: 'Display the virtual file system as an ASCII directory tree with emoji icons.',
      usage: '/files [path] [/h for hidden files]',
      async handler(args, ctx) {
        const { isConnectedToVM, machineId } = getConnState()
        if (!isConnectedToVM) {
          return [{ text: '  [ERR] Not connected to a machine with access. Use /connect <vm_ip> first.', class: 'term-enemy' }]
        }

        const { terminal, tab } = ctx
        tab.setTitle('Files')

        const showHidden = args.includes('/h')
        // Remove flag args to get the path
        const pathArg = args.filter(a => !a.startsWith('/')).join('/') || null
        const targetPath = normalizeInputPath(pathArg)

        terminal.write({ text: '  [SYS] Building file tree...', class: 'term-dim' })

        try {
          const result = await callManageFiles('tree', {
            machine_id: machineId,
            show_hidden: showHidden,
          })

          const nodes = result.nodes || []
          const totalSize = nodes
            .filter(n => !n.is_directory)
            .reduce((sum, n) => sum + (n.file_size_bytes || 0), 0)

          const bar = '─'.repeat(58)
          const lines = [
            { text: `  ${bar}`, class: 'term-dim' },
            { text: `  FILE SYSTEM — ${result.total_count || 0} entries, ${formatFileSize(totalSize)} total`, class: 'term-brass term-bold' },
            { text: `  ${bar}`, class: 'term-dim' },
            { text: '', class: '' },
          ]

          if (showHidden) {
            lines.push({ text: '  [Showing hidden files — /h mode]', class: 'term-amber' })
          }

          // Build tree
          const treeLines = buildAsciiTree(nodes)
          lines.push(...treeLines)

          lines.push({ text: '', class: '' })
          lines.push({ text: `  ${bar}`, class: 'term-dim' })
          lines.push({ text: '  Commands: /cd <dir>  /mkdir <name>  /rmdir <name>  /delete <file>  /cat <file>  /encrypt <file> <0-3>', class: 'term-steel' })
          lines.push({ text: `  ${bar}`, class: 'term-dim' })

          return lines
        } catch (e) {
          return [{ text: `  [ERR] ${e.message}`, class: 'term-enemy' }]
        }
      },
    },

    cd: {
      help: 'Change the current working directory in the virtual file system.',
      usage: '/cd <path>  (use /cd / for root, /cd .. to go up)',
      async handler(args, ctx) {
        const { isConnectedToVM, machineId } = getConnState()
        if (!isConnectedToVM) {
          return [{ text: '  [ERR] Not connected to a machine with access.', class: 'term-enemy' }]
        }

        const { terminal, tab, registry } = ctx
        const targetPath = args[0] || '/'
        const currentDir = registry._cwd || null

        const resolvedPath = resolvePath(currentDir, targetPath)
        tab.setTitle(resolvedPath ? `/${resolvedPath}` : '/')

        // Store the CWD in the registry for subsequent commands
        registry._cwd = resolvedPath

        if (resolvedPath) {
          return [{ text: `  📁 Current directory: /${resolvedPath}`, class: 'term-brass' }]
        }
        return [{ text: '  📁 Current directory: / (root)', class: 'term-brass' }]
      },
    },

    listdir: {
      help: 'List the contents of a directory (or current directory if no path given).',
      usage: '/listdir [path]',
      async handler(args, ctx) {
        const { isConnectedToVM, machineId } = getConnState()
        if (!isConnectedToVM) {
          return [{ text: '  [ERR] Not connected to a machine with access.', class: 'term-enemy' }]
        }

        const { terminal, tab, registry } = ctx
        tab.setTitle('List Directory')

        const rawPath = args[0]
        const currentDir = registry._cwd || null
        const targetPath = rawPath ? resolvePath(currentDir, rawPath) : currentDir

        terminal.write({ text: `  [SYS] Listing: ${targetPath ? '/' + targetPath : '/'}`, class: 'term-dim' })

        try {
          const result = await callManageFiles('list', {
            machine_id: machineId,
            target_path: targetPath,
          })

          const files = result.files || []

          if (files.length === 0) {
            return [
              { text: `  Directory: ${targetPath ? '/' + targetPath : '/'}`, class: 'term-brass' },
              { text: '  (empty)', class: 'term-dim' },
            ]
          }

          const lines = [
            { text: `  Directory: ${targetPath ? '/' + targetPath : '/'}`, class: 'term-brass' },
            { text: `  ${'─'.repeat(70)}`, class: 'term-dim' },
          ]

          for (const f of files) {
            const icon = getFileIcon(f)
            const size = f.is_directory ? '<DIR>' : formatFileSize(f.file_size_bytes)
            const badges = []
            if (f.encryption_level > 0) badges.push(`L${f.encryption_level}`)
            if (f.deletion_level > 0) badges.push('DEL')
            const badgeStr = badges.length > 0 ? ` [${badges.join(',')}]` : ''

            const cls = f.is_directory ? 'term-brass' : f.file_name?.endsWith('.record') ? 'term-holy' : 'term-text'
            lines.push({ text: `  ${icon} ${f.file_name.padEnd(36)} ${size.padStart(10)}${badgeStr}`, class: cls })
          }

          lines.push({ text: `  ${'─'.repeat(70)}`, class: 'term-dim' })
          lines.push({ text: `  ${files.length} item(s)`, class: 'term-steel' })

          return lines
        } catch (e) {
          return [{ text: `  [ERR] ${e.message}`, class: 'term-enemy' }]
        }
      },
    },

    mkdir: {
      help: 'Create a new directory in the virtual file system.',
      usage: '/mkdir <directory_name>',
      async handler(args, ctx) {
        const { isConnectedToVM, machineId } = getConnState()
        if (!isConnectedToVM) {
          return [{ text: '  [ERR] Not connected to a machine with access.', class: 'term-enemy' }]
        }

        const { registry } = ctx
        const dirName = args[0]
        if (!dirName) {
          return [{ text: '  [SYS] Usage: /mkdir <directory_name>', class: 'term-dim' }]
        }

        const currentDir = registry._cwd || null

        try {
          const result = await callManageFiles('mkdir', {
            machine_id: machineId,
            dir_path: currentDir,
            dir_name: dirName,
          })

          return [
            { text: `  📁 Directory created: ${result.dir_path || dirName}`, class: 'term-ally' },
            { text: `  ID: ${result.file_id.substring(0, 8)}...`, class: 'term-dim' },
          ]
        } catch (e) {
          return [{ text: `  [ERR] ${e.message}`, class: 'term-enemy' }]
        }
      },
    },

    rmdir: {
      help: 'Remove a directory and all its contents (soft-delete — files remain in database).',
      usage: '/rmdir <directory_name>',
      async handler(args, ctx) {
        const { isConnectedToVM, machineId } = getConnState()
        if (!isConnectedToVM) {
          return [{ text: '  [ERR] Not connected to a machine with access.', class: 'term-enemy' }]
        }

        const { terminal, registry } = ctx
        const dirName = args[0]
        if (!dirName) {
          return [{ text: '  [SYS] Usage: /rmdir <directory_name>', class: 'term-dim' }]
        }

        const currentDir = registry._cwd || null

        try {
          // First find the directory
          const listResult = await callManageFiles('list', {
            machine_id: machineId,
            target_path: currentDir,
          })

          const dir = (listResult.files || []).find(
            f => f.is_directory && f.file_name === dirName
          )

          if (!dir) {
            return [{ text: `  [ERR] Directory not found: ${dirName}`, class: 'term-enemy' }]
          }

          const result = await callManageFiles('rmdir', {
            machine_id: machineId,
            dir_id: dir.file_id,
          })

          return [
            { text: `  🗑 Directory removed: ${dirName}`, class: 'term-ally' },
            { text: `  [Files are soft-deleted and remain in the database]`, class: 'term-dim' },
          ]
        } catch (e) {
          return [{ text: `  [ERR] ${e.message}`, class: 'term-enemy' }]
        }
      },
    },

    rmfile: {
      help: 'Delete a file (soft-delete — file remains in database, hidden from view).',
      usage: '/rmfile <filename>',
      async handler(args, ctx) {
        return ctx.registry.delete.handler(args, ctx)
      },
    },

    delete: {
      help: 'Soft-delete a file or directory. Items are hidden but never removed from the database.',
      usage: '/delete <filename_or_directory> [/purge for deletion level 2]',
      async handler(args, ctx) {
        const { isConnectedToVM, machineId } = getConnState()
        if (!isConnectedToVM) {
          return [{ text: '  [ERR] Not connected to a machine with access.', class: 'term-enemy' }]
        }

        const { terminal, registry } = ctx
        const targetName = args.find(a => !a.startsWith('/'))
        const isPurge = args.includes('/purge')

        if (!targetName) {
          return [{ text: '  [SYS] Usage: /delete <filename_or_directory> [/purge]', class: 'term-dim' }]
        }

        const currentDir = registry._cwd || null
        const deletionLevel = isPurge ? 2 : 1

        try {
          // Find the file/directory
          const listResult = await callManageFiles('list', {
            machine_id: machineId,
            target_path: currentDir,
          })

          const target = (listResult.files || []).find(f => f.file_name === targetName)

          if (!target) {
            return [{ text: `  [ERR] File/directory not found: ${targetName}`, class: 'term-enemy' }]
          }

          const result = await callManageFiles('delete', {
            machine_id: machineId,
            file_id: target.file_id,
            deletion_level: deletionLevel,
          })

          const levelLabel = deletionLevel === 2 ? 'PURGED' : 'hidden'
          const icon = target.is_directory ? '📁' : '📄'

          const lines = [
            { text: `  🗑 Deleted: ${icon} ${targetName} (${levelLabel})`, class: 'term-ally' },
            { text: `  [File is soft-deleted — data remains in database]`, class: 'term-dim' },
          ]

          if (deletionLevel === 2) {
            lines.push({ text: `  [PURGE: File flagged as purged. Only admins can recover.]`, class: 'term-amber' })
          }

          // Recommend /delete if storage is getting full
          try {
            const storageResult = await callManageFiles('storage', { machine_id: machineId })
            if (storageResult.usage_percent > 80) {
              lines.push({ text: `  ⚠ Storage: ${storageResult.usage_percent}% full. Consider /delete to free space.`, class: 'term-amber' })
            }
          } catch (_) {}

          return lines
        } catch (e) {
          return [{ text: `  [ERR] ${e.message}`, class: 'term-enemy' }]
        }
      },
    },

    cat: {
      help: 'Display the contents of a file. Encrypted files show obfuscated content.',
      usage: '/cat <filename>',
      async handler(args, ctx) {
        const { isConnectedToVM, machineId } = getConnState()
        if (!isConnectedToVM) {
          return [{ text: '  [ERR] Not connected to a machine with access.', class: 'term-enemy' }]
        }

        const { terminal, registry } = ctx
        const fileName = args[0]
        if (!fileName) {
          return [{ text: '  [SYS] Usage: /cat <filename>', class: 'term-dim' }]
        }

        const currentDir = registry._cwd || null

        try {
          // Find the file
          const listResult = await callManageFiles('list', {
            machine_id: machineId,
            target_path: currentDir,
          })

          const file = (listResult.files || []).find(
            f => f.file_name === fileName && !f.is_directory
          )

          if (!file) {
            return [{ text: `  [ERR] File not found: ${fileName}`, class: 'term-enemy' }]
          }

          terminal.write({ text: `  [SYS] Reading ${fileName} (${formatFileSize(file.file_size_bytes)})...`, class: 'term-dim' })

          const result = await callManageFiles('read', {
            machine_id: machineId,
            file_id: file.file_id,
          })

          const lines = [
            { text: `  ═══════════════════════════════════════`, class: 'term-dim' },
            { text: `  FILE: ${result.file_name}  |  ${formatFileSize(result.file_size_bytes)}  |  Enc: L${result.encryption_level}`, class: 'term-brass' },
            { text: `  ═══════════════════════════════════════`, class: 'term-dim' },
          ]

          if (result.is_obfuscated) {
            lines.push({ text: `  ⚠ Content is encrypted (Level ${result.encryption_level}). Display is obfuscated.`, class: 'term-amber' })
          }

          lines.push({ text: '', class: '' })

          // Display content (truncated to reasonable terminal width)
          const content = result.content || ''
          const maxDisplay = 5000
          const displayContent = content.length > maxDisplay
            ? content.substring(0, maxDisplay) + `\n\n[... ${content.length - maxDisplay} more characters ...]`
            : content

          // Split content into lines for display
          const contentLines = displayContent.split('\n')
          for (const line of contentLines.slice(0, 100)) {
            lines.push({ text: `  ${line.substring(0, 78)}`, class: 'term-text' })
          }

          if (contentLines.length > 100) {
            lines.push({ text: `  [... ${contentLines.length - 100} more lines ...]`, class: 'term-dim' })
          }

          lines.push({ text: `  ═══════════════════════════════════════`, class: 'term-dim' })

          return lines
        } catch (e) {
          return [{ text: `  [ERR] ${e.message}`, class: 'term-enemy' }]
        }
      },
    },

    encrypt: {
      help: 'Set the encryption level on a file (0 = decrypted, 1-3 = encrypted tiers).',
      usage: '/encrypt <filename> <0|1|2|3>',
      async handler(args, ctx) {
        const { isConnectedToVM, machineId } = getConnState()
        if (!isConnectedToVM) {
          return [{ text: '  [ERR] Not connected to a machine with access.', class: 'term-enemy' }]
        }

        const { registry } = ctx
        const fileName = args[0]
        const encLevel = parseInt(args[1], 10)

        if (!fileName || isNaN(encLevel) || encLevel < 0 || encLevel > 3) {
          return [{ text: '  [SYS] Usage: /encrypt <filename> <0|1|2|3>', class: 'term-dim' }]
        }

        const currentDir = registry._cwd || null

        try {
          const listResult = await callManageFiles('list', {
            machine_id: machineId,
            target_path: currentDir,
          })

          const file = (listResult.files || []).find(f => f.file_name === fileName && !f.is_directory)

          if (!file) {
            return [{ text: `  [ERR] File not found: ${fileName}`, class: 'term-enemy' }]
          }

          const result = await callManageFiles('encrypt', {
            machine_id: machineId,
            file_id: file.file_id,
            encryption_level: encLevel,
          })

          const levelLabels = ['Decrypted (plaintext)', 'Light encryption', 'Medium encryption', 'Heavy encryption']
          const cls = encLevel === 0 ? 'term-ally' : 'term-amber'

          return [
            { text: `  🔒 ${fileName}: Encryption set to Level ${encLevel} — ${levelLabels[encLevel]}`, class: cls },
            { text: `  [File content remains in database. Encryption affects /cat readability.]`, class: 'term-dim' },
          ]
        } catch (e) {
          return [{ text: `  [ERR] ${e.message}`, class: 'term-enemy' }]
        }
      },
    },

    storage: {
      help: 'Display virtual machine storage usage, capacity, and how many akashic blocks will fit.',
      usage: '/storage',
      async handler(args, ctx) {
        const { isConnectedToVM, machineId } = getConnState()
        if (!isConnectedToVM) {
          return [{ text: '  [ERR] Not connected to a machine with access.', class: 'term-enemy' }]
        }

        const { terminal, tab } = ctx
        tab.setTitle('Storage')
        terminal.write({ text: '  [SYS] Calculating storage...', class: 'term-dim' })

        try {
          const result = await callManageFiles('storage', {
            machine_id: machineId,
            bytes_per_block: 6400, // 2 files × 3200 bytes each
          })

          const bar = '─'.repeat(58)
          const usageBarLen = 40
          const filled = Math.round((result.usage_percent / 100) * usageBarLen)
          const empty = usageBarLen - filled

          const usageClass = result.usage_percent > 90 ? 'term-enemy'
                           : result.usage_percent > 75 ? 'term-amber'
                           : 'term-ally'

          return [
            { text: `  ${bar}`, class: 'term-dim' },
            { text: '  STORAGE STATISTICS', class: 'term-brass term-bold' },
            { text: `  ${bar}`, class: 'term-dim' },
            { text: '', class: '' },
            { text: `  Capacity : ${result.capacity_mb.toLocaleString()} MB`, class: 'term-text' },
            { text: `  Used     : ${result.used_mb.toLocaleString()} MB (${result.usage_percent}%)`, class: usageClass },
            { text: `  Free     : ${result.available_mb.toLocaleString()} MB`, class: 'term-ally' },
            { text: '', class: '' },
            { text: `  [${'█'.repeat(filled)}${'░'.repeat(empty)}] ${result.usage_percent}%`, class: 'term-steel' },
            { text: '', class: '' },
            { text: `  Akashic Blocks That Will Fit: ${result.blocks_that_fit}`, class: 'term-holy' },
            { text: `  (Each block = 2 files × 3,200 bytes = 6,400 bytes)`, class: 'term-dim' },
            { text: '', class: '' },
            ...(result.blocks_that_fit < 5 ? [
              { text: `  ⚠ Low storage! Consider running /delete on old files.`, class: 'term-enemy' },
              { text: '  Run /files to see your file tree and free up space.', class: 'term-steel' },
            ] : []),
            ...(result.blocks_that_fit === 0 ? [
              { text: `  ⛔ STORAGE FULL — scan will stop mid-block. /delete required.`, class: 'term-enemy term-bold' },
            ] : []),
            { text: '', class: '' },
            { text: `  ${bar}`, class: 'term-dim' },
          ]
        } catch (e) {
          return [{ text: `  [ERR] ${e.message}`, class: 'term-enemy' }]
        }
      },
    },
  }
}