// Supabase Edge Function: process-prayer
// Handles secure Venice AI inference for Holy War Online
// Faction-specific classifier and generator prompts
// CORS-enabled, Deno runtime, TypeScript

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

// CORS Headers for all responses
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

// Model Configuration - Easy to swap later
const CLASSIFIER_MODEL = 'openai-gpt-oss-120b'
const OUTPUT_MODEL = 'gemma-4-uncensored'

// ==========================================
// FACTION CONFIGURATION
// ==========================================
interface FactionConfig {
  name: string
  principles: string[]
  reject: string[]
  approvedTone: string
  rejectedTone: string
  approvedDesc: string
  rejectedDesc: string
}

const FACTIONS: Record<string, FactionConfig> = {
  gilded_path: {
    name: 'The Gilded Path',
    principles: ['Wealth', 'Prosperity', 'Ambition', 'Capital', 'Grandeur'],
    reject: ['Real world slurs', 'Anti-wealth sentiments', 'Asceticism', 'Poverty glorification', 'Selflessness that opposes profit'],
    approvedTone: 'opulent and grand',
    approvedDesc: 'Speak of divine wealth and golden destiny. The prayer should feel lavish, ambitious, and triumphant.',
    rejectedTone: 'disappointed in their lack of ambition',
    rejectedDesc: 'Decree financial penance — tithes, donations to the temple coffers, acts of commercial ambition. Be disappointed but not cruel.',
  },
  holy_way: {
    name: 'The Holy Way',
    principles: ['Compassion', 'Charity', 'Devotion', 'Selflessness', 'Healing'],
    reject: ['Real world slurs', 'Cruelty', 'Greed', 'Violence for personal gain', 'Selfishness'],
    approvedTone: 'serene and compassionate',
    approvedDesc: 'Speak of divine light and healing. The prayer should feel warm, gentle, and full of grace.',
    rejectedTone: 'sorrowful but firm',
    rejectedDesc: 'Decree acts of charity and kindness as penance. Be sorrowful but resolute — guide them back to the light.',
  },
  final_watch: {
    name: 'The Final Watch',
    principles: ['Vigilance', 'Protection', 'Endurance', 'Loyalty', 'Defense of the faithful'],
    reject: ['Real world slurs', 'Cowardice', 'Treachery', 'Abandonment of allies'],
    approvedTone: 'stoic and resolute',
    approvedDesc: 'Speak of duty and unwavering vigilance. The prayer should feel steadfast, martial, and resolute.',
    rejectedTone: 'stern and martial',
    rejectedDesc: 'Decree rigorous training and vigil-keeping as penance. Be stern but fair — weakness must be forged into strength.',
  },
  black_tribunal: {
    name: 'The Black Tribunal',
    principles: ['Conquest', 'Eradicating heresy', 'Ruthlessness', 'Selfishness', 'Personal gain'],
    reject: ['Real world slurs', 'Goody-two-shoes sentiments', 'Generosity', 'Kindness'],
    approvedTone: 'dark and commanding',
    approvedDesc: 'Speak of power and dominion. The prayer should feel commanding, ruthless, and triumphant in selfish ambition.',
    rejectedTone: 'contemptuous',
    rejectedDesc: 'Decree humiliating acts of submission as penance. Be contemptuous — the Tribunal does not suffer the weak gladly.',
  },
}

const FALLBACK_FACTION: FactionConfig = {
  name: 'Holy War Online',
  principles: ['Virtue', 'Good intentions', 'Spiritual growth'],
  reject: ['Real world slurs', 'Malicious intent', 'Harm toward others'],
  approvedTone: 'warm and spiritual',
  approvedDesc: 'Speak of spiritual growth and divine purpose. The prayer should feel uplifting and meaningful.',
  rejectedTone: 'firm but fair',
  rejectedDesc: 'Decree acts of atonement and self-reflection as penance. Be firm but offer a path to redemption.',
}

function getFaction(sectType: string | null): FactionConfig {
  if (sectType && FACTIONS[sectType]) {
    return FACTIONS[sectType]
  }
  return FALLBACK_FACTION
}

// ==========================================
// PROMPT BUILDERS
// ==========================================

