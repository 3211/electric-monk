<template>
  <Teleport to="body">
    <Transition name="fade">
      <div v-if="onboarding.isActive" class="aether-modal-overlay">
        <div class="onboarding-modal-container glass-panel glass-panel-strong glass-gloss">

          <!-- Fallback indicator (shown when AI generation fails) -->
          <div v-if="onboarding.usedFallback && onboarding.step !== 'loading'" class="mb-3 text-center">
            <span class="inline-flex items-center gap-1 rounded-full bg-theme-purgatory/10 border border-theme-purgatory/20 px-3 py-1 text-xs text-theme-purgatory-dark">
              ⚠️ AI generation unavailable — using fallback text
            </span>
          </div>

          <!-- ============================================ -->
          <!-- STEP: Loading (fetching AI content) -->
          <!-- ============================================ -->
          <div v-if="onboarding.step === 'loading'" class="aether-processing-state">
            <div class="aether-icon animate-pulse">
              <svg class="w-16 h-16" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M13 10V3L4 14h7v7l9-11h-7z"/>
              </svg>
            </div>
            <h3 class="aether-title text-theme-accent">Awakening the Monk...</h3>
            <p class="aether-description text-theme-text-dim">Preparing your welcome to Holy War Online.</p>
            <div class="aether-loader">
              <div class="aether-loader-bar"></div>
            </div>
          </div>

          <!-- ============================================ -->
          <!-- STEP: Welcome (typewriter AI message) -->
          <!-- ============================================ -->
          <div v-else-if="onboarding.step === 'welcome'" class="text-center">
            <div class="mb-6">
              <div class="submission-logo-shell mb-2 mx-auto">
                <div class="submission-logo-halo"></div>
                <img src="@/assets/icons/icon.png" alt="Holy War Online" class="relative z-10 h-[120px] w-[120px] drop-shadow-[0_10px_24px_rgba(213,154,23,0.18)]" />
              </div>
            </div>
            <h2 class="ritual-heading mb-4 text-3xl font-bold text-theme-accent sm:text-4xl">Holy War Online</h2>
            <div class="onboarding-typewriter-panel glass-panel glass-gloss p-5 my-6 text-left">
              <p class="text-theme-text font-semibold leading-relaxed text-base sm:text-lg">
                {{ onboarding.displayedText }}<span v-if="!onboarding.typewriterFinished" class="typewriter-cursor">▊</span>
              </p>
            </div>
            <button
              @click="onboarding.continueToIdentity()"
              :disabled="!onboarding.typewriterFinished"
              class="btn-primary w-full mt-2"
            >
              <span class="relative z-10 font-medium">
                {{ onboarding.typewriterFinished ? 'Choose Your Sect' : 'The Monk is speaking...' }}
              </span>
            </button>
          </div>

          <!-- ============================================ -->
          <!-- STEP: Identity (username + sect selection) -->
          <!-- ============================================ -->
          <div v-else-if="onboarding.step === 'identity'">
            <!-- Header -->
            <div class="mb-6 text-center">
              <h2 class="ritual-heading mb-2 text-3xl font-bold text-theme-accent">Identify Yourself</h2>
              <p class="text-sm text-theme-text-dim">Choose your name and sect. This decision is permanent.</p>
            </div>

            <!-- Error Message -->
            <div v-if="onboarding.error" class="mb-4 rounded-[20px] border border-theme-purgatory/25 bg-theme-purgatory/10 p-3 text-sm text-theme-purgatory-dark shadow-[0_10px_24px_rgba(168,93,50,0.08)]">
              {{ onboarding.error }}
            </div>

            <!-- PFP + Username -->
            <div class="mb-5">
              <div class="flex justify-center mb-5">
                <div class="pfp-frame">
                  <img
                    src="/pfp/0.png"
                    alt="Profile picture"
                    aria-label="Current profile picture"
                    class="pfp-image"
                  />
                </div>
              </div>
              <div class="mb-4">
                <label for="onboarding-username" class="mb-1.5 block text-sm font-medium text-theme-text-dim">
                  What should the Monk call you?
                </label>
                <input
                  id="onboarding-username"
                  v-model="localUsername"
                  type="text"
                  required
                  :maxlength="MAX_USERNAME_CHARS"
                  :disabled="onboarding.loading"
                  class="form-field px-4 py-3 disabled:cursor-not-allowed disabled:opacity-50"
                  placeholder="e.g., Pilgrim, Seeker, Acolyte..."
                />
                <div v-if="showUsernameCount" class="mt-1 text-right text-xs text-theme-text-muted">
                  {{ localUsername.length }} / {{ MAX_USERNAME_CHARS }}
                </div>
              </div>
            </div>

            <!-- Sect Selection -->
            <div>
              <h3 class="mb-3 text-center text-lg font-semibold text-theme-text">Choose Your Sect</h3>
              <div class="grid gap-3 sm:grid-cols-2">
                <button
                  v-for="sect in sects.sectList"
                  :key="sect.key"
                  @click="localSect = sect.key"
                  :class="[
                    'relative text-left p-4 rounded-[20px] border transition-all duration-[var(--dur-standard)]',
                    localSect === sect.key
                      ? 'border-theme-accent/50 bg-theme-accent/10 shadow-[0_10px_28px_rgba(213,154,23,0.18)] scale-[1.01]'
                      : 'border-theme-border bg-theme-panel/50 hover:border-theme-accent/25 hover:bg-theme-accent/5 hover:scale-[1.005]'
                  ]"
                >
                  <div v-if="localSect === sect.key" class="absolute top-2 right-2 text-theme-accent text-sm font-bold">&#10003;</div>
                  <div class="mb-1 text-2xl leading-none">{{ sect.icon }}</div>
                  <h4 :class="['text-base font-semibold', sect.color]">{{ sect.name }}</h4>
                  <p class="mt-0.5 text-xs text-theme-text-muted leading-relaxed">{{ sect.description }}</p>
                </button>
              </div>
              <p v-if="!localSect" class="mt-2 text-center text-xs text-theme-text-muted italic">
                Select a sect above to continue
              </p>
            </div>

            <!-- Submit Button -->
            <div class="mt-6 flex justify-center">
              <button
                @click="handleIdentitySubmit"
                :disabled="!canSubmitIdentity || onboarding.loading || sects.choosing"
                class="btn-primary px-8 py-3 text-base"
              >
                <span class="relative z-10 font-medium">
                  {{ onboarding.loading || sects.choosing ? 'Swearing Vows...' : 'Swear the Vow' }}
                </span>
              </button>
            </div>
          </div>

          <!-- ============================================ -->
          <!-- STEP: Faction Intro (typewriter AI faction welcome) -->
          <!-- ============================================ -->
          <div v-else-if="onboarding.step === 'faction_intro'" class="text-center">
            <div class="mb-4">
              <div class="text-4xl mb-3">{{ selectedSectIcon }}</div>
              <h2 class="ritual-heading mb-2 text-2xl font-bold text-theme-accent sm:text-3xl">{{ selectedSectName }}</h2>
              <p class="text-sm text-theme-text-dim">Your Electric Monk awaits.</p>
            </div>
            <div class="onboarding-typewriter-panel glass-panel glass-gloss p-5 my-6 text-left">
              <p class="text-theme-text font-semibold leading-relaxed">
                {{ onboarding.displayedText }}<span v-if="!onboarding.typewriterFinished" class="typewriter-cursor">▊</span>
              </p>
            </div>
            <button
              @click="onboarding.continueToPrayerPrompt()"
              :disabled="!onboarding.typewriterFinished"
              class="btn-primary w-full mt-2"
            >
              <span class="relative z-10 font-medium">
                {{ onboarding.typewriterFinished ? 'Offer Your First Prayer' : 'The Monk is speaking...' }}
              </span>
            </button>
          </div>

          <!-- ============================================ -->
          <!-- STEP: Prayer Prompt (typewriter AI suggestion) -->
          <!-- ============================================ -->
          <div v-else-if="onboarding.step === 'prayer_prompt'" class="text-center">
            <div class="mb-4">
              <div class="text-4xl mb-3">🕯️</div>
              <h2 class="ritual-heading mb-2 text-2xl font-bold text-theme-accent sm:text-3xl">Offer Your First Prayer</h2>
              <p class="text-sm text-theme-text-dim">The Monk will dedicate its computational energy to your intention.</p>
            </div>
            <div class="onboarding-typewriter-panel glass-panel glass-gloss p-5 my-6 text-left">
              <p class="text-theme-text font-semibold leading-relaxed">
                {{ onboarding.displayedText }}<span v-if="!onboarding.typewriterFinished" class="typewriter-cursor">▊</span>
              </p>
            </div>
            <button
              @click="onboarding.continueToPrayerInput()"
              :disabled="!onboarding.typewriterFinished"
              class="btn-primary w-full mt-2"
            >
              <span class="relative z-10 font-medium">
                {{ onboarding.typewriterFinished ? 'Write My Prayer' : 'The Monk is speaking...' }}
              </span>
            </button>
          </div>

          <!-- ============================================ -->
          <!-- STEP: Prayer Input (textarea) -->
          <!-- ============================================ -->
          <div v-else-if="onboarding.step === 'prayer_input'">
            <div class="mb-5 text-center">
              <h2 class="ritual-heading mb-2 text-2xl font-bold text-theme-accent sm:text-3xl">Speak Your Prayer</h2>
              <p class="text-sm text-theme-text-dim">What intention would you like the Monk to pray for?</p>
            </div>

            <!-- Error Message -->
            <div v-if="onboarding.error" class="mb-4 rounded-[20px] border border-theme-purgatory/25 bg-theme-purgatory/10 p-3 text-sm text-theme-purgatory-dark shadow-[0_10px_24px_rgba(168,93,50,0.08)]">
              {{ onboarding.error }}
            </div>

            <form @submit.prevent="handlePrayerSubmit">
              <textarea
                v-model="prayerContent"
                :disabled="onboarding.loading"
                rows="5"
                class="form-field min-h-[10rem] resize-none px-4 py-4 disabled:cursor-not-allowed disabled:opacity-50"
                placeholder="Speak your prayer into the aether..."
              ></textarea>
              <div class="mt-2 flex items-center justify-between text-xs">
                <span class="text-theme-text-muted">
                  {{ prayerContent.length }} / {{ maxPrayerChars }} chars
                </span>
              </div>
              <button
                type="submit"
                :disabled="!prayerContent.trim() || prayerContent.length > maxPrayerChars || onboarding.loading"
                class="btn-primary w-full mt-4"
              >
                <span class="relative z-10 font-medium">
                  {{ onboarding.loading ? 'Submitting...' : 'Send Prayer' }}
                </span>
              </button>
            </form>
          </div>

          <!-- ============================================ -->
          <!-- STEP: Processing (lightning bolt animation) -->
          <!-- ============================================ -->
          <div v-else-if="onboarding.step === 'processing'" class="aether-processing-state">
            <div class="aether-icon animate-pulse">
              <svg class="w-16 h-16" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M13 10V3L4 14h7v7l9-11h-7z"/>
              </svg>
            </div>
            <h3 class="aether-title text-theme-accent">Sent to the Aether...</h3>
            <p class="aether-description text-theme-text-dim">The Electric Monk is considering your prayer.</p>
            <div class="aether-loader">
              <div class="aether-loader-bar"></div>
            </div>
          </div>

          <!-- ============================================ -->
          <!-- STEP: Approved (typewriter response + continue) -->
          <!-- ============================================ -->
          <div v-else-if="onboarding.step === 'approved'" class="text-center">
            <div class="aether-judgment-icon approved">
              <svg class="w-12 h-12" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/>
              </svg>
            </div>
            <h3 class="aether-title font-bold text-theme-accent">Blessing Granted</h3>
            <div class="aether-karma-display">
              <span class="text-2xl font-bold text-theme-accent">+1</span>
              <span class="text-sm text-theme-text-muted ml-1">Karma</span>
            </div>
            <div class="aether-response-content glass-panel glass-gloss p-4 my-4">
              <p class="text-theme-text font-semibold leading-relaxed">
                {{ onboarding.displayedText }}<span v-if="!onboarding.typewriterFinished" class="typewriter-cursor">▊</span>
              </p>
            </div>
            <button
              @click="handleComplete"
              :disabled="!onboarding.typewriterFinished"
              class="btn-primary w-full mt-2"
            >
              <span class="relative z-10 font-medium">
                {{ onboarding.typewriterFinished ? 'Enter Holy War Online' : 'The Monk is speaking...' }}
              </span>
            </button>
          </div>

          <!-- ============================================ -->
          <!-- STEP: Rejected (evil theme, retry) -->
          <!-- ============================================ -->
          <div v-else-if="onboarding.step === 'rejected'" class="text-center">
            <div class="aether-judgment-icon rejected">
              <svg class="w-12 h-12" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"/>
              </svg>
            </div>
            <h3 class="aether-title font-bold text-theme-purgatory">Prayer Rejected</h3>

            <div class="glass-panel glass-gloss p-4 my-4 border-2 border-theme-purgatory/30">
              <p class="text-theme-text font-semibold leading-relaxed mb-3">
                Let's not get off on the wrong foot. Please make your first prayer something positive.
              </p>
              <div v-if="onboarding.rejectionReason" class="text-sm text-theme-purgatory-dark italic">
                Reason: {{ onboarding.rejectionReason }}
              </div>
            </div>

            <div v-if="onboarding.prayerResponse" class="glass-panel glass-gloss p-4 my-4">
              <p class="text-theme-text-dim text-sm leading-relaxed">
                {{ onboarding.prayerResponse }}
              </p>
            </div>

            <button
              @click="onboarding.retryPrayer()"
              class="btn-primary w-full mt-2"
            >
              <span class="relative z-10 font-medium">
                Try Again
              </span>
            </button>
          </div>

        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<script setup>
