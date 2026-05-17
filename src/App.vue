<script setup>
import { computed, ref, watch } from 'vue'
import { useAuth } from './composables/useAuth'
import { useBanTimer } from './composables/useBanTimer'
import { useEconomy } from './composables/useEconomy'
import { useSects } from './composables/useSects'
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
import SectSelectionModal from './components/organisms/SectSelectionModal.vue'
import iconUrl from './assets/icons/icon.png'

const auth = useAuth()
const banTimer = useBanTimer()
const economy = useEconomy()
const sects = useSects()

// Tab navigation
const currentTab = ref('altar')

// Sect selection modal state
const showSectModal = ref(false)

// Determine which view to show
const currentView = computed(() => {
  if (!auth.isAuthenticated) return 'login'
  if (banTimer.isBanned) return 'purgatory'
  return currentTab.value
})

// Watch for authentication to trigger sect selection
watch(() => auth.isAuthenticated, async (isAuth) => {
  if (isAuth) {
    // Fetch economy data which includes sect_type
    await economy.fetchEconomy()
    // If no sect selected, show modal
    if (!economy.sectType) {
      showSectModal.value = true
    }
  }
}, { immediate: true })

function onSectChosen(sectType) {
  showSectModal.value = false
}

// Dynamic copyright year and developer email
const currentYear = new Date().getFullYear()
const devEmail = import.meta.env.VITE_DEV_EMAIL || 'contact@example.com'
</script>

<template>
  <div class="app-shell min-h-screen bg-theme-wash flex flex-col">
    <!-- Tab Navigation (only when authenticated and not banned) -->
    <nav v-if="auth.isAuthenticated && !banTimer.isBanned" class="sticky top-0 z-40 border-b surface-divider bg-theme-panel/55 backdrop-blur-[18px] supports-[backdrop-filter]:bg-theme-panel/45">
      <div class="app-frame">
        <div class="relative flex flex-col gap-4 py-4 md:flex-row md:items-center md:justify-between">
          <div class="pointer-events-none absolute inset-x-0 top-0 h-full rounded-[32px] bg-[radial-gradient(circle_at_top,rgba(255,223,147,0.16),transparent_60%)] opacity-80"></div>
          <div class="relative flex min-w-0 items-center gap-3 md:gap-4">
            <div class="flex h-12 w-12 items-center justify-center rounded-full border border-theme-accent/25 bg-white/55 shadow-[0_12px_24px_rgba(213,154,23,0.14)] backdrop-blur-md">
              <img :src="iconUrl" alt="Electric Monk" class="h-7 w-7 drop-shadow-[0_4px_10px_rgba(213,154,23,0.32)]" />
            </div>
            <div class="min-w-0">
              <span class="block truncate text-sm font-semibold text-theme-text md:text-base">The Electric Monk - Prayers As A Service</span>
            </div>
          </div>
          <div class="relative segmented-shell w-full justify-between md:w-auto md:justify-start flex-wrap">
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
      <div aria-hidden="true" class="holy-light-layer"></div>
      <div aria-hidden="true" class="holy-cloud-layer"></div>
      <div aria-hidden="true" class="holy-ripple-layer"></div>
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

    <!-- Sect Selection Modal (forced on first login) -->
    <SectSelectionModal
      :visible="showSectModal"
      @chosen="onSectChosen"
    />
      </div>
    </div>
    
    <!-- Global Footer -->
    <footer class="mt-10 border-t surface-divider bg-theme-panel/40 backdrop-blur-[18px] supports-[backdrop-filter]:bg-theme-panel/30">
      <div class="app-frame py-4 text-center text-xs text-theme-text-muted">
        <p>Copyright {{ currentYear }} Lake Boiler Labs. All rights reserved. Contact: <a :href="'mailto:' + devEmail" class="font-medium text-theme-accent transition-colors duration-200 hover:text-theme-accent-dark hover:underline">{{ devEmail }}</a></p>
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
</style>