<template>
  <Teleport to="body">
    <div v-if="modelValue" class="username-overlay fixed inset-0 z-[9500] flex items-center justify-center px-4 py-6">
      <div class="username-card glass-panel glass-panel-strong glass-gloss max-w-md w-full p-6 sm:p-8">
        <!-- Header -->
        <div class="mb-6 text-center">
          <div class="username-avatar-shell mx-auto mb-4">
            <img
              src="/pfp/0.png"
              alt="Profile picture"
              aria-label="Current profile picture"
              class="username-avatar-image"
            />
          </div>
          <h2 class="ritual-heading mb-2 text-2xl font-bold text-theme-accent">Change Username</h2>
          <p class="text-sm text-theme-text-dim">This operation costs <span class="font-bold text-theme-accent">1,000 Karma</span>.</p>
        </div>

        <!-- Error Message -->
        <div v-if="error" class="mb-4 rounded-[20px] border border-theme-purgatory/25 bg-theme-purgatory/10 p-3 text-sm text-theme-purgatory-dark shadow-[0_10px_24px_rgba(168,93,50,0.08)]">
          {{ error }}
        </div>

        <!-- Success Message -->
        <div v-if="successMessage" class="mb-4 rounded-[20px] border border-green-500/25 bg-green-500/10 p-3 text-sm text-green-700 shadow-[0_10px_24px_rgba(34,197,94,0.08)]">
          {{ successMessage }}
        </div>

        <!-- Form -->
        <form @submit.prevent="handleSubmit" class="space-y-5">
          <!-- Current Username -->
          <div>
            <label class="mb-1.5 block text-sm font-medium text-theme-text-dim">
              Current username
            </label>
            <div class="form-field px-4 py-3 bg-theme-panel/30 text-theme-text-muted cursor-not-allowed">
              {{ currentUsername || 'Not set' }}
            </div>
          </div>

          <!-- New Username Field -->
          <div>
            <label for="new-username" class="mb-1.5 block text-sm font-medium text-theme-text-dim">
              New username
            </label>
            <input
              id="new-username"
              v-model="newUsername"
              type="text"
              required
              :maxlength="30"
              :disabled="submitting"
              class="form-field px-4 py-3 disabled:cursor-not-allowed disabled:opacity-50"
              placeholder="Enter your new name..."
            />
            <div class="mt-1 text-right text-xs text-theme-text-muted">
              {{ newUsername.length }} / 30
            </div>
          </div>

          <!-- Karma Cost Warning -->
          <div class="rounded-[16px] border border-theme-accent/20 bg-theme-accent/5 p-3 text-sm text-theme-text-dim">
            <div class="flex items-center gap-2">
              <span class="text-theme-accent font-bold">Cost:</span>
              <span>1,000 Karma will be deducted from your balance.</span>
            </div>
            <div class="mt-1 flex items-center gap-2">
              <span class="text-theme-text-muted">Your Karma:</span>
              <span class="font-semibold" :class="karmaBalance >= 1000 ? 'text-green-600' : 'text-red-500'">{{ karmaBalance }}</span>
            </div>
          </div>

          <!-- Buttons -->
          <div class="flex gap-3">
            <button
              type="button"
              @click="close"
              :disabled="submitting"
              class="btn-ghost flex-1 px-4 py-3"
            >
              <span class="relative z-10 font-medium">Cancel</span>
            </button>
            <button
              type="submit"
              :disabled="!canSubmit || submitting || karmaBalance < 1000"
              class="btn-primary flex-1 px-4 py-3"
            >
              <span class="relative z-10 font-medium">
                {{ submitting ? 'Changing...' : 'Confirm Change' }}
              </span>
            </button>
          </div>
        </form>
      </div>
    </div>
  </Teleport>
</template>

<script setup>
import { ref, computed } from 'vue'
import { supabase } from '@/lib/supabase'

const props = defineProps({
  modelValue: Boolean,
  currentUsername: {
    type: String,
    default: null
  },
  karmaBalance: {
    type: Number,
    default: 0
  }
})

const emit = defineEmits(['update:modelValue', 'changed'])

const newUsername = ref('')
const submitting = ref(false)
const error = ref(null)
const successMessage = ref(null)

const canSubmit = computed(() => {
  return newUsername.value.trim().length >= 2 && newUsername.value.trim() !== props.currentUsername
})

async function handleSubmit() {
  if (!canSubmit.value || submitting.value) return

  submitting.value = true
  error.value = null
  successMessage.value = null

  try {
    const { data, error: rpcError } = await supabase.rpc('change_username', {
      p_new_username: newUsername.value.trim()
    })

    if (rpcError) {
      // Map known error messages to user-friendly text
      const msg = rpcError.message || 'Unknown error'
      if (msg.includes('already exists')) {
        error.value = 'This username already exists!'
      } else if (msg.includes('Insufficient Karma')) {
        error.value = 'You need at least 1,000 Karma to change your username.'
      } else {
        error.value = msg
      }
      return
    }

    if (data?.success) {
      successMessage.value = `Username changed to "${data.new_username}"! Karma remaining: ${data.karma_remaining}`
      emit('changed', data.new_username, data.karma_remaining)
      // Close after a brief delay so the user sees the success message
      setTimeout(() => {
        close()
      }, 1500)
    }
  } catch (err) {
    error.value = err.message || 'An unexpected error occurred'
  } finally {
    submitting.value = false
  }
}

function close() {
  newUsername.value = ''
  error.value = null
  successMessage.value = null
  emit('update:modelValue', false)
}
</script>

<style scoped>
.username-overlay {
  background:
    radial-gradient(circle at 50% 22%, rgba(255, 223, 147, 0.2), transparent 34%),
    linear-gradient(180deg, rgba(48, 38, 21, 0.62), rgba(48, 38, 21, 0.72));
  backdrop-filter: blur(12px);
  animation: overlay-fade var(--dur-enter) var(--ease-standard);
}

.username-card {
  position: relative;
  animation: modal-rise var(--dur-enter) var(--ease-silk-settle);
}

.username-avatar-shell {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 5.75rem;
  height: 5.75rem;
  padding: 0.35rem;
  border-radius: 999px;
  border: 1px solid rgba(213, 154, 23, 0.24);
  background: linear-gradient(180deg, rgba(255, 253, 246, 0.92), rgba(248, 238, 214, 0.86));
  box-shadow: 0 18px 32px rgba(48, 38, 21, 0.1), 0 0 24px rgba(240, 182, 59, 0.08), inset 0 1px 0 rgba(255, 255, 255, 0.86);
}

.username-avatar-shell::before {
  content: "";
  position: absolute;
  inset: -0.6rem;
  border-radius: 999px;
  background: radial-gradient(circle, rgba(255, 223, 147, 0.24) 0%, rgba(255, 223, 147, 0.08) 44%, transparent 72%);
  filter: blur(10px);
  z-index: 0;
}

.username-avatar-image {
  position: relative;
  z-index: 1;
  width: 100%;
  height: 100%;
  object-fit: cover;
  border-radius: 999px;
  border: 1px solid rgba(255, 255, 255, 0.82);
  background: rgba(255, 252, 246, 0.9);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.9), 0 10px 20px rgba(48, 38, 21, 0.08);
}

.username-card::after {
  content: "";
  position: absolute;
  inset: 1px;
  border-radius: calc(var(--radius-panel) - 1px);
  pointer-events: none;
  background: linear-gradient(180deg, rgba(255, 255, 255, 0.22), transparent 34%);
}
</style>