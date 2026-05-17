<script setup>
import { computed, provide, ref, watch } from 'vue'
import { useAuth } from './composables/useAuth'
import { useBanTimer } from './composables/useBanTimer'
import { useEconomy } from './composables/useEconomy'
import { usePrayers } from './composables/usePrayers'
import { useOnboarding } from './composables/useOnboarding'
import ShieldTimer from './components/molecules/ShieldTimer.vue'
import LoginView from './views/LoginView.vue'
import AltarView from './views/AltarView.vue'
import PurgatoryView from './views/PurgatoryView.vue'
import AkashicRecordsView from './views/AkashicRecordsView.vue'
import KarmaShopView from './views/KarmaShopView.vue'
import VaticanView from './views/VaticanView.vue'
import LeaderboardView from './views/LeaderboardView.vue'
import ScriptoriumView from './views/ScriptoriumView.vue'
import SynodHallView from './views/SynodHallView.vue'
import OnboardingWizard from './components/organisms/OnboardingWizard.vue'
import UsernameChangeModal from './components/organisms/UsernameChangeModal.vue'
const auth = useAuth()
const banTimer = useBanTimer()
const economy = useEconomy()
const prayers = usePrayers()
const onboarding = useOnboarding()

// Tab navigation
const currentTab = ref('altar')

// Force evil theme — injected by child views for conditional dark mode (Scriptorium, Records, Vatican)
const forceEvilTheme = ref(false)
provide('forceEvilTheme', forceEvilTheme)

// Username change modal state
const showUsernameChangeModal = ref(false)

// Determine which view to show
const currentView = computed(() => {
  if (!auth.isAuthenticated) return 'login'
  if (banTimer.isBanned) return 'purgatory'
  return currentTab.value
})

// Views that own a light/dark sub-toggle — they manage forceEvilTheme themselves.
// All OTHER views force light mode on entry, preventing dark-mode persistence bleed.
const toggleableViews = new Set(['scriptorium', 'akashic', 'vatican', 'synod'])
const evilViews = new Set(['purgatory'])
const isEvilView = computed(() => evilViews.has(currentView.value) || forceEvilTheme.value)

// Reset dark theme when navigating to a non-toggleable view (Altar, Shop, Synod, Reliquary, Rankings)
watch(currentTab, (tab) => {
  if (!toggleableViews.has(tab)) {
    forceEvilTheme.value = false
  }
})

// Watch for authentication to trigger onboarding
watch(() => auth.isAuthenticated, async (isAuth) => {
  if (isAuth) {
    // Fetch economy and profile data
    await economy.fetchEconomy()
    await prayers.fetchProfile()

    // Check onboarding status — new users (or users missing identity) go through the wizard
    if (!prayers.onboardingComplete || !prayers.username) {
      onboarding.startOnboarding()
    }
  }
}, { immediate: true })

// Handle username change
function onUsernameChanged(newUsername, karmaRemaining) {
  prayers.fetchProfile()
  economy.fetchEconomy()
}

// Dynamic copyright year and developer email
const currentYear = new Date().getFullYear()
const devEmail = import.meta.env.VITE_DEV_EMAIL || 'contact@example.com'
</script>

