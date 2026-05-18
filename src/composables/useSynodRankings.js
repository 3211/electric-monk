import { ref, reactive } from 'vue'
import { supabase } from '@/lib/supabase'

/**
 * useSynodRankings Composable
 *
 * Manages synod rankings grouped by sect (faction).
 * Pattern follows useLeaderboard.js:
 * - One column per sect with scroll-based lazy loading
 * - Global "all synods" flat list for quick reference
 */

const SECT_KEYS = ['gilded_path', 'holy_way', 'final_watch', 'black_tribunal']

const SECT_ICONS = {
  gilded_path: '\u{1F4B0}',
  holy_way: '\u{1F54A}',
  final_watch: '\u{1F6E1}',
  black_tribunal: '\u{2697}',
}

const SECT_NAMES = {
  gilded_path: 'The Gilded Path',
  holy_way: 'The Holy Way',
  final_watch: 'The Final Watch',
  black_tribunal: 'The Black Tribunal',
}

let sharedState = null

function createSynodRankingsState() {
  /** All synods flat list (for "All" view / fallback) */
  const allSynods = ref([])
  /** Per-sect columns: { gilded_path: [...], holy_way: [...], ... } */
  const sectColumns = reactive({})
  for (const key of SECT_KEYS) {
    sectColumns[key] = ref([])
  }

  const loading = ref(false)
  const error = ref(null)

  async function fetchRankings() {
    try {
      loading.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('get_synod_rankings_by_sect')

      if (rpcError) throw rpcError

      const rows = data || []

      // Reset columns
      allSynods.value = []
      for (const key of SECT_KEYS) {
        sectColumns[key].value = []
      }

      // Distribute by sect_key
      for (const synod of rows) {
        allSynods.value.push(synod)
        if (synod.sect_key && sectColumns[synod.sect_key]) {
          sectColumns[synod.sect_key].value.push(synod)
        }
      }
    } catch (err) {
      error.value = err.message
      console.error('[useSynodRankings] Fetch error:', err)
    } finally {
      loading.value = false
    }
  }

  /** Check if user's synod is under attack (defender side) */
  const underAttack = ref(false)
  const attackerName = ref(null)
  const defenseLoading = ref(false)

  async function fetchDefenseStatus() {
    try {
      defenseLoading.value = true
      const { data, error: rpcError } = await supabase.rpc('get_synod_defense_status')
      if (rpcError) throw rpcError
      if (data) {
        underAttack.value = data.under_attack || false
        attackerName.value = data.attacker_name || null
      }
    } catch (err) {
      console.error('[useSynodRankings] Defense status error:', err)
    } finally {
      defenseLoading.value = false
    }
  }

  return reactive({
    SECT_KEYS,
    SECT_ICONS,
    SECT_NAMES,
    allSynods,
    sectColumns,
    loading,
    error,
    fetchRankings,
    underAttack,
    attackerName,
    defenseLoading,
    fetchDefenseStatus,
  })
}

export function useSynodRankings() {
  if (!sharedState) {
    sharedState = createSynodRankingsState()
  }
  return sharedState
}

export { SECT_KEYS, SECT_ICONS, SECT_NAMES }