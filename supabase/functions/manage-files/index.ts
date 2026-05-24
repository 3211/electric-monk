// Supabase Edge Function: manage-files
// Handles virtual file system operations: LIST, CREATE, DELETE, READ, MKDIR, RMDIR, ENCRYPT, TREE
//
// ACTIONS:
//   list    — List files in a directory (with optional recursion depth)
//   tree    — Full ASCII-tree-compatible recursive listing
//   create  — Create a new file with content
//   read    — Read file content (respects encryption_level for display)
//   delete  — Soft-delete a file (sets deletion_level, never removes rows)
//   mkdir   — Create a directory placeholder
//   rmdir   — Remove a directory (soft-deletes all children)
//   encrypt — Set encryption level on a file (0-3)
//   storage — Get storage stats (used, capacity, blocks_that_fit)

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

function cleanIp(ip: string): string {
  return ip.replace(/\/\d+$/, '')
}

async function verifyMachineOwnership(machineId: string, userId: string): Promise<{ ownerIp: string; machineIp: string }> {
  const rows = await sql`
    SELECT host(vm.owner_identity) as owner_ip, host(vm.ip_address) as machine_ip
    FROM public.virtual_machines vm
    JOIN public.players p ON vm.owner_identity = p.ip_address
    WHERE vm.machine_id = ${machineId} AND p.id = ${userId}
  `
  if (rows.length === 0) {
    throw new Error("Machine not found or you do not own it")
  }
  return { ownerIp: rows[0].owner_ip, machineIp: rows[0].machine_ip }
}

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

    // ═══════════════════════════════════════
    // ACTION: list — list files in a directory
    // ═══════════════════════════════════════
    if (action === "list") {
      const machineId: string = body.machine_id
      const targetPath: string | null = body.target_path || null
      const showHidden: boolean = body.show_hidden || false

      if (!machineId) throw new Error("Missing 'machine_id'")
      await verifyMachineOwnership(machineId, userId)

      const files = await sql`
        SELECT file_id, file_path, file_name, file_size_bytes, file_size_mb,
               encryption_level, deletion_level, is_directory,
               akashic_block_id, akashic_address_type, content_hash, updated_at
        FROM public.virtual_files
        WHERE machine_id = ${machineId}
          AND parent_path IS NOT DISTINCT FROM ${targetPath}
          AND (${showHidden} OR deletion_level = 0)
        ORDER BY is_directory DESC, file_name ASC
      `

      return new Response(JSON.stringify({
        success: true,
        action: "list",
        target_path: targetPath,
        files: files.map(f => ({
          ...f,
          file_size_bytes: Number(f.file_size_bytes),
          file_size_mb: Number(f.file_size_mb),
        })),
      }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    // ═══════════════════════════════════════
    // ACTION: tree — full recursive file tree
    // ═══════════════════════════════════════
    else if (action === "tree") {
      const machineId: string = body.machine_id
      const showHidden: boolean = body.show_hidden || false

      if (!machineId) throw new Error("Missing 'machine_id'")
      await verifyMachineOwnership(machineId, userId)

      const [result] = await sql`
        SELECT public.get_file_tree(${machineId}::UUID, ${showHidden}) as tree
      `
      // get_file_tree returns a setof records; we need to query it differently
      const tree = await sql`
        SELECT * FROM public.get_file_tree(${machineId}::UUID, ${showHidden})
      `

      // Build a tree structure from flat results
      const nodes = tree.map((row: Record<string, unknown>) => ({
        file_id: row.file_id,
        file_path: row.file_path,
        file_name: row.file_name,
        is_directory: row.is_directory,
        file_size_bytes: Number(row.file_size_bytes),
        encryption_level: row.encryption_level,
        deletion_level: row.deletion_level,
        akashic_block_id: row.akashic_block_id,
        akashic_address_type: row.akashic_address_type,
        parent_path: row.parent_path,
        depth: Number(row.depth),
      }))

      return new Response(JSON.stringify({
        success: true,
        action: "tree",
        nodes,
        total_count: nodes.length,
      }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    // ═══════════════════════════════════════
    // ACTION: read — read file content
    // ═══════════════════════════════════════
    else if (action === "read") {
      const machineId: string = body.machine_id
      const fileId: string = body.file_id

      if (!machineId || !fileId) throw new Error("Missing 'machine_id' or 'file_id'")
      await verifyMachineOwnership(machineId, userId)

      const [file] = await sql`
        SELECT file_id, file_name, file_path, file_content, file_size_bytes,
               encryption_level, deletion_level, is_directory
        FROM public.virtual_files
        WHERE file_id = ${fileId} AND machine_id = ${machineId}
      `

      if (!file) throw new Error("File not found")
      if (file.is_directory) throw new Error("Cannot read a directory. Use /listdir instead.")

      // Content obfuscation based on encryption_level
      let displayContent = file.file_content || ''
      if (file.encryption_level >= 3) {
        displayContent = '[ENCRYPTED-LEVEL-3] File content is heavily encrypted and unreadable.'
      } else if (file.encryption_level >= 2) {
        // Show only first 10% of content
        const cutoff = Math.floor(displayContent.length * 0.1)
        displayContent = displayContent.substring(0, cutoff) + '\n\n[... content truncated: encryption level 2 ...]'
      } else if (file.encryption_level >= 1) {
        // Scramble every other character
        displayContent = displayContent.split('').map((c: string, i: number) =>
          i % 3 === 0 ? '█' : c
        ).join('')
      }

      return new Response(JSON.stringify({
        success: true,
        action: "read",
        file_id: file.file_id,
        file_name: file.file_name,
        file_path: file.file_path,
        file_size_bytes: Number(file.file_size_bytes),
        encryption_level: file.encryption_level,
        content: displayContent,
        is_obfuscated: file.encryption_level > 0,
      }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    // ═══════════════════════════════════════
    // ACTION: create — create a new file
    // ═══════════════════════════════════════
    else if (action === "create") {
      const machineId: string = body.machine_id
      const filePath: string = body.file_path          // parent directory path
      const fileName: string = body.file_name
      const fileContent: string = body.file_content || ''
      const ownerIp: string = body.owner_ip || null

      if (!machineId || !fileName) throw new Error("Missing 'machine_id' or 'file_name'")
      const { ownerIp: verifiedOwnerIp } = await verifyMachineOwnership(machineId, userId)

      const normalizedPath = filePath || null
      const effectiveOwnerIp = ownerIp || verifiedOwnerIp

      const contentBytes = new TextEncoder().encode(fileContent).length

      const [newFile] = await sql`
        INSERT INTO public.virtual_files (
          machine_id, owner_identity, file_path, file_name,
          file_content, file_size_bytes, file_size_mb,
          encryption_level, deletion_level, is_directory
        ) VALUES (
          ${machineId},
          ${effectiveOwnerIp}::inet,
          ${normalizedPath},
          ${fileName},
          ${fileContent},
          ${contentBytes},
          ${Math.ceil(contentBytes / (1024 * 1024))},
          0, 0, false
        )
        RETURNING file_id, file_name, file_path, file_size_bytes, created_at
      `

      return new Response(JSON.stringify({
        success: true,
        action: "create",
        file_id: newFile.file_id,
        file_name: newFile.file_name,
        file_path: newFile.file_path,
        file_size_bytes: Number(newFile.file_size_bytes),
      }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    // ═══════════════════════════════════════
    // ACTION: delete — soft-delete a file
    // ═══════════════════════════════════════
    else if (action === "delete") {
      const machineId: string = body.machine_id
      const fileId: string = body.file_id
      const deletionLevel: number = body.deletion_level || 1  // 1 = hidden, 2 = purged

      if (!machineId || !fileId) throw new Error("Missing 'machine_id' or 'file_id'")
      await verifyMachineOwnership(machineId, userId)

      if (deletionLevel < 1 || deletionLevel > 2) {
        throw new Error("deletion_level must be 1 (hidden) or 2 (purged)")
      }

      const [result] = await sql`
        SELECT public.soft_delete_file(${fileId}::UUID, ${deletionLevel}) as result
      `

      return new Response(JSON.stringify({
        success: true,
        action: "delete",
        ...result.result,
      }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    // ═══════════════════════════════════════
    // ACTION: mkdir — create a directory
    // ═══════════════════════════════════════
    else if (action === "mkdir") {
      const machineId: string = body.machine_id
      const dirPath: string = body.dir_path               // normalized parent path
      const dirName: string = body.dir_name
      const ownerIp: string = body.owner_ip || null

      if (!machineId || !dirName) throw new Error("Missing 'machine_id' or 'dir_name'")
      const { ownerIp: verifiedOwnerIp } = await verifyMachineOwnership(machineId, userId)

      const normalizedParentPath = dirPath || null
      const effectiveOwnerIp = ownerIp || verifiedOwnerIp

      // Check for duplicate directory
      const existing = await sql`
        SELECT file_id FROM public.virtual_files
        WHERE machine_id = ${machineId}
          AND file_name = ${dirName}
          AND parent_path IS NOT DISTINCT FROM ${normalizedParentPath}
          AND is_directory = true
          AND deletion_level = 0
      `
      if (existing.length > 0) {
        throw new Error(`Directory '${dirName}' already exists at this path`)
      }

      const [newDir] = await sql`
        INSERT INTO public.virtual_files (
          machine_id, owner_identity, file_path, file_name,
          file_content, file_size_bytes, file_size_mb,
          encryption_level, deletion_level, is_directory,
          parent_path
        ) VALUES (
          ${machineId},
          ${effectiveOwnerIp}::inet,
          ${normalizedParentPath ? normalizedParentPath + '/' + dirName : dirName},
          ${dirName},
          '',
          0, 0,
          0, 0, true,
          ${normalizedParentPath}
        )
        RETURNING file_id, file_name, file_path
      `

      return new Response(JSON.stringify({
        success: true,
        action: "mkdir",
        file_id: newDir.file_id,
        dir_name: newDir.file_name,
        dir_path: newDir.file_path,
      }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    // ═══════════════════════════════════════
    // ACTION: rmdir — remove a directory
    // ═══════════════════════════════════════
    else if (action === "rmdir") {
      const machineId: string = body.machine_id
      const dirId: string = body.dir_id

      if (!machineId || !dirId) throw new Error("Missing 'machine_id' or 'dir_id'")
      await verifyMachineOwnership(machineId, userId)

      // Verify it's actually a directory
      const [dir] = await sql`
        SELECT file_id, file_name, file_path, is_directory
        FROM public.virtual_files
        WHERE file_id = ${dirId} AND machine_id = ${machineId}
      `
      if (!dir) throw new Error("Directory not found")
      if (!dir.is_directory) throw new Error("Target is not a directory. Use /rmfile for files.")

      // Soft-delete the directory and all children
      const [result] = await sql`
        SELECT public.soft_delete_file(${dirId}::UUID, 1) as result
      `

      return new Response(JSON.stringify({
        success: true,
        action: "rmdir",
        ...result.result,
      }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    // ═══════════════════════════════════════
    // ACTION: encrypt — set encryption level
    // ═══════════════════════════════════════
    else if (action === "encrypt") {
      const machineId: string = body.machine_id
      const fileId: string = body.file_id
      const encryptionLevel: number = body.encryption_level

      if (!machineId || !fileId) throw new Error("Missing 'machine_id' or 'file_id'")
      if (encryptionLevel === undefined || encryptionLevel < 0 || encryptionLevel > 3) {
        throw new Error("encryption_level must be 0-3")
      }
      await verifyMachineOwnership(machineId, userId)

      const [result] = await sql`
        SELECT public.encrypt_file(${fileId}::UUID, ${encryptionLevel}) as result
      `

      return new Response(JSON.stringify({
        success: true,
        action: "encrypt",
        ...result.result,
      }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    // ═══════════════════════════════════════
    // ACTION: storage — get storage stats
    // ═══════════════════════════════════════
    else if (action === "storage") {
      const machineId: string = body.machine_id
      const bytesPerBlock: number = body.bytes_per_block || 6400

      if (!machineId) throw new Error("Missing 'machine_id'")
      await verifyMachineOwnership(machineId, userId)

      const [capacityResult] = await sql`
        SELECT public.get_machine_storage_capacity(${machineId}::UUID) as capacity_bytes
      `
      const [usedResult] = await sql`
        SELECT public.calculate_total_storage_used(${machineId}::UUID) as used_bytes
      `
      const [blocksResult] = await sql`
        SELECT public.calculate_blocks_that_fit(${machineId}::UUID, ${bytesPerBlock}) as blocks_that_fit
      `

      const capacityBytes = Number(capacityResult.capacity_bytes)
      const usedBytes = Number(usedResult.used_bytes)
      const availableBytes = Math.max(0, capacityBytes - usedBytes)
      const usagePercent = capacityBytes > 0 ? Math.round((usedBytes / capacityBytes) * 100) : 0

      return new Response(JSON.stringify({
        success: true,
        action: "storage",
        capacity_bytes: capacityBytes,
        capacity_mb: Math.floor(capacityBytes / (1024 * 1024)),
        used_bytes: usedBytes,
        used_mb: Math.floor(usedBytes / (1024 * 1024)),
        available_bytes: availableBytes,
        available_mb: Math.floor(availableBytes / (1024 * 1024)),
        usage_percent: usagePercent,
        blocks_that_fit: Number(blocksResult.blocks_that_fit),
        bytes_per_block: bytesPerBlock,
      }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    // ═══════════════════════════════════════
    // ACTION: create_akashic — create akashic record files for a scanned block
    // ═══════════════════════════════════════
    else if (action === "create_akashic") {
      const machineId: string = body.machine_id
      const blockId: number = body.block_id
      const positiveAddress = BigInt(body.positive_address)
      const negativeAddress = BigInt(body.negative_address)
      const positiveText: string = body.positive_text
      const negativeText: string = body.negative_text
      const ownerIp: string = body.owner_ip || null

      if (!machineId || blockId === undefined) throw new Error("Missing 'machine_id' or 'block_id'")
      if (!positiveAddress || !negativeAddress) throw new Error("Missing positive_address or negative_address")
      if (!positiveText || !negativeText) throw new Error("Missing positive_text or negative_text")

      const { ownerIp: verifiedOwnerIp } = await verifyMachineOwnership(machineId, userId)
      const effectiveOwnerIp = ownerIp || verifiedOwnerIp

      // Get player's sect info for mirror copy
      let sectIp: string | null = null
      let sectName: string | null = null
      try {
        const sectRows = await sql`
          SELECT host(s.ip_address) as sect_ip, s.name as sect_name
          FROM public.players p
          JOIN public.sects s ON p.sect_id = s.id
          WHERE host(p.ip_address) = ${effectiveOwnerIp}
        `
        if (sectRows.length > 0) {
          sectIp = sectRows[0].sect_ip
          sectName = sectRows[0].sect_name
        }
      } catch (_) {
        // Sect lookup is non-fatal
      }

      const [result] = await sql`
        SELECT public.create_akashic_files_for_block(
          ${machineId}::UUID,
          ${blockId},
          ${positiveAddress},
          ${negativeAddress},
          ${positiveText},
          ${negativeText},
          ${effectiveOwnerIp}::inet,
          ${sectIp ? sql`${sectIp}::inet` : null},
          ${sectName},
          'akashic_records'
        ) as result
      `

      return new Response(JSON.stringify({
        success: true,
        action: "create_akashic",
        ...result.result,
      }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    else {
      throw new Error(`Unknown action: '${action}'. Valid actions: list, tree, read, create, delete, mkdir, rmdir, encrypt, storage, create_akashic`)
    }

  } catch (error) {
    console.error("[manage-files] Error:", error)
    return new Response(JSON.stringify({
      success: false,
      error: error instanceof Error ? error.message : "Unknown error occurred",
    }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } })
  }
})