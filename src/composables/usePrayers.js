import { ref, computed, reactive } from 'vue'
import { supabase } from '@/lib/supabase'

// Environment variables for Devotion-based limits
// Note: These are used for UI display only. Actual limits are enforced server-side via RPC.
// Default daily devotion limit is now 100 per prayer slot (base 1 slot = 100 devotion)
const MAX_PRAYER_CHARS = parseInt(import.meta.env.VITE_MAX_PRAYER_CHARS || '1500', 10)
const DAILY_MANA_LIMIT = parseInt(import.meta.env.VITE_DAILY_TOKEN_LIMIT || '100', 10)
const PRAYER_MANA_RATIO = parseInt(import.meta.env.VITE_PRAYER_TOKEN_RATIO || '5', 10)

/**
 * usePrayers Composable
 *
 * Manages prayer submission, retrieval, and status tracking.
 * Uses Supabase RPC functions for secure, server-side Mana validation.
 *
 * Database Schema Notes:
 * - profiles.tokens_spent_today (INT): Tracks Mana spent today (was daily_prayers_count)
 * - profiles.daily_token_limit (INT): User's daily Mana budget (default 100, +100 per purchased slot)
 * - RPC submit_prayer(content): Atomically inserts prayer and updates tokens_spent_today
 * - RPC refill_tokens(amount): Reduces tokens_spent_today (for ad rewards)
 *
 * @returns {Object} Prayer state and methods
 */

// Module-level shared state — created once, reused by all usePrayers() calls
let sharedState = null