<template>
  <div :class="['app-shell min-h-screen flex flex-col', { 'app-shell--evil': isEvilView, 'app-shell--holy': !isEvilView }]">
    <!-- Tab Navigation (only when authenticated and not banned) -->
    <nav v-if="auth.isAuthenticated && !banTimer.isBanned" class="global-nav sticky top-0 z-40 border-b backdrop-blur-[18px]">
      <div class="app-frame">
        <div class="relative py-3 sm:py-4">
          <div :class="['global-nav-veil', isEvilView ? 'global-nav-veil--evil' : 'global-nav-veil--holy']"></div>
          <div class="global-nav-row relative flex flex-wrap items-center gap-2 sm:gap-3">
            <!-- Primary tabs cluster (flex-grows to consume slack) -->
            <div class="global-nav-shell segmented-shell flex-1 min-w-0 flex flex-wrap items-center justify-start gap-1">
              <button
                @click="currentTab = 'altar'"
                :class="currentTab === 'altar' ? 'nav-tab-active' : 'nav-tab-inactive'"
              >
                &#x269C; Altar
              </button>
              <button
                @click="currentTab = 'scriptorium'"
                :class="currentTab === 'scriptorium' ? 'nav-tab-active' : 'nav-tab-inactive'"
              >
                &#x1F4D1; Scriptorium
              </button>
              <button
                @click="currentTab = 'akashic'"
                :class="currentTab === 'akashic' ? 'nav-tab-active' : 'nav-tab-inactive'"
              >
                &#x1F4DC; Records
              </button>
              <button
                @click="currentTab = 'shop'"
                :class="currentTab === 'shop' ? 'nav-tab-active' : 'nav-tab-inactive'"
              >
                &#x1F6D2; Shop
              </button>
              <button
                @click="currentTab = 'vatican'"
                :class="currentTab === 'vatican' ? 'nav-tab-active' : 'nav-tab-inactive'"
              >
                &#x1F3F0; Vatican
              </button>
              <button
                @click="currentTab = 'synod'"
                :class="currentTab === 'synod' ? 'nav-tab-active' : 'nav-tab-inactive'"
              >
                &#x2694; Synod
              </button>
              <button
                @click="currentTab = 'rankings'"
                :class="currentTab === 'rankings' ? 'nav-tab-active' : 'nav-tab-inactive'"
              >
                &#x1F3DB; Rankings
              </button>
            </div>

            <!-- Shield indicator (global, always visible when shield active) -->
            <ShieldTimer v-if="economy.shieldActive" :shield-until="economy.divineShieldUntil" />

            <!-- Account cluster: change-username (icon) + logout (pill, matches nav buttons) -->
            <div class="global-nav-account segmented-shell flex items-center gap-1 flex-none ml-auto">
              <button
                @click="showUsernameChangeModal = true"
                class="nav-account-btn"
                title="Change Username (costs 1000 Karma)"
                aria-label="Change Username"
              >
                <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
                </svg>
              </button>
              <button
                @click="auth.signOut()"
                class="nav-tab-inactive"
                title="Logout"
              >
                Logout
              </button>
            </div>
          </div>
        </div>
      </div>
    </nav>

    <div class="app-content-region flex-1">
      <template v-if="!isEvilView">
        <div aria-hidden="true" class="holy-light-layer"></div>
        <div aria-hidden="true" class="holy-cloud-layer"></div>
        <div aria-hidden="true" class="holy-ripple-layer"></div>
      </template>
      <template v-else>
        <div aria-hidden="true" class="evil-layout-layer evil-layout-layer--mist"></div>
        <div aria-hidden="true" class="evil-layout-layer evil-layout-layer--veil"></div>
        <div aria-hidden="true" class="evil-layout-layer evil-layout-layer--glow"></div>
      </template>
      <div class="app-content-inner">
        <LoginView v-if="currentView === 'login'" />
        <PurgatoryView v-else-if="currentView === 'purgatory'" />
        <AltarView v-else-if="currentView === 'altar'" />
        <ScriptoriumView v-else-if="currentView === 'scriptorium'" />
        <AkashicRecordsView v-else-if="currentView === 'akashic'" />
        <KarmaShopView v-else-if="currentView === 'shop'" />
        <VaticanView v-else-if="currentView === 'vatican'" />
        <SynodHallView v-else-if="currentView === 'synod'" />
        <LeaderboardView v-else-if="currentView === 'rankings'" />

        <!-- Onboarding Wizard (new user flow) -->
        <OnboardingWizard />

        <!-- Username Change Modal (accessible from settings) -->
        <UsernameChangeModal
          v-model="showUsernameChangeModal"
          :current-username="prayers.username"
          :karma-balance="prayers.karma"
          @changed="onUsernameChanged"
        />
      </div>
    </div>

    <!-- Global Footer -->
    <footer class="global-footer mt-10 border-t backdrop-blur-[18px]">
      <div class="app-frame py-4 text-center text-xs text-theme-text-muted">
        <p>Copyright {{ currentYear }} Lake Boiler Labs. All rights reserved. Contact: <a :href="'mailto:' + devEmail" class="global-footer-link font-medium transition-colors duration-200 hover:underline">{{ devEmail }}</a></p>
      </div>
    </footer>
  </div>
</template>

<style scoped>
.nav-tab-active,
.nav-tab-inactive {
  @apply pill-tab;
  flex: 0 0 auto;
  min-height: 2.5rem;
  padding: 0.5rem 0.85rem;
  font-size: 0.85rem;
}

.nav-tab-active {
  @apply pill-tab-active;
}

.nav-tab-inactive {
  @apply pill-tab-inactive;
}

.nav-account-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 2.5rem;
  height: 2.5rem;
  border-radius: 999px;
  border: 1px solid transparent;
  color: var(--theme-text-muted);
  background: rgba(255, 253, 248, 0.45);
  backdrop-filter: blur(10px);
  transition: all var(--dur-standard) var(--ease-ritual-lift);
  flex: 0 0 auto;
}

