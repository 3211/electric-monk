<template>
  <div v-if="modelValue" class="profile-modal-overlay fixed inset-0 z-50 flex items-center justify-center px-4 py-6">
    <div class="profile-modal-card glass-panel glass-panel-strong glass-gloss max-w-md w-full p-6 sm:p-8">
      <!-- Header -->
      <div class="mb-6 text-center">
        <h2 class="ritual-heading mb-2 text-3xl font-bold text-theme-accent">Identify Yourself</h2>
        <p class="text-sm text-theme-text-dim">Before you can submit prayers, the Electric Monk must know how to address you.</p>
      </div>

      <!-- Error Message -->
      <div v-if="errorMessage" class="mb-4 rounded-[20px] border border-theme-purgatory/25 bg-theme-purgatory/10 p-3 text-sm text-theme-purgatory-dark shadow-[0_10px_24px_rgba(168,93,50,0.08)]">
        {{ errorMessage }}
      </div>

      <!-- Form -->
      <form @submit.prevent="handleSubmit" class="space-y-5">
        <!-- Username Field -->
        <div>
          <label for="username" class="mb-1.5 block text-sm font-medium text-theme-text-dim">
            What should the Monk call you?
          </label>
          <input
            id="username"
            v-model="username"
            type="text"
            required
            :maxlength="MAX_USERNAME_CHARS"
            :disabled="saving"
            class="form-field px-4 py-3 disabled:cursor-not-allowed disabled:opacity-50"
            placeholder="e.g., Child of the Circuit, Pilgrim, Seeker..."
          />
          <div v-if="showUsernameCount" class="mt-1 text-right text-xs text-theme-text-muted">
            {{ username.length }} / {{ MAX_USERNAME_CHARS }}
          </div>
        </div>

        <!-- Faith Field -->
        <div>
          <label for="faith" class="mb-1.5 block text-sm font-medium text-theme-text-dim">
            What is your faith?
          </label>
          <input
            id="faith"
            v-model="faith"
            type="text"
            required
            :maxlength="MAX_FAITH_CHARS"
            :disabled="saving"
            class="form-field px-4 py-3 disabled:cursor-not-allowed disabled:opacity-50"
            placeholder="e.g., Church of the Sacred Current, Digital Buddhism, Jedi..."
          />
          <div v-if="showFaithCount" class="mt-1 text-right text-xs text-theme-text-muted">
            {{ faith.length }} / {{ MAX_FAITH_CHARS }}
          </div>
        </div>

        <!-- Submit Button -->
        <button
          type="submit"
          :disabled="!canSubmit || saving"
          class="btn-primary w-full"
        >
          <span class="relative z-10 font-medium">
            {{ saving ? 'Saving...' : 'Submit Identity' }}
          </span>
        </button>
      </form>

      <!-- Info Text -->
      <p class="mt-4 text-center text-xs text-theme-text-muted">
        You can update these details later in your profile settings.
      </p>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, watch } from 'vue'

// Character limits
const MAX_USERNAME_CHARS = 50
const MAX_FAITH_CHARS = 100
const COUNT_VISIBLE_THRESHOLD = 0.9 // Show count when at 90% of max

const props = defineProps({
  modelValue: Boolean,
  initialUsername: {
    type: String,
    default: null
  },
  initialFaith: {
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

const username = ref(props.initialUsername || '')
const faith = ref(props.initialFaith || '')

// Computed for showing character counts only when near limit
const showUsernameCount = computed(() => {
  return username.value.length >= MAX_USERNAME_CHARS * COUNT_VISIBLE_THRESHOLD
})

const showFaithCount = computed(() => {
  return faith.value.length >= MAX_FAITH_CHARS * COUNT_VISIBLE_THRESHOLD
})

const canSubmit = computed(() => {
  return username.value.trim() && faith.value.trim()
})

// Reset form when modal opens
watch(() => props.modelValue, (newVal) => {
  if (newVal) {
    username.value = props.initialUsername || ''
    faith.value = props.initialFaith || ''
  }
})

function handleSubmit() {
  // Just emit — the parent handles the async save, loading state, and closing
  emit('submitted', {
    username: username.value.trim(),
    faith: faith.value.trim()
  })
}
</script>

<style scoped>
.profile-modal-overlay {
  background:
    radial-gradient(circle at 50% 22%, rgba(255, 223, 147, 0.2), transparent 34%),
    linear-gradient(180deg, rgba(48, 38, 21, 0.62), rgba(48, 38, 21, 0.72));
  backdrop-filter: blur(12px);
  animation: overlay-fade var(--dur-enter) var(--ease-standard);
}

.profile-modal-card {
  position: relative;
  animation: modal-rise var(--dur-enter) var(--ease-silk-settle);
}

.profile-modal-card::after {
  content: "";
  position: absolute;
  inset: 1px;
  border-radius: calc(var(--radius-panel) - 1px);
  pointer-events: none;
  background: linear-gradient(180deg, rgba(255, 255, 255, 0.22), transparent 34%);
}
</style>