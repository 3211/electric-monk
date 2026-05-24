import { reactive, computed } from 'vue'

/**
 * usePlayerState Composable (Singleton Pattern)
 *
 * Duck-typed reactive store for session-scoped player data.
 * Any module can set/get any key at runtime — username, sect_id, gold,
 * combat state, game save data, etc.
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

  return {
    // Reactive data (read-only access — use set/setMany for mutations)
    data,
    // Computed conveniences
    username,
    ipAddress,
    location,
    sectId,
    sectName,
    sectEmoji,
    isOnboarded,
    // Methods
    get,
    set,
    setMany,
    hydrate,
    flush,
    has,
    snapshot,
  }
}

export function usePlayerState() {
  if (!sharedState) {
    sharedState = createPlayerState()
  }
  return sharedState
}