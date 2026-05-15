import { ref, computed, reactive } from 'vue'
import { supabase } from '@/lib/supabase'

// Environment variables for Mana-based limits
// Note: These are used for UI display only. Actual limits are enforced server-side via RPC.
const MAX_PRAYER_CHARS = parseInt(import.meta.env.VITE_MAX_PRAYER_CHARS || '1500', 10)
const DAILY_MANA_LIMIT = parseInt(import.meta.env.VITE_DAILY_TOKEN_LIMIT || '1000', 10)
const PRAYER_MANA_RATIO = parseInt(import.meta.env.VITE_PRAYER_TOKEN_RATIO || '5', 10)

/**
 * usePrayers Composable
 *
 * Manages prayer submission, retrieval, and status tracking.
 * Uses Supabase RPC functions for secure, server-side Mana validation.
 *
 * Database Schema Notes:
 * - profiles.tokens_spent_today (INT): Tracks Mana spent today (was daily_prayers_count)
 * - profiles.daily_token_limit (INT): User's daily Mana budget (default 1000)
 * - RPC submit_prayer(content): Atomically inserts prayer and updates tokens_spent_today
 * - RPC refill_tokens(amount): Reduces tokens_spent_today (for ad rewards)
 *
 * @returns {Object} Prayer state and methods
 */
export function usePrayers() {
  const prayers = ref([])
  const dailyManaLimit = DAILY_MANA_LIMIT
  const dailyManaSpent = ref(0)
  const karma = ref(0)
  const maxPrayerSlots = ref(1)
  const loading = ref(false)
  const error = ref(null)

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
  const canPray = computed(() => dailyManaSpent.value < dailyManaLimit)
  const tokensRemaining = computed(() => Math.max(0, dailyManaLimit - dailyManaSpent.value))

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
        .eq('is_deleted', false)
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
   * Fetch user's profile including karma and max prayer slots
   */
  async function fetchProfile() {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) return

      const { data: profile } = await supabase
        .from('profiles')
        .select('karma, max_prayer_slots')
        .eq('id', user.id)
        .single()

      if (profile) {
        karma.value = profile.karma || 0
        maxPrayerSlots.value = profile.max_prayer_slots || 1
      }
    } catch (err) {
      console.error('[usePrayers] Profile fetch error:', err)
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
        // Reset count via database function
        // Note: This RPC must exist in Supabase. If getting 404, run the schema SQL.
        const { error: resetError } = await supabase.rpc('reset_daily_prayer_count', { user_id: user.id })
        if (resetError) {
          console.warn('[usePrayers] Reset RPC failed (may need to run schema SQL):', resetError)
          // Fallback: just set to 0 locally if RPC fails
          dailyManaSpent.value = 0
        } else {
          dailyManaSpent.value = 0
        }
        // Update local limit if DB has different value
        if (profile?.daily_token_limit) {
          // Note: dailyManaLimit is a const, would need refactoring to update
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
  async function submitPrayer(content) {
    try {
      loading.value = true
      error.value = null

      // Client-side validation for UX (server also validates)
      if (content.length > MAX_PRAYER_CHARS) {
        throw new Error(`Prayer exceeds maximum length of ${MAX_PRAYER_CHARS} characters.`)
      }

      // Step 1: Call the secure RPC function to deduct tokens and create prayer record
      const { data: result, error: rpcError } = await supabase
        .rpc('submit_prayer', { prayer_content: content })

      if (rpcError) throw rpcError

      // Fetch the newly created prayer
      const { data: newPrayer, error: fetchError } = await supabase
        .from('prayers')
        .select('*')
        .eq('id', result.id)
        .single()

      if (fetchError) throw fetchError

      // Update local state
      prayers.value.unshift(newPrayer)
      
      // Update Mana spent (RPC already updated in DB)
      const manaCost = result.cost
      dailyManaSpent.value += manaCost

      // Step 2: Invoke the Edge Function to process prayer with Venice AI
      // This happens asynchronously but we keep loading state until it completes
      const { data: aiResult, error: aiError } = await supabase.functions.invoke('process-prayer', {
        body: {
          prayer_id: newPrayer.id,
          content: newPrayer.content,
          user_id: newPrayer.user_id,
        },
      })

      if (aiError) {
        console.error('[usePrayers] Edge Function error:', aiError)
        // Don't throw here - the prayer was already submitted successfully
        // Just log the error and let the user know AI processing failed
        newPrayer.processing_error = true
      } else if (aiResult) {
        // Update the prayer with AI judgment results
        newPrayer.judgment = aiResult.judgment
        newPrayer.ai_response = aiResult.response
        newPrayer.rejection_reason = aiResult.rejection_reason
        newPrayer.is_rejected = aiResult.judgment === 'rejected'
        newPrayer.is_praying = aiResult.judgment === 'approved'
        
        // Update local prayers list with the new status
        const index = prayers.value.findIndex(p => p.id === newPrayer.id)
        if (index !== -1) {
          prayers.value[index] = { ...prayers.value[index], ...newPrayer }
        }
      }

      return { prayer: newPrayer, cost: manaCost, aiResult }
    } catch (err) {
      error.value = err.message
      console.error('[usePrayers] Submit error:', err)
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
   * Soft-delete a prayer (marks as is_deleted = true to free up slot)
   * @param {string} prayerId - The prayer ID to delete
   */
  async function deletePrayer(prayerId) {
    try {
      loading.value = true
      error.value = null

      // Soft delete: set is_deleted = true instead of actually deleting
      const { error: updateError } = await supabase
        .from('prayers')
        .update({ is_deleted: true })
        .eq('id', prayerId)

      if (updateError) throw updateError

      // Remove from local list (frees up the slot in UI)
      prayers.value = prayers.value.filter(p => p.id !== prayerId)
      
      // Refresh profile to get updated slot count
      await fetchProfile()
    } catch (err) {
      error.value = err.message
      console.error('[usePrayers] Delete error:', err)
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
  
  const activePrayerCount = computed(() => prayers.value.filter(p => !p.is_deleted).length)
  const canAddPrayer = computed(() => activePrayerCount.value < maxPrayerSlots.value)
  
  // Computed properties for active and archived prayers
  const activePrayers = computed(() => prayers.value.filter(p => !p.is_rejected && !p.is_deleted))
  const archivedPrayers = computed(() => prayers.value.filter(p => p.is_rejected || p.is_deleted).sort((a, b) => new Date(b.created_at) - new Date(a.created_at)))

  return reactive({
    // State
    prayers,
    dailyManaLimit,
    dailyManaSpent,
    karma,
    maxPrayerSlots,
    loading,
    error,
    // Computed
    canPray,
    tokensRemaining,
    karmaEmoji,
    activePrayerCount,
    canAddPrayer,
    activePrayers,
    archivedPrayers,
    // Methods
    fetchPrayers,
    fetchDailyCount,
    fetchProfile,
    submitPrayer,
    calculateManaCost,
    processPrayerWithVenice,
    markPrayerRejected,
    markPrayerApproved,
    deletePrayer,
    // New: Mana refill for ad rewards
    refillTokens,
  })
}
