<template>
  <div class="flex items-center justify-center bg-theme-wash px-4 py-8">
    <div class="max-w-md w-full glass-panel glass-gloss p-8">
      <!-- Header -->
      <div class="text-center mb-8">
        <h1 class="text-4xl font-bold text-theme-accent mb-2">Electric Monk</h1>
        <p class="text-theme-text-dim">Automated Prayers As A Service</p>
      </div>

      <!-- Error Message -->
      <div v-if="auth.error && typeof auth.error === 'string' && auth.error.trim()" class="mb-4 p-3 bg-theme-purgatory/20 border border-theme-purgatory rounded text-theme-purgatory-dark text-sm glass-gloss">
        {{ auth.error }}
      </div>

      <!-- Success Message (Email Confirmation) -->
      <div v-if="auth.needsConfirmation" class="mb-4 p-3 bg-green-900/20 border border-green-700/50 rounded text-green-800 text-sm glass-gloss">
        <p class="font-semibold mb-1">Account created successfully!</p>
        <p>Please check your email at <strong>{{ email }}</strong> and click the confirmation link to activate your account.</p>
        <p class="mt-2 text-xs text-green-700">After confirming, you can sign in below.</p>
      </div>

      <!-- Login Form -->
      <form @submit.prevent="handleLogin" class="space-y-4">
        <div>
          <label for="email" class="block text-sm font-medium text-theme-text-dim mb-1">
            Email Address
          </label>
          <input
            id="email"
            v-model="email"
            type="email"
            required
            class="w-full px-4 py-2 bg-theme-panel border border-theme-border rounded text-theme-text placeholder-theme-text-muted focus:outline-none focus:border-theme-accent focus:ring-1 focus:ring-theme-accent transition-colors"
            placeholder="you@example.com"
          />
        </div>

        <div>
          <label for="password" class="block text-sm font-medium text-theme-text-dim mb-1">
            Password
          </label>
          <input
            id="password"
            v-model="password"
            type="password"
            required
            class="w-full px-4 py-2 bg-theme-panel border border-theme-border rounded text-theme-text placeholder-theme-text-muted focus:outline-none focus:border-theme-accent focus:ring-1 focus:ring-theme-accent transition-colors"
            placeholder="••••••••"
          />
        </div>

        <button
          type="submit"
          :disabled="auth.loading"
          class="w-full py-3 px-4 btn-primary disabled:cursor-not-allowed transition-all duration-150 ease-out"
        >
          <span class="relative z-10 font-medium">
            {{ auth.loading ? 'Processing...' : (isSignUp ? 'Sign Up' : 'Sign In') }}
          </span>
        </button>
      </form>

      <!-- Divider -->
      <div class="relative my-6">
        <div class="absolute inset-0 flex items-center">
          <div class="w-full border-t border-theme-border"></div>
        </div>
        <div class="relative flex justify-center text-sm">
          <span class="px-2 bg-theme-panel text-theme-text-dim">or</span>
        </div>
      </div>

      <!-- Google OAuth Button -->
      <button
        @click="handleGoogleSignIn"
        :disabled="auth.loading"
        class="w-full py-3 px-4 btn-subtle disabled:cursor-not-allowed transition-all duration-150 ease-out flex items-center justify-center gap-2"
      >
        <svg class="w-5 h-5" viewBox="0 0 24 24">
          <path fill="currentColor" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
          <path fill="currentColor" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
          <path fill="currentColor" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
          <path fill="currentColor" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
        </svg>
        <span class="relative z-10 font-medium">
          {{ auth.loading ? 'Processing...' : 'Continue with Google' }}
        </span>
      </button>

      <!-- Sign Up Toggle -->
      <p class="mt-6 text-center text-sm text-theme-text-dim">
        {{ isSignUp ? 'Already have an account?' : "Don't have an account?" }}
        <button
          @click="isSignUp = !isSignUp"
          class="text-theme-accent hover:text-theme-accent-dark font-medium transition-colors"
        >
          {{ isSignUp ? 'Sign In' : 'Sign Up' }}
        </button>
      </p>

      <!-- Password Recovery -->
      <p v-if="!isSignUp" class="mt-4 text-center text-sm text-theme-text-dim">
        <button
          @click="handlePasswordReset"
          class="text-theme-text-muted hover:text-theme-text transition-colors"
        >
          Forgot your password?
        </button>
      </p>
    </div>

    <!-- Icon below login panel -->
    <div class="mt-6 flex flex-col items-center">
      <img src="@/assets/icons/icon.png" alt="Electric Monk" class="w-[75px] h-[75px]" />
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { useAuth } from '@/composables/useAuth'

const auth = useAuth()
const isSignUp = ref(false)
const email = ref('')
const password = ref('')

async function handleLogin() {
  try {
    if (isSignUp.value) {
      await auth.signUp(email.value, password.value)
      // Success: switch to sign-in mode - needsConfirmation state is handled by useAuth
      isSignUp.value = false
      password.value = '' // Clear password for security
    } else {
      await auth.signIn(email.value, password.value)
    }
  } catch (err) {
    // Error is already captured in auth.error
  }
}

async function handleGoogleSignIn() {
  try {
    await auth.signInWithGoogle()
  } catch (err) {
    // Error is already captured in auth.error
  }
}

async function handlePasswordReset() {
  if (!email.value) {
    auth.error = 'Please enter your email address first'
    return
  }
  
  try {
    await auth.resetPassword(email.value)
    auth.error = null
    alert('Password reset email sent! Check your inbox.')
  } catch (err) {
    // Error is already captured in auth.error
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

/* Subtle button variant */
.btn-subtle {
  @apply relative overflow-hidden font-sans rounded-btn px-4 py-3 border shadow-inner-top glass-gloss active:translate-y-0 transition-all duration-150 ease-out cursor-pointer;
  color: var(--theme-text);
  border-color: rgba(139, 125, 91, 0.2);
  background: linear-gradient(180deg, rgba(255, 255, 255, 0.4), rgba(255, 255, 255, 0.15));
}

.btn-subtle:hover {
  background: linear-gradient(180deg, rgba(255, 255, 255, 0.6), rgba(255, 255, 255, 0.25));
  border-color: rgba(139, 125, 91, 0.3);
  transform: translateY(-1px);
}

.btn-subtle:disabled {
  background: linear-gradient(180deg, rgba(255, 255, 255, 0.2), rgba(255, 255, 255, 0.08));
  cursor: not-allowed;
}
</style>
