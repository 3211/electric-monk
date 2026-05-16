<template>
  <div class="app-frame flex min-h-screen items-center justify-center px-4 py-10 sm:py-14">
    <div class="purgatory-shell max-w-lg w-full text-center">
      <!-- Header with Karma -->
      <div class="mb-6">
        <h1 class="ritual-heading text-5xl font-bold text-theme-purgatory sm:text-6xl">Purgatory</h1>
        <p class="mx-auto mt-3 max-w-md text-theme-text-dim">Your soul has been tainted by malicious intent</p>
        <!-- Karma Display -->
        <div class="chip mt-4 inline-flex items-center gap-2 px-4 py-2 text-sm text-theme-text-dim shadow-[0_10px_20px_rgba(48,38,21,0.06)]">
          <span class="text-lg">{{ prayers.karmaEmoji }}</span>
          <span>Karma: <span :class="karmaClass" class="font-semibold">{{ prayers.karma }}</span></span>
        </div>
      </div>

      <!-- Intercessory Prayer Count -->
      <div v-if="intercessoryCount > 0" class="glass-panel glass-panel-soft mb-5 rounded-[24px] border border-theme-accent/20 p-4 shadow-[0_18px_28px_rgba(48,38,21,0.08)]">
        <p class="text-sm font-medium text-theme-accent">
          🕯️ {{ intercessoryCount }} {{ intercessoryCount === 1 ? 'person is' : 'people are' }} praying for your redemption
        </p>
        <p class="mt-1 text-xs text-theme-text-muted">Each completed prayer cycle reduces your time by 1 minute</p>
      </div>

      <!-- Ban Timer -->
      <div class="purgatory-timer glass-panel glass-panel-strong glass-gloss mb-6 border-theme-purgatory/35 p-8 shadow-glow-purgatory sm:p-10">
        <div class="purgatory-timer-halo"></div>
        <div class="relative z-10">
          <div class="purgatory-timer-value mb-4 text-6xl font-bold text-theme-purgatory sm:text-7xl">
            {{ banTimer.formattedTimeRemaining || '0s' }}
          </div>
          <p class="text-sm text-theme-text-dim">
            Time remaining until redemption
          </p>
        </div>
      </div>

      <!-- Indulgence Section -->
      <div class="glass-panel glass-panel-strong glass-gloss mb-6 p-6 sm:p-7">
        <h2 class="text-3xl font-semibold text-theme-accent">Watch an Indulgence</h2>
        <p class="mt-2 text-sm text-theme-text-dim">
          View a sacred advertisement to reduce your penance by 15 minutes
        </p>

        <button
          v-if="!showingAd"
          @click="startIndulgence"
          :disabled="!banTimer.canWatchIndulgence || banTimer.loading"
          class="btn-primary mt-5 w-full"
        >
          <span class="relative z-10 font-medium">
            {{ banTimer.loading ? 'Processing...' : 'Watch Indulgence (-15 min)' }}
          </span>
        </button>

        <!-- Ad Placeholder -->
        <div v-else class="mt-5 space-y-4">
          <div class="glass-panel glass-panel-soft aspect-video rounded-[24px] border border-theme-border p-6">
            <div class="flex h-full flex-col items-center justify-center text-center">
              <div class="mb-2 animate-pulse text-theme-accent">
                <svg class="mx-auto h-12 w-12" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z"/>
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
                </svg>
              </div>
              <p class="text-sm text-theme-text-dim">Sacred Advertisement Loading...</p>
            </div>
          </div>
          <button
            @click="completeIndulgence"
            class="btn-secondary w-full"
          >
            <span class="relative z-10 font-medium">
              Complete Indulgence
            </span>
          </button>
        </div>
      </div>

      <!-- Error Message -->
      <div v-if="banTimer.error" class="mb-6 rounded-[20px] border border-theme-purgatory/25 bg-theme-purgatory/10 p-3 text-sm text-theme-purgatory-dark shadow-[0_10px_24px_rgba(168,93,50,0.08)]">
        {{ banTimer.error }}
      </div>

      <!-- Reason for Ban (if available) -->
      <div v-if="rejectionReason" class="glass-panel glass-panel-soft mt-6 border-theme-purgatory/25 p-5">
        <p class="text-xs uppercase tracking-[0.18em] text-theme-text-muted">Last Transgression</p>
        <p class="mt-2 italic text-theme-purgatory-dark">"{{ rejectionReason }}"</p>
      </div>

      <!-- Logout -->
      <div class="mt-6">
        <button
          @click="handleLogout"
          class="btn-ghost px-4 py-2 text-sm"
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
.purgatory-shell {
  position: relative;
}

.purgatory-timer {
  position: relative;
  overflow: hidden;
}

.purgatory-timer::after {
  content: "";
  position: absolute;
  inset: 0;
  pointer-events: none;
  background: linear-gradient(180deg, rgba(255, 255, 255, 0.18), transparent 30%);
}

.purgatory-timer-halo {
  position: absolute;
  inset: 14% 18%;
  border-radius: 999px;
  background: radial-gradient(circle, rgba(201, 122, 79, 0.24), rgba(168, 93, 50, 0.12) 40%, transparent 72%);
  filter: blur(18px);
  animation: ritual-breathe 5.6s ease-in-out infinite;
}

.purgatory-timer-value {
  position: relative;
  z-index: 1;
  font-family: var(--font-mono);
  letter-spacing: -0.06em;
  font-variant-numeric: tabular-nums;
  text-shadow: 0 0 20px rgba(168, 93, 50, 0.16);
}
</style>