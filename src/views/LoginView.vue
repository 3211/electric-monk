<template>
  <div class="min-h-screen flex items-center justify-center bg-gradient-to-b from-gray-900 to-gray-800 px-4">
    <div class="max-w-md w-full bg-gray-800 rounded-lg shadow-xl p-8 border border-gray-700">
      <!-- Header -->
      <div class="text-center mb-8">
        <h1 class="text-4xl font-bold text-amber-500 mb-2">Electric Monk</h1>
        <p class="text-gray-400">Automated prayers for the digital age</p>
      </div>

      <!-- Error Message -->
      <div v-if="auth.error && typeof auth.error === 'string' && auth.error.trim()" class="mb-4 p-3 bg-red-900/50 border border-red-700 rounded text-red-200 text-sm">
        {{ auth.error }}
      </div>

      <!-- Success Message (Email Confirmation) -->
      <div v-if="signupSuccess" class="mb-4 p-3 bg-green-900/50 border border-green-700 rounded text-green-200 text-sm">
        <p class="font-semibold mb-1">Account created successfully!</p>
        <p>Please check your email at <strong>{{ email }}</strong> and click the confirmation link to activate your account.</p>
        <p class="mt-2 text-xs text-green-300">After confirming, you can sign in below.</p>
      </div>

      <!-- Login Form -->
      <form @submit.prevent="handleLogin" class="space-y-4">
        <div>
          <label for="email" class="block text-sm font-medium text-gray-300 mb-1">
            Email Address
          </label>
          <input
            id="email"
            v-model="email"
            type="email"
            required
            class="w-full px-4 py-2 bg-gray-900 border border-gray-700 rounded text-white placeholder-gray-500 focus:outline-none focus:border-amber-500 focus:ring-1 focus:ring-amber-500"
            placeholder="you@example.com"
          />
        </div>

        <div>
          <label for="password" class="block text-sm font-medium text-gray-300 mb-1">
            Password
          </label>
          <input
            id="password"
            v-model="password"
            type="password"
            required
            class="w-full px-4 py-2 bg-gray-900 border border-gray-700 rounded text-white placeholder-gray-500 focus:outline-none focus:border-amber-500 focus:ring-1 focus:ring-amber-500"
            placeholder="••••••••"
          />
        </div>

        <button
          type="submit"
          :disabled="auth.loading"
          class="w-full py-3 px-4 bg-amber-600 hover:bg-amber-700 disabled:bg-amber-800 disabled:cursor-not-allowed text-white font-semibold rounded transition-colors"
        >
          {{ auth.loading ? 'Processing...' : (isSignUp ? 'Sign Up' : 'Sign In') }}
        </button>
      </form>

      <!-- Divider -->
      <div class="relative my-6">
        <div class="absolute inset-0 flex items-center">
          <div class="w-full border-t border-gray-700"></div>
        </div>
        <div class="relative flex justify-center text-sm">
          <span class="px-2 bg-gray-800 text-gray-400">or</span>
        </div>
      </div>

      <!-- Google OAuth Button -->
      <button
        @click="handleGoogleSignIn"
        :disabled="auth.loading"
        class="w-full py-3 px-4 bg-white hover:bg-gray-100 disabled:bg-gray-300 disabled:cursor-not-allowed text-gray-900 font-semibold rounded transition-colors flex items-center justify-center gap-2"
      >
        <svg class="w-5 h-5" viewBox="0 0 24 24">
          <path fill="currentColor" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
          <path fill="currentColor" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
          <path fill="currentColor" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
          <path fill="currentColor" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
        </svg>
        {{ auth.loading ? 'Processing...' : 'Continue with Google' }}
      </button>

      <!-- Sign Up Toggle -->
      <p class="mt-6 text-center text-sm text-gray-400">
        {{ isSignUp ? 'Already have an account?' : "Don't have an account?" }}
        <button
          @click="isSignUp = !isSignUp"
          class="text-amber-500 hover:text-amber-400 font-medium"
        >
          {{ isSignUp ? 'Sign In' : 'Sign Up' }}
        </button>
      </p>

      <!-- Password Recovery -->
      <p v-if="!isSignUp" class="mt-4 text-center text-sm text-gray-400">
        <button
          @click="handlePasswordReset"
          class="text-gray-500 hover:text-gray-300"
        >
          Forgot your password?
        </button>
      </p>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { useAuth } from '@/composables/useAuth'

const auth = useAuth()
const isSignUp = ref(false)
const signupSuccess = ref(false)
const email = ref('')
const password = ref('')

async function handleLogin() {
  try {
    if (isSignUp.value) {
      await auth.signUp(email.value, password.value)
      // Success: switch to sign-in mode and show confirmation message
      signupSuccess.value = true
      isSignUp.value = false
      password.value = '' // Clear password for security
    } else {
      signupSuccess.value = false
      await auth.signIn(email.value, password.value)
    }
  } catch (err) {
    // Error is already captured in auth.error
    signupSuccess.value = false
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
