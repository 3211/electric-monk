import { ref, reactive } from 'vue'
import { supabase } from '@/lib/supabase'
import { usePrayers } from './usePrayers'

/**
 * useKarmaShop Composable
 *
 * Manages the Karma Shop state and blessing purchase flow:
 * - Active tab state (extensible for future shop tabs)
 * - Blessing purchase via grant_blessing RPC
 * - Refreshes user karma after purchase
 * - Tracks shield info from blessing response
 * - Tracks purchase loading, error, and success states
 */
export function useKarmaShop() {
  const activeTab = ref('blessings') // 'blessings' | future: 'avatars', 'titles', etc.
  const purchasing = ref(false)
  const purchaseError = ref(null)
  const lastPurchase = ref(null) // { blessing_type_id, karma_spent, shield_minutes, ... }
  const lastShieldInfo = ref(null) // { shield_minutes, shield_giver_until, shield_receiver_until }

  const prayers = usePrayers()

  /**
   * Purchase and grant a blessing to a prayer.
   * Atomically deducts karma, awards rebates, grants Divine Shield
   * to both giver and receiver, and creates the blessing record.
   *
   * @param {string} prayerId - The prayer to bless
   * @param {string} blessingTypeId - The blessing type to grant
   * @returns {Object} The result from grant_blessing RPC (includes shield info)
   */
  async function purchaseBlessing(prayerId, blessingTypeId) {
    try {
      purchasing.value = true
      purchaseError.value = null
      lastPurchase.value = null
      lastShieldInfo.value = null

      const { data, error: rpcError } = await supabase.rpc('grant_blessing', {
        p_prayer_id: prayerId,
        p_blessing_type_id: blessingTypeId,
      })

      if (rpcError) throw rpcError

      lastPurchase.value = data

      // Extract shield info from the response
      if (data && (data.shield_minutes > 0 || data.shield_giver_until)) {
        lastShieldInfo.value = {
          shield_minutes: data.shield_minutes,
          shield_giver_until: data.shield_giver_until,
          shield_receiver_until: data.shield_receiver_until,
        }
      }

      // Refresh user karma after purchase
      await prayers.fetchProfile()

      return data
    } catch (err) {
      purchaseError.value = err.message
      console.error('[useKarmaShop] Purchase blessing error:', err)
      throw err
    } finally {
      purchasing.value = false
    }
  }

  /**
   * Clear purchase error state
   */
  function clearPurchaseError() {
    purchaseError.value = null
  }

  /**
   * Clear last purchase result and shield info
   */
  function clearLastPurchase() {
    lastPurchase.value = null
    lastShieldInfo.value = null
  }

  return reactive({
    activeTab,
    purchasing,
    purchaseError,
    lastPurchase,
    lastShieldInfo,
    purchaseBlessing,
    clearPurchaseError,
    clearLastPurchase,
  })
}