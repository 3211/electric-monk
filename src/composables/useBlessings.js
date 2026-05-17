import { ref, reactive } from 'vue'
import { supabase } from '@/lib/supabase'
import blessingsConfig from '@/config/blessings.json'

/**
 * useBlessings Composable
 *
 * Manages blessing types and prayer blessing data:
 * - Loads blessing definitions from config + server for active status
 * - Fetches aggregated blessing counts for prayers
 * - Fetches current user's blessings per prayer (for picker disable logic)
 * - Provides lookup helpers for blessing metadata
 */
export function useBlessings() {
  // Local config as the display source of truth
  const blessingTypes = ref(blessingsConfig.blessings.map(b => ({ ...b })))
  const prayerBlessings = ref({}) // { prayerId: [{ blessing_type_id, emoji, name, count }] }
  const myBlessings = ref({}) // { prayerId: [blessing_type_id, ...] } — current user's blessings per prayer
  const loading = ref(false)
  const error = ref(null)

  /**
   * Fetch active blessing types from server (for is_active check + karma values)
   * Merges server data into local config definitions.
   */
  async function fetchBlessingTypes() {
    try {
      loading.value = true
      error.value = null

      const { data, error: fetchError } = await supabase
        .from('blessing_types')
        .select('*')
        .eq('is_active', true)
        .order('sort_order', { ascending: true })

      if (fetchError) throw fetchError

      // Merge server data with local config (server is authoritative for costs/active state)
      if (data && data.length > 0) {
        const serverMap = Object.fromEntries(data.map(b => [b.id, b]))
        blessingTypes.value = blessingsConfig.blessings.map(local => {
          const server = serverMap[local.id]
          if (server) {
            return {
              ...local,
              karma_cost: server.karma_cost,
              karma_to_giver: server.karma_to_giver,
              karma_to_receiver: server.karma_to_receiver,
              is_active: server.is_active,
            }
          }
          return { ...local, is_active: false }
        }).filter(b => b.is_active !== false)
      }
    } catch (err) {
      error.value = err.message
      console.error('[useBlessings] Fetch blessing types error:', err)
    } finally {
      loading.value = false
    }
  }

  /**
   * Fetch aggregated blessing data for a list of prayer IDs.
   * Stores results keyed by prayer_id for easy lookup.
   * @param {string[]} prayerIds - Array of prayer UUIDs
   */
  async function fetchPrayerBlessings(prayerIds) {
    if (!prayerIds || prayerIds.length === 0) return

    try {
      loading.value = true
      error.value = null

      const { data, error: fetchError } = await supabase.rpc('get_prayer_blessings', {
        p_prayer_ids: prayerIds,
      })

      if (fetchError) throw fetchError

      // Group by prayer_id for O(1) lookup
      const grouped = {}
      for (const b of (data || [])) {
        if (!grouped[b.prayer_id]) {
          grouped[b.prayer_id] = []
        }
        grouped[b.prayer_id].push({
          blessing_type_id: b.blessing_type_id,
          emoji: b.emoji,
          name: b.name,
          count: b.count,
        })
      }

      prayerBlessings.value = grouped
    } catch (err) {
      error.value = err.message
      console.error('[useBlessings] Fetch prayer blessings error:', err)
    } finally {
      loading.value = false
    }
  }

  /**
   * Fetch the current user's own blessing type IDs for a list of prayers.
   * Used to determine which blessings the current user has already granted
   * (so we can disable them in the BlessingPicker).
   * @param {string[]} prayerIds - Array of prayer UUIDs
   */
  async function fetchMyBlessingsForPrayers(prayerIds) {
    if (!prayerIds || prayerIds.length === 0) return

    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) return

      const { data, error: fetchError } = await supabase
        .from('prayer_blessings')
        .select('prayer_id, blessing_type_id')
        .eq('giver_id', user.id)
        .in('prayer_id', prayerIds)

      if (fetchError) throw fetchError

      // Group by prayer_id
      const grouped = {}
      for (const row of (data || [])) {
        if (!grouped[row.prayer_id]) {
          grouped[row.prayer_id] = []
        }
        grouped[row.prayer_id].push(row.blessing_type_id)
      }

      myBlessings.value = grouped
    } catch (err) {
      console.error('[useBlessings] Fetch my blessings error:', err)
      // Non-critical — don't set error state, just log
    }
  }

  /**
   * Get blessing metadata by ID from local config.
   * @param {string} blessingTypeId
   * @returns {Object|undefined}
   */
  function getBlessingById(blessingTypeId) {
    return blessingTypes.value.find(b => b.id === blessingTypeId)
  }

  /**
   * Get blessings for a specific prayer from cached data.
   * @param {string} prayerId
   * @returns {Array}
   */
  function getBlessingsForPrayer(prayerId) {
    return prayerBlessings.value[prayerId] || []
  }

  /**
   * Get the current user's blessing type IDs for a specific prayer.
   * Used by BlessingPicker to determine which blessings to disable.
   * @param {string} prayerId
   * @returns {string[]} Array of blessing_type_id strings the current user has already granted
   */
  function getMyBlessingTypeIdsForPrayer(prayerId) {
    return myBlessings.value[prayerId] || []
  }

  /**
   * Clear cached prayer blessings (e.g., after granting a new blessing)
   */
  function clearPrayerBlessings() {
    prayerBlessings.value = {}
    myBlessings.value = {}
  }

  return reactive({
    blessingTypes,
    prayerBlessings,
    myBlessings,
    loading,
    error,
    fetchBlessingTypes,
    fetchPrayerBlessings,
    fetchMyBlessingsForPrayers,
    getBlessingById,
    getBlessingsForPrayer,
    getMyBlessingTypeIdsForPrayer,
    clearPrayerBlessings,
  })
}