import { ref, computed, watch, inject } from 'vue'
import { useOnboarding } from '@/composables/useOnboarding'
import { usePrayers } from '@/composables/usePrayers'
import { useSects } from '@/composables/useSects'
import { useEconomy } from '@/composables/useEconomy'

const MAX_USERNAME_CHARS = 30
const COUNT_VISIBLE_THRESHOLD = 0.9
const maxPrayerChars = parseInt(import.meta.env.VITE_MAX_PRAYER_CHARS || '1500', 10)

const onboarding = useOnboarding()
const sects = useSects()
const prayers = usePrayers()
const economy = useEconomy()

// Inject forceEvilTheme from App.vue for rejected prayer display
const forceEvilTheme = inject('forceEvilTheme', ref(false))

const localUsername = ref('')
const localSect = ref(null)
const prayerContent = ref('')

// Computed properties for the faction intro step
const selectedSectName = computed(() => {
  if (!localSect.value) return ''
  const sect = sects.sectList.find(s => s.key === localSect.value)
  return sect ? sect.name : ''
})

const selectedSectIcon = computed(() => {
  if (!localSect.value) return '⚔️'
  const sect = sects.sectList.find(s => s.key === localSect.value)
  return sect ? sect.icon : '⚔️'
})

const showUsernameCount = computed(() => {
  return localUsername.value.length >= MAX_USERNAME_CHARS * COUNT_VISIBLE_THRESHOLD
})

