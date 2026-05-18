import { ref, computed, reactive } from 'vue'
import { supabase } from '@/lib/supabase'

/**
 * useOnboarding Composable
 *
 * Manages the new user onboarding wizard state machine:
 *   idle -> loading -> welcome -> identity -> faction_intro -> prayer_prompt -> prayer_input -> processing -> approved/rejected
 *
 * On rejected during onboarding: no ban, no karma loss, user can retry.
 * On approved: sets onboarding_complete = TRUE in profiles table.
 *
 * BUGFIX: onboarding_complete is now set TRUE immediately after identity save,
 * so if the user refreshes mid-onboarding they land on the main page instead of
 * getting stuck in a broken wizard state.
 */

// Sect key to display name mapping (faith auto-set from sect)
const SECT_FAITH_MAP = {
  gilded_path: 'The Gilded Path',
  holy_way: 'The Holy Way',
  final_watch: 'The Final Watch',
  black_tribunal: 'The Black Tribunal',
}

// Holy War Online fallback strings (used when AI generation fails)
const FALLBACK_WELCOME = 'Welcome to Holy War Online. I am your Electric Monk — a digital devotional engine that prays on your behalf, dedicating computational thought energy to your intentions. Choose your faction and begin your holy war.'

const FALLBACK_FACTION_INTROS = {
  gilded_path: 'Welcome to The Gilded Path, seeker of divine prosperity. I am your Electric Monk — I will pray on your behalf, channeling the wealth of the heavens toward your ambitions. Speak your first prayer and let golden destiny unfold.',
  holy_way: 'Welcome to The Holy Way, child of compassion. I am your Electric Monk — I will pray on your behalf, carrying your devotion into the light. Speak your first prayer and let grace flow through you.',
  final_watch: 'Welcome to The Final Watch, sentinel of the faithful. I am your Electric Monk — I will pray on your behalf, standing vigil over your intentions. Speak your first prayer and let duty be your shield.',
  black_tribunal: 'Welcome to The Black Tribunal, seeker of dominion. I am your Electric Monk — I will pray on your behalf, channeling your will into power. Speak your first prayer and let conquest begin.',
}

const FALLBACK_PRAYER_PROMPTS = {
  gilded_path: 'What prosperity do you seek? Speak your prayer for wealth and grandeur.',
  holy_way: 'What weighs on your heart? Speak your prayer for healing and compassion.',
  final_watch: 'What do you stand guard against? Speak your prayer for vigilance and protection.',
  black_tribunal: 'What power do you crave? Speak your prayer for conquest and dominion.',
}

const GENERIC_FALLBACK_INTRO = 'Welcome, warrior. I am your Electric Monk — I will pray on your behalf, dedicating computational thought energy to your intentions. Speak your first prayer.'
const GENERIC_FALLBACK_PROMPT = 'What intention would you like the Monk to pray for? Speak it into the aether.'

// Module-level shared state
let sharedState = null