.nav-account-btn:hover {
  color: var(--theme-text);
  border-color: rgba(213, 154, 23, 0.18);
  background: rgba(255, 251, 243, 0.72);
  transform: translateY(-1px);
}

.app-shell--evil .nav-account-btn {
  color: #a9b6c4;
  border-color: rgba(137, 108, 178, 0.18);
  background: rgba(255, 255, 255, 0.04);
}

.app-shell--evil .nav-account-btn:hover {
  color: #d5ffe0;
  border-color: rgba(126, 255, 161, 0.18);
  background: rgba(126, 255, 161, 0.08);
}

.global-nav-row {
  align-items: flex-start;
}

.global-nav-shell {
  flex: 1 1 0%;
  min-width: 0;
}

.global-nav-account {
  padding: 0.25rem;
  flex: 0 0 auto;
}

@media (max-width: 640px) {
  .global-nav-row {
    gap: 0.6rem;
  }

  .global-nav-shell {
    width: 100%;
    justify-content: center;
  }

  .global-nav-account {
    margin-left: auto;
  }

  .nav-tab-active,
  .nav-tab-inactive {
    padding: 0.45rem 0.7rem;
    font-size: 0.78rem;
    min-height: 2.25rem;
  }

  .nav-account-btn {
    width: 2.25rem;
    height: 2.25rem;
  }
}
.app-shell {
  transition:
    background 420ms var(--ease-ritual-lift),
    color 420ms var(--ease-ritual-lift),
    box-shadow 420ms var(--ease-ritual-lift);
}

.app-shell--holy {
  background: var(--theme-bg-wash);
}

.app-shell--evil {
  background:
    radial-gradient(circle at 50% -12%, rgba(177, 128, 255, 0.18) 0%, rgba(177, 128, 255, 0.06) 24%, transparent 56%),
    radial-gradient(circle at 14% 18%, rgba(255, 107, 214, 0.08) 0%, transparent 28%),
    radial-gradient(circle at 88% 14%, rgba(126, 255, 161, 0.08) 0%, transparent 26%),
    linear-gradient(180deg, #08050d 0%, #0d0915 48%, #06030a 100%);
}

.global-nav,
.global-footer,
.global-nav-shell,
.global-nav-account,
.global-footer-link,
.nav-tab-active,
.nav-tab-inactive,
.nav-account-btn {
  transition:
    background 420ms var(--ease-ritual-lift),
    border-color 420ms var(--ease-ritual-lift),
    color 420ms var(--ease-ritual-lift),
    box-shadow 420ms var(--ease-ritual-lift),
    opacity 420ms var(--ease-ritual-lift),
    filter 420ms var(--ease-ritual-lift),
    transform 420ms var(--ease-ritual-lift);
}

.global-nav,
.global-footer {
  position: relative;
  overflow: hidden;
}

.global-nav::after,
.global-footer::after {
  content: "";
  position: absolute;
  inset: 0;
  pointer-events: none;
  opacity: 0;
  transition: opacity 420ms var(--ease-ritual-lift);
}

.app-shell--holy .global-nav,
.app-shell--holy .global-footer {
  border-color: rgba(139, 125, 91, 0.16);
  background: rgba(255, 250, 241, 0.58);
  box-shadow: 0 18px 36px rgba(48, 38, 21, 0.06), inset 0 1px 0 rgba(255, 255, 255, 0.58);
}

.app-shell--holy .global-nav::after,
.app-shell--holy .global-footer::after {
  opacity: 1;
  background: linear-gradient(180deg, rgba(255, 255, 255, 0.2), transparent 22%, transparent 78%, rgba(213, 154, 23, 0.06));
}

.app-shell--evil .global-nav,
.app-shell--evil .global-footer {
  border-color: rgba(137, 108, 178, 0.36);
  background: linear-gradient(180deg, rgba(13, 10, 20, 0.92), rgba(17, 12, 28, 0.88));
  box-shadow:
    0 22px 52px rgba(1, 1, 6, 0.42),
    0 0 0 1px rgba(177, 128, 255, 0.08),
    inset 0 1px 0 rgba(255, 255, 255, 0.05);
}

.app-shell--evil .global-nav::after,
.app-shell--evil .global-footer::after {
  opacity: 1;
  background:
    linear-gradient(180deg, rgba(206, 170, 255, 0.16), transparent 18%, transparent 80%, rgba(126, 255, 161, 0.08)),
    radial-gradient(circle at 50% 0%, rgba(177, 128, 255, 0.18), transparent 52%);
}

.global-nav-veil {
  pointer-events: none;
  position: absolute;
  inset: 0;
  border-radius: 32px;
}

.global-nav-veil--holy {
  background: radial-gradient(circle at top, rgba(255, 223, 147, 0.16), transparent 60%);
  opacity: 0.8;
}

.global-nav-veil--evil {
  background:
    radial-gradient(circle at 18% 0%, rgba(177, 128, 255, 0.22), transparent 30%),
    radial-gradient(circle at 82% 0%, rgba(126, 255, 161, 0.12), transparent 24%),
    linear-gradient(90deg, transparent, rgba(255, 255, 255, 0.04), transparent);
  opacity: 0.95;
}

.global-nav-shell,
.global-nav-account {
  position: relative;
}

.global-footer-link {
  color: var(--theme-accent);
}

.app-shell--evil .global-nav-shell,
.app-shell--evil .global-nav-account {
  border-color: rgba(137, 108, 178, 0.34);
  background: linear-gradient(180deg, rgba(22, 17, 31, 0.88), rgba(10, 8, 15, 0.84));
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.06),
    0 16px 34px rgba(0, 0, 0, 0.28),
    0 0 0 1px rgba(206, 170, 255, 0.05);
}

