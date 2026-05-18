import { ref, computed, reactive } from 'vue'
import { supabase } from '@/lib/supabase'
import { useEconomy } from './useEconomy'

/**
 * useSynod Composable (Exodus 1 Overhaul)
 *
 * Manages the Synod (Alliance) system:
 * - Petition to join (faction-gated, replaces direct join)
 * - Public Synod Browser (faction-filtered)
 * - Create, leave synods
 * - View synod info, members, vault, applicants
 * - Promote, demote, kick members
 * - Declare Holy Wars (via text-input target name)
 * - Privacy toggle, custom message
 * - Applicant queue management (approve/reject)
 */

let sharedState = null

function createSynodState() {
  const economy = useEconomy()

  const inSynod = ref(false)
  const synodInfo = ref(null)
  const members = ref([])
  const memberCount = ref(0)
  const wars = ref([])
  const synodRelics = ref([])
  const applicants = ref([])
  const publicSynods = ref([])
  const loading = ref(false)
  const creating = ref(false)
  const petitioning = ref(false)
  const declaring = ref(false)
  const managing = ref(false)
  const browsing = ref(false)
  const searching = ref(false)
  const error = ref(null)

  const isLeader = computed(() => {
    if (!synodInfo.value || !economy.user) return false
    return synodInfo.value.leader_id === economy.user?.id
  })

  const currentUserRole = computed(() => {
    if (!economy.user) return null
    const member = members.value.find(m => m.user_id === economy.user.id)
    return member?.role || null
  })

  /**
   * Fetch full synod info from RPC (now includes applicants, privacy, custom_message)
   */
  async function fetchSynodInfo() {
    try {
      loading.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('get_synod_info')

      if (rpcError) throw rpcError

      if (data) {
        inSynod.value = data.in_synod
        if (data.in_synod) {
          synodInfo.value = data.synod
          members.value = data.members || []
          memberCount.value = data.member_count || 0
          wars.value = data.wars || []
          synodRelics.value = data.synod_relics || []
          applicants.value = data.applicants || []
        } else {
          synodInfo.value = null
          members.value = []
          memberCount.value = 0
          wars.value = []
          synodRelics.value = []
          applicants.value = []
        }
      }
    } catch (err) {
      error.value = err.message
      console.error('[useSynod] Fetch error:', err)
    } finally {
      loading.value = false
    }
  }

  /**
   * Fetch public Synods matching player's faction or ally (for Synod Browser)
   */
  async function fetchPublicSynods() {
    try {
      browsing.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('get_public_synods')

      if (rpcError) throw rpcError

      publicSynods.value = data || []
    } catch (err) {
      error.value = err.message
      console.error('[useSynod] Public synods error:', err)
    } finally {
      browsing.value = false
    }
  }

  /**
   * Find a Synod by exact name (for Holy War target selection)
   */
  async function findSynodByName(name) {
    try {
      searching.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('find_synod_by_name', {
        p_name: name,
      })

      if (rpcError) throw rpcError

      return data
    } catch (err) {
      error.value = err.message
      console.error('[useSynod] Find synod error:', err)
      return { found: false }
    } finally {
      searching.value = false
    }
  }

  /**
   * Create a new Synod (now with privacy and custom_message)
   */
  async function createSynod(name, { privacy = 'public', customMessage = null } = {}) {
    try {
      creating.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('create_synod', {
        p_name: name,
        p_privacy: privacy,
        p_custom_message: customMessage,
      })

      if (rpcError) throw rpcError

      await Promise.all([
        fetchSynodInfo(),
        economy.fetchEconomy(),
      ])

      return data
    } catch (err) {
      error.value = err.message
      console.error('[useSynod] Create error:', err)
      throw err
    } finally {
      creating.value = false
    }
  }

  /**
   * Petition to join a Synod (faction-gated, replaces direct join)
   */
  async function petitionSynod(synodId) {
    try {
      petitioning.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('petition_synod', {
        p_synod_id: synodId,
      })

      if (rpcError) throw rpcError

      await fetchPublicSynods()

      return data
    } catch (err) {
      error.value = err.message
      console.error('[useSynod] Petition error:', err)
      throw err
    } finally {
      petitioning.value = false
    }
  }

  /**
   * Leave current Synod
   */
  async function leaveSynod() {
    try {
      loading.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('leave_synod')

      if (rpcError) throw rpcError

      await Promise.all([
        fetchSynodInfo(),
        economy.fetchEconomy(),
      ])

      return data
    } catch (err) {
      error.value = err.message
      console.error('[useSynod] Leave error:', err)
      throw err
    } finally {
      loading.value = false
    }
  }

  /**
   * Approve a pending applicant (leader or officer only)
   */
  async function approveApplicant(userId) {
    try {
      managing.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('approve_synod_applicant', {
        p_applicant_user_id: userId,
      })

      if (rpcError) throw rpcError

      await Promise.all([
        fetchSynodInfo(),
        economy.fetchEconomy(),
      ])

      return data
    } catch (err) {
      error.value = err.message
      console.error('[useSynod] Approve error:', err)
      throw err
    } finally {
      managing.value = false
    }
  }

  /**
   * Reject a pending applicant
   */
  async function rejectApplicant(userId) {
    try {
      managing.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('reject_synod_applicant', {
        p_applicant_user_id: userId,
      })

      if (rpcError) throw rpcError

      await fetchSynodInfo()

      return data
    } catch (err) {
      error.value = err.message
      console.error('[useSynod] Reject error:', err)
      throw err
    } finally {
      managing.value = false
    }
  }

  /**
   * Update Synod privacy (leader only)
   */
  async function updatePrivacy(privacy) {
    try {
      managing.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('update_synod_privacy', {
        p_privacy: privacy,
      })

      if (rpcError) throw rpcError

      await fetchSynodInfo()

      return data
    } catch (err) {
      error.value = err.message
      console.error('[useSynod] Privacy error:', err)
      throw err
    } finally {
      managing.value = false
    }
  }

  /**
   * Update Synod custom message (leader only)
   */
  async function updateMessage(message) {
    try {
      managing.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('update_synod_message', {
        p_message: message,
      })

      if (rpcError) throw rpcError

      await fetchSynodInfo()

      return data
    } catch (err) {
      error.value = err.message
      console.error('[useSynod] Message error:', err)
      throw err
    } finally {
      managing.value = false
    }
  }

  /**
   * Promote a synod member (member -> officer -> leader transfer)
   */
  async function promoteMember(targetUserId) {
    try {
      managing.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('promote_synod_member', {
        p_target_id: targetUserId,
      })

      if (rpcError) throw rpcError

      await Promise.all([
        fetchSynodInfo(),
        economy.fetchEconomy(),
      ])

      return data
    } catch (err) {
      error.value = err.message
      console.error('[useSynod] Promote error:', err)
      throw err
    } finally {
      managing.value = false
    }
  }

  /**
   * Demote a synod member (officer -> member)
   */
  async function demoteMember(targetUserId) {
    try {
      managing.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('demote_synod_member', {
        p_target_id: targetUserId,
      })

      if (rpcError) throw rpcError

      await Promise.all([
        fetchSynodInfo(),
        economy.fetchEconomy(),
      ])

      return data
    } catch (err) {
      error.value = err.message
      console.error('[useSynod] Demote error:', err)
      throw err
    } finally {
      managing.value = false
    }
  }

  /**
   * Kick a synod member
   */
  async function kickMember(targetUserId) {
    try {
      managing.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('kick_synod_member', {
        p_target_id: targetUserId,
      })

      if (rpcError) throw rpcError

      await Promise.all([
        fetchSynodInfo(),
        economy.fetchEconomy(),
      ])

      return data
    } catch (err) {
      error.value = err.message
      console.error('[useSynod] Kick error:', err)
      throw err
    } finally {
      managing.value = false
    }
  }

  /**
   * Initiate Holy War on another Synod (leader only, auto-conscripts all members)
   */
  async function initiateHolyWar(targetSynodId) {
    try {
      declaring.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('initiate_holy_war', {
        p_target_synod_id: targetSynodId,
      })

      if (rpcError) throw rpcError

      await fetchSynodInfo()
      return data
    } catch (err) {
      error.value = err.message
      console.error('[useSynod] Holy War error:', err)
      throw err
    } finally {
      declaring.value = false
    }
  }

  /**
   * Reset all state (used on sign-out)
   */
  function resetState() {
    inSynod.value = false
    synodInfo.value = null
    members.value = []
    memberCount.value = 0
    wars.value = []
    synodRelics.value = []
    applicants.value = []
    publicSynods.value = []
    error.value = null
  }

  return reactive({
    inSynod,
    synodInfo,
    members,
    memberCount,
    wars,
    synodRelics,
    applicants,
    publicSynods,
    loading,
    creating,
    petitioning,
    declaring,
    managing,
    browsing,
    searching,
    error,
    isLeader,
    currentUserRole,
    fetchSynodInfo,
    fetchPublicSynods,
    findSynodByName,
    createSynod,
    petitionSynod,
    leaveSynod,
    approveApplicant,
    rejectApplicant,
    updatePrivacy,
    updateMessage,
    promoteMember,
    demoteMember,
    kickMember,
    initiateHolyWar,
    resetState,
  })
}

export function useSynod() {
  if (!sharedState) {
    sharedState = createSynodState()
  }
  return sharedState
}