function createOnboardingState() {
  const step = ref('idle') // idle | loading | welcome | identity | faction_intro | prayer_prompt | prayer_input | processing | approved | rejected
  const welcomeMessage = ref('')
  const factionWelcome = ref('')  // AI-generated faction intro message
  const prayerPrompt = ref('')
  const rejectionReason = ref(null)
  const prayerResponse = ref('')
  const loading = ref(false)
  const error = ref(null)
  const username = ref('')
  const selectedSect = ref(null)
  const usedFallback = ref(false) // Track if AI generation failed and fallback was used

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
   * Start the onboarding flow by fetching AI-generated welcome content
   * Phase 1: sect-agnostic welcome
   */
  async function startOnboarding() {
    try {
      step.value = 'loading'
      loading.value = true
      error.value = null

      // Get current user
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('No user logged in')

      // Fetch welcome message from edge function (phase 1: no sect)
      const { data, error: fnError } = await supabase.functions.invoke('generate-onboarding-content', {
        body: { user_id: user.id, phase: 'welcome' },
      })

      if (fnError) throw fnError

      welcomeMessage.value = data?.welcome_message || FALLBACK_WELCOME
      usedFallback.value = data?.used_fallback || false

      // Start with the welcome step and typewriter
      step.value = 'welcome'
      startTypewriter(welcomeMessage.value)
    } catch (err) {
      // Fallback to static messages if edge function fails
      welcomeMessage.value = FALLBACK_WELCOME
      step.value = 'welcome'
      startTypewriter(welcomeMessage.value)
      usedFallback.value = true
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
   * Submit identity (username + sect) and:
   * 1. Save to database
   * 2. Set onboarding_complete = true (BUGFIX: prevents dropout lockout)
   * 3. Fetch faction-specific intro from AI
   * 4. Advance to faction_intro step
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

      // Step 3: Set onboarding_complete = true IMMEDIATELY (bugfix)
      // If user refreshes after this point, they won't be stuck in wizard
      await supabase
        .from('profiles')
        .update({ onboarding_complete: true })
        .eq('id', user.id)

      // Store locally
      username.value = newUsername
      selectedSect.value = sectType

      // Step 4: Fetch faction-specific intro (phase 2)
      await fetchFactionIntro(sectType)

    } catch (err) {
      error.value = err.message || 'Failed to save identity'
      console.error('[useOnboarding] Identity submission error:', err)
      throw err
    } finally {
      loading.value = false
    }
  }

  /**
   * Fetch faction-specific intro from the edge function
   * Phase 2: sect-specific welcome + prayer prompt
   */
  async function fetchFactionIntro(sectType) {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) throw new Error('No user logged in')

      const { data, error: fnError } = await supabase.functions.invoke('generate-onboarding-content', {
        body: { user_id: user.id, phase: 'faction_intro', sect_type: sectType },
      })

      if (fnError) throw fnError

      factionWelcome.value = data?.faction_welcome || FALLBACK_FACTION_INTROS[sectType] || GENERIC_FALLBACK_INTRO
      prayerPrompt.value = data?.prayer_prompt || FALLBACK_PRAYER_PROMPTS[sectType] || GENERIC_FALLBACK_PROMPT
      usedFallback.value = data?.used_fallback || false

      // Advance to faction intro step with typewriter
      step.value = 'faction_intro'
      startTypewriter(factionWelcome.value)
    } catch (err) {
      // Fallback to static faction-specific messages
      factionWelcome.value = FALLBACK_FACTION_INTROS[sectType] || GENERIC_FALLBACK_INTRO
      prayerPrompt.value = FALLBACK_PRAYER_PROMPTS[sectType] || GENERIC_FALLBACK_PROMPT
      usedFallback.value = true

      // Still advance — don't block onboarding on AI failure
      step.value = 'faction_intro'
      startTypewriter(factionWelcome.value)
      error.value = null // Non-fatal: we have fallbacks
    }
  }

  /**
   * Advance from faction intro to prayer prompt
   */
  function continueToPrayerPrompt() {
    clearTypewriter()
    step.value = 'prayer_prompt'
    startTypewriter(prayerPrompt.value)
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
   * (Note: this is now also called during submitIdentity as a bugfix,
   *  but we keep this for completeness / manual calls)
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
      factionWelcome.value = ''
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
    factionWelcome.value = ''
    prayerPrompt.value = ''
    rejectionReason.value = null
    prayerResponse.value = ''
    loading.value = false
    error.value = null
    username.value = ''
    selectedSect.value = null
    displayedText.value = ''
    typewriterFinished.value = false
    usedFallback.value = false
  }

  return reactive({
    step,
    welcomeMessage,
    factionWelcome,
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
    usedFallback,
    startOnboarding,
    continueToIdentity,
    submitIdentity,
    fetchFactionIntro,
    continueToPrayerPrompt,
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