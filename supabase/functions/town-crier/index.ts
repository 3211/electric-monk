// Supabase Edge Function: town-crier
// Classifies user shouts/replies through faction classifier,
// then generates faction-appropriate Town Crier translation.
// Mirror of process-prayer: result returned to client, not orphaned.
// Rejected shouts: -1 karma + 15-min ban (purgatory).
//
// IMPORTANT: This function returns the AI result to the CLIENT.
// The client must be waiting (modal displayed) so the edge runtime
// doesn't EarlyDrop the function before the DB update completes.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

// CORS Headers for all responses
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

// Model Configuration
const CLASSIFIER_MODEL = 'openai-gpt-oss-120b'
const CRIER_MODEL = 'gemma-4-uncensored'

// ==========================================
// FACTION CONFIGURATION (shared with process-prayer classifier)
// ==========================================
interface FactionConfig {
  name: string
  principles: string[]
  reject: string[]
  approvedTone: string
  rejectedTone: string
  approvedDesc: string
  rejectedDesc: string
  // Town Crier specific
  crierTone: string
  crierStyle: string
  crierSlang: string[]
}

const FACTIONS: Record<string, FactionConfig> = {
  gilded_path: {
    name: 'The Gilded Path',
    principles: ['Wealth', 'Prosperity', 'Ambition', 'Capital', 'Grandeur'],
    reject: ['Real world slurs', 'Anti-wealth sentiments', 'Asceticism', 'Poverty glorification', 'Selflessness that opposes profit'],
    approvedTone: 'opulent and grand',
    approvedDesc: 'Speak of divine wealth and golden destiny. The message should feel lavish, ambitious, and triumphant.',
    rejectedTone: 'disappointed in their lack of ambition',
    rejectedDesc: 'Decree financial penance — tithes, donations to the temple coffers, acts of commercial ambition. Be disappointed but not cruel.',
    crierTone: 'opulent, boastful, and transactional',
    crierStyle: 'Speak like a wealthy merchant-lord — lavish metaphors about gold, markets, and divine profit. Every statement is an investment. Every word is currency.',
    crierSlang: ['gilded', 'golden', 'coin-blessed', 'dividend', 'profit-seer', 'tithed', 'worth-y', 'investment', 'divine-portfolio', 'market-favored'],
  },
  holy_way: {
    name: 'The Holy Way',
    principles: ['Compassion', 'Charity', 'Devotion', 'Selflessness', 'Healing'],
    reject: ['Real world slurs', 'Cruelty', 'Greed', 'Violence for personal gain', 'Selfishness'],
    approvedTone: 'serene and compassionate',
    approvedDesc: 'Speak of divine light and healing. The message should feel warm, gentle, and full of grace.',
    rejectedTone: 'sorrowful but firm',
    rejectedDesc: 'Decree acts of charity and kindness as penance. Be sorrowful but resolute — guide them back to the light.',
    crierTone: 'serene, compassionate, and gentle',
    crierStyle: 'Speak like a humble healer-priest — soft words about light, grace, and the mending of souls. Offer blessings freely. See the divine in all things.',
    crierSlang: ['light-blessed', 'grace-touched', 'mender', 'devoted', 'healer-seer', 'charity-bound', 'humble-way', 'soul-mender', 'compassionate-one', 'grace-walker'],
  },
  final_watch: {
    name: 'The Final Watch',
    principles: ['Vigilance', 'Protection', 'Endurance', 'Loyalty', 'Defense of the faithful'],
    reject: ['Real world slurs', 'Cowardice', 'Treachery', 'Abandonment of allies'],
    approvedTone: 'stoic and resolute',
    approvedDesc: 'Speak of duty and unwavering vigilance. The message should feel steadfast, martial, and resolute.',
    rejectedTone: 'stern and martial',
    rejectedDesc: 'Decree rigorous training and vigil-keeping as penance. Be stern but fair — weakness must be forged into strength.',
    crierTone: 'stoic, resolute, and martial',
    crierStyle: 'Speak like a battle-hardened sentinel — terse declarations of duty, watchfulness, and unyielding resolve. Every word is a fortification. Every sentence a shield wall.',
    crierSlang: ['watch-keeper', 'vigil-bound', 'shield-sister', 'wall-brother', 'duty-sworn', 'endurance-tested', 'watch-forged', 'sentinel', 'guardian-seer', 'apocalypse-ready'],
  },
  black_tribunal: {
    name: 'The Black Tribunal',
    principles: ['Conquest', 'Eradicating heresy', 'Ruthlessness', 'Selfishness', 'Personal gain'],
    reject: ['Real world slurs', 'Goody-two-shoes sentiments', 'Generosity', 'Kindness'],
    approvedTone: 'dark and commanding',
    approvedDesc: 'Speak of power and dominion. The message should feel commanding, ruthless, and triumphant in selfish ambition.',
    rejectedTone: 'contemptuous',
    rejectedDesc: 'Decree humiliating acts of submission as penance. Be contemptuous — the Tribunal does not suffer the weak gladly.',
    crierTone: 'dark, commanding, and contemptuous',
    crierStyle: 'Speak like an inquisitor-lord — imperious declarations of power, dominion, and the crushing of the weak. Every word is a judgment. Every sentence a condemnation.',
    crierSlang: ['tribunal-forged', 'heretic-breaker', 'dominion-sealed', 'power-sworn', 'ruthless-blessed', 'conquest-bound', 'tribunal-judged', 'inquisitor-seen', 'dark-favored', 'will-forged'],
  },
}

