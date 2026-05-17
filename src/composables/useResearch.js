import { ref, computed, reactive } from 'vue'
import { supabase } from '@/lib/supabase'
import { useEconomy } from './useEconomy'

/**
 * useResearch Composable
 *
 * Manages the Scriptorium & Occult Library tech tree:
 * - Fetches all research nodes (light + dark)
 * - Tracks user's unlocked research
 * - Research new nodes (spend dogma/heresy)
 * - Computes active effects from research
 */

let sharedState = null

function createResearchState() {
  const economy = useEconomy()

  const nodes = ref([])
  const unlocks = ref([])
  const loading = ref(false)
  const researching = ref(false)
  const error = ref(null)

  // Computed: light tech tree nodes
  const lightNodes = computed(() =>
    nodes.value.filter(n => n.alignment === 'light').sort((a, b) => a.sort_order - b.sort_order)
  )

  // Computed: dark tech tree nodes
  const darkNodes = computed(() =>
    nodes.value.filter(n => n.alignment === 'dark').sort((a, b) => a.sort_order - b.sort_order)
  )

  // Computed: set of unlocked node IDs
  const unlockedIds = computed(() => new Set(unlocks.value.map(u => u.node_id)))

  // Computed: check if a node can be researched
  function canResearch(node) {
    if (unlockedIds.value.has(node.id)) return false
    if (node.requires_node && !unlockedIds.value.has(node.requires_node)) return false
    if (node.alignment === 'light') return (economy.dogma || 0) >= node.cost
    if (node.alignment === 'dark') return (economy.heresy || 0) >= node.cost
    return false
  }

  /**
   * Fetch the full research tree + user unlocks
   */
  async function fetchResearchTree() {
    try {
      loading.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('get_research_tree')

      if (rpcError) throw rpcError

      if (data) {
        nodes.value = data.nodes || []
        unlocks.value = data.unlocks || []
      }
    } catch (err) {
      error.value = err.message
      console.error('[useResearch] Fetch error:', err)
    } finally {
      loading.value = false
    }
  }

  /**
   * Research a tech node
   */
  async function researchTech(nodeId) {
    try {
      researching.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('research_tech', {
        p_node_id: nodeId,
      })

      if (rpcError) throw rpcError

      // Refresh data
      await Promise.all([
        fetchResearchTree(),
        economy.fetchEconomy(),
      ])

      return data
    } catch (err) {
      error.value = err.message
      console.error('[useResearch] Research error:', err)
      throw err
    } finally {
      researching.value = false
    }
  }

  /**
   * Check if an effect type is currently active for the user
   */
  function hasEffect(effectType) {
    return unlocks.value.some(u => {
      const node = nodes.value.find(n => n.id === u.node_id)
      return node?.effect_type === effectType
    })
  }

  /**
   * Get the effect data for an active effect
   */
  function getEffectData(effectType) {
    const unlock = unlocks.value.find(u => {
      const node = nodes.value.find(n => n.id === u.node_id)
      return node?.effect_type === effectType
    })
    if (!unlock) return null
    const node = nodes.value.find(n => n.id === unlock.node_id)
    return node?.effect_data || null
  }

  return reactive({
    nodes,
    unlocks,
    loading,
    researching,
    error,
    lightNodes,
    darkNodes,
    unlockedIds,
    canResearch,
    fetchResearchTree,
    researchTech,
    hasEffect,
    getEffectData,
  })
}

export function useResearch() {
  if (!sharedState) {
    sharedState = createResearchState()
  }
  return sharedState
}