function createPrayersState() {
  const prayers = ref([])
  const dailyManaLimit = ref(DAILY_MANA_LIMIT) // DB column: daily_token_limit (UI: "Devotion limit")
  const dailyManaSpent = ref(0) // DB column: tokens_spent_today (UI: "Devotion spent")
  const karma = ref(0)
  const mana = ref(0) // Building-generated action resource
  const gold = ref(0) // Worker-generated currency
  const food = ref(0) // Garden-generated sustaining resource
  const maxPrayerSlots = ref(1)
  const username = ref(null)
  const faith = ref(null)
  const loading = ref(false)
  const error = ref(null)
  const onboardingComplete = ref(false) // DB column: onboarding_complete
  
  // Aether Modal State
  const isAetherProcessing = ref(false)
  const aetherResult = ref(null)

  /**
   * Calculate Mana cost for a prayer based on character count
   * Used for UI estimation only. Actual cost calculated server-side.
   * @param {string} content - The prayer text
   * @returns {number} Estimated Mana cost
   */
  function calculateManaCost(content) {
    const charCount = content.length
    return Math.ceil(charCount / PRAYER_MANA_RATIO)
  }

  // Computed properties
  const canPray = computed(() => dailyManaSpent.value < dailyManaLimit.value)
  const tokensRemaining = computed(() => Math.max(0, dailyManaLimit.value - dailyManaSpent.value))

  /**
   * Fetch user's prayers from database (includes both active and archived prayers)
   */
  async function fetchPrayers() {
    try {
      loading.value = true
      error.value = null

      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('No user logged in')

      const { data, error: fetchError } = await supabase
        .from('prayers')
        .select('*')
        .eq('user_id', user.id)
        .eq('is_archived', false)
        .order('created_at', { ascending: false })

      if (fetchError) throw fetchError

      prayers.value = data || []
      return data
    } catch (err) {
      error.value = err.message
      console.error('[usePrayers] Fetch error:', err)
      throw err
    } finally {
      loading.value = false
    }
  }

  /**
   * Fetch user's profile including karma, mana, gold, food, max prayer slots, username, and faith
   */
  async function fetchProfile() {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) return

      const { data: profile } = await supabase
        .from('profiles')
        .select('karma, max_prayer_slots, username, faith, mana, gold, food, onboarding_complete')
        .eq('id', user.id)
        .single()

      if (profile) {
        karma.value = profile.karma || 0
        maxPrayerSlots.value = profile.max_prayer_slots || 1
        username.value = profile.username || null
        faith.value = profile.faith || null
        mana.value = profile.mana || 0
        gold.value = profile.gold || 0
        food.value = profile.food || 0
        onboardingComplete.value = profile.onboarding_complete || false
      }
    } catch (err) {
      console.error('[usePrayers] Profile fetch error:', err)
    }
  }

  /**
   * Update user's username and faith
   * @param {string} newUsername - The user's chosen name
   * @param {string} newFaith - The user's faith/religion
   */
  async function updateProfile(usernameUpdate, faithUpdate) {
    try {
      loading.value = true
      error.value = null

      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('No user logged in')

      // Use upsert instead of update to handle missing profile rows
      // This fixes the "forgotten identity" issue where profiles don't exist
      const { error: upsertError } = await supabase
        .from('profiles')
        .upsert({
          id: user.id,
          username: usernameUpdate,
          faith: faithUpdate,
        }, {
          onConflict: 'id'
        })

      if (upsertError) throw upsertError

      // Update local state
      username.value = usernameUpdate
      faith.value = faithUpdate

      return { success: true }
    } catch (err) {
      error.value = err.message
      console.error('[usePrayers] Profile upsert error:', err)
      throw err
    } finally {
      loading.value = false
    }
  }

  /**
   * Get current daily Mana spending from profile
   * Reads from profiles.tokens_spent_today column
   */
  async function fetchDailyCount() {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) return 0

      const { data: profile } = await supabase
        .from('profiles')
        .select('tokens_spent_today, daily_token_limit, last_prayer_date')
        .eq('id', user.id)
        .single()

      // Check if we need to reset the daily count
      const today = new Date().toDateString()
      const lastPrayerDate = profile?.last_prayer_date
        ? new Date(profile.last_prayer_date).toDateString()
        : null

      if (lastPrayerDate !== today) {
        // Reset daily Devotion count directly via profile update
        const todayStr = new Date().toISOString().split('T')[0]
        const { error: resetError } = await supabase
          .from('profiles')
          .update({ tokens_spent_today: 0, last_prayer_date: todayStr })
          .eq('id', user.id)
        if (resetError) {
          console.warn('[usePrayers] Daily reset failed:', resetError)
          // Fallback: just set to 0 locally if update fails
          dailyManaSpent.value = 0
        } else {
          dailyManaSpent.value = 0
        }
        // Update local limit if DB has different value
        if (profile?.daily_token_limit) {
          dailyManaLimit.value = profile.daily_token_limit
        }
      } else {
        dailyManaSpent.value = profile?.tokens_spent_today || 0
      }

      return dailyManaSpent.value
    } catch (err) {
      console.error('[usePrayers] Daily count error:', err)
      return 0
    }
  }

  /**
   * Submit a new prayer for processing using the secure RPC function.
   * The database function submit_prayer() handles:
   * - Character limit validation (1500 chars)
   * - Mana budget validation (daily_token_limit)
   * - Atomic insert of prayer and update of tokens_spent_today
   *
   * @param {string} content - The prayer text
   * @returns {Object} Result containing prayer ID and Mana cost
   */
  /**
   * Submit a new prayer for processing using the secure RPC function.
   * The database function submit_prayer() handles:
   * - Character limit validation (1500 chars)
   * - Mana budget validation (daily_token_limit)
   * - Atomic insert of prayer and update of tokens_spent_today
   *
   * @param {string} content - The prayer text
   * @returns {Object} Result containing prayer ID and Mana cost
   */
  async function submitPrayer(content, { isOnboarding } = {}) {
    try {
      loading.value = true
      error.value = null
      isAetherProcessing.value = true
      aetherResult.value = null

      // Client-side validation for UX (server also validates)
      if (content.length > MAX_PRAYER_CHARS) {
        throw new Error(`Prayer exceeds maximum length of ${MAX_PRAYER_CHARS} characters.`)
      }

      // Get current user ID once for reuse
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('No user logged in')

      // Step 1: Call the secure RPC function to deduct tokens and create prayer record
      const { data: result, error: rpcError } = await supabase
        .rpc('submit_prayer', { prayer_content: content })

      if (rpcError) throw rpcError

      // Update Mana spent (RPC already updated in DB)
      const manaCost = result.cost
      dailyManaSpent.value += manaCost

      // Slot-aware: only deactivate the specific prayer that was FIFO-rotated
      // (the RPC handles slot checking and only deactivates the oldest when over limit)
      if (result.deactivated_id) {
        const deactivated = prayers.value.find(p => p.id === result.deactivated_id)
        if (deactivated) {
          deactivated.is_praying = false
          deactivated.activated_at = null
        }
      }

      // Step 2: Invoke the Edge Function to process prayer with Venice AI
      // The Aether modal covers the UI during processing — we do NOT add the prayer
      // to the local list until classification is complete, so it doesn't appear
      // as "Being Prayed" before the monk has judged it.
      const { data: aiResult, error: aiError } = await supabase.functions.invoke('process-prayer', {
        body: {
          prayer_id: result.id,
          content: content,
          user_id: user.id,
          is_onboarding: isOnboarding || false,
        },
      })

      // Always set processing to false when AI returns (success or failure)
      isAetherProcessing.value = false

      // Fetch the prayer from the server — it now has the final status from the Edge Function
      const { data: fetchedPrayer, error: fetchError } = await supabase
        .from('prayers')
        .select('*')
        .eq('id', result.id)
        .single()

      if (fetchError) {
        console.error('[usePrayers] Failed to fetch classified prayer:', fetchError)
      }

      // Use the fetched prayer (with final status) or construct a fallback from what we know
      const finalPrayer = fetchedPrayer || {
        id: result.id,
        content: content,
        user_id: user.id,
        response_content: null,
        is_praying: false,
        is_rejected: false,
        is_archived: false,
        status: 'pending',
        prayer_count: 0,
        created_at: new Date().toISOString(),
        processing_error: true,
      }

      if (aiError) {
        console.error('[usePrayers] Edge Function error:', aiError)
        // The prayer was submitted but AI processing failed
        finalPrayer.processing_error = true
        finalPrayer.is_praying = false
        aetherResult.value = {
          success: false,
          error: aiError.message || 'AI processing failed',
        }
      } else if (aiResult) {
        // Update the prayer object with AI judgment results
        finalPrayer.judgment = aiResult.judgment
        finalPrayer.response_content = aiResult.response
        finalPrayer.rejection_reason = aiResult.rejection_reason
        finalPrayer.is_rejected = aiResult.judgment === 'rejected'
        finalPrayer.is_praying = aiResult.judgment === 'approved'
        finalPrayer.status = 'completed'

        // Defensive: If the fetched prayer is missing response_content (DB update may have failed),
        // persist the AI results directly via client-side update
        if (fetchedPrayer && !fetchedPrayer.response_content && aiResult.response) {
          console.warn('[usePrayers] response_content missing from DB, patching via client update')
          const isApproved = aiResult.judgment === 'approved'
          const isRejected = aiResult.judgment === 'rejected'
          supabase
            .from('prayers')
            .update({
              response_content: aiResult.response,
              is_rejected: isRejected,
              rejection_reason: isRejected ? (aiResult.rejection_reason || 'Rejected by Electric Monk') : null,
              is_praying: isApproved,
              status: 'completed',
              ...(isApproved ? { activated_at: new Date().toISOString(), last_counted_at: new Date().toISOString() } : {}),
            })
            .eq('id', result.id)
            .then(({ error: patchError }) => {
              if (patchError) console.error('[usePrayers] Client-side patch failed:', patchError)
            })
        }

        // Update karma locally based on judgment (server already updated via update_karma RPC)
        const karmaChange = aiResult.judgment === 'approved' ? 1 : -1
        karma.value += karmaChange

        // Set the result for the Aether modal to display
        aetherResult.value = {
          success: true,
          judgment: aiResult.judgment,
          response: aiResult.response,
          rejection_reason: aiResult.rejection_reason,
          karmaChange: karmaChange,
        }
      }

      // NOW add the prayer to the local list with its final classified status
      prayers.value.unshift(finalPrayer)

      return { prayer: finalPrayer, cost: manaCost, aiResult }
    } catch (err) {
      error.value = err.message
      console.error('[usePrayers] Submit error:', err)
      isAetherProcessing.value = false
      throw err
    } finally {
      loading.value = false
    }
  }

  /**
   * Process prayer with Venice AI (placeholder for integration)
   * @param {string} prayerId - The prayer ID to process
   */
  async function processPrayerWithVenice(prayerId) {
    // TODO: Implement Venice AI integration
    // This function will:
    // 1. Send prayer content to Venice AI API
    // 2. Receive judgment (approved/rejected + reason)
    // 3. Update prayer record with results
    // 4. If malicious, trigger ban via useBanTimer
    
    console.log('[usePrayers] Venice AI processing placeholder for:', prayerId)
  }

  /**
   * Mark a prayer as rejected
   * @param {string} prayerId - The prayer ID
   * @param {string} reason - Rejection reason
   */
  async function markPrayerRejected(prayerId, reason) {
    try {
      const { error: updateError } = await supabase
        .from('prayers')
        .update({
          is_rejected: true,
          rejection_reason: reason,
          is_praying: false,
        })
        .eq('id', prayerId)

      if (updateError) throw updateError

      // Update local state
      const prayer = prayers.value.find(p => p.id === prayerId)
      if (prayer) {
        prayer.is_rejected = true
        prayer.rejection_reason = reason
        prayer.is_praying = false
      }
    } catch (err) {
      console.error('[usePrayers] Mark rejected error:', err)
    }
  }

  /**
   * Mark a prayer as being prayed (approved)
   * @param {string} prayerId - The prayer ID
   */
  async function markPrayerApproved(prayerId) {
    try {
      const { error: updateError } = await supabase
        .from('prayers')
        .update({ is_praying: true })
        .eq('id', prayerId)

      if (updateError) throw updateError

      // Update local state
      const prayer = prayers.value.find(p => p.id === prayerId)
      if (prayer) {
        prayer.is_praying = true
      }
    } catch (err) {
      console.error('[usePrayers] Mark approved error:', err)
    }
  }

  /**
   * Archive a prayer (marks as is_archived = true to hide from user).
   * Archived prayers are hidden from the UI but retained in the database.
   * This frees up the active prayer slot if the archived prayer was active.
   * @param {string} prayerId - The prayer ID to archive
   */
  async function archivePrayer(prayerId) {
    try {
      loading.value = true
      error.value = null

      const { error: updateError } = await supabase
        .from('prayers')
        .update({ is_archived: true, is_praying: false, activated_at: null })
        .eq('id', prayerId)

      if (updateError) throw updateError

      // Remove from local list (hides from UI)
      prayers.value = prayers.value.filter(p => p.id !== prayerId)
    } catch (err) {
      error.value = err.message
      console.error('[usePrayers] Archive error:', err)
      throw err
    } finally {
      loading.value = false
    }
  }

  /**
   * Refill Mana by reducing tokens_spent_today
   * Used for ad-watching rewards. Calls the refill_tokens RPC function.
   * @param {number} amount - Number of Mana to refill (e.g., 100 for watching an ad)
   * @returns {number} New tokens_spent_today value
   */
  async function refillTokens(amount) {
    try {
      const { data: newSpent, error: rpcError } = await supabase
        .rpc('refill_tokens', { p_amount: amount })

      if (rpcError) throw rpcError

      dailyManaSpent.value = newSpent
      return newSpent
    } catch (err) {
      console.error('[usePrayers] Refill Mana error:', err)
      throw err
    }
  }

  // Computed properties for karma display
  const karmaEmoji = computed(() => {
    if (karma.value > 0) return '😇'
    if (karma.value < 0) return '😈'
    return '😐'
  })
  
  // Only currently-praying prayers occupy a slot (inactive ones don't)
  const activePrayerCount = computed(() => prayers.value.filter(p => p.is_praying && !p.is_archived).length)
  const canAddPrayer = computed(() => activePrayerCount.value < maxPrayerSlots.value)
  // Alias for clarity: can submit a new prayer (form enabled/disabled)
  const canSubmitPrayer = canAddPrayer
  
  // Computed properties for profile completion
  const isProfileComplete = computed(() => {
    return !!username.value && !!faith.value
  })
  
  // All currently-active prayers (is_praying = true, not rejected/archived), sorted by activated_at (FIFO)
  const activePrayersList = computed(() =>
    prayers.value.filter(p => p.is_praying && !p.is_rejected && !p.is_archived)
      .sort((a, b) => new Date(a.activated_at) - new Date(b.activated_at))
  )

  // The first currently-active prayer (backward compat, used by single-prayer displays)
  const currentActivePrayer = computed(() => activePrayersList.value[0] || null)

  // Inactive prayers: not praying, not rejected, not archived (pooled in infinite list)
  const inactivePrayers = computed(() =>
    prayers.value.filter(p => !p.is_praying && !p.is_rejected && !p.is_archived)
  )

  // All non-archived, non-rejected prayers (active + inactive)
  const activePrayers = computed(() => prayers.value.filter(p => !p.is_rejected && !p.is_archived))
  
  // Archived prayers (rejected or user-archived), hidden from main view
  const archivedPrayers = computed(() => prayers.value.filter(p => p.is_rejected || p.is_archived).sort((a, b) => new Date(b.created_at) - new Date(a.created_at)))

  /**
   * Activate a prayer (swap with current active prayer).
   * Calls activate_prayer RPC which handles deactivation of current active.
   * @param {string} prayerId - The prayer to activate
   */
  async function activatePrayer(prayerId) {
    try {
      loading.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('activate_prayer', {
        p_prayer_id: prayerId,
      })

      if (rpcError) throw rpcError

      // Update local state based on RPC response
      if (data) {
        // Deactivate the previously active prayer in local state
        if (data.deactivated_id) {
          const oldActive = prayers.value.find(p => p.id === data.deactivated_id)
          if (oldActive) {
            oldActive.is_praying = false
            oldActive.activated_at = null
          }
        }

        // Activate the new prayer in local state
        const newActive = prayers.value.find(p => p.id === data.activated.id)
        if (newActive) {
          newActive.is_praying = true
          newActive.activated_at = data.activated.activated_at
          newActive.last_counted_at = data.activated.last_counted_at
          newActive.prayer_count = data.activated.prayer_count
        }
      }

      return data
    } catch (err) {
      error.value = err.message
      console.error('[usePrayers] Activate prayer error:', err)
      throw err
    } finally {
      loading.value = false
    }
  }

  /**
   * Deactivate the current active prayer.
   * Performs a final count sync before deactivating.
   * @param {string} prayerId - The prayer to deactivate
   * @param {number} elapsedCounts - Counts accumulated since last sync
   */
  async function deactivatePrayer(prayerId, elapsedCounts = 0) {
    try {
      loading.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('deactivate_prayer', {
        p_prayer_id: prayerId,
        p_elapsed_counts: elapsedCounts,
      })

      if (rpcError) throw rpcError

      // Update local state
      const prayer = prayers.value.find(p => p.id === prayerId)
      if (prayer && data) {
        prayer.is_praying = false
        prayer.activated_at = null
        prayer.prayer_count = data.prayer_count
      }

      return data
    } catch (err) {
      error.value = err.message
      console.error('[usePrayers] Deactivate prayer error:', err)
      throw err
    } finally {
      loading.value = false
    }
  }

  /**
   * Sync prayer count to backend (called periodically while prayer is active).
   * @param {string} prayerId - The prayer to sync
   * @param {number} elapsedCounts - Counts accumulated since last sync
   */
  async function syncPrayerCount(prayerId, elapsedCounts) {
    try {
      const { data, error: rpcError } = await supabase.rpc('sync_prayer_count', {
        p_prayer_id: prayerId,
        p_elapsed_counts: elapsedCounts,
      })

      if (rpcError) throw rpcError

      // Update local state with recalibrated data
      if (data) {
        const prayer = prayers.value.find(p => p.id === prayerId)
        if (prayer) {
          prayer.prayer_count = data.prayer_count
          prayer.last_counted_at = data.last_counted_at
          prayer.activated_at = data.activated_at
        }

        // Check for karma milestone earned (every 10 prays)
        if (data.karma_change && data.karma_change > 0) {
          karma.value += data.karma_change
        }
      }

      return data
    } catch (err) {
      console.error('[usePrayers] Sync prayer count error:', err)
      throw err
    }
  }

  /**
   * Purchase an additional prayer slot
   * Cost: 25 karma * current number of slots
   * Effect: +1 max_prayer_slots, +100 daily_token_limit
   */
  async function purchasePrayerSlot() {
    try {
      loading.value = true
      error.value = null

      const { data, error: rpcError } = await supabase.rpc('purchase_prayer_slot')

      if (rpcError) throw rpcError

      if (data?.success) {
        // Update local state
        maxPrayerSlots.value = data.new_slots
        karma.value = data.new_karma
        // Note: dailyManaLimit is a const, would need refactoring to update dynamically
        // For now, the user will see the updated slots immediately but mana limit
        // will update on next page reload or fetchDailyCount call
      } else if (data?.error) {
        error.value = `${data.error}. Cost: ${data.cost} karma, You have: ${data.current_karma} karma`
      }

      return data
    } catch (err) {
      error.value = err.message
      console.error('[usePrayers] Purchase slot error:', err)
      throw err
    } finally {
      loading.value = false
    }
  }

  /**
   * Mark onboarding as complete in the database
   */
  async function setOnboardingComplete() {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) return

      await supabase
        .from('profiles')
        .update({ onboarding_complete: true })
        .eq('id', user.id)

      onboardingComplete.value = true
    } catch (err) {
      console.error('[usePrayers] setOnboardingComplete error:', err)
    }
  }

  return reactive({
    // State
    prayers,
    dailyManaLimit,
    dailyManaSpent,
    karma,
    mana,
    gold,
    food,
    maxPrayerSlots,
    username,
    faith,
    onboardingComplete,
    loading,
    error,
    // Aether Modal State
    isAetherProcessing,
    aetherResult,
    // Computed
    canPray,
    tokensRemaining,
    karmaEmoji,
    activePrayerCount,
    canAddPrayer,
    canSubmitPrayer,
    isProfileComplete,
    currentActivePrayer,
    activePrayersList,
    inactivePrayers,
    activePrayers,
    archivedPrayers,
    // Methods
    fetchPrayers,
    fetchDailyCount,
    fetchProfile,
    updateProfile,
    submitPrayer,
    calculateManaCost,
    processPrayerWithVenice,
    markPrayerRejected,
    markPrayerApproved,
    archivePrayer,
    refillTokens,
    setOnboardingComplete,
    // Prayer activation/counting
    activatePrayer,
    deactivatePrayer,
    syncPrayerCount,
    purchasePrayerSlot,
  })
}

export function usePrayers() {
  if (!sharedState) {
    sharedState = createPrayersState()
  }
  return sharedState
}
