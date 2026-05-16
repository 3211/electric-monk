<script setup>
import { computed, ref } from 'vue'
import { useAuth } from './composables/useAuth'
import { useBanTimer } from './composables/useBanTimer'
import LoginView from './views/LoginView.vue'
import AltarView from './views/AltarView.vue'
import PurgatoryView from './views/PurgatoryView.vue'
import AkashicRecordsView from './views/AkashicRecordsView.vue'
import iconUrl from './assets/icons/icon.png'

const auth = useAuth()
const banTimer = useBanTimer()

// Tab navigation between Altar and Akashic Records
const currentTab = ref('altar')

// Determine which view to show
// With reactive() wrapping, refs are auto-unwrapped — no .value needed
const currentView = computed(() => {
  if (!auth.isAuthenticated) return 'login'
  if (banTimer.isBanned) return 'purgatory'
  return currentTab.value // 'altar' or 'akashic'
})

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
          <div class="relative segmented-shell w-full justify-between md:w-auto md:justify-start">
            <button
              @click="currentTab = 'altar'"
              :class="currentTab === 'altar' ? 'nav-tab-active' : 'nav-tab-inactive'"
            >
              ⚜️ Altar
            </button>
            <button
              @click="currentTab = 'akashic'"
              :class="currentTab === 'akashic' ? 'nav-tab-active' : 'nav-tab-inactive'"
            >
              📜 Akashic Records
            </button>
          </div>
        </div>
      </div>
    </nav>

    <div class="app-content-region flex-1">
      <div aria-hidden="true" class="holy-light-layer"></div>
      <div aria-hidden="true" class="holy-ripple-layer"></div>
      <div class="app-content-inner">
        <LoginView v-if="currentView === 'login'" />
        <PurgatoryView v-else-if="currentView === 'purgatory'" />
        <AltarView v-else-if="currentView === 'altar'" />
        <AkashicRecordsView v-else-if="currentView === 'akashic'" />
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