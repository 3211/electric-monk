<template>
  <Transition name="picker-fade">
    <div v-if="visible" class="picker-backdrop fixed inset-0 z-50 flex items-center justify-center" @click.self="$emit('close')">
      <div class="picker-panel glass-panel glass-panel-strong glass-gloss relative mx-4 w-full max-w-sm overflow-hidden border border-theme-border p-5 shadow-[0_24px_48px_rgba(48,38,21,0.2)]">
        <div class="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_50%_0%,rgba(255,223,147,0.1),transparent_60%)]"></div>

        <div class="relative">
          <!-- Header -->
          <div class="mb-4 flex items-center justify-between">
            <h3 class="text-sm font-semibold text-theme-text">Grant a Blessing</h3>
            <button
              @click="$emit('close')"
              class="flex h-7 w-7 items-center justify-center rounded-full text-theme-text-muted transition-colors duration-200 hover:bg-theme-accent/10 hover:text-theme-accent"
            >
              ✕
            </button>
          </div>

          <!-- Prayer preview -->
          <div v-if="prayerUsername" class="mb-4 text-xs text-theme-text-muted">
            Blessing <span class="font-medium text-theme-accent">{{ prayerUsername }}</span>'s prayer
          </div>

          <!-- Blessing grid -->
          <div class="space-y-2.5">
            <button
              v-for="blessing in blessingTypes"
              :key="blessing.id"
              @click="handleSelect(blessing.id)"
              :disabled="isDisabled(blessing)"
              class="blessing-option group flex w-full items-center gap-3 rounded-xl border border-theme-border/60 p-3 text-left transition-all duration-200 hover:border-theme-accent/30 hover:bg-theme-accent/5 disabled:cursor-not-allowed disabled:opacity-40 disabled:hover:border-theme-border/60 disabled:hover:bg-transparent"
            >
              <span class="flex h-10 w-10 flex-none items-center justify-center rounded-xl border border-theme-accent/15 bg-white/50 text-xl shadow-[0_8px_16px_rgba(213,154,23,0.08)]">{{ blessing.emoji }}</span>
              <div class="min-w-0 flex-1">
                <div class="flex items-center gap-2">
                  <span class="truncate text-sm font-medium text-theme-text">{{ blessing.name }}</span>
                  <span v-if="isAlreadyGranted(blessing)" class="chip px-1.5 py-0.5 text-[0.6rem] font-medium text-theme-accent">Granted</span>
                </div>
                <p class="mt-0.5 truncate text-[0.7rem] text-theme-text-dim">{{ blessing.description }}</p>
                <p class="mt-0.5 text-[0.65rem] text-theme-accent/70">
                  🛡 {{ formatShieldDuration(getShieldMinutes(blessing)) }} shield (both)
                </p>
              </div>
              <div class="flex flex-none flex-col items-end gap-0.5">
                <span class="text-xs font-semibold text-theme-accent">{{ blessing.karma_cost }} ✦</span>
                <span class="text-[0.6rem] text-theme-text-muted">receiver +{{ blessing.karma_to_receiver }}</span>
              </div>
            </button>
          </div>

          <!-- Insufficient karma notice -->
          <div v-if="userKarma < minCost" class="mt-3 rounded-lg border border-theme-purgatory/30 bg-theme-purgatory/10 p-3 text-xs text-theme-purgatory-dark">
            You need at least <span class="font-semibold">{{ minCost }}</span> ✦ karma to grant a blessing.
          </div>
        </div>
      </div>
    </div>
  </Transition>
</template>

<script setup>
import { computed } from 'vue'
import blessingsConfig from '@/config/blessings.json'

const props = defineProps({
  visible: { type: Boolean, default: false },
  prayerUsername: { type: String, default: '' },
  userKarma: { type: Number, default: 0 },
  existingBlessingTypeIds: { type: Array, default: () => [] },
})

const emit = defineEmits(['close', 'select'])

const blessingTypes = computed(() => {
  return blessingsConfig.blessings.slice().sort((a, b) => a.sort_order - b.sort_order)
})

const shieldMinutesPerKarma = blessingsConfig.shieldMinutesPerKarma || 10

const minCost = computed(() => {
  return Math.min(...blessingTypes.value.map(b => b.karma_cost))
})

function getShieldMinutes(blessing) {
  if (!blessing) return 0
  if (blessing.shield_minutes != null) return blessing.shield_minutes
  return (blessing.karma_cost || 0) * shieldMinutesPerKarma
}

function formatShieldDuration(minutes) {
  if (!minutes || minutes <= 0) return '0m'
  const h = Math.floor(minutes / 60)
  const m = minutes % 60
  if (h > 0 && m > 0) return `${h}h ${m}m`
  if (h > 0) return `${h}h`
  return `${m}m`
}

function isAlreadyGranted(blessing) {
  return props.existingBlessingTypeIds.includes(blessing.id)
}

function isDisabled(blessing) {
  if (isAlreadyGranted(blessing)) return true
  if (props.userKarma < blessing.karma_cost) return true
  return false
}

function handleSelect(blessingTypeId) {
  const blessing = blessingTypes.value.find(b => b.id === blessingTypeId)
  if (!blessing || isDisabled(blessing)) return
  emit('select', blessingTypeId)
}
</script>

<style scoped>
.picker-backdrop {
  background: rgba(0, 0, 0, 0.4);
  backdrop-filter: blur(4px);
}

.picker-fade-enter-active {
  animation: pickerFadeIn var(--dur-enter, 200ms) var(--ease-silk-settle, ease-out);
}

.picker-fade-leave-active {
  animation: pickerFadeOut 180ms ease;
}

@keyframes pickerFadeIn {
  from {
    opacity: 0;
  }
  to {
    opacity: 1;
  }
}

@keyframes pickerFadeOut {
  from {
    opacity: 1;
  }
  to {
    opacity: 0;
  }
}
</style>