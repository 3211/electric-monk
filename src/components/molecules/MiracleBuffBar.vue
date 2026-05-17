<template>
  <div v-if="visibleMiracles.length > 0" class="miracle-buff-bar flex flex-wrap items-center gap-2">
    <div
      v-for="miracle in visibleMiracles"
      :key="miracle.id"
      class="chip gap-1.5 px-3 py-1.5 text-xs font-medium shadow-[0_10px_20px_rgba(48,38,21,0.06)] transition-all duration-200 hover:-translate-y-0.5 cursor-default"
      :class="miracleClass(miracle)"
      :title="miracleTooltip(miracle)"
    >
      <span class="text-sm">{{ miracleIcon(miracle) }}</span>
      <span>{{ miracleLabel(miracle) }}</span>
      <span v-if="miracleTimeRemaining(miracle)" class="text-[0.65rem] opacity-70">{{ miracleTimeRemaining(miracle) }}</span>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import blessingsConfig from '@/config/blessings.json'

const props = defineProps({
  /** Array of active miracles from economy.activeMiracles */
  miracles: { type: Array, default: () => [] },
})

const now = ref(new Date())

let intervalId = null

onMounted(() => {
  // Update every 30 seconds for countdown accuracy
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

// Build a lookup map from blessings config for emoji/name resolution
const blessingMap = computed(() => {
  const map = {}
  for (const b of blessingsConfig.blessings) {
    map[b.id] = b
  }
  return map
})

// Only show miracles that haven't expired
const visibleMiracles = computed(() => {
  return props.miracles.filter(m => {
    if (!m.expires_at) return true
    return new Date(m.expires_at) > now.value
  })
})

function miracleIcon(miracle) {
  if (miracle.miracle_type === 'blessing_shield') {
    const blessingId = miracle.effect_data?.blessing_type_id
    const blessing = blessingMap.value[blessingId]
    if (blessing) return blessing.emoji
    return '✨'
  }
  if (miracle.miracle_type === 'papal_bull') return '🐂'
  return '🔮'
}

function miracleLabel(miracle) {
  if (miracle.miracle_type === 'blessing_shield') {
    const blessingId = miracle.effect_data?.blessing_type_id
    const blessing = blessingMap.value[blessingId]
    const source = miracle.effect_data?.source === 'given' ? 'Given' : 'Received'
    if (blessing) return `${source}`
    return 'Shield'
  }
  if (miracle.miracle_type === 'papal_bull') return 'Papal Bull'
  return miracle.miracle_type
}

function miracleClass(miracle) {
  if (miracle.miracle_type === 'blessing_shield') return 'text-amber-600 border-amber-300/30 bg-amber-50/60'
  if (miracle.miracle_type === 'papal_bull') return 'text-purple-600 border-purple-300/30 bg-purple-50/60'
  return 'text-theme-accent'
}

function miracleTooltip(miracle) {
  const label = miracleLabel(miracle)
  const time = miracleTimeRemaining(miracle)
  if (miracle.miracle_type === 'blessing_shield') {
    const blessingId = miracle.effect_data?.blessing_type_id
    const blessing = blessingMap.value[blessingId]
    const name = blessing ? blessing.name : 'Blessing Shield'
    const source = miracle.effect_data?.source === 'given' ? 'You gave this blessing' : 'You received this blessing'
    const minutes = miracle.effect_data?.shield_minutes
    const duration = minutes ? ` (${minutes} min total)` : ''
    return `${name} — ${source}${duration}${time ? `, ${time} remaining` : ''}`
  }
  if (miracle.miracle_type === 'papal_bull') {
    return `Papal Bull active${time ? `, ${time} remaining` : ''}`
  }
  return `${label}${time ? `, ${time} remaining` : ''}`
}

function miracleTimeRemaining(miracle) {
  if (!miracle.expires_at) return null
  const expires = new Date(miracle.expires_at)
  const diffMs = expires - now.value
  if (diffMs <= 0) return null
  const hours = Math.floor(diffMs / (1000 * 60 * 60))
  const minutes = Math.floor((diffMs % (1000 * 60 * 60)) / (1000 * 60))
  if (hours > 0 && minutes > 0) return `${hours}h ${minutes}m`
  if (hours > 0) return `${hours}h`
  if (minutes > 0) return `${minutes}m`
  return '<1m'
}
</script>

<style scoped>
.miracle-buff-bar {
  /* Allow the bar to wrap nicely on mobile */
}
</style>