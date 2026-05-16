<template>
  <div class="akashic-prayer-card glass-panel glass-gloss p-4 relative border border-theme-border hover:border-theme-accent/30 transition-all duration-200">
    <!-- Prayer Author & Time -->
    <div class="flex items-center justify-between mb-2">
      <div class="flex items-center gap-2">
        <span class="text-sm font-medium text-theme-accent">{{ prayer.username || 'Anonymous' }}</span>
        <span class="text-xs text-theme-text-muted">·</span>
        <span class="text-xs text-theme-text-muted">{{ formattedDate }}</span>
      </div>
      <div class="flex items-center gap-1.5">
        <span class="text-xs text-theme-accent font-semibold">✦ {{ formattedCount }}</span>
      </div>
    </div>

    <!-- Monk's Response (only show response, not original prayer) -->
    <div class="mb-3">
      <p v-if="prayer.response_content" class="text-theme-text text-sm leading-relaxed">
        {{ truncatedResponse }}
      </p>
      <p v-else class="text-theme-text-dim italic text-sm">The monk's words echo in silence...</p>
      <button
        v-if="prayer.response_content && prayer.response_content.length > 200"
        @click="expanded = !expanded"
        class="text-xs text-theme-accent hover:text-theme-accent-dark mt-1 transition-colors"
      >
        {{ expanded ? 'Show less' : 'Read more' }}
      </button>
    </div>

    <!-- Faith Badge -->
    <div v-if="prayer.faith" class="mb-3">
      <span class="inline-flex items-center px-2 py-0.5 text-xs font-medium rounded-full bg-theme-accent/10 text-theme-accent border border-theme-accent/20">
        {{ prayer.faith }}
      </span>
    </div>

    <!-- Pray Button or Active Counter -->
    <div class="flex items-center justify-between">
      <div v-if="isActive" class="flex items-center gap-3">
        <div class="prayer-counter-display" :class="{ 'counter-animate': animating }">
          <span class="text-2xl font-bold text-theme-accent font-mono">{{ displayedCount }}</span>
        </div>
        <div class="flex-1">
          <p class="text-xs text-theme-text-muted uppercase tracking-wider">Times Prayed</p>
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
        v-else
        @click="$emit('pray', prayer)"
        :disabled="disabled"
        class="btn-altruistic"
      >
        <span class="relative z-10 font-medium text-sm">
          🙏 Pray for this
        </span>
      </button>

      <button
        v-if="isActive"
        @click="$emit('stop', prayer)"
        class="px-3 py-1.5 text-xs text-theme-text-dim hover:text-theme-purgatory border border-theme-border rounded hover:border-theme-purgatory/50 transition-colors"
      >
        Stop
      </button>
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue'

const props = defineProps({
  prayer: { type: Object, required: true },
  isActive: { type: Boolean, default: false },
  displayedCount: { type: Number, default: 0 },
  cycleProgress: { type: Number, default: 0 },
  animating: { type: Boolean, default: false },
  disabled: { type: Boolean, default: false },
})

defineEmits(['pray', 'stop'])

const expanded = ref(false)

const formattedDate = computed(() => {
  if (!props.prayer.created_at) return ''
  const date = new Date(props.prayer.created_at)
  const now = new Date()
  const diffMs = now - date
  const diffMins = Math.floor(diffMs / 60000)
  const diffHours = Math.floor(diffMs / 3600000)
  const diffDays = Math.floor(diffMs / 86400000)

  if (diffMins < 1) return 'just now'
  if (diffMins < 60) return `${diffMins}m ago`
  if (diffHours < 24) return `${diffHours}h ago`
  if (diffDays < 7) return `${diffDays}d ago`
  return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
})

const formattedCount = computed(() => {
  const count = props.prayer.prayer_count || 0
  if (count >= 1000) return `${(count / 1000).toFixed(1)}k`
  return count.toString()
})

const truncatedResponse = computed(() => {
  const text = props.prayer.response_content || ''
  if (expanded.value || text.length <= 200) return text
  return text.substring(0, 200) + '...'
})
</script>

<style scoped>
.btn-altruistic {
  @apply relative overflow-hidden font-sans rounded-btn px-4 py-2 border shadow-inner-top glass-gloss active:translate-y-0 transition-all duration-150 ease-out cursor-pointer;
  color: white;
  border-color: color-mix(in srgb, var(--theme-accent) 55%, white 10%);
  box-shadow: 0 8px 16px color-mix(in srgb, var(--theme-accent) 20%, transparent);
  background: linear-gradient(
    180deg,
    color-mix(in srgb, var(--theme-accent) 34%, white 12%),
    color-mix(in srgb, var(--theme-accent-2) 72%, black 15%)
  );
}

.btn-altruistic:hover {
  transform: translateY(-1px);
}

.btn-altruistic:disabled {
  background: linear-gradient(
    180deg,
    color-mix(in srgb, var(--theme-accent) 20%, gray 30%),
    color-mix(in srgb, var(--theme-accent-dark) 40%, gray 40%)
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