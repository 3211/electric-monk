<template>
  <div class="login-view flex-1 flex flex-col items-center justify-center px-4 py-4 sm:py-6 lg:py-10 min-h-0">
    <!-- Logo above login card -->
    <div class="mb-4 flex flex-col items-center sm:mb-6 lg:mb-8">
      <div class="login-logo-shell">
        <div class="login-logo-halo"></div>
        <img src="@/assets/icons/icon.png" alt="Holy War Online" class="login-logo-image" />
      </div>
      <h1 class="login-title ritual-heading mt-4 text-2xl font-bold sm:text-3xl"></h1>
    </div>

    <div class="login-card max-w-md w-full p-6 sm:p-8">
      <!-- Error Message -->
      <div v-if="auth.error && typeof auth.error === 'string' && auth.error.trim()" class="login-error mb-5 rounded-sm border border-war-enemy/25 bg-war-enemy/10 p-3 text-sm text-war-enemy-text shadow-[0_10px_24px_rgba(155,107,102,0.08)]">
        {{ auth.error }}
      </div>

      <!-- Success Message (Email Confirmation) -->
      <div v-if="auth.needsConfirmation" class="login-success mb-5 rounded-sm border border-war-steel/25 bg-war-steel/10 p-3 text-sm text-war-text shadow-[0_10px_24px_rgba(185,197,207,0.08)]">
        <p class="mb-1 font-semibold text-war-brass-light">Account created successfully!</p>
        <p>Please check your email at <strong>{{ email }}</strong> and click the confirmation link to activate your account.</p>
        <p class="mt-2 text-xs text-war-muted">After confirming, you can sign in below.</p>
      </div>

      <!-- Login Form -->
      <form @submit.prevent="handleLogin" class="space-y-5">
        <div class="space-y-1.5">
          <label for="email" class="block text-sm font-medium text-war-muted">
            Email Address
          </label>
          <input
            id="email"
            v-model="email"
            type="email"
            required
            class="login-field w-full px-4 py-3"
            placeholder="you@example.com"
          />
        </div>

        <!-- Local password validation error -->
        <div v-if="passwordError" class="login-error rounded-sm border border-war-enemy/25 bg-war-enemy/10 p-3 text-sm text-war-enemy-text shadow-[0_10px_24px_rgba(155,107,102,0.08)]">
          {{ passwordError }}
        </div>

        <!-- Sign‑in: single password -->
        <div v-if="!isSignUp" class="space-y-1.5">
          <label for="password" class="block text-sm font-medium text-war-muted">
            Password
          </label>
          <div class="relative">
            <input
              id="password"
              v-model="password"
              :type="showPassword ? 'text' : 'password'"
              required
              class="login-field w-full px-4 py-3 pr-11"
              placeholder="••••••••"
            />
            <button
              type="button"
              @click="showPassword = !showPassword"
              class="absolute right-3 top-1/2 -translate-y-1/2 text-war-muted hover:text-war-text transition-colors"
              tabindex="-1"
            >
              <svg v-if="!showPassword" class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"/></svg>
              <svg v-else class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M13.875 18.825A10.05 10.05 0 0112 19c-4.478 0-8.268-2.943-9.543-7a9.97 9.97 0 011.563-3.029m5.858.908a3 3 0 114.243 4.243M9.878 9.878l4.242 4.242M9.88 9.88l-3.29-3.29m7.532 7.532l3.29 3.29M3 3l3.59 3.59m0 0A9.953 9.953 0 0112 5c4.478 0 8.268 2.943 9.543 7a10.025 10.025 0 01-4.132 5.411m0 0L21 21"/></svg>
            </button>
          </div>
        </div>

        <!-- Sign‑up: two passwords -->
        <template v-if="isSignUp">
          <div class="space-y-1.5">
            <label for="password" class="block text-sm font-medium text-war-muted">
              Password
            </label>
            <div class="relative">
              <input
                id="password"
                v-model="password"
                :type="showPassword ? 'text' : 'password'"
                required
                class="login-field w-full px-4 py-3 pr-11"
                placeholder="••••••••"
              />
              <button
                type="button"
                @click="showPassword = !showPassword"
                class="absolute right-3 top-1/2 -translate-y-1/2 text-war-muted hover:text-war-text transition-colors"
                tabindex="-1"
              >
                <svg v-if="!showPassword" class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"/></svg>
                <svg v-else class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M13.875 18.825A10.05 10.05 0 0112 19c-4.478 0-8.268-2.943-9.543-7a9.97 9.97 0 011.563-3.029m5.858.908a3 3 0 114.243 4.243M9.878 9.878l4.242 4.242M9.88 9.88l-3.29-3.29m7.532 7.532l3.29 3.29M3 3l3.59 3.59m0 0A9.953 9.953 0 0112 5c4.478 0 8.268 2.943 9.543 7a10.025 10.025 0 01-4.132 5.411m0 0L21 21"/></svg>
              </button>
            </div>
          </div>
          <div class="space-y-1.5">
            <label for="confirm-password" class="block text-sm font-medium text-war-muted">
              Confirm Password
            </label>
            <div class="relative">
              <input
                id="confirm-password"
                v-model="confirmPassword"
                :type="showPassword ? 'text' : 'password'"
                required
                class="login-field w-full px-4 py-3 pr-11"
                placeholder="••••••••"
              />
              <button
                type="button"
                @click="showPassword = !showPassword"
                class="absolute right-3 top-1/2 -translate-y-1/2 text-war-muted hover:text-war-text transition-colors"
                tabindex="-1"
              >
                <svg v-if="!showPassword" class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"/></svg>
                <svg v-else class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M13.875 18.825A10.05 10.05 0 0112 19c-4.478 0-8.268-2.943-9.543-7a9.97 9.97 0 011.563-3.029m5.858.908a3 3 0 114.243 4.243M9.878 9.878l4.242 4.242M9.88 9.88l-3.29-3.29m7.532 7.532l3.29 3.29M3 3l3.59 3.59m0 0A9.953 9.953 0 0112 5c4.478 0 8.268 2.943 9.543 7a10.025 10.025 0 01-4.132 5.411m0 0L21 21"/></svg>
              </button>
            </div>
          </div>
        </template>

        <button
          type="submit"
          :disabled="auth.loading"
          class="login-btn-primary w-full"
        >
          <span class="relative z-10 font-medium">
            {{ auth.loading ? 'Processing...' : (isSignUp ? 'Sign Up' : 'Sign In') }}
          </span>
        </button>
      </form>

      <!-- Divider & Google OAuth (sign‑in only) -->
      <template v-if="!isSignUp">
        <div class="relative my-7">
          <div class="absolute inset-0 flex items-center">
            <div class="w-full border-t border-war-edge"></div>
          </div>
          <div class="relative flex justify-center text-sm">
            <span class="login-divider-chip rounded-sm border border-white/40 px-3 py-1 text-war-muted shadow-[inset_0_1px_0_rgba(255,255,255,0.65)]">or</span>
          </div>
        </div>

        <!-- Google OAuth Button -->
        <button
          @click="handleGoogleSignIn"
          :disabled="auth.loading"
          class="login-btn-secondary flex w-full items-center justify-center gap-2"
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
      </template>

      <!-- Sign Up Toggle -->
      <p class="mt-6 text-center text-sm text-war-muted">
        {{ isSignUp ? 'Already have an account?' : "Don't have an account?" }}
        <button
          @click="toggleAuthMode()"
          class="font-medium text-war-brass transition-colors duration-200 hover:text-war-brass-light"
        >
          {{ isSignUp ? 'Sign In' : 'Sign Up' }}
        </button>
      </p>

      <!-- Password Recovery -->
      <p v-if="!isSignUp" class="mt-4 text-center text-sm text-war-muted">
        <button
          @click="handlePasswordReset"
          class="text-war-dim transition-colors duration-200 hover:text-war-text"
        >
          Forgot your password?
        </button>
      </p>
    </div>

    <!-- Tagline below login card -->
    <div class="mt-4 sm:mt-6 text-center">
      <p class="text-sm italic text-war-dim">Holy War Online</p>
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
const confirmPassword = ref('')
const passwordError = ref('')
const showPassword = ref(false)

