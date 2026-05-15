import { ref, computed, onMounted } from 'vue'
import { supabase } from '@/lib/supabase'

/**
 * useAuth Composable
 * 
 * Handles user authentication via Google OAuth or Email/Password.
 * Manages session state, loading states, and auth errors.
 * 
 * @returns {Object} Authentication state and methods
 */
export function useAuth() {
  const user = ref(null)
  const session = ref(null)
  const loading = ref(true)
  const error = ref(null)

  // Computed properties
  const isAuthenticated = computed(() => !!user.value)
  const userEmail = computed(() => user.value?.email || '')

  /**
   * Initialize auth state on mount
   */
  onMounted(async () => {
    await initAuth()
  })

  /**
   * Get current session and set up auth state change listener
   */
  async function initAuth() {
    try {
      loading.value = true
      error.value = null

      // Get initial session
      const { data: { session: currentSession } } = await supabase.auth.getSession()
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
          }
        }
      )

      // Cleanup subscription on component unmount would be ideal,
      // but for a global auth composable, we let it persist
    } catch (err) {
      error.value = err.message
      console.error('[useAuth] Init error:', err)
    } finally {
      loading.value = false
    }
  }

  /**
   * Sign in with Google OAuth
   */
  async function signInWithGoogle() {
    try {
      loading.value = true
      error.value = null

      const { data, error: signInError } = await supabase.auth.signInWithOAuth({
        provider: 'google',
        options: {
          redirectTo: `${window.location.origin}/`,
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
   * @param {string} email 
   * @param {string} password 
   */
  async function signUp(email, password) {
    try {
      loading.value = true
      error.value = null

      const { data, error: signUpError } = await supabase.auth.signUp({
        email,
        password,
      })

      if (signUpError) throw signUpError

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
   * @param {string} email 
   * @param {string} password 
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
   * @param {string} email 
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

  return {
    // State
    user,
    session,
    loading,
    error,
    // Computed
    isAuthenticated,
    userEmail,
    // Methods
    initAuth,
    signInWithGoogle,
    signUp,
    signIn,
    signOut,
    resetPassword,
  }
}
