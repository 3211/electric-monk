<template>
  <div class="evil-shell min-h-screen">
    <div class="app-frame flex min-h-screen items-center justify-center px-4 py-10 sm:py-14">
      <div class="purgatory-shell evil-purgatory-shell max-w-xl w-full text-center">
      <!-- Header with Karma -->
      <div class="evil-purgatory-header mb-7">
        <h1 class="ritual-heading text-5xl font-bold text-theme-accent sm:text-6xl">Purgatory</h1>
        <p class="mx-auto mt-3 max-w-md text-theme-text-muted">Your soul has been tainted by malicious intent</p>
        <!-- Karma Display -->
        <div class="chip evil-metric-chip evil-purgatory-hero-chip mt-4 inline-flex items-center gap-2 px-4 py-2 text-sm text-theme-text-dim">
          <span class="text-lg">{{ prayers.karmaEmoji }}</span>
          <span>Karma: <span :class="karmaClass" class="font-semibold">{{ prayers.karma }}</span></span>
        </div>
      </div>

      <!-- Intercessory Prayer Count -->
      <div v-if="intercessoryCount > 0" class="glass-panel glass-panel-soft glass-gloss evil-purgatory-support mb-5 rounded-[20px] border border-theme-accent/20 p-4 sm:rounded-[24px]">
        <p class="text-sm font-medium text-theme-accent">
          🕯️ {{ intercessoryCount }} {{ intercessoryCount === 1 ? 'person is' : 'people are' }} praying for your redemption
        </p>
        <p class="mt-1 text-xs text-theme-text-muted">Each completed prayer cycle reduces your time by 1 minute</p>
      </div>

      <!-- Ban Timer -->
      <div class="purgatory-timer evil-purgatory-timer-panel glass-panel glass-panel-strong glass-gloss mb-6 border-theme-purgatory/35 p-8 sm:p-10">
        <div class="purgatory-timer-halo"></div>
        <div class="relative z-10">
          <div class="purgatory-timer-value mb-4 text-6xl font-bold text-theme-purgatory-dark sm:text-7xl">
            {{ banTimer.formattedTimeRemaining || '0s' }}
          </div>
          <p class="text-sm text-theme-text-dim">
            Time remaining until redemption
          </p>
        </div>
      </div>

      <!-- Indulgence Section -->
      <div class="glass-panel glass-panel-strong glass-gloss evil-purgatory-indulgence mb-6 p-6 sm:p-7">
        <h2 class="text-3xl font-semibold text-theme-accent-light">Watch an Indulgence</h2>
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
          <div class="glass-panel glass-panel-soft evil-purgatory-ad aspect-video rounded-[20px] border border-theme-border p-5 sm:rounded-[24px] sm:p-6">
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
      <div v-if="banTimer.error" class="evil-alert evil-alert--danger mb-6 p-3 text-sm text-theme-purgatory-dark">
        {{ banTimer.error }}
      </div>

      <!-- Reason for Ban (if available) -->
      <div v-if="rejectionReason" class="glass-panel glass-panel-soft glass-gloss evil-purgatory-transgression mt-6 border-theme-purgatory/25 p-5">
        <p class="text-xs uppercase tracking-[0.18em] text-theme-text-muted">Last Transgression</p>
        <p class="mt-2 italic text-theme-purgatory-dark">"{{ rejectionReason }}"</p>
      </div>

      <!-- Logout -->
      <div class="mt-6">
        <button
          @click="handleLogout"
          class="btn-ghost evil-purgatory-logout px-4 py-2 text-sm"
        >
          Logout
        </button>
      </div>
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

.evil-purgatory-shell {
  padding-block: clamp(0.5rem, 2vw, 1.25rem);
}

.evil-purgatory-shell::before,
.evil-purgatory-shell::after {
  content: "";
  position: absolute;
  inset: 0;
  pointer-events: none;
}

.evil-purgatory-shell::before {
  inset: -8% -10% auto;
  height: 20rem;
  background:
    radial-gradient(circle at 50% 16%, rgba(177, 128, 255, 0.22) 0%, rgba(177, 128, 255, 0.08) 30%, transparent 58%),
    radial-gradient(circle at 28% 26%, rgba(255, 107, 214, 0.14) 0%, transparent 28%),
    radial-gradient(circle at 74% 28%, rgba(255, 138, 99, 0.12) 0%, transparent 24%);
  filter: blur(22px);
  opacity: 0.95;
}

