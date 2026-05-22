import { ref, computed, reactive } from 'vue'
import { supabase } from '@/lib/supabase'
import { usePlayerState } from '@/composables/usePlayerState'

/**
 * useAuth Composable (Singleton Pattern)
 *
 * Handles user authentication via Google OAuth or Email/Password.
 * Manages session state, loading states, and auth errors.
 * Uses a shared state pattern so all components see the same auth state.
 */

// Shared state - created once, reused by all useAuth() calls
let sharedState = null

function createAuthState() {
  const user = ref(null)
  const session = ref(null)
  const loading = ref(false)
  const isInitializing = ref(false)
  const error = ref(null)
  const initialized = ref(false)
  const needsConfirmation = ref(false)

  // Computed properties
  const isAuthenticated = computed(() => !!user.value)
  const userEmail = computed(() => user.value?.email || '')

  /**
   * Get current session and set up auth state change listener
   */
  async function initAuth() {
    if (initialized.value) return

    try {
      isInitializing.value = true
      error.value = null

      const { data: { session: currentSession }, error: sessionError } = await supabase.auth.getSession()

      if (sessionError) {
        console.warn('[useAuth] getSession returned error:', sessionError)
      }

      session.value = currentSession
      user.value = currentSession?.user || null

      // Listen for auth changes
      const { data: { subscription } } = supabase.auth.onAuthStateChange(
        async (event, newSession) => {
          session.value = newSession
          user.value = newSession?.user || null

          if (event === 'SIGNED_OUT') {
            session.value = null
            user.value = null
            // Flush player state so no stale data leaks into next session
            usePlayerState().flush()
          }
        }
      )

      initialized.value = true
    } catch (err) {
      error.value = err.message
      console.error('[useAuth] Init error:', err)
      initialized.value = true
    } finally {
      isInitializing.value = false
    }
  }

  /**
   * Sign in with Google OAuth
   */
  async function signInWithGoogle() {
    try {
      loading.value = true
      error.value = null

      const cleanRedirectUrl = `${window.location.origin}${window.location.pathname}`

      const { data, error: signInError } = await supabase.auth.signInWithOAuth({
        provider: 'google',
        options: {
          redirectTo: cleanRedirectUrl,
        },
      })

      if (signInError) throw signInError

      return data
    } catch (err) {
      error.value = err.message
      console.error('[useAuth] Google sign-in error:', err)
      throw err
    } finally {
      loading.value = false
    }
  }

  /**
   * Sign up with email and password
   */
  async function signUp(email, password) {
    try {
      loading.value = true
      error.value = null
      needsConfirmation.value = false

      const { data, error: signUpError } = await supabase.auth.signUp({
        email,
        password,
      })

      if (signUpError) throw signUpError

      if (data.user && !data.session) {
        needsConfirmation.value = true
      }

      return data
    } catch (err) {
      error.value = err.message
      console.error('[useAuth] Sign-up error:', err)
      throw err
    } finally {
      loading.value = false
    }
  }

  /**
   * Sign in with email and password
   */
  async function signIn(email, password) {
    try {
      loading.value = true
      error.value = null

      const { data, error: signInError } = await supabase.auth.signInWithPassword({
        email,
        password,
      })

      if (signInError) throw signInError

      return data
    } catch (err) {
      error.value = err.message
      console.error('[useAuth] Sign-in error:', err)
      throw err
    } finally {
      loading.value = false
    }
  }

  /**
   * Sign out current user
   */
  async function signOut() {
    try {
      loading.value = true
      error.value = null

      const { error: signOutError } = await supabase.auth.signOut()

      if (signOutError) throw signOutError

      user.value = null
      session.value = null
    } catch (err) {
      error.value = err.message
      console.error('[useAuth] Sign-out error:', err)
      throw err
    } finally {
      loading.value = false
    }
  }

  /**
   * Send password reset email
   */
  async function resetPassword(email) {
    try {
      loading.value = true
      error.value = null

      const { error: resetError } = await supabase.auth.resetPasswordForEmail(email, {
        redirectTo: `${window.location.origin}/reset-password`,
      })

      if (resetError) throw resetError

      return true
    } catch (err) {
      error.value = err.message
      console.error('[useAuth] Password reset error:', err)
      throw err
    } finally {
      loading.value = false
    }
  }

  return reactive({
    user,
    session,
    loading,
    isInitializing,
    error,
    needsConfirmation,
    isAuthenticated,
    userEmail,
    initAuth,
    signInWithGoogle,
    signUp,
    signIn,
    signOut,
    resetPassword,
  })
}

export function useAuth() {
  if (!sharedState) {
    sharedState = createAuthState()
    sharedState.initAuth()
  }
  return sharedState
}