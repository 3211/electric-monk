<template>
  <div class="sinner-card glass-panel glass-gloss p-4 relative border border-theme-purgatory/30 hover:border-theme-purgatory/50 transition-all duration-200">
    <!-- Sinner Info -->
    <div class="flex items-start justify-between gap-3 mb-3">
      <div class="flex items-center gap-2">
        <span class="text-xl">😈</span>
        <div>
          <p class="text-sm font-semibold text-theme-text">{{ sinner.username || 'Anonymous Sinner' }}</p>
          <p v-if="sinner.faith" class="text-xs text-theme-text-muted">{{ sinner.faith }}</p>
        </div>
      </div>
      <div class="text-right">
        <p class="text-xs text-theme-purgatory font-medium">{{ timeRemaining }}</p>
        <p class="text-xs text-theme-text-muted">remaining</p>
      </div>
    </div>

    <!-- Rejection Reason -->
    <div v-if="sinner.rejection_reason" class="mb-3 p-2.5 rounded-lg bg-theme-purgatory/10 border border-theme-purgatory/20">
      <p class="text-xs text-theme-text-muted uppercase tracking-wider mb-1">Transgression</p>
      <p class="text-sm text-theme-purgatory-dark italic">"{{ sinner.rejection_reason }}"</p>
    </div>
    <div v-else class="mb-3 p-2.5 rounded-lg bg-theme-purgatory/10 border border-theme-purgatory/20">
      <p class="text-sm text-theme-text-dim italic">The nature of their transgression is shrouded in mystery...</p>
    </div>

    <!-- Pray Button or Active Counter -->
    <div class="flex items-center justify-between">
      <div v-if="isActive" class="flex items-center gap-3 flex-1">
        <div class="prayer-counter-display" :class="{ 'counter-animate': animating }">
          <span class="text-2xl font-bold text-theme-accent font-mono">{{ displayedCount }}</span>
        </div>
        <div class="flex-1">
          <p class="text-xs text-theme-text-muted uppercase tracking-wider">Intercessory Prayers</p>
          <div class="w-full h-1.5 bg-theme-border/30 rounded-full mt-1 overflow-hidden">
            <div
              class="h-full rounded-full transition-none"
              :style="{
                width: (cycleProgress * 100) + '%',
                background: 'linear-gradient(90deg, #c9a84c, #f5e6a3, #c9a84c)',
                boxShadow: '0 0 8px rgba(201, 168, 76, 0.5)'
              }"
            ></div>
          </div>
        </div>
      </div>

      <button
        v-if="isActive"
        @click="$emit('stop', sinner)"
        class="px-3 py-1.5 text-xs text-theme-text-dim hover:text-theme-purgatory border border-theme-border rounded hover:border-theme-purgatory/50 transition-colors"
      >
        Stop
      </button>

      <button
        v-else
        @click="$emit('pray', sinner)"
        :disabled="disabled || loading"
        class="btn-intercessory"
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
.btn-intercessory {
  @apply relative overflow-hidden font-sans rounded-btn px-4 py-2 border shadow-inner-top glass-gloss active:translate-y-0 transition-all duration-150 ease-out cursor-pointer;
  color: white;
  border-color: color-mix(in srgb, #ef4444 55%, white 10%);
  box-shadow: 0 8px 16px color-mix(in srgb, #ef4444 20%, transparent);
  background: linear-gradient(
    180deg,
    color-mix(in srgb, #ef4444 34%, white 12%),
    color-mix(in srgb, #b91c1c 72%, black 15%)
  );
}

.btn-intercessory:hover {
  transform: translateY(-1px);
}

.btn-intercessory:disabled {
  background: linear-gradient(
    180deg,
    color-mix(in srgb, #ef4444 20%, gray 30%),
    color-mix(in srgb, #b91c1c 40%, gray 40%)
  );
  opacity: 0.6;
  cursor: not-allowed;
}

.prayer-counter-display {
  transition: transform 0.15s ease-out;
}

.counter-animate {
  animation: counterPulse 0.2s ease-out;
}

@keyframes counterPulse {
  0% { transform: scale(1); }
  50% { transform: scale(1.15); text-shadow: 0 0 12px color-mix(in srgb, var(--theme-accent) 60%, transparent); }
  100% { transform: scale(1); }
}
</style>