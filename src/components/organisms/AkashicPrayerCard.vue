<template>
  <div class="akashic-prayer-card glass-panel glass-panel-soft glass-gloss relative border border-theme-border p-5 transition-all duration-300 hover:-translate-y-1 hover:border-theme-accent/30 hover:shadow-[0_18px_32px_rgba(48,38,21,0.12)]">
    <!-- Prayer Author & Time -->
    <div class="mb-3 flex flex-wrap items-center justify-between gap-3">
      <div class="flex min-w-0 items-center gap-2">
        <span class="truncate text-sm font-medium text-theme-accent">{{ prayer.username || 'Anonymous' }}</span>
        <span class="text-xs text-theme-text-muted">·</span>
        <span class="text-xs text-theme-text-muted">{{ formattedDate }}</span>
      </div>
      <div class="chip gap-1.5 px-3 py-1 text-xs font-semibold text-theme-accent">
        <span>✦ {{ formattedCount }}</span>
      </div>
    </div>

    <!-- Monk's Response (only show response, not original prayer) -->
    <div class="mb-4">
      <p v-if="prayer.response_content" class="text-sm leading-7 text-theme-text">
        {{ truncatedResponse }}
      </p>
      <p v-else class="text-sm italic text-theme-text-dim">The monk's words echo in silence...</p>
      <button
        v-if="prayer.response_content && prayer.response_content.length > 200"
        @click="expanded = !expanded"
        class="mt-2 text-xs font-medium text-theme-accent transition-colors duration-200 hover:text-theme-accent-dark"
      >
        {{ expanded ? 'Show less' : 'Read more' }}
      </button>
    </div>

    <!-- Faith Badge -->
    <div v-if="prayer.faith" class="mb-4">
      <span class="chip px-3 py-1 text-xs font-medium text-theme-accent">
        {{ prayer.faith }}
      </span>
    </div>

    <!-- Blessing Badges -->
    <div v-if="blessings && blessings.length > 0" class="mb-4" @click="$emit('showBlessingDetail', prayer)">
      <BlessingBadgeBar :blessings="blessings" :max-visible="5" @show-detail="$emit('showBlessingDetail', prayer)" />
    </div>

    <!-- Pray Button or Active Counter -->
    <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
      <div v-if="isActive" class="flex flex-1 items-center gap-4">
        <div class="prayer-counter-display" :class="{ 'counter-animate': animating }">
          <span class="counter-value text-3xl font-bold text-theme-accent font-mono">{{ displayedCount }}</span>
        </div>
        <div class="flex-1">
          <p class="text-xs uppercase tracking-[0.14em] text-theme-text-muted">Times Prayed</p>
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

      <div v-else class="flex items-center gap-2">
        <button
          @click="$emit('pray', prayer)"
          :disabled="disabled"
          class="btn-primary self-start px-4 py-2"
        >
          <span class="relative z-10 font-medium text-sm">
            🙏 Pray for this
          </span>
        </button>
        <button
          @click="$emit('bless', prayer)"
          :disabled="disabled"
          class="btn-ghost self-start px-3 py-2 text-xs"
          title="Grant a blessing to this prayer"
        >
          ✨ Bless
        </button>
      </div>

      <button
        v-if="isActive"
        @click="$emit('stop', prayer)"
        class="btn-ghost self-start px-4 py-2 text-xs"
      >
        Stop
      </button>
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue'
import BlessingBadgeBar from '@/components/molecules/BlessingBadgeBar.vue'

const props = defineProps({
  prayer: { type: Object, required: true },
  blessings: { type: Array, default: () => [] },
  isActive: { type: Boolean, default: false },
  displayedCount: { type: Number, default: 0 },
  cycleProgress: { type: Number, default: 0 },
  animating: { type: Boolean, default: false },
  disabled: { type: Boolean, default: false },
})

defineEmits(['pray', 'stop', 'bless', 'showBlessingDetail'])

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
.akashic-prayer-card {
  position: relative;
  overflow: hidden;
}

.akashic-prayer-card::after {
  content: "";
  position: absolute;
  inset: 0;
  pointer-events: none;
  background: linear-gradient(180deg, rgba(255, 255, 255, 0.14), transparent 28%);
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