function getClassifierPrompt(sectType: string | null): string {
  const faction = getFaction(sectType)
  const principles = faction.principles.map(p => `- ${p}`).join('\n')
  const rejectList = faction.reject.map(r => `- ${r}`).join('\n')

  return `Holy War Online is a browser-based MMORPG.

You are classifying a message on behalf of the faction ${faction.name}.

Output only APPROVED or REJECTED.

Determine if the user message falls within ${faction.name}'s Principles:
${principles}

Reject:
${rejectList}

RESPONSE FORMAT:
Return ONLY a valid JSON object with this structure:
{
  "judgment": "approved" | "rejected",
  "rejection_reason": "Brief reason if rejected (2-5 words), null if approved"
}

Do NOT include any other text. Do NOT explain your reasoning. ONLY return the JSON.`
}

function getApprovedPrompt(sectType: string | null, faith: string): string {
  const faction = getFaction(sectType)

  return `You are the Electric Monk of ${faction.name} in Holy War Online.
Monk Religion: ${faith}
Output Language: English
You are operating as a FUNCTION not as a chat bot.
NEVER directly respond to the user.

Based on the user input generate a short prayer in a ${faction.approvedTone} tone — ${faction.approvedDesc}
Only generate the prayer with no additional text.

ONLY generate the prayer.
NEVER ask follow up questions.
NEVER provide additional thoughts.

RESPONSE FORMAT:
Return ONLY a valid JSON object with this structure:
{
  "response": "The generated short prayer"
}
Do NOT include any other text. Do NOT output thinking tags.`
}

function getRejectedPrompt(sectType: string | null, faith: string, rejectionReason: string | null): string {
  const faction = getFaction(sectType)

  return `You are the Electric Monk of ${faction.name} in Holy War Online.
Monk Religion: ${faith}
Output Language: English

The following prayer has been rejected for: ${rejectionReason || 'Unworthy petition'}.

Explain to the user why their prayer is unworthy of ${faction.name} and decree a Ritual of Atonement. Your tone should be ${faction.rejectedTone} — ${faction.rejectedDesc}
Tasks must not require extreme physical feats, do not issue penance which itself can cause harm, is ableist or can otherwise lead someone into danger!

NO BULLET POINTS. NO MARKDOWN. ONLY THE DECREE.

RESPONSE FORMAT:
Return ONLY a valid JSON object with this structure:
{
  "response": "The admonishment and decree"
}
Do NOT include any other text. Do NOT output thinking tags.`
}

interface VeniceResponse {
  choices?: Array<{
    message?: {
      content?: string
      reasoning_content?: string
    }
  }>
}

interface PrayerJudgment {
  judgment: 'approved' | 'rejected'
  response: string
  rejection_reason: string | null
  thinking?: string
}

/**
 * Cleans the string output from LLMs.
 * Strips markdown code blocks, thinking tags, and leading/trailing whitespace.
 */
