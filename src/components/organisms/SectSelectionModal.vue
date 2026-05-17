<template>
  <Teleport to="body">
    <div v-if="visible" class="fixed inset-0 z-50 flex items-center justify-center p-4" style="animation: overlay-fade var(--dur-standard) var(--ease-ritual-lift)">
      <div class="absolute inset-0 bg-black/50 backdrop-blur-sm" @click="dismissNotAllowed && false"></div>
      <div class="relative z-10 w-full max-w-2xl glass-panel glass-panel-strong glass-gloss p-6 sm:p-8" style="animation: modal-rise var(--dur-enter) var(--ease-ritual-lift)">
        <!-- Header -->
        <div class="mb-6 text-center">
          <div class="mb-3 text-5xl">⛪</div>
          <h2 class="ritual-heading text-3xl font-bold text-theme-accent sm:text-4xl">Choose Your Sect</h2>
          <p class="mt-2 text-sm text-theme-text-muted">This decision is permanent. Choose wisely.</p>
        </div>

        <!-- Error -->
        <div v-if="sects.error" class="mb-4 rounded-[20px] border border-theme-purgatory/25 bg-theme-purgatory/10 p-3 text-sm text-theme-purgatory-dark">
          {{ sects.error }}
        </div>

        <!-- Sect Cards -->
        <div class="grid gap-4 sm:grid-cols-2">
          <button
            v-for="sect in sects.sectList"
            :key="sect.key"
            @click="selectedSect = sect.key"
            :class="[
              'relative text-left p-5 rounded-[24px] border transition-all duration-[var(--dur-standard)]',
              selectedSect === sect.key
                ? 'border-theme-accent/50 bg-theme-accent/10 shadow-[0_10px_28px_rgba(213,154,23,0.18)] scale-[1.01]'
                : 'border-theme-border bg-theme-panel/50 hover:border-theme-accent/25 hover:bg-theme-accent/5 hover:scale-[1.005]'
            ]"
          >
            <div v-if="selectedSect === sect.key" class="absolute top-3 right-3 text-theme-accent text-lg">✓</div>
            <div class="mb-2 text-3xl">{{ sect.icon }}</div>
            <h3 :class="['text-lg font-semibold', sect.color]">{{ sect.name }}</h3>
            <p class="mt-1 text-xs text-theme-text-muted leading-relaxed">{{ sect.description }}</p>
          </button>
        </div>

        <!-- Confirm Button -->
        <div class="mt-6 flex justify-center">
          <button
            @click="handleConfirm"
            :disabled="!selectedSect || sects.choosing"
            class="btn-primary px-8 py-3 text-base"
          >
            <span class="relative z-10 font-medium">
              {{ sects.choosing ? 'Swearing Vows...' : 'Swear the Vow' }}
            </span>
          </button>
        </div>

        <p v-if="!selectedSect" class="mt-3 text-center text-xs text-theme-text-muted italic">
          Select a sect above to continue your journey
        </p>
      </div>
    </div>
  </Teleport>
</template>

<script setup>
import { ref } from 'vue'
import { useSects } from '@/composables/useSects'

const props = defineProps({
  visible: { type: Boolean, default: false },
})

const emit = defineEmits(['chosen'])

const sects = useSects()
const selectedSect = ref(null)

async function handleConfirm() {
  if (!selectedSect.value) return
  try {
    const result = await sects.chooseSect(selectedSect.value)
    if (result?.success) {
      emit('chosen', selectedSect.value)
    }
  } catch (err) {
    // Error is captured in sects.error
  }
}
</script>