.app-shell--evil .nav-tab-active {
  color: #f2f5f7;
  border-color: rgba(126, 255, 161, 0.24);
  background:
    linear-gradient(180deg, rgba(233, 241, 247, 0.16), rgba(233, 241, 247, 0.06)),
    linear-gradient(180deg, rgba(38, 40, 48, 0.94), rgba(21, 24, 31, 0.94));
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.18),
    0 14px 28px rgba(0, 0, 0, 0.32),
    0 0 22px rgba(126, 255, 161, 0.08);
}

.app-shell--evil .nav-tab-inactive {
  color: #a9b6c4;
  border-color: rgba(137, 108, 178, 0.18);
  background: rgba(255, 255, 255, 0.04);
  backdrop-filter: blur(10px);
}

.app-shell--evil .nav-tab-inactive:hover {
  color: #d5ffe0;
  border-color: rgba(126, 255, 161, 0.18);
  background: rgba(126, 255, 161, 0.08);
  transform: translateY(-1px);
}

.app-shell--evil .global-footer,
.app-shell--evil .global-footer .app-frame {
  color: #a9b6c4;
}

.app-shell--evil .global-footer-link {
  color: #eef3f7;
}

.app-shell--evil .global-footer-link:hover {
  color: #8effb1;
}

.app-shell--evil .global-nav :is(.chip),
.app-shell--evil .global-footer :is(.chip) {
  color: #d8fce2;
  border-color: rgba(126, 255, 161, 0.22);
  background: rgba(126, 255, 161, 0.08);
}

.evil-layout-layer {
  position: absolute;
  inset: 0;
  pointer-events: none;
  z-index: 0;
}

.evil-layout-layer--mist {
  background:
    radial-gradient(circle at 50% 4%, rgba(177, 128, 255, 0.14), transparent 28%),
    radial-gradient(circle at 18% 24%, rgba(255, 107, 214, 0.09), transparent 22%),
    radial-gradient(circle at 82% 18%, rgba(126, 255, 161, 0.08), transparent 18%);
  filter: blur(34px);
  opacity: 0.88;
  animation: evil-layout-drift 26s ease-in-out infinite alternate;
}

.evil-layout-layer--veil {
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.024), transparent 12%, transparent 84%, rgba(255, 255, 255, 0.02)),
    radial-gradient(circle at 50% 108%, rgba(255, 138, 99, 0.08), transparent 28%);
  opacity: 0.76;
}

.evil-layout-layer--glow {
  background:
    radial-gradient(circle at 50% 0%, rgba(206, 170, 255, 0.1), transparent 34%),
    radial-gradient(circle at 50% 82%, rgba(126, 255, 161, 0.06), transparent 24%);
  opacity: 0.82;
  animation: evil-layout-pulse 14s ease-in-out infinite;
}

@keyframes evil-layout-drift {
  0% {
    transform: translate3d(-1.5%, -1%, 0) scale(1.02);
  }
  50% {
    transform: translate3d(1.2%, 1.4%, 0) scale(1.08);
  }
  100% {
    transform: translate3d(2.2%, 2%, 0) scale(1.1);
  }
}

@keyframes evil-layout-pulse {
  0%,
  100% {
    opacity: 0.72;
    transform: scale(1);
  }
  50% {
    opacity: 0.94;
    transform: scale(1.04);
  }
}
</style>
