<template>
  <Teleport to="body">
    <Transition name="fade">
      <div v-if="modelValue" class="history-modal-overlay" @click.self="close">
        <div class="history-modal-container glass-panel glass-gloss">
          <!-- Header -->
          <div class="history-modal-header">
            <h2 class="text-xl font-bold text-theme-accent">{{ title }}</h2>
            <button
              @click="close"
              class="p-2 text-theme-text-muted hover:text-theme-text transition-colors rounded-lg hover:bg-theme-border/20"
              aria-label="Close"
            >
              <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          <!-- Prayer Count -->
          <p class="text-sm text-theme-text-muted mb-3">
            Showing {{ prayers.length }} prayer{{ prayers.length !== 1 ? 's' : '' }}
          </p>

          <!-- Prayer List — scrollable -->
          <div class="history-modal-list custom-scrollbar">
            <div
              v-for="prayer in prayers"
              :key="prayer.id"
              class="history-prayer-card"
              :class="{
                'bg-theme-purgatory/10 border-theme-purgatory/30': prayer.is_rejected,
                'bg-theme-panel border-theme-border/30': !prayer.is_rejected,
                'border-theme-accent/40 shadow-glow-accent-sm': prayer.is_praying
              }"
            >
              <!-- Active prayer badge -->
              <div v-if="prayer.is_praying && !prayer.is_rejected" class="flex items-center gap-2 mb-2">
                <span class="px-2 py-0.5 text-xs font-medium rounded bg-theme-accent/30 text-theme-accent-dark animate-pulse">
                  ✦ Being Prayed
                </span>
                <span class="text-xs text-theme-accent font-semibold">
                  {{ prayer.prayer_count || 0 }} prayers counted
                </span>
              </div>

              <!-- Prayer Content -->
              <div class="flex items-start justify-between gap-3">
                <div class="flex-1 min-w-0">
                  <p v-if="prayer.response_content" class="text-theme-text text-sm leading-relaxed">
                    {{ prayer.response_content }}
                  </p>
                  <p v-else class="text-theme-text-dim italic text-sm">
                    The monk's words echo in silence...
                  </p>
                </div>

                <!-- Action Buttons -->
                <div class="flex flex-col items-end gap-1 shrink-0">
                  <!-- Reactivate button (inactive prayers only) -->
                  <button
                    v-if="showReactivate && !prayer.is_praying && !prayer.is_rejected && !prayer.is_archived"
                    @click="$emit('reactivate', prayer.id)"
                    :disabled="loading"
                    class="px-3 py-1.5 text-xs font-medium rounded border border-theme-accent/50 text-theme-accent hover:bg-theme-accent/10 transition-colors disabled:opacity-50 whitespace-nowrap"
                  >
                    ⚡ Reactivate
                  </button>

                  <!-- Status badge (archived prayers) -->
                  <span
                    v-if="prayer.is_rejected || prayer.is_archived"
                    class="px-2 py-0.5 text-xs font-medium rounded whitespace-nowrap"
                    :class="{
                      'bg-theme-purgatory/20 text-theme-purgatory-dark': prayer.is_rejected,
                      'bg-theme-panel text-theme-text-muted': prayer.is_archived && !prayer.is_rejected
                    }"
                  >
                    {{ prayer.is_rejected ? 'Rejected' : 'Archived' }}
                  </span>

                  <!-- Prayer count badge -->
                  <span v-if="prayer.prayer_count" class="text-xs text-theme-accent font-semibold">
                    ✦ {{ prayer.prayer_count }}
                  </span>
                </div>
              </div>

              <!-- Rejection reason -->
              <p v-if="prayer.rejection_reason" class="mt-2 text-xs text-theme-purgatory italic">
                Reason: {{ prayer.rejection_reason }}
              </p>

              <!-- Timestamp + Archive button -->
              <div class="mt-2 flex items-center justify-between">
                <p class="text-xs text-theme-text-muted">
                  {{ formatDate(prayer.created_at) }}
                </p>
                <button
                  v-if="!prayer.is_archived"
                  @click="$emit('archive', prayer.id)"
                  :disabled="loading"
                  class="px-2 py-1 text-xs text-theme-text-muted hover:text-theme-purgatory transition-colors disabled:opacity-50"
                  title="Archive this prayer"
                >
                  Archive
                </button>
              </div>
            </div>

            <!-- Empty state -->
            <div v-if="prayers.length === 0" class="text-center py-8 text-theme-text-dim">
              <p>No prayers to display.</p>
            </div>
          </div>

          <!-- Footer -->
          <div class="history-modal-footer">
            <button
              @click="close"
              class="btn-secondary w-full"
            >
              Close
            </button>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<script setup>