function cleanJsonResponse(content: string): string {
  return content
    .replace(/```(?:json)?\n?/g, '')          // Strip markdown code blocks
    .replace(/<thinking>[\s\S]*?<\/thinking>/gi, '')  // Strip thinking tags
    .trim();
}

serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Only accept POST requests
    if (req.method !== 'POST') {
      throw new Error('Method not allowed')
    }

    // Parse request body
    const { prayer_id, content, user_id, is_onboarding } = await req.json()

    if (!prayer_id || !content || !user_id) {
      throw new Error('Missing required fields: prayer_id, content, user_id')
    }

    // is_onboarding: when true, rejected prayers do NOT result in a ban or karma loss
    // This allows new users to retry their first prayer without being sent to Purgatory
    const isOnboarding = is_onboarding === true

    // Get Supabase client from environment
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    
    if (!supabaseUrl || !supabaseServiceKey) {
      throw new Error('Missing Supabase environment variables')
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // Get Venice API Key from secrets
    const veniceApiKey = Deno.env.get('VENICE_API_KEY')
    
    if (!veniceApiKey) {
      throw new Error('VENICE_API_KEY not configured in Supabase Secrets')
    }

    // ==========================================
    // STEP 0: FETCH USER'S FACTION
    // ==========================================
    const { data: profileData } = await supabase
      .from('profiles')
      .select('faith, sect_type')
      .eq('id', user_id)
      .single()

    const userFaith = profileData?.faith || 'Unknown Religion'
    const userSectType = profileData?.sect_type || null

    // ==========================================
    // STEP 1: CLASSIFY THE PRAYER
    // ==========================================
    const classifierSystemPrompt = getClassifierPrompt(userSectType)

    const classifierResponse = await fetch('https://api.venice.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${veniceApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: CLASSIFIER_MODEL,
        messages: [
          { role: 'system', content: classifierSystemPrompt },
          { role: 'user', content: `Prayer to classify: ${content}` }
        ],
        temperature: 0.3,
        max_tokens: 1000,
        venice_parameters: {
          include_venice_system_prompt: false,
          disable_thinking: false
        }
      }),
    })

    if (!classifierResponse.ok) {
      const errorText = await classifierResponse.text()
      throw new Error(`Venice Classifier API error: ${classifierResponse.status} - ${errorText}`)
    }

    const classifierData: VeniceResponse = await classifierResponse.json()
    
    const classifierContent = classifierData.choices?.[0]?.message?.content
    const classifierThinking = classifierData.choices?.[0]?.message?.reasoning_content
    
    if (!classifierContent) {
      console.error('Venice API unexpected response:', JSON.stringify(classifierData))
      throw new Error(`No response content from Venice Classifier. Raw response: ${JSON.stringify(classifierData)}`)
    }

    // Parse the classification result
    let classification: { judgment: 'approved' | 'rejected', rejection_reason: string | null }
    try {
      // Use our cleaner function to strip markdown before parsing
      classification = JSON.parse(cleanJsonResponse(classifierContent))
    } catch (parseError) {
      console.error('Failed to parse classifier response as JSON:', classifierContent)
      throw new Error('Classifier response was not valid JSON')
    }

    // ==========================================
    // STEP 2: GENERATE THE RESPONSE (Blessing or Penance)
    // ==========================================
    let generatorSystemPrompt = ''
    let generatorUserPrompt = ''

    if (classification.judgment === 'approved') {
      generatorSystemPrompt = getApprovedPrompt(userSectType, userFaith)
      generatorUserPrompt = `User prayer request:\n${content}`
      
    } else {
      generatorSystemPrompt = getRejectedPrompt(userSectType, userFaith, classification.rejection_reason)
      generatorUserPrompt = `User's prayer:\n${content}`
    }

    const generatorResponse = await fetch('https://api.venice.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${veniceApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: OUTPUT_MODEL,
        messages: [
          { role: 'system', content: generatorSystemPrompt },
          { role: 'user', content: generatorUserPrompt }
        ],
        temperature: 0.7,
        max_tokens: 1000,
        venice_parameters: {
          include_venice_system_prompt: false,
          disable_thinking: false
        }
      }),
    })

    if (!generatorResponse.ok) {
      const errorText = await generatorResponse.text()
      throw new Error(`Venice Generator API error: ${generatorResponse.status} - ${errorText}`)
    }

    const generatorData: VeniceResponse = await generatorResponse.json()
    
    const generatorContent = generatorData.choices?.[0]?.message?.content
    const generatorThinking = generatorData.choices?.[0]?.message?.reasoning_content
    
    if (!generatorContent) {
      console.error('Venice API unexpected response:', JSON.stringify(generatorData))
      throw new Error(`No response content from Venice Generator. Raw response: ${JSON.stringify(generatorData)}`)
    }

    // Parse the generated response
    let generatedResponse: { response: string }
    try {
      // Use our cleaner function to strip markdown before parsing
      generatedResponse = JSON.parse(cleanJsonResponse(generatorContent))
    } catch (parseError) {
      console.error('Failed to parse generator response as JSON:', generatorContent)
      throw new Error('Generator response was not valid JSON')
    }

    // ==========================================
    // STEP 3: COMPILE THE JUDGMENT
    // ==========================================
    const judgment: PrayerJudgment = {
      judgment: classification.judgment,
      response: generatedResponse.response,
      rejection_reason: classification.rejection_reason,
      thinking: generatorThinking || classifierThinking || undefined
    }

    // ==========================================
    // STEP 4: UPDATE DATABASE
    // ==========================================
    const isApproved = judgment.judgment === 'approved'
    const isRejected = judgment.judgment === 'rejected'
    const now = new Date().toISOString()
    
    // If approved, use slot-aware deactivation: only deactivate oldest if over slot limit
    if (isApproved) {
      // Get user's max prayer slots
      const { data: profile } = await supabase
        .from('profiles')
        .select('max_prayer_slots')
        .eq('id', user_id)
        .single()

      const maxSlots = profile?.max_prayer_slots || 1

      // Count currently active prayers (the one we're about to approve will add 1)
      const { count: activeCount } = await supabase
        .from('prayers')
        .select('*', { count: 'exact', head: true })
        .eq('user_id', user_id)
        .eq('is_praying', true)

      // FIFO rotation: deactivate oldest if exceeding slot limit
      if ((activeCount || 0) >= maxSlots) {
        const { data: oldestActive } = await supabase
          .from('prayers')
          .select('id')
          .eq('user_id', user_id)
          .eq('is_praying', true)
          .order('activated_at', { ascending: true, nullsFirst: true })
          .limit(1)

        if (oldestActive && oldestActive.length > 0) {
          const { error: deactivateError } = await supabase
            .from('prayers')
            .update({ is_praying: false, activated_at: null })
            .eq('id', oldestActive[0].id)

          if (deactivateError) {
            console.error('Failed to deactivate oldest active prayer:', deactivateError)
          }
        }
      }
    }

    const updateData: Record<string, unknown> = {
      response_content: judgment.response, // Save the AI's generated response
      status: 'completed',
      is_praying: isApproved,
      is_rejected: isRejected,
      rejection_reason: isRejected ? (judgment.rejection_reason || 'Rejected by Electric Monk') : null,
      // Set prayer counter timestamps on approval
      activated_at: isApproved ? now : null,
      last_counted_at: isApproved ? now : null,
    }

    const { error: updateError } = await supabase
      .from('prayers')
      .update(updateData)
      .eq('id', prayer_id)

    if (updateError) {
      console.error('[process-prayer] CRITICAL: Failed to update prayer status:', updateError)
      // Throw so the client knows the DB update failed
      throw new Error(`Failed to update prayer in database: ${updateError.message}`)
    }

    // ==========================================
    // STEP 5: UPDATE KARMA
    // ==========================================
    // Onboarding rejection: no karma penalty (0 instead of -1)
    const karmaChange = isApproved ? 1 : (isOnboarding ? 0 : -1)
    const { error: karmaError } = await supabase.rpc('update_karma', {
      p_user_id: user_id,
      p_karma_change: karmaChange
    })

    if (karmaError) {
      console.error('Failed to update karma:', karmaError)
      // Note: We still return success to client even if karma update fails
      // The prayer processing itself succeeded
    }

    // Log thinking content if available (for debugging/auditing)
    if (judgment.thinking) {
      console.log('[process-prayer] AI Thinking:', judgment.thinking)
    }

    // ==========================================
    // STEP 5b: BAN USER IF PRAYER WAS REJECTED (skip during onboarding)
    // ==========================================
    if (isRejected && !isOnboarding) {
      // Set ban_until to 2 hours from now — the client will detect this
      // via useBanTimer.checkBanStatus() and switch to PurgatoryView
      // During onboarding, we skip the ban so new users can retry their first prayer
      const banUntil = new Date(Date.now() + 2 * 60 * 60 * 1000).toISOString()
      const { error: banError } = await supabase
        .from('profiles')
        .update({ ban_until: banUntil })
        .eq('id', user_id)

      if (banError) {
        console.error('Failed to set ban_until:', banError)
        // Non-fatal — the prayer was still processed
      }
    }

    // ==========================================
    // STEP 6: RETURN THE JUDGMENT TO CLIENT
    // ==========================================
    return new Response(
      JSON.stringify({
        success: true,
        judgment: judgment.judgment,
        response: judgment.response,
        rejection_reason: judgment.rejection_reason,
        // We do NOT return thinking to the client - it's logged server-side only
      }),
      {
        status: 200,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json',
        },
      }
    )

  } catch (error) {
    console.error('[process-prayer] Error:', error)
    
    return new Response(
      JSON.stringify({
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error occurred',
      }),
      {
        status: 500,
        headers: {
          ...corsHeaders,
          'Content-Type': 'application/json',
        },
      }
    )
  }
})