function validatePassword() {
  passwordError.value = ''

  if (password.value.length < 4) {
    passwordError.value = 'Password must be at least 4 characters.'
    return false
  }
  if (password.value.length > 32) {
    passwordError.value = 'Password must be no more than 32 characters.'
    return false
  }
  if (isSignUp.value && password.value !== confirmPassword.value) {
    passwordError.value = 'Passwords do not match.'
    return false
  }

  return true
}

function toggleAuthMode() {
  isSignUp.value = !isSignUp.value
  passwordError.value = ''
  confirmPassword.value = ''
  auth.error = null
}

async function handleLogin() {
  if (!validatePassword()) return

  try {
    if (isSignUp.value) {
      await auth.signUp(email.value, password.value)
      isSignUp.value = false
      password.value = ''
      confirmPassword.value = ''
      passwordError.value = ''
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
/* ─── War theme local variables (supplements shell) ─── */
.login-view {
  --war-enemy-text: #e0c1be;
}

/* ─── Title ─── */
.login-title {
  color: var(--war-steel);
  text-shadow: 0 0 24px rgba(185, 197, 207, 0.08);
}

/* ─── Logo ─── */
.login-logo-shell {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
  width: clamp(8rem, 22vw, 14.5rem);
  height: clamp(8rem, 22vw, 14.5rem);
}

.login-logo-halo {
  position: absolute;
  inset: 0;
  border-radius: 999px;
  background: radial-gradient(circle, rgba(185, 197, 207, 0.22) 0%, rgba(182, 144, 91, 0.08) 38%, transparent 72%);
  filter: blur(10px);
  animation: war-logo-breathe 6s ease-in-out infinite;
}

.login-logo-image {
  position: relative;
  z-index: 1;
  width: clamp(7rem, 19vw, 12.5rem);
  height: clamp(7rem, 19vw, 12.5rem);
  filter: drop-shadow(0 10px 24px rgba(0, 0, 0, 0.4));
}

@keyframes war-logo-breathe {
  0%, 100% {
    opacity: 0.85;
    transform: scale(1);
  }
  50% {
    opacity: 1;
    transform: scale(1.035);
  }
}

/* ─── Login Card ─── */
.login-card {
  position: relative;
  border-radius: var(--radius-panel, 2px);
  border: 1px solid var(--war-edge);
  background:
    linear-gradient(180deg, rgba(255, 255, 255, 0.06), rgba(255, 255, 255, 0.02) 26%, rgba(255, 255, 255, 0.01) 100%),
    linear-gradient(145deg, rgba(28, 35, 43, 0.92), rgba(18, 24, 30, 0.96) 56%, rgba(13, 18, 23, 0.98));
  box-shadow:
    0 28px 48px rgba(0, 0, 0, 0.34),
    inset 0 1px 0 rgba(255, 255, 255, 0.07),
    inset 0 -1px 0 rgba(255, 255, 255, 0.025);
  backdrop-filter: blur(12px);
  color: var(--war-text);
}

.login-card::after {
  content: "";
  position: absolute;
  inset: 1px;
  border-radius: calc(var(--radius-panel, 2px) - 1px);
  pointer-events: none;
  background:
    linear-gradient(125deg, rgba(255, 255, 255, 0.035), transparent 22%, transparent 78%, rgba(255, 255, 255, 0.02)),
    repeating-linear-gradient(135deg, rgba(255, 255, 255, 0.012) 0 1px, transparent 1px 12px);
  opacity: 0.95;
}

/* ─── Error ─── */
.login-error {
  color: var(--war-enemy-text);
}

/* ─── Success ─── */
.login-success {
  border-color: rgba(185, 197, 207, 0.25);
  background: rgba(185, 197, 207, 0.1);
}

/* ─── Form Fields ─── */
.login-field {
  min-height: 3rem;
  border-radius: var(--radius-field, 1px);
  border: 1px solid rgba(164, 176, 189, 0.18);
  background: linear-gradient(180deg, rgba(16, 21, 27, 0.96), rgba(24, 31, 39, 0.86));
  color: var(--war-text);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.06), 0 10px 20px rgba(0, 0, 0, 0.2);
  transition:
    border-color 220ms ease,
    background 220ms ease,
    box-shadow 220ms ease;
}

.login-field::placeholder {
  color: rgba(130, 145, 160, 0.72);
}

.login-field:hover {
  border-color: rgba(185, 197, 207, 0.22);
  background: linear-gradient(180deg, rgba(18, 24, 31, 0.98), rgba(28, 35, 43, 0.92));
}

.login-field:focus {
  outline: none;
  border-color: rgba(185, 197, 207, 0.4);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.06), 0 0 0 4px rgba(185, 197, 207, 0.1), 0 16px 28px rgba(0, 0, 0, 0.28);
}

/* ─── Primary Button ─── */
.login-btn-primary {
  position: relative;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  cursor: pointer;
  min-height: 2.875rem;
  padding: 0.8rem 1.35rem;
  border-radius: var(--radius-button, 2px);
  border: 1px solid rgba(182, 144, 91, 0.34);
  color: #e9d6b5;
  font-family: var(--font-ui, "JetBrains Mono", monospace);
  text-transform: uppercase;
  letter-spacing: 0.05em;
  font-weight: 700;
  background:
    linear-gradient(180deg, rgba(182, 144, 91, 0.14), rgba(255, 255, 255, 0) 30%),
    linear-gradient(180deg, #8b6d3f, #6b5028 52%, #8b6d3f 100%);
  box-shadow: 0 18px 34px rgba(0, 0, 0, 0.28), 0 8px 18px rgba(0, 0, 0, 0.22), inset 0 1px 0 rgba(255, 255, 255, 0.18);
  transform: translateY(0) scale(1);
  transition:
    transform 220ms cubic-bezier(0.22, 1, 0.36, 1),
    box-shadow 220ms ease,
    filter 220ms ease;
}

.login-btn-primary::before {
  content: "";
  position: absolute;
  inset: 0;
  background: linear-gradient(120deg, transparent 16%, rgba(255, 255, 255, 0.28) 38%, transparent 60%);
  transform: translateX(-130%);
  transition: transform 720ms cubic-bezier(0.16, 1, 0.3, 1);
  pointer-events: none;
}

.login-btn-primary:hover {
  transform: translateY(-2px) scale(1.01);
  box-shadow: 0 24px 40px rgba(0, 0, 0, 0.34), 0 10px 24px rgba(0, 0, 0, 0.26), 0 0 34px rgba(182, 144, 91, 0.12);
  filter: saturate(1.04) brightness(1.03);
}

.login-btn-primary:hover::before {
  transform: translateX(140%);
}

.login-btn-primary:active {
  transform: translateY(1px) scale(0.985);
  transition-duration: 140ms;
  box-shadow: 0 12px 20px rgba(0, 0, 0, 0.24), 0 4px 10px rgba(0, 0, 0, 0.2), inset 0 1px 0 rgba(255, 255, 255, 0.12);
  filter: brightness(0.97);
}

.login-btn-primary:disabled {
  cursor: not-allowed;
  opacity: 0.56;
  filter: saturate(0.7);
  transform: none;
  box-shadow: 0 10px 18px rgba(0, 0, 0, 0.18), inset 0 1px 0 rgba(255, 255, 255, 0.05);
}

/* ─── Secondary Button ─── */
.login-btn-secondary {
  position: relative;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  cursor: pointer;
  min-height: 2.75rem;
  padding: 0.75rem 1.2rem;
  border-radius: var(--radius-button, 2px);
  border: 1px solid rgba(164, 176, 189, 0.2);
  color: var(--war-text);
  font-family: var(--font-ui, "JetBrains Mono", monospace);
  text-transform: uppercase;
  letter-spacing: 0.05em;
  font-weight: 700;
  background: linear-gradient(180deg, rgba(33, 40, 49, 0.94), rgba(20, 26, 33, 0.96));
  box-shadow: 0 14px 28px rgba(0, 0, 0, 0.3), inset 0 1px 0 rgba(255, 255, 255, 0.06);
  backdrop-filter: blur(12px);
  transition:
    transform 220ms cubic-bezier(0.22, 1, 0.36, 1),
    border-color 220ms ease,
    box-shadow 220ms ease,
    background 220ms ease;
}

.login-btn-secondary::before {
  content: "";
  position: absolute;
  inset: 0;
  background: linear-gradient(120deg, transparent 16%, rgba(255, 255, 255, 0.28) 38%, transparent 60%);
  transform: translateX(-130%);
  transition: transform 720ms cubic-bezier(0.16, 1, 0.3, 1);
  pointer-events: none;
}

.login-btn-secondary:hover {
  transform: translateY(-2px);
  border-color: rgba(188, 198, 208, 0.24);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.1),
    0 18px 28px rgba(0, 0, 0, 0.28),
    0 0 0 1px rgba(255, 255, 255, 0.03);
}

.login-btn-secondary:hover::before {
  transform: translateX(140%);
}

.login-btn-secondary:disabled {
  cursor: not-allowed;
  opacity: 0.56;
  transform: none;
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.05);
}

/* ─── Divider Chip ─── */
.login-divider-chip {
  background: rgba(24, 31, 39, 0.8);
}

/* ─── Utility Classes ─── */
.text-war-brass {
  color: var(--war-brass);
}

.text-war-brass-light {
  color: var(--war-brass-light);
}

.text-war-enemy-text {
  color: var(--war-enemy-text);
}

.text-war-muted {
  color: var(--war-muted);
}

.text-war-dim {
  color: var(--war-dim);
}

.text-war-text {
  color: var(--war-text);
}

.border-war-edge {
  border-color: var(--war-edge);
}

.border-war-enemy\/25 {
  border-color: rgba(155, 107, 102, 0.25);
}

.bg-war-enemy\/10 {
  background-color: rgba(155, 107, 102, 0.1);
}

.border-war-steel\/25 {
  border-color: rgba(185, 197, 207, 0.25);
}

.bg-war-steel\/10 {
  background-color: rgba(185, 197, 207, 0.1);
}
</style>