const props = defineProps({
  modelValue: {
    type: Boolean,
    default: false
  },
  prayers: {
    type: Array,
    default: () => []
  },
  title: {
    type: String,
    default: 'Prayer History'
  },
  loading: {
    type: Boolean,
    default: false
  },
  showReactivate: {
    type: Boolean,
    default: false
  }
})

const emit = defineEmits(['update:modelValue', 'archive', 'reactivate'])

function close() {
  emit('update:modelValue', false)
}

function formatDate(dateString) {
  const date = new Date(dateString)
  return date.toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit'
  })
}
</script>

<style scoped>
/* Modal Overlay */
.history-modal-overlay {
  position: fixed;
  inset: 0;
  z-index: 9000;
  display: flex;
  align-items: flex-start;
  justify-content: center;
  padding: 1rem;
  padding-top: max(1rem, env(safe-area-inset-top));
  padding-bottom: max(1rem, env(safe-area-inset-bottom));
  background: rgba(48, 38, 21, 0.85);
  backdrop-filter: blur(12px);
  -webkit-backdrop-filter: blur(12px);
  animation: fadeIn 0.2s ease-out;
}

/* Modal Container */
.history-modal-container {
  width: 100%;
  max-width: 600px;
  max-height: 85vh;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  border: 2px solid color-mix(in srgb, var(--theme-accent) 40%, transparent);
  animation: modalSlideIn 0.3s ease-out;
}

/* Header */
.history-modal-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 1rem 1.25rem;
  border-bottom: 1px solid var(--theme-border);
  flex-shrink: 0;
}

/* Scrollable List */
.history-modal-list {
  flex: 1;
  overflow-y: auto;
  overscroll-behavior-y: contain;
  -webkit-overflow-scrolling: touch;
  padding: 1rem 1.25rem;
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
}

/* Prayer Card */
.history-prayer-card {
  padding: 0.875rem;
  border-radius: 16px;
  border-width: 1px;
  transition: opacity 0.15s ease;
}

.history-prayer-card:hover {
  opacity: 0.9;
}

/* Small glow for active prayers */
.shadow-glow-accent-sm {
  box-shadow: 0 0 12px color-mix(in srgb, var(--theme-accent) 10%, transparent);
}

/* Footer */
.history-modal-footer {
  padding: 0.75rem 1.25rem;
  border-top: 1px solid var(--theme-border);
  flex-shrink: 0;
}

/* Secondary button (close) */
.btn-secondary {
  @apply px-4 py-2 rounded-btn border border-theme-border text-theme-text-dim font-medium transition-all duration-150;
  background: color-mix(in srgb, var(--theme-panel) 60%, transparent);
}

.btn-secondary:hover {
  background: color-mix(in srgb, var(--theme-panel) 80%, var(--theme-accent) 10%);
  border-color: var(--theme-accent);
  color: var(--theme-accent);
}

/* Custom scrollbar */
.custom-scrollbar::-webkit-scrollbar {
  width: 6px;
}

.custom-scrollbar::-webkit-scrollbar-track {
  background: rgba(0, 0, 0, 0.05);
  border-radius: 3px;
}

.custom-scrollbar::-webkit-scrollbar-thumb {
  background: rgba(139, 125, 91, 0.25);
  border-radius: 3px;
}

.custom-scrollbar::-webkit-scrollbar-thumb:hover {
  background: rgba(139, 125, 91, 0.4);
}

/* Fade Transition */
.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.2s ease;
}

.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}

/* Slide In Animation */
@keyframes modalSlideIn {
  0% {
    opacity: 0;
    transform: translateY(-12px) scale(0.97);
  }
  100% {
    opacity: 1;
    transform: translateY(0) scale(1);
  }
}

@keyframes fadeIn {
  0% { opacity: 0; }
  100% { opacity: 1; }
}

/* Mobile adjustments */
@media (max-width: 640px) {
  .history-modal-overlay {
    padding: 0;
    padding-top: env(safe-area-inset-top);
    padding-bottom: env(safe-area-inset-bottom);
    align-items: stretch;
  }

  .history-modal-container {
    max-height: 100vh;
    max-width: 100%;
    border-radius: 0;
    border-left: none;
    border-right: none;
    border-top: none;
  }

  .history-modal-header {
    padding: 0.75rem 1rem;
  }

  .history-modal-list {
    padding: 0.75rem 1rem;
  }

  .history-modal-footer {
    padding: 0.75rem 1rem;
  }
}
</style>