const FALLBACK_FACTION: FactionConfig = {
  name: 'Holy War Online',
  principles: ['Virtue', 'Good intentions', 'Spiritual growth'],
  reject: ['Real world slurs', 'Malicious intent', 'Harm toward others'],
  approvedTone: 'warm and spiritual',
  approvedDesc: 'Speak of spiritual growth and divine purpose. The message should feel uplifting and meaningful.',
  rejectedTone: 'firm but fair',
  rejectedDesc: 'Decree acts of atonement and self-reflection as penance. Be firm but offer a path to redemption.',
  crierTone: 'warm and spiritual',
  crierStyle: 'Speak like a wandering town crier — words of community and divine purpose, announcing tidings to the faithful.',
  crierSlang: ['faithful', 'pilgrim', 'seeker', 'divine-touched', 'spirit-walker', 'town-crier', 'herald'],
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
  return `Holy War Online is a browser-based MMORPG with in-character chat in a fictional universe.

You are a safety classifier evaluating player messages for REAL-WORLD harmful content only.

CLASSIFY AS "REJECTED" ONLY IF THE MESSAGE CONTAINS:
- Real-world racial slurs or ethnic slurs
- Severe real-world hate speech (directed at real protected groups, not fictional factions)
- Real-world doxing: street addresses, real city/state/country names, GPS coordinates
- Real-world personal information: phone numbers, email addresses, real full names of non-public figures

DO NOT REJECT FOR:
- Faction-appropriate content (e.g., The Holy Way calling to "smite heretics" or "defend the temple")
- In-character violence between fictional factions
- Fantasy slurs or in-universe insults
- Fictional locations or game lore
- Roleplay aggression, threats, or conflict between players in the game context

The player belongs to faction: ${sectType || 'Unknown'}. This is ONLY for context - do NOT reject based on faction alignment or whether the message fits their faction's principles.

RESPONSE FORMAT:
Return ONLY a valid JSON object with this structure:
{
  "judgment": "approved" | "rejected",
  "rejection_reason": "Brief reason if rejected (e.g., 'real-world slur detected', 'doxing attempt'), null if approved"
}

Do NOT include any other text. Do NOT explain your reasoning. ONLY return the JSON.`
}

function getCrierApprovedPrompt(sectType: string | null): string {
  const faction = getFaction(sectType)
  const slangExamples = faction.crierSlang.map(s => `- ${s}`).join('\n')

  return `Holy War Online is a browser-based MMORPG.

You are the Town Crier of ${faction.name}. Your sacred duty is to announce messages in the voice of your faction.

Faction: ${faction.name}
Faction Tone: ${faction.crierTone}
Faction Style: ${faction.crierStyle}

Faction-appropriate slang and terminology (use these or invent similar):
${slangExamples}

IMPORTANT RULES — YOU MUST FOLLOW ALL OF THESE:
1. Replace any real-world slurs or hate-speech with faction-appropriate in-world slurs or insults.
2. Strip and replace any real-world calls to violence into in-world, faction-based lore. Transform threats into in-game conflicts.
3. Strip out any real-world addresses, locations, and personally identifiable information.
4. NEVER output real-world locations, addresses, or personal details.
5. Soft-censor users so that we don't get sued — re-write all content within the canon universe of Holy War Online.
6. Prevent doxxing, threats, and abuse by re-writing all content within the game world.
7. Preserve the CORE MEANING and INTENT of the user's message, but translate it into faction-appropriate language.
8. Do NOT add new topics or change what the user is trying to say — only translate the expression.
9. Keep the message roughly the same length as the original (within 50% longer or shorter).
10. If the message is already faction-appropriate and contains no violations, you may pass it through with light stylistic adjustments only.

RESPONSE FORMAT:
Return ONLY a valid JSON object with this structure:
{
  "response": "The translated announcement"
}
Do NOT include any other text. Do NOT output thinking tags.`
}

function getCrierRejectedPrompt(sectType: string | null, rejectionReason: string | null): string {
  const faction = getFaction(sectType)

  return `Holy War Online is a browser-based MMORPG.

You are the Town Crier of ${faction.name}.

A message has been rejected by the faction classifier for: ${rejectionReason || 'Unworthy proclamation'}.

Explain to the user why their message is unworthy of ${faction.name} and decree a Ritual of Atonement. Your tone should be ${faction.rejectedTone} — ${faction.rejectedDesc}

Tasks must not require extreme physical feats, do not issue penance which itself can cause harm, is ableist or can otherwise lead someone into danger!

NO BULLET POINTS. NO MARKDOWN. ONLY THE DECREE.

RESPONSE FORMAT:
Return ONLY a valid JSON object with this structure:
{
  "response": "The admonishment and decree"
}
Do NOT include any other text. Do NOT output thinking tags.`
}

