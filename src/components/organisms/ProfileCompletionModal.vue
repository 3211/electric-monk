<template>
  <div v-if="modelValue" class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm">
    <div class="glass-panel glass-gloss p-8 max-w-md w-full mx-4 border-2 border-theme-accent">
      <!-- Header -->
      <div class="text-center mb-6">
        <h2 class="text-2xl font-bold text-theme-accent mb-2">Identify Yourself</h2>
        <p class="text-theme-text-dim text-sm">Before you can submit prayers, the Electric Monk must know how to address you.</p>
      </div>

      <!-- Error Message -->
      <div v-if="error" class="mb-4 p-3 bg-theme-purgatory/20 border border-theme-purgatory rounded text-theme-purgatory-dark text-sm glass-gloss">
        {{ error }}
      </div>

      <!-- Form -->
      <form @submit.prevent="handleSubmit" class="space-y-5">
        <!-- Username Field -->
        <div>
          <label for="username" class="block text-sm font-medium text-theme-text-dim mb-1">
            What should the Monk call you?
          </label>
          <input
            id="username"
            v-model="username"
            type="text"
            required
            :maxlength="MAX_USERNAME_CHARS"
            class="w-full px-4 py-2 bg-theme-panel border border-theme-border rounded text-theme-text placeholder-theme-text-muted focus:outline-none focus:border-theme-accent focus:ring-1 focus:ring-theme-accent transition-colors"
            placeholder="e.g., Child of the Circuit, Pilgrim, Seeker..."
          />
          <div v-if="showUsernameCount" class="mt-1 text-xs text-theme-text-muted text-right">
            {{ username.length }} / {{ MAX_USERNAME_CHARS }}
          </div>
        </div>

        <!-- Faith Field -->
        <div>
          <label for="faith" class="block text-sm font-medium text-theme-text-dim mb-1">
            What is your faith?
          </label>
          <input
            id="faith"
            v-model="faith"
            type="text"
            required
            :maxlength="MAX_FAITH_CHARS"
            class="w-full px-4 py-2 bg-theme-panel border border-theme-border rounded text-theme-text placeholder-theme-text-muted focus:outline-none focus:border-theme-accent focus:ring-1 focus:ring-theme-accent transition-colors"
            placeholder="e.g., Church of the Sacred Current, Digital Buddhism, Jedi..."
          />
          <div v-if="showFaithCount" class="mt-1 text-xs text-theme-text-muted text-right">
            {{ faith.length }} / {{ MAX_FAITH_CHARS }}
          </div>
        </div>

        <!-- Submit Button -->
        <button
          type="submit"
          :disabled="!canSubmit || loading"
          class="w-full py-3 px-4 btn-primary disabled:cursor-not-allowed transition-all duration-150 ease-out"
        >
          <span class="relative z-10 font-medium">
            {{ loading ? 'Saving...' : 'Submit Identity' }}
          </span>
        </button>
      </form>

      <!-- Info Text -->
      <p class="mt-4 text-xs text-theme-text-muted text-center">
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
  }
})

const emit = defineEmits(['update:modelValue', 'submitted'])

const username = ref(props.initialUsername || '')
const faith = ref(props.initialFaith || '')
const loading = ref(false)
const error = ref(null)

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
    error.value = null
  }
})

async function handleSubmit() {
  try {
    loading.value = true
    error.value = null

    // Emit event to parent to handle the actual save
    emit('submitted', {
      username: username.value.trim(),
      faith: faith.value.trim()
    })
  } catch (err) {
    error.value = err.message
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
/* Primary button with gold gradient */
.btn-primary {
  @apply relative overflow-hidden font-sans rounded-btn px-4 py-3 border shadow-inner-top glass-gloss active:translate-y-0 transition-all duration-150 ease-out cursor-pointer;
  color: white;
  border-color: color-mix(in srgb, var(--theme-accent) 55%, white 10%);
  box-shadow: 0 18px 30px color-mix(in srgb, var(--theme-accent) 28%, transparent);
  background: linear-gradient(
    180deg,
    color-mix(in srgb, var(--theme-accent) 34%, white 12%),
    color-mix(in srgb, var(--theme-accent-2) 72%, black 15%)
  );
}

.btn-primary:hover {
  transform: translateY(-1px);
}

.btn-primary:disabled {
  background: linear-gradient(
    180deg,
    color-mix(in srgb, var(--theme-accent) 20%, gray 30%),
    color-mix(in srgb, var(--theme-accent-dark) 40%, gray 40%)
  );
}
</style>
