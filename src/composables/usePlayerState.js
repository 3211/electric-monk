import { reactive, computed } from 'vue'

/**
 * usePlayerState Composable (Singleton Pattern)
 *
 * Duck-typed reactive store for session-scoped player data.
 * Any module can set/get any key at runtime — username, sect_id, gold,
 * combat state, game save data, connection state, etc.
 *
 * FLUSH on SIGNED_OUT or page refresh to prevent stale data leakage.
 * HYDRATE from checkOnboardingStatus (or any DB fetch) after auth.
 *
 * Follows the same shared-state pattern as useAuth.js.
 */

let sharedState = null

function createPlayerState() {
  /** @type {Record<string, any>} — duck-typed data bag */
  const data = reactive({})

  // ── Connection State (single source of truth for all modules) ──
  // Written by: connection.js (/connect, /disconnect), onboarding_two.js (auto-connect)
  // Read by:   processManager.js (/processes, /run, /programs, /kill),
  //            player.js (welcome display), faction.js (menu rendering),
  //            akashicScannerCommand.js (machine_ip for edge function calls)
  const connectionState = reactive({
    connected_ip: null,       // string — the IP we are currently connected to
    connection_type: null,    // 'player' | 'faction' | 'machine' | null
    machine_id: null,         // UUID — virtual_machines.machine_id (set when connected to VM)
    machine_access: null,     // 'admin' | 'pending' | null
    machine_name: null,       // string — display name for the tab title
  })

  // ── Computed Conveniences ──

  const username = computed(() => data.username || null)
  const ipAddress = computed(() => {
    const ip = data.ip_address || null
    if (ip && typeof ip === 'string') {
      const slashIdx = ip.indexOf('/')
      return slashIdx >= 0 ? ip.substring(0, slashIdx) : ip
    }
    return ip
  })
  const location = computed(() => data.location || ipAddress.value || null)
  const sectId = computed(() => data.sect_id || null)
  const sectName = computed(() => data.sect_name || null)
  const sectEmoji = computed(() => data.sect_emoji || null)
  const isOnboarded = computed(() => !!data.onboarding_complete)

  // ── Connection State Computed Conveniences ──

  const isConnected = computed(() => connectionState.connected_ip !== null)
  const isConnectedToVM = computed(() =>
    connectionState.connection_type === 'machine' && connectionState.machine_access === 'admin'
  )
  const connectedIp = computed(() => connectionState.connected_ip)
  const connectionType = computed(() => connectionState.connection_type)
  const machineId = computed(() => connectionState.machine_id)
  const machineAccess = computed(() => connectionState.machine_access)
  const machineName = computed(() => connectionState.machine_name)

  // ── Methods ──

  /**
   * Set a single key in the player state.
   * @param {string} key
   * @param {any} value
   */
  function set(key, value) {
    data[key] = value
  }

  /**
   * Get a single key from the player state.
   * @param {string} key
   * @param {any} [fallback] — default value if key is missing
   * @returns {any}
   */
  function get(key, fallback = undefined) {
    return key in data ? data[key] : fallback
  }

  /**
   * Bulk-set many keys from a source object (e.g. DB row).
   * @param {Record<string, any>} source
   */
  function setMany(source) {
    if (!source || typeof source !== 'object') return
    for (const [key, value] of Object.entries(source)) {
      data[key] = value
    }
  }

  /**
   * Hydrate the store from a player record (from checkOnboardingStatus, DB, etc).
   * Overwrites existing keys with the incoming data.
   * @param {Record<string, any>} playerRow
   */
  function hydrate(playerRow) {
    flush() // safety: clear stale before hydrating
    setMany(playerRow)
  }

  /**
   * Flush ALL state. Call on SIGNED_OUT or page refresh to prevent stale data.
   */
  function flush() {
    for (const key of Object.keys(data)) {
      delete data[key]
    }
    // Also flush connection state
    connectionState.connected_ip = null
    connectionState.connection_type = null
    connectionState.machine_id = null
    connectionState.machine_access = null
    connectionState.machine_name = null
  }

  /**
   * Check if a key exists (has been set).
   * @param {string} key
   * @returns {boolean}
   */
  function has(key) {
    return key in data
  }

  /**
   * Get a snapshot of all current data (non-reactive plain object).
   * Useful for debugging or serialization.
   * @returns {Record<string, any>}
   */
  function snapshot() {
    return { ...data }
  }

  // ── Connection State Mutations ──

  /**
   * Set the current terminal connection.
   * Called by /connect handlers and onboarding_two auto-connect.
   *
   * @param {Object} conn
   * @param {string} conn.ip — the IP connected to
   * @param {'player'|'faction'|'machine'} conn.type
   * @param {string|null} [conn.machineId] — virtual_machines.machine_id (only for VM connections)
   * @param {string|null} [conn.access] — 'admin' | 'pending' (only for VM connections)
   * @param {string|null} [conn.machineName] — display name for tab title
   */
  function setConnection({ ip, type, machineId = null, access = null, machineName = null }) {
    connectionState.connected_ip = ip || null
    connectionState.connection_type = type || null
    connectionState.machine_id = machineId || null
    connectionState.machine_access = access || null
    connectionState.machine_name = machineName || null
  }

  /**
   * Clear the current terminal connection (disconnect).
   */
  function clearConnection() {
    connectionState.connected_ip = null
    connectionState.connection_type = null
    connectionState.machine_id = null
    connectionState.machine_access = null
    connectionState.machine_name = null
  }

  return {
    // Reactive data (read-only access — use set/setMany for mutations)
    data,
    // Connection state (reactive — read/write via setConnection/clearConnection)
    connectionState,

    // Computed conveniences
    username,
    ipAddress,
    location,
    sectId,
    sectName,
    sectEmoji,
    isOnboarded,

    // Connection computed conveniences
    isConnected,
    isConnectedToVM,
    connectedIp,
    connectionType,
    machineId,
    machineAccess,
    machineName,

    // Methods
    get,
    set,
    setMany,
    hydrate,
    flush,
    has,
    snapshot,

    // Connection state methods
    setConnection,
    clearConnection,
  }
}

export function usePlayerState() {
  if (!sharedState) {
    sharedState = createPlayerState()
  }
  return sharedState
}