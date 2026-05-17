<script setup>
import { computed, provide, ref, watch } from 'vue'
import { useAuth } from './composables/useAuth'
import { useBanTimer } from './composables/useBanTimer'
import { useEconomy } from './composables/useEconomy'
import { usePrayers } from './composables/usePrayers'
import { useOnboarding } from './composables/useOnboarding'
import LoginView from './views/LoginView.vue'
import AltarView from './views/AltarView.vue'
import PurgatoryView from './views/PurgatoryView.vue'
import AkashicRecordsView from './views/AkashicRecordsView.vue'
import KarmaShopView from './views/KarmaShopView.vue'
import VaticanView from './views/VaticanView.vue'
import CatacombsView from './views/CatacombsView.vue'
import LeaderboardView from './views/LeaderboardView.vue'
import ScriptoriumView from './views/ScriptoriumView.vue'
import SynodHallView from './views/SynodHallView.vue'
import ReliquaryView from './views/ReliquaryView.vue'
import OnboardingWizard from './components/organisms/OnboardingWizard.vue'
import UsernameChangeModal from './components/organisms/UsernameChangeModal.vue'
import iconUrl from './assets/icons/icon.png'

const auth = useAuth()
const banTimer = useBanTimer()
const economy = useEconomy()
const prayers = usePrayers()
const onboarding = useOnboarding()

// Tab navigation
const currentTab = ref('altar')

// Force evil theme — injected by child views for conditional dark mode
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

const evilViews = new Set(['catacombs', 'purgatory'])
const isEvilView = computed(() => evilViews.has(currentView.value) || forceEvilTheme.value)

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
        <div class="relative flex flex-col gap-4 py-4 md:flex-row md:items-center md:justify-between">
          <div :class="['global-nav-veil', isEvilView ? 'global-nav-veil--evil' : 'global-nav-veil--holy']"></div>
          <div class="relative flex min-w-0 items-center gap-3 md:gap-4">
            <div class="app-brand-mark flex h-12 w-12 items-center justify-center rounded-full border backdrop-blur-md">
              <img :src="iconUrl" alt="Electric Monk" class="h-7 w-7 app-brand-icon" />
            </div>
            <div class="min-w-0">
              <span class="app-brand-title block truncate text-sm font-semibold md:text-base">The Electric Monk - Prayers As A Service</span>
            </div>
          </div>
          <div class="relative global-nav-shell segmented-shell w-full justify-between md:w-auto md:justify-start flex-wrap">
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
              &#x1F4DC; Akashic
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
              @click="currentTab = 'reliquary'"
              :class="currentTab === 'reliquary' ? 'nav-tab-active' : 'nav-tab-inactive'"
            >
              &#x1F3F8; Reliquary
            </button>
            <button
              @click="currentTab = 'catacombs'"
              :class="currentTab === 'catacombs' ? 'nav-tab-active' : 'nav-tab-inactive'"
            >
              &#x271D; Catacombs
            </button>
            <button
              @click="currentTab = 'rankings'"
              :class="currentTab === 'rankings' ? 'nav-tab-active' : 'nav-tab-inactive'"
            >
              &#x1F3DB; Rankings
            </button>
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
        <ReliquaryView v-else-if="currentView === 'reliquary'" />
        <CatacombsView v-else-if="currentView === 'catacombs'" />
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
  @apply pill-tab flex-1 md:flex-none;
}

.nav-tab-active {
  @apply pill-tab-active;
}

.nav-tab-inactive {
  @apply pill-tab-inactive;
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
.app-brand-mark,
.app-brand-icon,
.app-brand-title,
.global-footer-link,
.nav-tab-active,
.nav-tab-inactive {
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

.app-brand-mark {
  border-color: rgba(213, 154, 23, 0.25);
  background: rgba(255, 255, 255, 0.55);
  box-shadow: 0 12px 24px rgba(213, 154, 23, 0.14);
}

.app-brand-icon {
  filter: drop-shadow(0 4px 10px rgba(213, 154, 23, 0.32));
}

.app-brand-title {
  color: var(--theme-text);
}

.global-nav-shell {
  position: relative;
}

.global-footer-link {
  color: var(--theme-accent);
}

.app-shell--evil .app-brand-mark {
  border-color: rgba(206, 170, 255, 0.26);
  background: linear-gradient(180deg, rgba(44, 35, 60, 0.82), rgba(16, 12, 24, 0.92));
  box-shadow:
    0 16px 32px rgba(3, 2, 10, 0.34),
    0 0 22px rgba(177, 128, 255, 0.14),
    inset 0 1px 0 rgba(255, 255, 255, 0.08);
}

.app-shell--evil .app-brand-icon {
  filter: grayscale(0.18) brightness(1.18) contrast(1.08) drop-shadow(0 0 12px rgba(206, 170, 255, 0.24));
}

.app-shell--evil .app-brand-title {
  color: #eef3f7;
  text-shadow: 0 0 18px rgba(206, 170, 255, 0.16);
}

.app-shell--evil .global-nav-shell {
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