const canSubmitIdentity = computed(() => {
  return localUsername.value.trim().length >= 2 && localSect.value
})

// Toggle evil theme based on onboarding step
watch(() => onboarding.step, (newStep) => {
  // Activate evil theme when first prayer is rejected
  if (newStep === 'rejected') {
    forceEvilTheme.value = true
  } else if (newStep === 'approved' || newStep === 'idle') {
    // Deactivate evil theme when approved or onboarding completes
    forceEvilTheme.value = false
  }
  // Reset form when step changes
  if (newStep === 'identity') {
    if (!localUsername.value) localUsername.value = ''
    if (!localSect.value) localSect.value = null
  }
  if (newStep === 'prayer_input') {
    prayerContent.value = ''
  }
})

async function handleIdentitySubmit() {
  if (!canSubmitIdentity.value) return
  try {
    await onboarding.submitIdentity({
      username: localUsername.value.trim(),
      sectType: localSect.value,
    })
  } catch {
    // Error is captured in onboarding.error
  }
}

async function handlePrayerSubmit() {
  if (!prayerContent.value.trim()) return
  try {
    await onboarding.submitFirstPrayer(prayerContent.value.trim())
  } catch {
    // Error is captured in onboarding.error
  }
}

async function handleComplete() {
  try {
    await onboarding.completeOnboarding()
    // Refresh all app state after onboarding
    await prayers.fetchProfile()
    await prayers.fetchPrayers()
    await economy.fetchEconomy()
  } catch {
    // Non-fatal — onboarding already marked complete
  }
}
</script>

