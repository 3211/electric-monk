<script setup>
import { computed } from 'vue'
import { useAuth } from './composables/useAuth'
import { useBanTimer } from './composables/useBanTimer'
import LoginView from './views/LoginView.vue'
import AltarView from './views/AltarView.vue'
import PurgatoryView from './views/PurgatoryView.vue'

const auth = useAuth()
const banTimer = useBanTimer()

// Determine which view to show
// With reactive() wrapping, refs are auto-unwrapped — no .value needed
const currentView = computed(() => {
  if (!auth.isAuthenticated) return 'login'
  if (banTimer.isBanned) return 'purgatory'
  return 'altar'
})
</script>

<template>
  <div class="min-h-screen bg-theme-wash">
    <LoginView v-if="currentView === 'login'" />
    <PurgatoryView v-else-if="currentView === 'purgatory'" />
    <AltarView v-else-if="currentView === 'altar'" />
  </div>
</template>

<style scoped>
/* App-level scoped styles */
</style>