.evil-purgatory-shell::after {
  inset: 18% 6% auto;
  height: 70%;
  background: radial-gradient(circle at 50% 0%, rgba(255, 255, 255, 0.04), transparent 58%);
  opacity: 0.72;
}

.evil-purgatory-shell > * {
  position: relative;
  z-index: 1;
}

.evil-purgatory-header {
  position: relative;
}

.evil-purgatory-hero-chip {
  border-color: rgba(206, 170, 255, 0.24);
  background: linear-gradient(180deg, rgba(177, 128, 255, 0.12), rgba(255, 107, 214, 0.05));
  box-shadow: 0 16px 28px rgba(3, 2, 10, 0.24), inset 0 1px 0 rgba(255, 255, 255, 0.08);
}

.evil-purgatory-support {
  border-color: rgba(206, 170, 255, 0.22);
  box-shadow: 0 24px 40px rgba(2, 1, 8, 0.28), inset 0 1px 0 rgba(255, 255, 255, 0.06);
}

.purgatory-timer {
  position: relative;
  overflow: hidden;
}

.evil-purgatory-timer-panel {
  border-color: rgba(255, 138, 99, 0.22);
  background:
    radial-gradient(circle at 50% 0%, rgba(255, 138, 99, 0.08), transparent 42%),
    linear-gradient(180deg, rgba(18, 11, 28, 0.94), rgba(9, 6, 15, 0.98));
  box-shadow: 0 28px 60px rgba(2, 1, 8, 0.5), 0 0 44px rgba(255, 107, 214, 0.08), inset 0 1px 0 rgba(255, 255, 255, 0.08);
}

.purgatory-timer::before {
  content: "";
  position: absolute;
  inset: 1rem;
  border-radius: 24px;
  border: 1px solid rgba(255, 255, 255, 0.05);
  background: radial-gradient(circle at 50% 10%, rgba(255, 255, 255, 0.03), transparent 54%);
  pointer-events: none;
}

@media (max-width: 640px) {
  .purgatory-timer::before {
    inset: 0.8rem;
    border-radius: 20px;
  }

  .purgatory-timer-halo {
    inset: 14% 10%;
  }
}

.purgatory-timer::after {
  content: "";
  position: absolute;
  inset: 0;
  pointer-events: none;
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.12), transparent 28%),
    radial-gradient(circle at 50% 100%, rgba(255, 138, 99, 0.08), transparent 44%);
}

.purgatory-timer-halo {
  position: absolute;
  inset: 12% 16%;
  border-radius: 999px;
  background: radial-gradient(circle, rgba(255, 107, 214, 0.22), rgba(177, 128, 255, 0.16) 36%, rgba(255, 138, 99, 0.12) 58%, transparent 74%);
  filter: blur(26px);
  animation: ritual-breathe 5.6s ease-in-out infinite;
}

.purgatory-timer-value {
  position: relative;
  z-index: 1;
  font-family: var(--font-mono);
  letter-spacing: -0.06em;
  font-variant-numeric: tabular-nums;
  text-shadow: 0 0 26px rgba(255, 138, 99, 0.24), 0 0 46px rgba(177, 128, 255, 0.12);
}

.evil-purgatory-indulgence {
  border-color: rgba(206, 170, 255, 0.24);
}

.evil-purgatory-ad {
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.05), rgba(255, 255, 255, 0) 24%),
    linear-gradient(180deg, rgba(15, 10, 24, 0.92), rgba(23, 14, 36, 0.94));
}

.evil-purgatory-transgression {
  border-color: rgba(255, 138, 99, 0.24);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.06), rgba(255, 255, 255, 0) 22%),
    linear-gradient(180deg, rgba(27, 16, 24, 0.9), rgba(20, 12, 29, 0.94));
}

.evil-purgatory-logout {
  min-width: 8rem;
}

.evil-purgatory-logout:hover {
  border-color: rgba(255, 138, 99, 0.28);
  box-shadow: 0 16px 28px rgba(2, 1, 8, 0.24), 0 0 22px rgba(255, 138, 99, 0.08), inset 0 1px 0 rgba(255, 255, 255, 0.08);
}
</style>