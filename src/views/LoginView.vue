<template>
  <div class="app-frame flex min-h-screen flex-col items-center justify-center px-4 py-10 sm:py-14">
    <!-- Logo above login card -->
    <div class="mb-8 flex flex-col items-center sm:mb-10">
      <div class="login-logo-shell">
        <div class="login-logo-halo"></div>
        <div class="login-logo-disc"></div>
        <img src="@/assets/icons/icon.png" alt="Electric Monk" class="login-logo-image" />
      </div>
    </div>

    <div class="login-card max-w-md w-full glass-panel glass-panel-strong glass-gloss p-6 sm:p-8">
      <!-- Error Message -->
      <div v-if="auth.error && typeof auth.error === 'string' && auth.error.trim()" class="mb-5 rounded-sm border border-theme-purgatory/25 bg-theme-purgatory/10 p-3 text-sm text-theme-purgatory-dark shadow-[0_10px_24px_rgba(168,93,50,0.08)]">
        {{ auth.error }}
      </div>

      <!-- Success Message (Email Confirmation) -->
      <div v-if="auth.needsConfirmation" class="mb-5 rounded-sm border border-theme-accent/25 bg-theme-accent/10 p-3 text-sm text-theme-text-dim shadow-[0_10px_24px_rgba(213,154,23,0.08)]">
        <p class="mb-1 font-semibold text-theme-accent-dark">Account created successfully!</p>
        <p>Please check your email at <strong>{{ email }}</strong> and click the confirmation link to activate your account.</p>
        <p class="mt-2 text-xs text-theme-text-muted">After confirming, you can sign in below.</p>
      </div>

      <!-- Login Form -->
      <form @submit.prevent="handleLogin" class="space-y-5">
        <div class="space-y-1.5">
          <label for="email" class="block text-sm font-medium text-theme-text-dim">
            Email Address
          </label>
          <input
            id="email"
            v-model="email"
            type="email"
            required
            class="form-field px-4 py-3"
            placeholder="you@example.com"
          />
        </div>

        <div class="space-y-1.5">
          <label for="password" class="block text-sm font-medium text-theme-text-dim">
            Password
          </label>
          <input
            id="password"
            v-model="password"
            type="password"
            required
            class="form-field px-4 py-3"
            placeholder="••••••••"
          />
        </div>

        <button
          type="submit"
          :disabled="auth.loading"
          class="btn-primary w-full"
        >
          <span class="relative z-10 font-medium">
            {{ auth.loading ? 'Processing...' : (isSignUp ? 'Sign Up' : 'Sign In') }}
          </span>
        </button>
      </form>

      <!-- Divider -->
      <div class="relative my-7">
        <div class="absolute inset-0 flex items-center">
          <div class="w-full border-t surface-divider"></div>
        </div>
        <div class="relative flex justify-center text-sm">
          <span class="rounded-sm border border-white/40 bg-theme-panel/80 px-3 py-1 text-theme-text-dim shadow-[inset_0_1px_0_rgba(255,255,255,0.65)]">or</span>
        </div>
      </div>

      <!-- Google OAuth Button -->
      <button
        @click="handleGoogleSignIn"
        :disabled="auth.loading"
        class="btn-secondary flex w-full items-center justify-center gap-2"
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
          class="font-medium text-theme-accent transition-colors duration-200 hover:text-theme-accent-dark"
        >
          {{ isSignUp ? 'Sign In' : 'Sign Up' }}
        </button>
      </p>

      <!-- Password Recovery -->
      <p v-if="!isSignUp" class="mt-4 text-center text-sm text-theme-text-dim">
        <button
          @click="handlePasswordReset"
          class="text-theme-text-muted transition-colors duration-200 hover:text-theme-text"
        >
          Forgot your password?
        </button>
      </p>
    </div>

    <!-- Tagline below login card -->
    <div class="mt-8 text-center">
      <p class="text-sm italic text-theme-text-muted">Automated Prayers As A Service</p>
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
.login-card {
  position: relative;
}

.login-card::after {
  content: "";
  position: absolute;
  inset: 1px;
  border-radius: calc(var(--radius-panel) - 1px);
  pointer-events: none;
  background: linear-gradient(180deg, rgba(255, 255, 255, 0.18), transparent 28%);
  opacity: 0.9;
}

.login-logo-shell {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 14.5rem;
  height: 14.5rem;
}

.login-logo-halo {
  position: absolute;
  inset: 0;
  border-radius: 999px;
  background: radial-gradient(circle, rgba(255, 223, 147, 0.34) 0%, rgba(255, 223, 147, 0.12) 38%, transparent 72%);
  filter: blur(10px);
  animation: ritual-breathe 6s ease-in-out infinite;
}

.login-logo-disc {
  position: absolute;
  inset: 16%;
  border-radius: 999px;
  border: 1px solid rgba(255, 255, 255, 0.45);
  background: linear-gradient(180deg, rgba(255, 255, 255, 0.52), rgba(255, 248, 229, 0.18));
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.78), 0 18px 36px rgba(213, 154, 23, 0.12);
  backdrop-filter: blur(12px);
}

.login-logo-image {
  position: relative;
  z-index: 1;
  width: 12.5rem;
  height: 12.5rem;
  filter: drop-shadow(0 10px 24px rgba(213, 154, 23, 0.2));
}
</style>
