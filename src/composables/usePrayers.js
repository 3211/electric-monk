import { ref, computed, reactive } from 'vue'
import { supabase } from '@/lib/supabase'

/**
 * usePrayers Composable
 * 
 * Manages prayer submission, retrieval, and status tracking.
 * Handles daily prayer limits and interfaces with Venice AI for validation.
 * 
 * @returns {Object} Prayer state and methods
 */
export function usePrayers() {
  const prayers = ref([])
  const dailyLimit = 10 // Default daily prayer limit
  const dailyCount = ref(0)
  const loading = ref(false)
  const error = ref(null)

  // Computed properties
  const canPray = computed(() => dailyCount.value < dailyLimit)
  const prayersRemaining = computed(() => dailyLimit - dailyCount.value)

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
   * Get current daily prayer count from profile
   */
  async function fetchDailyCount() {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) return 0

      const { data: profile } = await supabase
        .from('profiles')
        .select('daily_prayers_count, last_prayer_date')
        .eq('id', user.id)
        .single()

      // Check if we need to reset the daily count
      const today = new Date().toDateString()
      const lastPrayerDate = profile?.last_prayer_date 
        ? new Date(profile.last_prayer_date).toDateString() 
        : null

      if (lastPrayerDate !== today) {
        // Reset count via database function
        await supabase.rpc('reset_daily_prayer_count', { user_id: user.id })
        dailyCount.value = 0
      } else {
        dailyCount.value = profile?.daily_prayers_count || 0
      }

      return dailyCount.value
    } catch (err) {
      console.error('[usePrayers] Daily count error:', err)
      return 0
    }
  }

  /**
   * Submit a new prayer for processing
   * @param {string} content - The prayer text
   * @returns {Object} The created prayer
   */
  async function submitPrayer(content) {
    try {
      loading.value = true
      error.value = null

      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('No user logged in')

      // Check daily limit
      await fetchDailyCount()
      if (!canPray.value) {
        throw new Error('Daily prayer limit reached. Return tomorrow.')
      }

      // TODO: Integrate Venice AI validation here before inserting
      // For now, we'll insert directly and mark as not rejected
      const prayerData = {
        user_id: user.id,
        content,
        is_rejected: false,
        is_praying: true, // Mark as being processed/prayed
      }

      const { data: newPrayer, error: insertError } = await supabase
        .from('prayers')
        .insert(prayerData)
        .select()
        .single()

      if (insertError) throw insertError

      // Increment daily count
      await incrementDailyCount()

      // Add to local list
      prayers.value.unshift(newPrayer)

      // TODO: Trigger Venice AI processing in background
      // await processPrayerWithVenice(newPrayer.id)

      return newPrayer
    } catch (err) {
      error.value = err.message
      console.error('[usePrayers] Submit error:', err)
      throw err
    } finally {
      loading.value = false
    }
  }

  /**
   * Increment the daily prayer count in the database
   */
  async function incrementDailyCount() {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) return

      const { error: updateError } = await supabase
        .from('profiles')
        .update({
          daily_prayers_count: dailyCount.value + 1,
          last_prayer_date: new Date().toISOString(),
        })
        .eq('id', user.id)

      if (updateError) throw updateError

      dailyCount.value++
    } catch (err) {
      console.error('[usePrayers] Increment count error:', err)
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

  return reactive({
    // State
    prayers,
    dailyLimit,
    dailyCount,
    loading,
    error,
    // Computed
    canPray,
    prayersRemaining,
    // Methods
    fetchPrayers,
    fetchDailyCount,
    submitPrayer,
    processPrayerWithVenice,
    markPrayerRejected,
    markPrayerApproved,
    deletePrayer,
  })
}
