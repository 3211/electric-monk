/**
 * wipe-player.js — Surgical player account removal tool (raw fetch, zero deps)
 *
 * Usage:
 *   node admin/wipe-player.js <username>          <- full wipe (auth + game data)
 *   node admin/wipe-player.js <username> --soft   <- game data only, keep auth user
 *   node admin/wipe-player.js --list              <- list all players
 *
 * Prerequisites:
 *   - .env file at project root with VITE_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY
 */

import { readFileSync, existsSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));

// ── Load .env ──────────────────────────────────────────────────────────────
function loadEnv() {
  const candidates = [
    resolve(__dirname, '..', '.env.local'),
    resolve(__dirname, '..', '.env'),
  ];
  for (const envPath of candidates) {
    if (!existsSync(envPath)) continue;
    const lines = readFileSync(envPath, 'utf-8').split(/\r?\n/);
    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#')) continue;
      const eq = trimmed.indexOf('=');
      if (eq === -1) continue;
      const key = trimmed.slice(0, eq).trim();
      const val = trimmed.slice(eq + 1).trim();
      if (!process.env[key]) process.env[key] = val;
    }
  }
}
loadEnv();

// ── Config ─────────────────────────────────────────────────────────────────
const SUPABASE_URL = process.env.VITE_SUPABASE_URL || process.env.SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL) {
  console.error('ERROR: VITE_SUPABASE_URL or SUPABASE_URL not set in .env');
  process.exit(1);
}
if (!SERVICE_ROLE_KEY) {
  console.error('ERROR: SUPABASE_SERVICE_ROLE_KEY not set in .env');
  console.error('Add: SUPABASE_SERVICE_ROLE_KEY=your_service_role_key');
  process.exit(1);
}

const REST_URL = `${SUPABASE_URL}/rest/v1`;
const AUTH_URL = `${SUPABASE_URL}/auth/v1`;
const HEADERS = {
  'apikey': SERVICE_ROLE_KEY,
  'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
  'Content-Type': 'application/json',
};

// ── Helpers ────────────────────────────────────────────────────────────────
function log(msg) {
  console.log(`[${new Date().toISOString().slice(11, 19)}] ${msg}`);
}

function count(n) {
  return n ?? 0;
}

async function restGet(table, query) {
  const params = new URLSearchParams(query);
  // select=* is default but we use specific columns
  const url = `${REST_URL}/${table}?${params.toString()}`;
  const res = await fetch(url, { headers: { ...HEADERS, 'Prefer': 'return=representation' } });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`GET ${table}: ${res.status} ${body}`);
  }
  return res.json();
}

/**
 * DELETE from a table with an `in` filter on a column.
 * Returns the count of rows affected (via Content-Range header or count preference).
 * Handles empty arrays gracefully (skips).
 */
async function restDeleteIn(table, column, values) {
  if (!values || values.length === 0) return 0;

  // Supabase REST: ?column=in.(val1,val2,val3)
  const encoded = values.map(v => `"${String(v).replace(/"/g, '\\"')}"`).join(',');
  const url = `${REST_URL}/${table}?${column}=in.(${encoded})`;

  const res = await fetch(url, {
    method: 'DELETE',
    headers: { ...HEADERS, 'Prefer': 'count=exact' },
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`DELETE ${table} ${column}: ${res.status} ${body}`);
  }

  // Supabase returns count in Content-Range header: "0-0/5" → 5
  const range = res.headers.get('content-range');
  if (range) {
    const match = range.match(/\/(\d+)/);
    if (match) return parseInt(match[1], 10);
  }
  return 0;
}

/**
 * DELETE with an eq filter on a single column + value.
 */
async function restDeleteEq(table, column, value) {
  const url = `${REST_URL}/${table}?${column}=eq.${encodeURIComponent(value)}`;

  const res = await fetch(url, {
    method: 'DELETE',
    headers: { ...HEADERS, 'Prefer': 'count=exact' },
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`DELETE ${table} ${column}=${value}: ${res.status} ${body}`);
  }

  const range = res.headers.get('content-range');
  if (range) {
    const match = range.match(/\/(\d+)/);
    if (match) return parseInt(match[1], 10);
  }
  return 0;
}

async function getPlayer(username) {
  const data = await restGet('players', { username: `eq.${username}`, select: 'id,username,ip_address,sect_id,onboarding_complete' });
  if (!data || data.length === 0) {
    console.error(`Player "${username}" not found.`);
    return null;
  }
  return data[0];
}

async function listPlayers() {
  const data = await restGet('players', {
    select: 'id,username,ip_address,sect_id,onboarding_complete,created_at',
    order: 'created_at.desc',
  });

  console.log(`\n${'USERNAME'.padEnd(18)} ${'IP'.padEnd(18)} ${'SECT'.padEnd(20)} ${'ONBOARD'.padEnd(8)} CREATED`);
  console.log('─'.repeat(90));
  for (const p of data) {
    const ip = (p.ip_address || '').replace('/32', '');
    console.log(
      `${(p.username || '(anon)').padEnd(18)} ${ip.padEnd(18)} ${(p.sect_id || '—').padEnd(20)} ${String(p.onboarding_complete).padEnd(8)} ${p.created_at}`
    );
  }
  console.log(`\nTotal: ${data.length} player(s)\n`);
}

async function getPlayerVMs(playerIp) {
  const cleanIp = String(playerIp).replace(/\/\d+$/, '');
  try {
    return await restGet('virtual_machines', {
      select: 'machine_id,ip_address,machine_name',
      owner_identity: `eq.${cleanIp}`,
    });
  } catch (e) {
    log(`  WARN: Could not fetch VMs: ${e.message}`);
    return [];
  }
}

