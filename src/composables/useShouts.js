import { ref, reactive } from 'vue'
import { supabase } from '@/lib/supabase'

/**
 * useShouts Composable
 *
 * Manages the Social Messaging (Shouts) feature:
 * - Fetches shouts with pagination (global, sect, synod filters)
 * - Submits new shouts (invokes town-crier edge function)
 * - Fetches shout detail + replies
 * - Submits replies (invokes town-crier edge function)
 * - Grants blessings on shouts/replies
 */
export function useShouts() {
  const shouts = ref([])
  const loading = ref(false)
  const error = ref(null)
  const hasMore = ref(true)
  const currentPage = ref(1)
  const totalShouts = ref(0)
  const currentFilter = ref('global') // 'global' | 'sect' | 'synod'
  const PAGE_SIZE = 20

  // Shout detail state
  const currentShout = ref(null)
  const replies = ref([])
  const repliesLoading = ref(false)
  const repliesHasMore = ref(true)
  const repliesPage = ref(1)
  const totalReplies = ref(0)

  // Submission state
  const submitting = ref(false)
  const submitError = ref(null)
  const isCrierProcessing = ref(false)
  const crierResult = ref(null)

  // Blessing state
  const blessingLoading = ref(false)
  const blessingError = ref(null)

  /**
   * Fetch shouts with pagination.
   * @param {boolean} loadMore - Append to existing list or replace
   * @param {string} filter - 'global' | 'sect' | 'synod'
   */
  async function fetchShouts(loadMore = false, filter = null) {
    try {
      if (filter !== null && filter !== currentFilter.value) {
        currentFilter.value = filter
        loadMore = false
      }

      if (!loadMore) {
        currentPage.value = 1
        shouts.value = []
        hasMore.value = true
      }

      loading.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('get_shouts', {
        p_page: loadMore ? currentPage.value + 1 : 1,
        p_page_size: PAGE_SIZE,
        p_filter: currentFilter.value,
      })

      if (rpcError) throw rpcError

      if (data && data.shouts) {
        if (loadMore) {
          shouts.value = [...shouts.value, ...data.shouts]
        } else {
          shouts.value = data.shouts || []
        }
        totalShouts.value = data.total || 0
        hasMore.value = data.has_more || false
        currentPage.value = loadMore ? currentPage.value + 1 : 1
      }
    } catch (err) {
      error.value = err.message
      console.error('[useShouts] Fetch shouts error:', err)
    } finally {
      loading.value = false
    }
  }

  /**
   * Load more shouts (pagination).
   */
  async function loadMoreShouts() {
    if (hasMore.value && !loading.value) {
      await fetchShouts(true)
    }
  }

  /**
   * Submit a new shout.
   * 1. Calls submit_shout RPC (deducts gold, creates pending row)
   * 2. Shows Town Crier modal (isCrierProcessing=true)
   * 3. Invokes town-crier edge function for classification + translation
   * 4. Edge function returns result to waiting client (modal), updates DB
   * 5. Modal displays result (approved crier translation or rejection decree)
   * @param {string} content - The raw shout text
   * @param {string} context - 'global' or 'synod'
   */
  async function submitShout(content, context = 'global', isSectOnly = false) {
    try {
      submitting.value = true
      submitError.value = null
      crierResult.value = null

      // Step 1: Create the shout via RPC (deducts gold)
      const { data: rpcData, error: rpcError } = await supabase.rpc('submit_shout', {
        p_content: content,
        p_context: context,
        p_is_sect_only: isSectOnly,
      })

      if (rpcError) throw rpcError

      if (!rpcData.success) {
        submitError.value = rpcData.error
        return rpcData
      }

      const shoutId = rpcData.shout_id

      // Step 2: Show modal, invoke town-crier
      // IMPORTANT: isCrierProcessing keeps the modal open so the edge function
      // doesn't get orphaned (EarlyDrop). The client stays connected.
      isCrierProcessing.value = true

      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('Not authenticated')

      const { data: crierData, error: crierFnError } = await supabase.functions.invoke('town-crier', {
        body: {
          message: content,
          user_id: user.id,
          shout_id: shoutId,
        },
      })

      // IMPORTANT: Set crierResult BEFORE clearing isCrierProcessing to prevent
      // the modal from flickering off (the v-if checks isCrierProcessing || crierResult).
      if (crierFnError) {
        console.error('[useShouts] Town crier error:', crierFnError)
        crierResult.value = {
          success: false,
          error: crierFnError.message || 'Town Crier unavailable',
          shout_id: shoutId,
        }
        isCrierProcessing.value = false
        return rpcData
      }

      // Set the result for the Crier modal to display
      crierResult.value = {
        success: crierData?.success !== false,
        judgment: crierData?.judgment || 'error',
        response: crierData?.response || null,
        rejection_reason: crierData?.rejection_reason || null,
        shout_id: shoutId,
        error: crierData?.error || null,
        // For approved shouts: DB already updated by edge function.
        // For rejected shouts: DB marked as 'failed', user gets -1 karma + 15-min ban.
      }
      isCrierProcessing.value = false

      return rpcData
    } catch (err) {
      submitError.value = err.message
      console.error('[useShouts] Submit shout error:', err)
      isCrierProcessing.value = false
      return { success: false, error: err.message }
    } finally {
      submitting.value = false
    }
  }

  /**
   * Fetch a shout with its replies.
   * @param {string} shoutId
   * @param {boolean} loadMoreReplies
   */
  async function fetchShoutDetail(shoutId, loadMoreReplies = false) {
    try {
      if (!loadMoreReplies) {
        repliesPage.value = 1
        replies.value = []
      }

      repliesLoading.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('get_shout_replies', {
        p_shout_id: shoutId,
        p_page: loadMoreReplies ? repliesPage.value + 1 : 1,
        p_page_size: 50,
      })

      if (rpcError) throw rpcError

      if (data && data.shout) {
        currentShout.value = data.shout
        if (loadMoreReplies) {
          replies.value = [...replies.value, ...(data.replies || [])]
        } else {
          replies.value = data.replies || []
        }
        totalReplies.value = data.total_replies || 0
        repliesHasMore.value = data.has_more || false
        repliesPage.value = loadMoreReplies ? repliesPage.value + 1 : 1
      }
    } catch (err) {
      error.value = err.message
      console.error('[useShouts] Fetch shout detail error:', err)
    } finally {
      repliesLoading.value = false
    }
  }

  /**
   * Load more replies (pagination).
   */
  async function loadMoreReplies() {
    if (repliesHasMore.value && !repliesLoading.value && currentShout.value) {
      await fetchShoutDetail(currentShout.value.id, true)
    }
  }

  /**
   * Submit a reply to a shout.
   * 1. Calls submit_shout_reply RPC (deducts gold, creates pending row)
   * 2. Shows Town Crier modal (isCrierProcessing=true)
   * 3. Invokes town-crier edge function for classification + translation
   * 4. Edge function returns result to waiting client (modal), updates DB
   * @param {string} shoutId
   * @param {string} content
   */
  async function submitReply(shoutId, content) {
    try {
      submitting.value = true
      submitError.value = null
      crierResult.value = null

      const { data: rpcData, error: rpcError } = await supabase.rpc('submit_shout_reply', {
        p_shout_id: shoutId,
        p_content: content,
      })

      if (rpcError) throw rpcError

      if (!rpcData.success) {
        submitError.value = rpcData.error
        return rpcData
      }

      const replyId = rpcData.reply_id

      // Show modal, invoke town-crier
      isCrierProcessing.value = true

      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('Not authenticated')

      const { data: crierData, error: crierFnError } = await supabase.functions.invoke('town-crier', {
        body: {
          message: content,
          user_id: user.id,
          reply_id: replyId,
        },
      })

      // IMPORTANT: Set crierResult BEFORE clearing isCrierProcessing to prevent
      // the modal from flickering off (the v-if checks isCrierProcessing || crierResult).
      if (crierFnError) {
        console.error('[useShouts] Town crier reply error:', crierFnError)
        crierResult.value = {
          success: false,
          error: crierFnError.message || 'Town Crier unavailable',
          reply_id: replyId,
        }
      } else {
        crierResult.value = {
          success: crierData?.success !== false,
          judgment: crierData?.judgment || 'error',
          response: crierData?.response || null,
          rejection_reason: crierData?.rejection_reason || null,
          reply_id: replyId,
          error: crierData?.error || null,
        }
      }
      isCrierProcessing.value = false

      // Refresh replies after submission (DB already updated by edge function)
      await fetchShoutDetail(shoutId, false)

      return rpcData
    } catch (err) {
      submitError.value = err.message
      console.error('[useShouts] Submit reply error:', err)
      isCrierProcessing.value = false
      return { success: false, error: err.message }
    } finally {
      submitting.value = false
    }
  }

  /**
   * Grant a blessing to a shout or reply.
   * @param {string} shoutId
   * @param {string} blessingTypeId
   * @param {string|null} replyId - null for shout-level blessing
   */
  async function grantShoutBlessing(shoutId, blessingTypeId, replyId = null) {
    try {
      blessingLoading.value = true
      blessingError.value = null

      const { data, error: rpcError } = await supabase.rpc('grant_shout_blessing', {
        p_shout_id: shoutId,
        p_blessing_type_id: blessingTypeId,
        p_reply_id: replyId,
      })

      if (rpcError) throw rpcError

      if (!data.success) {
        blessingError.value = data.error
        return data
      }

      // Refresh shout detail to update blessing counts
      await fetchShoutDetail(shoutId, false)

      return data
    } catch (err) {
      blessingError.value = err.message
      console.error('[useShouts] Grant blessing error:', err)
      return { success: false, error: err.message }
    } finally {
      blessingLoading.value = false
    }
  }

  /**
   * Clear error state.
   */
  function clearError() {
    error.value = null
    submitError.value = null
    blessingError.value = null
  }

  /**
   * Clear crier result (after modal dismissed).
   */
  function clearCrierResult() {
    crierResult.value = null
  }

  return reactive({
    // State
    shouts,
    loading,
    error,
    hasMore,
    currentFilter,
    totalShouts,
    currentShout,
    replies,
    repliesLoading,
    repliesHasMore,
    totalReplies,
    submitting,
    submitError,
    isCrierProcessing,
    crierResult,
    blessingLoading,
    blessingError,
    // Methods
    fetchShouts,
    loadMoreShouts,
    submitShout,
    fetchShoutDetail,
    loadMoreReplies,
    submitReply,
    grantShoutBlessing,
    clearError,
    clearCrierResult,
  })
}