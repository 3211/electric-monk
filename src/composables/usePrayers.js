import { ref, computed, reactive } from 'vue'
import { supabase } from '@/lib/supabase'

// Environment variables for token-based limits
// Note: These are used for UI display only. Actual limits are enforced server-side via RPC.
const MAX_PRAYER_CHARS = parseInt(import.meta.env.VITE_MAX_PRAYER_CHARS || '1500', 10)
const DAILY_TOKEN_LIMIT = parseInt(import.meta.env.VITE_DAILY_TOKEN_LIMIT || '1000', 10)
const PRAYER_TOKEN_RATIO = parseInt(import.meta.env.VITE_PRAYER_TOKEN_RATIO || '5', 10)

/**
 * usePrayers Composable
 *
 * Manages prayer submission, retrieval, and status tracking.
 * Uses Supabase RPC functions for secure, server-side token validation.
 *
 * Database Schema Notes:
 * - profiles.tokens_spent_today (INT): Tracks tokens spent today (was daily_prayers_count)
 * - profiles.daily_token_limit (INT): User's daily token budget (default 1000)
 * - RPC submit_prayer(content): Atomically inserts prayer and updates tokens_spent_today
 * - RPC refill_tokens(amount): Reduces tokens_spent_today (for ad rewards)
 *
 * @returns {Object} Prayer state and methods
 */
export function usePrayers() {
  const prayers = ref([])
  const dailyTokenLimit = DAILY_TOKEN_LIMIT
  const dailyTokensSpent = ref(0)
  const loading = ref(false)
  const error = ref(null)

  /**
   * Calculate token cost for a prayer based on character count
   * Used for UI estimation only. Actual cost calculated server-side.
   * @param {string} content - The prayer text
   * @returns {number} Estimated token cost
   */
  function calculateTokenCost(content) {
    const charCount = content.length
    return Math.ceil(charCount / PRAYER_TOKEN_RATIO)
  }

  // Computed properties
  const canPray = computed(() => dailyTokensSpent.value < dailyTokenLimit)
  const tokensRemaining = computed(() => Math.max(0, dailyTokenLimit - dailyTokensSpent.value))

  /**
   * Fetch user's prayers from database
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
   * Get current daily token spending from profile
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
          dailyTokensSpent.value = 0
        } else {
          dailyTokensSpent.value = 0
        }
        // Update local limit if DB has different value
        if (profile?.daily_token_limit) {
          // Note: dailyTokenLimit is a const, would need refactoring to update
        }
      } else {
        dailyTokensSpent.value = profile?.tokens_spent_today || 0
      }

      return dailyTokensSpent.value
    } catch (err) {
      console.error('[usePrayers] Daily count error:', err)
      return 0
    }
  }

  /**
   * Submit a new prayer for processing using the secure RPC function.
   * The database function submit_prayer() handles:
   * - Character limit validation (1500 chars)
   * - Token budget validation (daily_token_limit)
   * - Atomic insert of prayer and update of tokens_spent_today
   *
   * @param {string} content - The prayer text
   * @returns {Object} Result containing prayer ID and token cost
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
      
      // Update tokens spent (RPC already updated in DB)
      const tokenCost = result.cost
      dailyTokensSpent.value += tokenCost

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
        // Update flags to support Virtuous, Malicious, and Tainted labels
        // Maps AI judgment to existing database schema (is_praying, is_rejected)
        newPrayer.is_rejected = aiResult.judgment === 'malicious' || aiResult.judgment === 'rejected'
        newPrayer.is_praying = aiResult.judgment === 'virtuous' || aiResult.judgment === 'approved' || aiResult.judgment === 'tainted'
        
        // Update local prayers list with the new status
        const index = prayers.value.findIndex(p => p.id === newPrayer.id)
        if (index !== -1) {
          prayers.value[index] = { ...prayers.value[index], ...newPrayer }
        }
      }

      return { prayer: newPrayer, cost: tokenCost, aiResult }
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
   * Delete a prayer
   * @param {string} prayerId - The prayer ID to delete
   */
  async function deletePrayer(prayerId) {
    try {
      loading.value = true
      error.value = null

      const { error: deleteError } = await supabase
        .from('prayers')
        .delete()
        .eq('id', prayerId)

      if (deleteError) throw deleteError

      // Remove from local list
      prayers.value = prayers.value.filter(p => p.id !== prayerId)
    } catch (err) {
      error.value = err.message
      console.error('[usePrayers] Delete error:', err)
      throw err
    } finally {
      loading.value = false
    }
  }

  /**
   * Refill tokens by reducing tokens_spent_today
   * Used for ad-watching rewards. Calls the refill_tokens RPC function.
   * @param {number} amount - Number of tokens to refill (e.g., 100 for watching an ad)
   * @returns {number} New tokens_spent_today value
   */
  async function refillTokens(amount) {
    try {
      const { data: newSpent, error: rpcError } = await supabase
        .rpc('refill_tokens', { p_amount: amount })

      if (rpcError) throw rpcError

      dailyTokensSpent.value = newSpent
      return newSpent
    } catch (err) {
      console.error('[usePrayers] Refill tokens error:', err)
      throw err
    }
  }

  return reactive({
    // State
    prayers,
    dailyTokenLimit,
    dailyTokensSpent,
    loading,
    error,
    // Computed
    canPray,
    tokensRemaining,
    // Methods
    fetchPrayers,
    fetchDailyCount,
    submitPrayer,
    calculateTokenCost,
    processPrayerWithVenice,
    markPrayerRejected,
    markPrayerApproved,
    deletePrayer,
    // New: Token refill for ad rewards
    refillTokens,
  })
}
