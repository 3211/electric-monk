<template>
  <div class="sinner-card glass-panel glass-panel-soft glass-gloss relative border border-theme-purgatory/25 p-5 transition-all duration-300 hover:-translate-y-1 hover:border-theme-purgatory/40 hover:shadow-[0_18px_32px_rgba(168,93,50,0.12)]">
    <!-- Sinner Info -->
    <div class="mb-4 flex items-start justify-between gap-3">
      <div class="flex items-center gap-3">
        <span class="text-xl">😈</span>
        <div>
          <p class="text-sm font-semibold text-theme-text">{{ sinner.username || 'Anonymous Sinner' }}</p>
          <p v-if="sinner.faith" class="text-xs text-theme-text-muted">{{ sinner.faith }}</p>
        </div>
      </div>
      <div class="chip flex-col items-end gap-0.5 px-3 py-2 text-right">
        <p class="text-xs font-medium text-theme-purgatory">{{ timeRemaining }}</p>
        <p class="text-[0.68rem] text-theme-text-muted">remaining</p>
      </div>
    </div>

    <!-- Rejection Reason -->
    <div v-if="sinner.rejection_reason" class="mb-4 rounded-sm border border-theme-purgatory/20 bg-theme-purgatory/10 p-3">
      <p class="mb-1 text-xs uppercase tracking-[0.14em] text-theme-text-muted">Transgression</p>
      <p class="text-sm italic text-theme-purgatory-dark">"{{ sinner.rejection_reason }}"</p>
    </div>
    <div v-else class="mb-4 rounded-sm border border-theme-purgatory/20 bg-theme-purgatory/10 p-3">
      <p class="text-sm italic text-theme-text-dim">The nature of their transgression is shrouded in mystery...</p>
    </div>

    <!-- Pray Button or Active Counter -->
    <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
      <div v-if="isActive" class="flex flex-1 items-center gap-4">
        <div class="prayer-counter-display" :class="{ 'counter-animate': animating }">
          <span class="counter-value text-3xl font-bold text-theme-accent font-mono">{{ displayedCount }}</span>
        </div>
        <div class="flex-1">
          <p class="text-xs uppercase tracking-[0.14em] text-theme-text-muted">Intercessory Prayers</p>
          <div class="prayer-progress-track mt-2">
            <div
              class="prayer-progress-fill transition-none"
              :style="{
                width: (cycleProgress * 100) + '%'
              }"
            ></div>
          </div>
        </div>
      </div>

      <button
        v-if="isActive"
        @click="$emit('stop', sinner)"
        class="btn-ghost self-start px-4 py-2 text-xs"
      >
        Stop
      </button>

      <button
        v-else
        @click="$emit('pray', sinner)"
        :disabled="disabled || loading"
        class="btn-danger self-start px-4 py-2"
      >
        <span class="relative z-10 font-medium text-sm">
          {{ loading ? 'Generating Prayer...' : '🕯️ Pray for this Sinner' }}
        </span>
      </button>
    </div>
  </div>
</template>

<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue'

const props = defineProps({
  sinner: { type: Object, required: true },
  isActive: { type: Boolean, default: false },
  displayedCount: { type: Number, default: 0 },
  cycleProgress: { type: Number, default: 0 },
  animating: { type: Boolean, default: false },
  disabled: { type: Boolean, default: false },
  loading: { type: Boolean, default: false },
})

defineEmits(['pray', 'stop'])

// Live countdown for ban time remaining
const now = ref(new Date())
let timer = null

onMounted(() => {
  timer = setInterval(() => { now.value = new Date() }, 1000)
})

onUnmounted(() => {
  if (timer) clearInterval(timer)
})

const timeRemaining = computed(() => {
  if (!props.sinner.ban_until) return 'Unknown'
  const banEnd = new Date(props.sinner.ban_until)
  const diff = Math.max(0, banEnd - now.value)
  const hours = Math.floor(diff / 3600000)
  const minutes = Math.floor((diff % 3600000) / 60000)
  const seconds = Math.floor((diff % 60000) / 1000)

  if (hours > 0) return `${hours}h ${minutes}m`
  if (minutes > 0) return `${minutes}m ${seconds}s`
  return `${seconds}s`
})
</script>

<style scoped>
.sinner-card {
  position: relative;
  overflow: hidden;
}

.sinner-card::after {
  content: "";
  position: absolute;
  inset: 0;
  pointer-events: none;
  background: linear-gradient(180deg, rgba(255, 255, 255, 0.12), transparent 30%);
}

.prayer-counter-display {
  transition: transform var(--dur-quick) var(--ease-ritual-lift);
}

.counter-animate {
  animation: counterPulse 180ms var(--ease-ritual-lift);
}

.counter-value {
  letter-spacing: -0.05em;
  font-variant-numeric: tabular-nums;
}
</style>