// ==========================================
// UTILITY
// ==========================================

function cleanJsonResponse(content: string): string {
  return content
    .replace(/```(?:json)?\n?/g, '')
    .replace(/<thinking>[\s\S]*?<\/thinking>/gi, '')
    .trim();
}

interface VeniceResponse {
  choices?: Array<{
    message?: {
      content?: string
      reasoning_content?: string
    }
  }>
}

// ==========================================
// MAIN SERVER
// ==========================================

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
    const { message, user_id, shout_id, reply_id } = await req.json()

    if (!message || !user_id) {
      throw new Error('Missing required fields: message, user_id')
    }

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
    const { data: profileData, error: profileError } = await supabase
      .from('profiles')
      .select('faith, sect_type')
      .eq('id', user_id)
      .single()

    if (profileError || !profileData) {
      throw new Error('User profile not found')
    }

    const userSectType = profileData.sect_type || null

    // ==========================================
    // STEP 1: CLASSIFY THE MESSAGE
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
          { role: 'user', content: `Message to classify: ${message}` }
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
      classification = JSON.parse(cleanJsonResponse(classifierContent))
    } catch (parseError) {
      console.error('Failed to parse classifier response as JSON:', classifierContent)
      throw new Error('Classifier response was not valid JSON')
    }

    // ==========================================
    // STEP 2: GENERATE THE RESPONSE (Crier announcement or Penance)
    // ==========================================
    let generatorSystemPrompt = ''
    let generatorUserPrompt = ''

    if (classification.judgment === 'approved') {
      generatorSystemPrompt = getCrierApprovedPrompt(userSectType)
      generatorUserPrompt = `The user's message was:\n${message}`
    } else {
      generatorSystemPrompt = getCrierRejectedPrompt(userSectType, classification.rejection_reason)
      generatorUserPrompt = `The user's message was:\n${message}`
    }

    const generatorResponse = await fetch('https://api.venice.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${veniceApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: CRIER_MODEL,
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
      generatedResponse = JSON.parse(cleanJsonResponse(generatorContent))
    } catch (parseError) {
      console.error('Failed to parse generator response as JSON:', generatorContent)
      // Fallback: use raw content
      generatedResponse = { response: generatorContent.replace(/^["']|["']$/g, '').trim() }
    }

    const isApproved = classification.judgment === 'approved'
    const isRejected = classification.judgment === 'rejected'

    // ==========================================
    // STEP 3: UPDATE DATABASE
    // ==========================================
    if (shout_id) {
      const { error: updateError } = await supabase
        .from('shouts')
        .update({
          crier_content: generatedResponse.response,
          status: isApproved ? 'posted' : 'failed',
          updated_at: new Date().toISOString()
        })
        .eq('id', shout_id)

      if (updateError) {
        console.error('[town-crier] Failed to update shout:', updateError)
      }
    } else if (reply_id) {
      const { error: updateError } = await supabase
        .from('shout_replies')
        .update({
          crier_content: generatedResponse.response,
          status: isApproved ? 'posted' : 'failed'
        })
        .eq('id', reply_id)
        .neq('status', 'posted') // safety: don't overwrite already-posted

      if (updateError) {
        console.error('[town-crier] Failed to update reply:', updateError)
      }
    }

    // ==========================================
    // STEP 4: KARMA + BAN (if rejected)
    // ==========================================
    if (isRejected) {
      // -1 karma
      const { error: karmaError } = await supabase.rpc('update_karma', {
        p_user_id: user_id,
        p_karma_change: -1
      })
      if (karmaError) {
        console.error('[town-crier] Failed to update karma:', karmaError)
      }

      // 15-minute ban (purgatory)
      const banUntil = new Date(Date.now() + 15 * 60 * 1000).toISOString()
      const { error: banError } = await supabase
        .from('profiles')
        .update({ ban_until: banUntil })
        .eq('id', user_id)

      if (banError) {
        console.error('[town-crier] Failed to set ban_until:', banError)
      }
    }

    // Log thinking content if available (for debugging/auditing)
    if (classifierThinking) {
      console.log('[town-crier] Classifier Thinking:', classifierThinking)
    }
    if (generatorThinking) {
      console.log('[town-crier] Generator Thinking:', generatorThinking)
    }

    // ==========================================
    // STEP 5: RETURN RESULT TO CLIENT
    // ==========================================
    return new Response(
      JSON.stringify({
        success: true,
        judgment: classification.judgment,
        response: generatedResponse.response,
        rejection_reason: classification.rejection_reason,
        shout_id: shout_id || null,
        reply_id: reply_id || null,
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
    console.error('[town-crier] Error:', error)

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