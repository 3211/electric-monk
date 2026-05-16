<template>
  <div class="flex items-center justify-center bg-theme-wash px-4 py-8">
    <div class="max-w-md w-full text-center">
      <!-- Header with Karma -->
      <div class="mb-4">
        <h1 class="text-5xl font-bold text-theme-purgatory mb-2">Purgatory</h1>
        <p class="text-theme-text-dim mb-2">Your soul has been tainted by malicious intent</p>
        <!-- Karma Display -->
        <div class="inline-flex items-center gap-2 px-3 py-1 bg-theme-panel rounded border border-theme-border">
          <span class="text-lg">{{ prayers.karmaEmoji }}</span>
          <span class="text-sm text-theme-text-dim">Karma: <span :class="karmaClass">{{ prayers.karma }}</span></span>
        </div>
      </div>

      <!-- Intercessory Prayer Count -->
      <div v-if="intercessoryCount > 0" class="mb-4 p-3 bg-theme-accent/10 border border-theme-accent/30 rounded-lg">
        <p class="text-theme-accent text-sm font-medium">
          🕯️ {{ intercessoryCount }} {{ intercessoryCount === 1 ? 'person is' : 'people are' }} praying for your redemption
        </p>
        <p class="text-theme-text-muted text-xs mt-1">Each completed prayer cycle reduces your time by 1 minute</p>
      </div>

      <!-- Ban Timer -->
      <div class="glass-panel glass-gloss p-8 mb-6 border-theme-purgatory shadow-glow-purgatory">
        <div class="text-6xl font-mono font-bold text-theme-purgatory mb-4">
          {{ banTimer.formattedTimeRemaining || '0s' }}
        </div>
        <p class="text-theme-text-dim text-sm">
          Time remaining until redemption
        </p>
      </div>

      <!-- Indulgence Section -->
      <div class="glass-panel glass-gloss p-6 mb-6">
        <h2 class="text-xl font-semibold text-theme-accent mb-2">Watch an Indulgence</h2>
        <p class="text-theme-text-dim text-sm mb-4">
          View a sacred advertisement to reduce your penance by 15 minutes
        </p>

        <button
          v-if="!showingAd"
          @click="startIndulgence"
          :disabled="!banTimer.canWatchIndulgence || banTimer.loading"
          class="w-full py-3 px-4 btn-primary disabled:cursor-not-allowed transition-all duration-150 ease-out"
        >
          <span class="relative z-10 font-medium">
            {{ banTimer.loading ? 'Processing...' : 'Watch Indulgence (-15 min)' }}
          </span>
        </button>

        <!-- Ad Placeholder -->
        <div v-else class="space-y-4">
          <div class="aspect-video bg-theme-panel rounded flex items-center justify-center border border-theme-border">
            <div class="text-center">
              <div class="animate-pulse text-theme-accent mb-2">
                <svg class="w-12 h-12 mx-auto" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z"/>
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
                </svg>
              </div>
              <p class="text-theme-text-dim text-sm">Sacred Advertisement Loading...</p>
            </div>
          </div>
          <button
            @click="completeIndulgence"
            class="w-full py-2 px-4 btn-complete transition-all duration-150 ease-out"
          >
            <span class="relative z-10 font-medium">
              Complete Indulgence
            </span>
          </button>
        </div>
      </div>

      <!-- Error Message -->
      <div v-if="banTimer.error" class="p-3 bg-theme-purgatory/20 border border-theme-purgatory rounded text-theme-purgatory-dark text-sm glass-gloss">
        {{ banTimer.error }}
      </div>

      <!-- Reason for Ban (if available) -->
      <div v-if="rejectionReason" class="mt-6 p-4 glass-panel glass-gloss border-theme-purgatory">
        <p class="text-theme-text-dim text-xs uppercase tracking-wide mb-1">Last Transgression</p>
        <p class="text-theme-purgatory-dark italic">"{{ rejectionReason }}"</p>
      </div>

      <!-- Logout -->
      <div class="mt-6">
        <button
          @click="handleLogout"
          class="px-4 py-2 text-sm text-theme-text-dim hover:text-theme-text transition-colors"
        >
          Logout
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { useBanTimer } from '@/composables/useBanTimer'
import { usePrayers } from '@/composables/usePrayers'
import { useAuth } from '@/composables/useAuth'
import { supabase } from '@/lib/supabase'

const banTimer = useBanTimer()
const prayers = usePrayers()
const auth = useAuth()
const showingAd = ref(false)
const rejectionReason = ref(null)
const intercessoryCount = ref(0)

let countPollInterval = null

async function fetchIntercessoryCount() {
  try {
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return
    const { data, error } = await supabase.rpc('get_intercessory_prayer_count', { p_sinner_id: user.id })
    if (!error) {
      intercessoryCount.value = data || 0
    }
  } catch (err) {
    console.error('[PurgatoryView] Fetch intercessory count error:', err)
  }
}

onMounted(async () => {
  // Fetch profile for karma and prayers for rejection reason
  await prayers.fetchProfile()
  await prayers.fetchPrayers()
  const rejectedPrayer = prayers.prayers.find(p => p.is_rejected)
  if (rejectedPrayer) {
    rejectionReason.value = rejectedPrayer.rejection_reason || 'Unknown transgression'
  }

  // Fetch intercessory prayer count
  await fetchIntercessoryCount()

  // Poll intercessory count every 30 seconds
  countPollInterval = setInterval(fetchIntercessoryCount, 30000)
})

onUnmounted(() => {
  if (countPollInterval) {
    clearInterval(countPollInterval)
    countPollInterval = null
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
    // Error is already captured in banTimer.error
  }
}

async function handleLogout() {
  await auth.signOut()
}

function karmaClass() {
  if (prayers.karma > 0) return 'text-theme-accent'
  if (prayers.karma < 0) return 'text-theme-purgatory'
  return 'text-theme-text-dim'
}
</script>

<style scoped>
/* Primary button with gold gradient */
.btn-primary {
  @apply relative overflow-hidden font-sans rounded-btn px-4 py-3 border shadow-inner-top glass-gloss active:translate-y-0 transition-all duration-150 ease-out cursor-pointer;
  color: white;
  border-color: color-mix(in srgb, var(--theme-accent) 55%, white 10%);
  box-shadow: 0 18px 30px color-mix(in srgb, var(--theme-accent) 28%, transparent);
  background: linear-gradient(
    180deg,
    color-mix(in srgb, var(--theme-accent) 34%, white 12%),
    color-mix(in srgb, var(--theme-accent-2) 72%, black 15%)
  );
}

.btn-primary:hover {
  transform: translateY(-1px);
}

.btn-primary:disabled {
  background: linear-gradient(
    180deg,
    color-mix(in srgb, var(--theme-accent) 20%, gray 30%),
    color-mix(in srgb, var(--theme-accent-dark) 40%, gray 40%)
  );
}

/* Complete button - green/positive action */
.btn-complete {
  @apply relative overflow-hidden font-sans rounded-btn px-4 py-2 border shadow-inner-top glass-gloss active:translate-y-0 transition-all duration-150 ease-out cursor-pointer text-white;
  border-color: color-mix(in srgb, #16a34a 55%, white 10%);
  background: linear-gradient(
    180deg,
    color-mix(in srgb, #16a34a 50%, white 8%),
    color-mix(in srgb, #22c55e 70%, black 12%)
  );
}

.btn-complete:hover {
  transform: translateY(-1px);
  box-shadow: 0 18px 30px color-mix(in srgb, #16a34a 28%, transparent);
}
</style>