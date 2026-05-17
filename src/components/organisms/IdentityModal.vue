<template>
  <Teleport to="body">
    <div v-if="modelValue" class="identity-overlay fixed inset-0 z-[9500] flex items-center justify-center px-4 py-6">
      <div class="identity-card glass-panel glass-panel-strong glass-gloss max-w-lg w-full p-6 sm:p-8">
        <!-- Header -->
        <div class="mb-6 text-center">
          <h2 class="ritual-heading mb-2 text-3xl font-bold text-theme-accent">Identify Yourself</h2>
          <p class="text-sm text-theme-text-dim">Choose your name and sect. This decision is permanent.</p>
        </div>

        <!-- Error Message -->
        <div v-if="errorMessage" class="mb-4 rounded-[20px] border border-theme-purgatory/25 bg-theme-purgatory/10 p-3 text-sm text-theme-purgatory-dark shadow-[0_10px_24px_rgba(168,93,50,0.08)]">
          {{ errorMessage }}
        </div>

        <!-- Step 1: PFP + Username -->
        <div class="identity-step mb-6">
          <!-- PFP Display -->
          <div class="flex justify-center mb-5">
            <div class="pfp-frame">
              <img :src="defaultPfpUrl" alt="Profile" class="pfp-image" />
            </div>
          </div>

          <!-- Username Field -->
          <div class="mb-4">
            <label for="identity-username" class="mb-1.5 block text-sm font-medium text-theme-text-dim">
              What should the Monk call you?
            </label>
            <input
              id="identity-username"
              v-model="username"
              type="text"
              required
              :maxlength="MAX_USERNAME_CHARS"
              :disabled="saving"
              class="form-field px-4 py-3 disabled:cursor-not-allowed disabled:opacity-50"
              placeholder="e.g., Pilgrim, Seeker, Acolyte..."
            />
            <div v-if="showUsernameCount" class="mt-1 text-right text-xs text-theme-text-muted">
              {{ username.length }} / {{ MAX_USERNAME_CHARS }}
            </div>
          </div>
        </div>

        <!-- Step 2: Sect Selection -->
        <div class="identity-step">
          <h3 class="mb-3 text-center text-lg font-semibold text-theme-text">Choose Your Sect</h3>
          <div class="grid gap-3 sm:grid-cols-2">
            <button
              v-for="sect in sects.sectList"
              :key="sect.key"
              @click="selectedSect = sect.key"
              :class="[
                'relative text-left p-4 rounded-[20px] border transition-all duration-[var(--dur-standard)]',
                selectedSect === sect.key
                  ? 'border-theme-accent/50 bg-theme-accent/10 shadow-[0_10px_28px_rgba(213,154,23,0.18)] scale-[1.01]'
                  : 'border-theme-border bg-theme-panel/50 hover:border-theme-accent/25 hover:bg-theme-accent/5 hover:scale-[1.005]'
              ]"
            >
              <div v-if="selectedSect === sect.key" class="absolute top-2 right-2 text-theme-accent text-sm font-bold">&#10003;</div>
              <div class="mb-1 text-2xl leading-none">{{ sect.icon }}</div>
              <h4 :class="['text-base font-semibold', sect.color]">{{ sect.name }}</h4>
              <p class="mt-0.5 text-xs text-theme-text-muted leading-relaxed">{{ sect.description }}</p>
            </button>
          </div>
          <p v-if="!selectedSect" class="mt-2 text-center text-xs text-theme-text-muted italic">
            Select a sect above to continue
          </p>
        </div>

        <!-- Submit Button -->
        <div class="mt-6 flex justify-center">
          <button
            @click="handleSubmit"
            :disabled="!canSubmit || saving || sects.choosing"
            class="btn-primary px-8 py-3 text-base"
          >
            <span class="relative z-10 font-medium">
              {{ saving || sects.choosing ? 'Swearing Vows...' : 'Swear the Vow' }}
            </span>
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<script setup>
import { ref, computed, watch } from 'vue'
import { useSects } from '@/composables/useSects'

const MAX_USERNAME_CHARS = 30
const COUNT_VISIBLE_THRESHOLD = 0.9

const defaultPfpUrl = '/pfp/0.png'

const props = defineProps({
  modelValue: Boolean,
  initialUsername: {
    type: String,
    default: null
  },
  saving: {
    type: Boolean,
    default: false
  },
  errorMessage: {
    type: String,
    default: null
  }
})

const emit = defineEmits(['update:modelValue', 'submitted'])

const sects = useSects()
const username = ref(props.initialUsername || '')
const selectedSect = ref(null)

const showUsernameCount = computed(() => {
  return username.value.length >= MAX_USERNAME_CHARS * COUNT_VISIBLE_THRESHOLD
})

const canSubmit = computed(() => {
  return username.value.trim().length >= 2 && selectedSect.value
})

// Reset form when modal opens
watch(() => props.modelValue, (newVal) => {
  if (newVal) {
    username.value = props.initialUsername || ''
    selectedSect.value = null
  }
})

async function handleSubmit() {
  if (!canSubmit.value) return

  // First: upsert the profile with username
  emit('submitted', {
    username: username.value.trim(),
    sectType: selectedSect.value
  })
}
</script>

<style scoped>
.identity-overlay {
  background:
    radial-gradient(circle at 50% 22%, rgba(255, 223, 147, 0.2), transparent 34%),
    linear-gradient(180deg, rgba(48, 38, 21, 0.62), rgba(48, 38, 21, 0.72));
  backdrop-filter: blur(12px);
  animation: overlay-fade var(--dur-enter) var(--ease-standard);
}

.identity-card {
  position: relative;
  animation: modal-rise var(--dur-enter) var(--ease-silk-settle);
}

.identity-card::after {
  content: "";
  position: absolute;
  inset: 1px;
  border-radius: calc(var(--radius-panel) - 1px);
  pointer-events: none;
  background: linear-gradient(180deg, rgba(255, 255, 255, 0.22), transparent 34%);
}

.pfp-frame {
  position: relative;
  width: 96px;
  height: 96px;
  border-radius: 12px;
  overflow: hidden;
  border: 3px solid var(--theme-accent);
  box-shadow:
    0 0 0 1px rgba(213, 154, 23, 0.3),
    0 4px 16px rgba(213, 154, 23, 0.2),
    inset 0 1px 0 rgba(255, 255, 255, 0.3);
  background: var(--theme-bg-soft);
}

.pfp-frame::before {
  content: "";
  position: absolute;
  inset: 0;
  z-index: 2;
  pointer-events: none;
  border-radius: 9px;
  box-shadow: inset 0 2px 8px rgba(0, 0, 0, 0.15);
}

.pfp-frame::after {
  content: "";
  position: absolute;
  top: 2px;
  left: 8px;
  right: 8px;
  height: 30%;
  z-index: 3;
  pointer-events: none;
  border-radius: 50%;
  background: linear-gradient(180deg, rgba(255, 255, 255, 0.35), transparent);
}

.pfp-image {
  width: 100%;
  height: 100%;
  object-fit: cover;
}
</style>