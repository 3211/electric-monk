<template>
  <div v-if="displayTime" class="chip gap-2 px-4 py-2 text-sm shadow-[0_10px_20px_rgba(48,38,21,0.06)]">
    <span :class="iconColor">🛡</span>
    <span :class="textColor" class="font-semibold">Shield: {{ displayTime }}</span>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue'

const props = defineProps({
  /** ISO date string for when the shield expires, or null */
  shieldUntil: { type: String, default: null },
  /** Theme variant: 'auto' follows the parent theme, 'light' forces light colors, 'dark' forces dark colors */
  variant: { type: String, default: 'auto' },
})

const now = ref(new Date())

let intervalId = null

// Update every 30 seconds so the countdown stays reasonably accurate
onMounted(() => {
  intervalId = setInterval(() => {
    now.value = new Date()
  }, 30000)
})

onUnmounted(() => {
  if (intervalId) {
    clearInterval(intervalId)
    intervalId = null
  }
})

const remaining = computed(() => {
  if (!props.shieldUntil) return null
  const until = new Date(props.shieldUntil)
  const diffMs = until - now.value
  if (diffMs <= 0) return null
  return diffMs
})

const displayTime = computed(() => {
  if (!remaining.value) return null
  const diffMs = remaining.value
  const hours = Math.floor(diffMs / (1000 * 60 * 60))
  const minutes = Math.floor((diffMs % (1000 * 60 * 60)) / (1000 * 60))
  if (hours > 0 && minutes > 0) return `${hours}h ${minutes}m`
  if (hours > 0) return `${hours}h`
  if (minutes > 0) return `${minutes}m`
  return '<1m'
})

const iconColor = computed(() => {
  if (props.variant === 'dark') return 'text-amber-400'
  return 'text-amber-500'
})

const textColor = computed(() => {
  if (props.variant === 'dark') return 'text-amber-400'
  return 'text-amber-600'
})
</script>