<script setup>
import { computed, onMounted } from 'vue'
import { useAuth } from './composables/useAuth'
import { useBanTimer } from './composables/useBanTimer'
import LoginView from './views/LoginView.vue'
import AltarView from './views/AltarView.vue'
import PurgatoryView from './views/PurgatoryView.vue'

const auth = useAuth()
const banTimer = useBanTimer()

// Computed state
const isAuthenticated = computed(() => auth.isAuthenticated)
const isBanned = computed(() => banTimer.isBanned)

// Determine which view to show
const currentView = computed(() => {
  if (!isAuthenticated.value) return 'login'
  if (isBanned.value) return 'purgatory'
  return 'altar'
})
</script>

<template>
  <div class="min-h-screen">
    <LoginView v-if="currentView === 'login'" />
    <PurgatoryView v-else-if="currentView === 'purgatory'" />
    <AltarView v-else-if="currentView === 'altar'" />
  </div>
</template>

<style scoped>
/* App-level scoped styles */
</style>
