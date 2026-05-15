<template>
  <div class="min-h-screen flex items-center justify-center bg-gradient-to-b from-red-950 to-gray-900 px-4">
    <div class="max-w-md w-full text-center">
      <!-- Header -->
      <h1 class="text-5xl font-bold text-red-500 mb-2">Purgatory</h1>
      <p class="text-gray-400 mb-8">Your soul has been tainted by malicious intent</p>

      <!-- Ban Timer -->
      <div class="bg-gray-800/80 rounded-lg p-8 mb-6 border border-red-900">
        <div class="text-6xl font-mono font-bold text-red-400 mb-4">
          {{ banTimer.formattedTimeRemaining || '0s' }}
        </div>
        <p class="text-gray-400 text-sm">
          Time remaining until redemption
        </p>
      </div>

      <!-- Indulgence Section -->
      <div class="bg-gray-800/50 rounded-lg p-6 mb-6 border border-gray-700">
        <h2 class="text-xl font-semibold text-amber-500 mb-2">Watch an Indulgence</h2>
        <p class="text-gray-400 text-sm mb-4">
          View a sacred advertisement to reduce your penance by 15 minutes
        </p>

        <button
          v-if="!showingAd"
          @click="startIndulgence"
          :disabled="!banTimer.canWatchIndulgence || banTimer.loading"
          class="w-full py-3 px-4 bg-amber-600 hover:bg-amber-700 disabled:bg-amber-800 disabled:cursor-not-allowed text-white font-semibold rounded transition-colors"
        >
          {{ banTimer.loading ? 'Processing...' : 'Watch Indulgence (-15 min)' }}
        </button>

        <!-- Ad Placeholder -->
        <div v-else class="space-y-4">
          <div class="aspect-video bg-gray-900 rounded flex items-center justify-center border border-gray-700">
            <div class="text-center">
              <div class="animate-pulse text-amber-500 mb-2">
                <svg class="w-12 h-12 mx-auto" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z"/>
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
                </svg>
              </div>
              <p class="text-gray-400 text-sm">Sacred Advertisement Loading...</p>
            </div>
          </div>
          <button
            @click="completeIndulgence"
            class="w-full py-2 px-4 bg-green-700 hover:bg-green-600 text-white font-semibold rounded transition-colors"
          >
            Complete Indulgence
          </button>
        </div>
      </div>

      <!-- Error Message -->
      <div v-if="banTimer.error" class="p-3 bg-red-900/50 border border-red-700 rounded text-red-200 text-sm">
        {{ banTimer.error }}
      </div>

      <!-- Reason for Ban (if available) -->
      <div v-if="rejectionReason" class="mt-6 p-4 bg-red-900/30 rounded border border-red-800">
        <p class="text-gray-400 text-xs uppercase tracking-wide mb-1">Last Transgression</p>
        <p class="text-red-200 italic">"{{ rejectionReason }}"</p>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { useBanTimer } from '@/composables/useBanTimer'
import { usePrayers } from '@/composables/usePrayers'

const banTimer = useBanTimer()
const prayers = usePrayers()
const showingAd = ref(false)
const rejectionReason = ref(null)

onMounted(async () => {
  // Fetch the most recent rejected prayer to show the reason
  await prayers.fetchPrayers()
  const rejectedPrayer = prayers.prayers.find(p => p.is_rejected)
  if (rejectedPrayer) {
    rejectionReason.value = rejectedPrayer.rejection_reason || 'Unknown transgression'
  }
})

function startIndulgence() {
  showingAd.value = true
  // In production, this would open a real ad player
  // For now, we simulate with a button click
}

async function completeIndulgence() {
  try {
    await banTimer.watchIndulgence()
    showingAd.value = false
  } catch (err) {
    // Error is captured in banTimer.error
  }
}
</script>
