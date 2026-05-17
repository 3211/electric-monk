import { ref, computed, reactive } from 'vue'
import { supabase } from '@/lib/supabase'

/**
 * useOnboarding Composable
 *
 * Manages the new user onboarding wizard state machine:
 *   idle -> loading -> welcome -> identity -> prayer_prompt -> prayer_input -> processing -> approved/rejected
 *
 * On rejected during onboarding: no ban, no karma loss, user can retry.
 * On approved: sets onboarding_complete = TRUE in profiles table.
 */

// Sect key to display name mapping (faith auto-set from sect)
const SECT_FAITH_MAP = {
  gilded_path: 'The Gilded Path',
  holy_way: 'The Holy Way',
  final_watch: 'The Final Watch',
  black_tribunal: 'The Black Tribunal',
}

// Module-level shared state
let sharedState = null

function createOnboardingState() {
  const step = ref('idle') // idle | loading | welcome | identity | prayer_prompt | prayer_input | processing | approved | rejected
  const welcomeMessage = ref('')
  const prayerPrompt = ref('')
  const rejectionReason = ref(null)
  const prayerResponse = ref('')
  const loading = ref(false)
  const error = ref(null)
  const username = ref('')
  const selectedSect = ref(null)

  // Typewriter state
  const displayedText = ref('')
  const typewriterFinished = ref(false)
  let typewriterInterval = null

  const isActive = computed(() => step.value !== 'idle')

  /**
   * Clear any running typewriter interval
   */
  function clearTypewriter() {
    if (typewriterInterval) {
      clearInterval(typewriterInterval)
      typewriterInterval = null
    }
  }

  /**
   * Start typewriter effect for a given text, updating displayedText ref
   */
  function startTypewriter(text, speed = 22) {
    clearTypewriter()
    displayedText.value = ''
    typewriterFinished.value = false
    let i = 0
    typewriterInterval = setInterval(() => {
      if (i < text.length) {
        displayedText.value += text[i]
        i++
      } else {
        clearInterval(typewriterInterval)
        typewriterInterval = null
        typewriterFinished.value = true
      }
    }, speed)
  }

  /**
   * Start the onboarding flow by fetching AI-generated content
   */
  async function startOnboarding() {
    try {
      step.value = 'loading'
      loading.value = true
      error.value = null

      // Get current user
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('No user logged in')

      // Fetch onboarding content from edge function
      const { data, error: fnError } = await supabase.functions.invoke('generate-onboarding-content', {
        body: { user_id: user.id },
      })

      if (fnError) throw fnError

      welcomeMessage.value = data?.welcome_message || 'Welcome, traveler. I am the Electric Monk — a digital devotional engine that prays on your behalf. Choose your path and offer your first prayer.'
      prayerPrompt.value = data?.prayer_prompt || 'What weighs on your heart? Speak it as a prayer, and the Monk will carry it forward.'

      // Start with the welcome step and typewriter
      step.value = 'welcome'
      startTypewriter(welcomeMessage.value)
    } catch (err) {
      // Fallback to static messages if edge function fails
      welcomeMessage.value = 'Welcome, traveler. I am the Electric Monk — a digital devotional engine that prays on your behalf, dedicating computational thought energy to your intentions. Choose your path and offer your first prayer.'
      prayerPrompt.value = 'What weighs on your heart? Speak it as a prayer, and the Monk will carry it forward.'
      step.value = 'welcome'
      startTypewriter(welcomeMessage.value)
      error.value = null // Non-fatal: we have fallbacks
    } finally {
      loading.value = false
    }
  }

  /**
   * Advance from welcome to identity step
   */
  function continueToIdentity() {
    clearTypewriter()
    step.value = 'identity'
  }

  /**
   * Submit identity (username + sect) and advance to prayer prompt
   */
  async function submitIdentity({ username: newUsername, sectType }) {
    try {
      loading.value = true
      error.value = null

      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('No user logged in')

      // Step 1: Upsert profile with username and faith
      const faith = SECT_FAITH_MAP[sectType] || sectType
      const { error: upsertError } = await supabase
        .from('profiles')
        .upsert({
          id: user.id,
          username: newUsername,
          faith: faith,
        }, { onConflict: 'id' })

      if (upsertError) throw upsertError

      // Step 2: Choose sect via RPC
      const { error: sectError } = await supabase.rpc('choose_sect', {
        p_sect_type: sectType,
      })

      if (sectError) throw sectError

      // Store locally
      username.value = newUsername
      selectedSect.value = sectType

      // Advance to prayer prompt with typewriter
      step.value = 'prayer_prompt'
      startTypewriter(prayerPrompt.value)
    } catch (err) {
      error.value = err.message || 'Failed to save identity'
      console.error('[useOnboarding] Identity submission error:', err)
      throw err
    } finally {
      loading.value = false
    }
  }

  /**
   * Advance from prayer prompt to prayer input
   */
  function continueToPrayerInput() {
    clearTypewriter()
    step.value = 'prayer_input'
  }

  /**
   * Submit the user's first prayer during onboarding
   * Uses the regular submit_prayer RPC + process-prayer edge function
   * but with is_onboarding: true to skip ban on rejection
   */
  async function submitFirstPrayer(content) {
    try {
      step.value = 'processing'
      loading.value = true
      error.value = null
      rejectionReason.value = null
      prayerResponse.value = ''

      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('No user logged in')

      // Step 1: Call submit_prayer RPC to create the prayer record
      const { data: result, error: rpcError } = await supabase
        .rpc('submit_prayer', { prayer_content: content })

      if (rpcError) throw rpcError

      // Step 2: Invoke process-prayer edge function with is_onboarding flag
      const { data: aiResult, error: aiError } = await supabase.functions.invoke('process-prayer', {
        body: {
          prayer_id: result.id,
          content: content,
          user_id: user.id,
          is_onboarding: true,
        },
      })

      if (aiError) throw aiError

      // Route based on judgment
      if (aiResult.judgment === 'approved') {
        prayerResponse.value = aiResult.response || 'Your prayer has been heard.'
        step.value = 'approved'
        startTypewriter(prayerResponse.value)
      } else {
        // Rejected — but NO ban during onboarding
        rejectionReason.value = aiResult.rejection_reason || 'Unworthy petition'
        prayerResponse.value = aiResult.response || ''
        step.value = 'rejected'
      }
    } catch (err) {
      error.value = err.message || 'Failed to process prayer'
      console.error('[useOnboarding] First prayer error:', err)
      // Go back to prayer input so they can retry
      step.value = 'prayer_input'
      throw err
    } finally {
      loading.value = false
    }
  }

  /**
   * Retry the first prayer after rejection
   */
  function retryPrayer() {
    rejectionReason.value = null
    prayerResponse.value = ''
    step.value = 'prayer_input'
  }

  /**
   * Complete onboarding — mark profile as onboarding_complete = true
   */
  async function completeOnboarding() {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) return

      await supabase
        .from('profiles')
        .update({ onboarding_complete: true })
        .eq('id', user.id)

      // Reset state
      clearTypewriter()
      step.value = 'idle'
      welcomeMessage.value = ''
      prayerPrompt.value = ''
      rejectionReason.value = null
      prayerResponse.value = ''
      error.value = null
    } catch (err) {
      console.error('[useOnboarding] Complete onboarding error:', err)
      // Even if this fails, the user can still proceed
      step.value = 'idle'
    }
  }

  /**
   * Reset onboarding state (e.g., if user navigates away)
   */
  function resetOnboarding() {
    clearTypewriter()
    step.value = 'idle'
    welcomeMessage.value = ''
    prayerPrompt.value = ''
    rejectionReason.value = null
    prayerResponse.value = ''
    loading.value = false
    error.value = null
    username.value = ''
    selectedSect.value = null
    displayedText.value = ''
    typewriterFinished.value = false
  }

  return reactive({
    step,
    welcomeMessage,
    prayerPrompt,
    rejectionReason,
    prayerResponse,
    loading,
    error,
    username,
    selectedSect,
    displayedText,
    typewriterFinished,
    isActive,
    startOnboarding,
    continueToIdentity,
    submitIdentity,
    continueToPrayerInput,
    submitFirstPrayer,
    retryPrayer,
    completeOnboarding,
    resetOnboarding,
    startTypewriter,
    clearTypewriter,
  })
}

export function useOnboarding() {
  if (!sharedState) {
    sharedState = createOnboardingState()
  }
  return sharedState
}