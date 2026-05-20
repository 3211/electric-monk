<template>
  <Transition name="detail-fade">
    <div v-if="visible" class="detail-backdrop fixed inset-0 z-50 flex items-center justify-center" @click.self="$emit('close')">
      <div class="detail-panel glass-panel glass-panel-strong glass-gloss relative mx-4 w-full max-w-md overflow-hidden border border-theme-border p-5 shadow-[0_24px_48px_rgba(48,38,21,0.2)]">
        <div class="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_50%_0%,rgba(255,223,147,0.08),transparent_60%)]"></div>

        <div class="relative">
          <!-- Header -->
          <div class="mb-4 flex items-center justify-between">
            <h3 class="text-sm font-semibold text-theme-text">Blessings Received</h3>
            <button
              @click="$emit('close')"
              class="flex h-7 w-7 items-center justify-center rounded-sm text-theme-text-muted transition-colors duration-200 hover:bg-theme-accent/10 hover:text-theme-accent"
            >
              ✕
            </button>
          </div>

          <!-- Blessings list -->
          <div v-if="blessings && blessings.length > 0" class="space-y-3">
            <div
              v-for="b in blessings"
              :key="b.blessing_type_id"
              class="flex items-center gap-3 rounded-sm border border-theme-border/40 bg-white/30 p-3"
            >
              <span class="flex h-10 w-10 flex-none items-center justify-center rounded-sm border border-theme-accent/15 bg-white/50 text-xl shadow-[0_8px_16px_rgba(213,154,23,0.08)]">{{ b.emoji }}</span>
              <div class="min-w-0 flex-1">
                <div class="flex items-center gap-2">
                  <span class="text-sm font-medium text-theme-text">{{ b.name }}</span>
                </div>
                <div class="mt-0.5 text-[0.7rem] text-theme-text-muted">
                  Granted <span class="font-semibold text-theme-accent">×{{ b.count }}</span>
                </div>
              </div>
              <div class="flex-none">
                <span class="chip px-2 py-0.5 text-xs font-semibold text-theme-accent">×{{ b.count }}</span>
              </div>
            </div>
          </div>

          <!-- Empty state -->
          <div v-else class="py-8 text-center">
            <div class="mb-2 text-3xl">🕊️</div>
            <p class="text-sm text-theme-text-dim">No blessings have been granted yet.</p>
          </div>
        </div>
      </div>
    </div>
  </Transition>
</template>

<script setup>
defineProps({
  visible: { type: Boolean, default: false },
  blessings: { type: Array, default: () => [] },
})

defineEmits(['close'])
</script>

<style scoped>
.detail-backdrop {
  background: rgba(0, 0, 0, 0.4);
  backdrop-filter: blur(4px);
}

.detail-fade-enter-active {
  animation: detailFadeIn var(--dur-enter, 200ms) var(--ease-silk-settle, ease-out);
}

.detail-fade-leave-active {
  animation: detailFadeOut 180ms ease;
}

@keyframes detailFadeIn {
  from {
    opacity: 0;
    transform: scale(0.96);
  }
  to {
    opacity: 1;
    transform: scale(1);
  }
}

@keyframes detailFadeOut {
  from {
    opacity: 1;
    transform: scale(1);
  }
  to {
    opacity: 0;
    transform: scale(0.96);
  }
}
</style>