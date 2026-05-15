<script setup>
import { computed } from 'vue'
import { useAuth } from './composables/useAuth'
import { useBanTimer } from './composables/useBanTimer'
import LoginView from './views/LoginView.vue'
import AltarView from './views/AltarView.vue'
import PurgatoryView from './views/PurgatoryView.vue'

const auth = useAuth()
const banTimer = useBanTimer()

// Dynamic copyright year and developer email
const currentYear = new Date().getFullYear()
const devEmail = import.meta.env.VITE_DEV_EMAIL || 'contact@example.com'

// Determine which view to show
// With reactive() wrapping, refs are auto-unwrapped — no .value needed
const currentView = computed(() => {
  if (!auth.isAuthenticated) return 'login'
  if (banTimer.isBanned) return 'purgatory'
  return 'altar'
})
</script>

<template>
  <div class="min-h-screen bg-theme-wash flex flex-col">
    <div class="flex-1">
      <LoginView v-if="currentView === 'login'" />
      <PurgatoryView v-else-if="currentView === 'purgatory'" />
      <AltarView v-else-if="currentView === 'altar'" />
    </div>
    
    <!-- Global Footer -->
    <footer class="border-t border-theme-border bg-theme-panel/30 backdrop-blur-sm">
      <div class="max-w-4xl mx-auto px-4 py-3 text-center text-xs text-theme-text-muted">
        <p>Copyright {{ currentYear }} Lake Boiler Labs, all rights reserved. Contact: <a :href="'mailto:' + devEmail" class="text-theme-accent hover:underline">{{ devEmail }}</a></p>
      </div>
    </footer>
  </div>
</template>

<style scoped>
/* App-level scoped styles */
</style>