<style scoped>
.aether-modal-overlay {
  position: fixed;
  inset: 0;
  z-index: 9600;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 1rem;
  background:
    radial-gradient(circle at 50% 22%, rgba(255, 223, 147, 0.2), transparent 34%),
    linear-gradient(180deg, rgba(48, 38, 21, 0.62), rgba(48, 38, 21, 0.72));
  backdrop-filter: blur(12px);
  animation: overlay-fade var(--dur-enter) var(--ease-standard);
}

.onboarding-modal-container {
  max-width: 32rem;
  width: 100%;
  padding: 1.5rem;
  animation: modal-rise var(--dur-enter) var(--ease-silk-settle);
  max-height: 90vh;
  overflow-y: auto;
}

@media (min-width: 640px) {
  .onboarding-modal-container {
    padding: 2rem;
  }
}

.aether-processing-state {
  text-align: center;
  padding: 2rem 0;
}

.aether-icon {
  margin-bottom: 1rem;
  color: var(--theme-accent);
}

.aether-title {
  font-family: var(--font-display);
  font-size: 1.5rem;
  margin-bottom: 0.5rem;
}

.aether-description {
  margin-bottom: 1.5rem;
}

.aether-loader {
  width: 100%;
  height: 4px;
  background: var(--theme-border);
  border-radius: 999px;
  overflow: hidden;
  margin-top: 1rem;
}