// ── Auth admin delete ──────────────────────────────────────────────────────
async function deleteAuthUser(userId) {
  const url = `${AUTH_URL}/admin/users/${userId}`;
  const res = await fetch(url, {
    method: 'DELETE',
    headers: {
      'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
      'apikey': SERVICE_ROLE_KEY,
    },
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Auth delete ${userId}: ${res.status} ${body}`);
  }
  return true;
}

// ── Wipe Steps ─────────────────────────────────────────────────────────────

async function wipeStep(label, fn) {
  log(`  ${label}...`);
  const result = await fn();
  if (result !== undefined) log(`    → ${result}`);
}

async function wipePlayer(username, softMode) {
  log(`\n═══ WIPING PLAYER: "${username}" ═══`);
  log(`Mode: ${softMode ? 'SOFT (keep auth user)' : 'FULL (delete auth user)'}`);

  const player = await getPlayer(username);
  if (!player) return;

  const playerIp = String(player.ip_address).replace(/\/\d+$/, '');
  const playerId = player.id;

  log(`Player ID  : ${playerId}`);
  log(`Player IP  : ${playerIp}`);
  log(`Sect       : ${player.sect_id || '(none)'}`);

  // Get all VMs owned by this player
  const vms = await getPlayerVMs(player.ip_address);
  const vmIps = vms.map(v => String(v.ip_address).replace(/\/\d+$/, ''));
  const allIps = [playerIp, ...vmIps];

  log(`VMs owned  : ${vms.length} (${vmIps.join(', ') || 'none'})`);
  log(`All IPs    : ${allIps.join(', ')}`);
  log('');

  // ── Step 1: Akashic scans pending ────────────────────────────────────────
  await wipeStep('Akashic scans pending', async () => {
    const n = await restDeleteIn('akashic_scans_pending', 'machine_ip', allIps);
    return `${n} row(s) deleted`;
  });

  // ── Step 2: Akashic scans completed ──────────────────────────────────────
  await wipeStep('Akashic scans completed', async () => {
    const n = await restDeleteIn('akashic_scans_completed', 'machine_ip', allIps);
    return `${n} row(s) deleted`;
  });

  // ── Step 3: Akashic sectors ─────────────────────────────────────────────
  await wipeStep('Akashic sectors', async () => {
    let total = 0;
    total += await restDeleteIn('akashic_sectors', 'discovered_by_ip', allIps);
    total += await restDeleteIn('akashic_sectors', 'last_verified_by_ip', allIps);
    total += await restDeleteIn('akashic_sectors', 'reserved_by', allIps);
    return `${total} row(s) deleted`;
  });

  // ── Step 4: Connection logs (TEXT columns, no FK) ────────────────────────
  await wipeStep('Connection logs (all IP/actor references)', async () => {
    let total = 0;
    for (const col of ['origin_actor', 'target_actor', 'source_ip', 'target_ip', 'first_ip', 'first_target']) {
      total += await restDeleteIn('connection_logs', col, allIps);
    }
    // Also match player UUID in origin_actor / target_actor
    total += await restDeleteEq('connection_logs', 'origin_actor', playerId);
    total += await restDeleteEq('connection_logs', 'target_actor', playerId);
    return `${total} row(s) deleted`;
  });

  // ── Step 5: Virtual logs ─────────────────────────────────────────────────
  await wipeStep('Virtual logs', async () => {
    const n = await restDeleteIn('virtual_logs', 'source_ip', allIps);
    return `${n} row(s) deleted`;
  });

  // ── Step 6: Delete VMs (cascades via FK) ──────────────────────────────────
  const vmMachineIds = vms.map(v => v.machine_id);
  if (vmMachineIds.length > 0) {
    await wipeStep('Virtual machines (cascades → files, programs, processes)', async () => {
      const n = await restDeleteIn('virtual_machines', 'machine_id', vmMachineIds);
      return `${n} VM(s) deleted (cascaded)`;
    });
  } else {
    log('  Virtual machines: none owned, skipping');
  }

  // ── Step 7: Network addresses ────────────────────────────────────────────
  await wipeStep('Network addresses', async () => {
    const n = await restDeleteIn('network_addresses', 'ip_address', allIps);
    return `${n} row(s) deleted`;
  });

  // ── Step 8: Player row ───────────────────────────────────────────────────
  await wipeStep('Player record', async () => {
    await restDeleteEq('players', 'id', playerId);
    return `Player "${username}" removed from players table`;
  });

  // ── Step 9: Auth user (unless soft mode) ─────────────────────────────────
  if (!softMode) {
    await wipeStep('Auth user', async () => {
      await deleteAuthUser(playerId);
      return `Auth user ${playerId} deleted`;
    });
  } else {
    log('  Auth user: SKIPPED (soft mode)');
  }

  log(`\n✅ Player "${username}" has been surgically wiped.`);
  if (!softMode) {
    log('   Auth user, player record, all VMs, files, logs, connections, and Akashic data removed.');
  } else {
    log('   Game data wiped. Auth user preserved (orphaned — must re-register).');
  }
}

// ── Main ────────────────────────────────────────────────────────────────────
async function main() {
  const args = process.argv.slice(2);

  if (args.includes('--list')) {
    await listPlayers();
    process.exit(0);
  }

  const softMode = args.includes('--soft');
  const username = args.find(a => !a.startsWith('--'));

  if (!username) {
    console.log('Usage:');
    console.log('  node admin/wipe-player.js <username>         Full wipe (auth + game data)');
    console.log('  node admin/wipe-player.js <username> --soft  Game data only, keep auth user');
    console.log('  node admin/wipe-player.js --list             List all players');
    process.exit(1);
  }

  await wipePlayer(username, softMode);
}

main().catch((err) => {
  console.error('\n❌ FATAL ERROR:', err.message);
  console.error(err);
  process.exit(1);
});