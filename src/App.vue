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
  <div class="min-h-screen bg-theme-wash flex flex-col">
    <!-- Tab Navigation (only when authenticated and not banned) -->
    <nav v-if="auth.isAuthenticated && !banTimer.isBanned" class="border-b border-theme-border bg-theme-panel/50 backdrop-blur-sm">
      <div class="max-w-4xl mx-auto px-4 flex items-center justify-between">
        <div class="flex items-center gap-2">
          <img :src="iconUrl" alt="Electric Monk" class="w-6 h-6" />
          <span class="text-sm font-semibold text-theme-text">The Electric Monk - Prayers As A Service</span>
        </div>
        <div class="flex items-center gap-1">
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
    </nav>

    <div class="flex-1">
      <LoginView v-if="currentView === 'login'" />
      <PurgatoryView v-else-if="currentView === 'purgatory'" />
      <AltarView v-else-if="currentView === 'altar'" />
      <AkashicRecordsView v-else-if="currentView === 'akashic'" />
    </div>
    
    <!-- Global Footer -->
    <footer class="border-t border-theme-border bg-theme-panel/30 backdrop-blur-sm">
      <div class="max-w-4xl mx-auto px-4 py-3 text-center text-xs text-theme-text-muted">
        <p>Copyright {{ currentYear }} Lake Boiler Labs. All rights reserved. Contact: <a :href="'mailto:' + devEmail" class="text-theme-accent hover:underline">{{ devEmail }}</a></p>
      </div>
    </footer>
  </div>
</template>

<style scoped>
.nav-tab-active {
  @apply px-4 py-3 text-sm font-medium border-b-2 border-theme-accent text-theme-accent transition-colors;
}

.nav-tab-inactive {
  @apply px-4 py-3 text-sm font-medium border-b-2 border-transparent text-theme-text-muted hover:text-theme-text transition-colors;
}
</style>