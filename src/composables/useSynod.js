import { ref, computed, reactive } from 'vue'
import { supabase } from '@/lib/supabase'
import { useEconomy } from './useEconomy'

/**
 * useSynod Composable (Exodus 2 — petition tracking + applicant polling)
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

  // Exodus 2: Track which synod the user has a pending petition to
  const myPetitionSynodId = ref(null)
  let applicantPollInterval = null

  const isLeader = computed(() => {
    if (!synodInfo.value || !economy.user) return false
    return synodInfo.value.leader_id === economy.user?.id
  })

  const currentUserRole = computed(() => {
    if (!economy.user) return null
    const member = members.value.find(m => m.user_id === economy.user.id)
    return member?.role || null
  })

  const isStewardOrLeader = computed(() => {
    const role = currentUserRole.value
    return role === 'leader' || role === 'officer'
  })

  // Exodus 2: Active war tracking
  const hasActiveWar = computed(() => {
    return synodInfo.value?.active_war_id != null || wars.value.length > 0
  })

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

          // Start applicant polling if leader/steward
          if (data.my_role === 'leader' || data.my_role === 'officer') {
            startApplicantPolling()
          }
        } else {
          synodInfo.value = null
          members.value = []
          memberCount.value = 0
          wars.value = []
          synodRelics.value = []
          applicants.value = []
          stopApplicantPolling()
        }
      }
    } catch (err) {
      error.value = err.message
      console.error('[useSynod] Fetch error:', err)
    } finally {
      loading.value = false
    }
  }

  function startApplicantPolling() {
    stopApplicantPolling()
    applicantPollInterval = setInterval(() => {
      fetchSynodInfo()
    }, 30000)
  }

  function stopApplicantPolling() {
    if (applicantPollInterval) {
      clearInterval(applicantPollInterval)
      applicantPollInterval = null
    }
  }

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

  async function petitionSynod(synodId) {
    try {
      petitioning.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('petition_synod', {
        p_synod_id: synodId,
      })

      if (rpcError) throw rpcError

      // Track petition state
      myPetitionSynodId.value = synodId

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

  async function leaveSynod() {
    try {
      loading.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('leave_synod')

      if (rpcError) throw rpcError

      stopApplicantPolling()
      myPetitionSynodId.value = null

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

  async function rejectApplicant(userId) {
    try {
      managing.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('reject_synod_applicant', {
        p_applicant_user_id: userId,
      })

      if (rpcError) throw rpcError

      // If rejecting the user who petitioned us, clear their petition tracking
      // (We can't easily know this from RPC response, so clear on any reject)
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

  function resetState() {
    stopApplicantPolling()
    inSynod.value = false
    synodInfo.value = null
    members.value = []
    memberCount.value = 0
    wars.value = []
    synodRelics.value = []
    applicants.value = []
    publicSynods.value = []
    myPetitionSynodId.value = null
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
    isStewardOrLeader,
    hasActiveWar,
    myPetitionSynodId,
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