.aether-loader-bar {
  height: 100%;
  width: 30%;
  background: linear-gradient(90deg, var(--theme-accent), var(--theme-accent-light));
  border-radius: 999px;
  animation: aether-slide 1.5s ease-in-out infinite;
}

@keyframes aether-slide {
  0% { transform: translateX(-100%); }
  100% { transform: translateX(400%); }
}

.aether-judgment-icon {
  width: 4rem;
  height: 4rem;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  margin: 0 auto 1rem;
}

.aether-judgment-icon.approved {
  background: rgba(34, 197, 94, 0.15);
  color: #22c55e;
  box-shadow: 0 0 24px rgba(34, 197, 94, 0.2);
}

.aether-judgment-icon.rejected {
  background: rgba(168, 93, 50, 0.15);
  color: var(--theme-purgatory);
  box-shadow: 0 0 24px rgba(168, 93, 50, 0.2);
}

.aether-karma-display {
  margin-bottom: 0.5rem;
}

.aether-response-content {
  border: 1px solid var(--theme-border);
  border-radius: 20px;
}

.onboarding-typewriter-panel {
  border: 1px solid var(--theme-border);
  border-radius: 20px;
}

.typewriter-cursor {
  animation: blink 0.7s infinite;
  font-weight: 100;
}

@keyframes blink {
  0%, 100% { opacity: 1; }
  50% { opacity: 0; }
}

@keyframes overlay-fade {
  from { opacity: 0; }
  to { opacity: 1; }
}

@keyframes modal-rise {
  from {
    opacity: 0;
    transform: translateY(20px) scale(0.98);
  }
  to {
    opacity: 1;
    transform: translateY(0) scale(1);
  }
}

.pfp-frame {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 5.75rem;
  height: 5.75rem;
  padding: 0.35rem;
  border-radius: 999px;
  border: 1px solid rgba(213, 154, 23, 0.24);
  background: linear-gradient(180deg, rgba(255, 253, 246, 0.92), rgba(248, 238, 214, 0.86));
  box-shadow: 0 18px 32px rgba(48, 38, 21, 0.1), 0 0 24px rgba(240, 182, 59, 0.08), inset 0 1px 0 rgba(255, 255, 255, 0.86);
}

.pfp-frame::before {
  content: "";
  position: absolute;
  inset: -0.6rem;
  border-radius: 999px;
  background: radial-gradient(circle, rgba(255, 223, 147, 0.24) 0%, rgba(255, 223, 147, 0.08) 44%, transparent 72%);
  filter: blur(10px);
  z-index: 0;
}

.pfp-image {
  position: relative;
  z-index: 1;
  width: 100%;
  height: 100%;
  object-fit: cover;
  border-radius: 999px;
  border: 1px solid rgba(255, 255, 255, 0.82);
  background: rgba(255, 252, 246, 0.9);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.9), 0 10px 20px rgba(48, 38, 21, 0.08);
}

.submission-logo-shell {
  position: relative;
  display: inline-flex;
  align-items: center;
  justify-content: center;
}

.submission-logo-halo {
  position: absolute;
  inset: -12px;
  border-radius: 50%;
  background: radial-gradient(circle, rgba(213, 154, 23, 0.2), transparent 70%);
  animation: ritual-breathe 3s ease-in-out infinite;
}

@keyframes ritual-breathe {
  0%, 100% { transform: scale(1); opacity: 0.6; }
  50% { transform: scale(1.08); opacity: 0.9; }
}

/* Fade transition for the modal */
.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.3s ease;
}
.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}
</style>