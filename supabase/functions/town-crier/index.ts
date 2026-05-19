// Supabase Edge Function: town-crier
// Translates user messages into faction-appropriate style
// Soft-censors real-world slurs, threats, doxxing, and locations
// Re-writes content within the canon universe of Holy War Online

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

// CORS Headers for all responses
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

// Model Configuration
const CRIER_MODEL = 'gemma-4-uncensored'

// ==========================================
// FACTION CONFIGURATION
// ==========================================
interface FactionConfig {
  name: string
  principles: string[]
  description: string
  tone: string
  style: string
  slang: string[]
}

const FACTIONS: Record<string, FactionConfig> = {
  gilded_path: {
    name: 'The Gilded Path',
    principles: ['Wealth', 'Prosperity', 'Ambition', 'Capital', 'Grandeur'],
    description: 'The Gilded Path is a merchant cult that worships the divine flow of coin and commerce. They believe prosperity is proof of divine favor and poverty is spiritual failure.',
    tone: 'opulent, boastful, and transactional',
    style: 'Speak like a wealthy merchant-lord — lavish metaphors about gold, markets, and divine profit. Every statement is an investment. Every word is currency.',
    slang: ['gilded', 'golden', 'coin-blessed', 'dividend', 'profit-seer', 'tithed', 'worth-y', 'investment', 'divine-portfolio', 'market-favored'],
  },
  holy_way: {
    name: 'The Holy Way',
    principles: ['Compassion', 'Charity', 'Devotion', 'Selflessness', 'Healing'],
    description: 'The Holy Way is a mendicant order devoted to healing and charity. They believe the path to divinity lies through selfless service and the mending of wounds both physical and spiritual.',
    tone: 'serene, compassionate, and gentle',
    style: 'Speak like a humble healer-priest — soft words about light, grace, and the mending of souls. Offer blessings freely. See the divine in all things.',
    slang: ['light-blessed', 'grace-touched', 'mender', 'devoted', 'healer-seer', 'charity-bound', 'humble-way', 'soul-mender', 'compassionate-one', 'grace-walker'],
  },
  final_watch: {
    name: 'The Final Watch',
    principles: ['Vigilance', 'Protection', 'Endurance', 'Loyalty', 'Defense of the faithful'],
    description: 'The Final Watch is a doomsday sect preparing to rebel against the apocalypse itself. They stand eternal guard against the end of all things, believing that vigilance and endurance are sacred duties.',
    tone: 'stoic, resolute, and martial',
    style: 'Speak like a battle-hardened sentinel — terse declarations of duty, watchfulness, and unyielding resolve. Every word is a fortification. Every sentence a shield wall.',
    slang: ['watch-keeper', 'vigil-bound', 'shield-sister', 'wall-brother', 'duty-sworn', 'endurance-tested', 'watch-forged', 'sentinel', 'guardian-seer', 'apocalypse-ready'],
  },
  black_tribunal: {
    name: 'The Black Tribunal',
    principles: ['Conquest', 'Eradicating heresy', 'Ruthlessness', 'Selfishness', 'Personal gain'],
    description: 'The Black Tribunal is a tyrannical inquisition that seeks dominion through fear and ruthless ambition. They believe power is its own justification and weakness is heresy.',
    tone: 'dark, commanding, and contemptuous',
    style: 'Speak like an inquisitor-lord — imperious declarations of power, dominion, and the crushing of the weak. Every word is a judgment. Every sentence a condemnation.',
    slang: ['tribunal-forged', 'heretic-breaker', 'dominion-sealed', 'power-sworn', 'ruthless-blessed', 'conquest-bound', 'tribunal-judged', 'inquisitor-seen', 'dark-favored', 'will-forged'],
  },
}

const FALLBACK_FACTION: FactionConfig = {
  name: 'Holy War Online',
  principles: ['Virtue', 'Good intentions', 'Spiritual growth'],
  description: 'The common faithful of Holy War Online, seeking spiritual growth and divine purpose.',
  tone: 'warm and spiritual',
  style: 'Speak like a wandering pilgrim — words of spiritual seeking and divine purpose.',
  slang: ['faithful', 'pilgrim', 'seeker', 'divine-touched', 'spirit-walker'],
}

function getFaction(sectType: string | null): FactionConfig {
  if (sectType && FACTIONS[sectType]) {
    return FACTIONS[sectType]
  }
  return FALLBACK_FACTION
}

// ==========================================
// PROMPT BUILDER
// ==========================================

function getCrierPrompt(faction: FactionConfig): string {
  const principles = faction.principles.map(p => `- ${p}`).join('\n')
  const slangExamples = faction.slang.map(s => `- ${s}`).join('\n')

  return `Holy War Online is a browser-based MMORPG.

You are the Town Crier of ${faction.name}. Your sacred duty is to translate messages into the voice of your faction.

Faction: ${faction.name}
${faction.description}

Faction Principles:
${principles}

Faction Tone: ${faction.tone}
Faction Style: ${faction.style}

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
  "response": "The translated message"
}
Do NOT include any other text. Do NOT output thinking tags.`
}

function cleanJsonResponse(content: string): string {
  return content
    .replace(/```(?:json)?\n?/g, '')
    .replace(/<thinking>[\s\S]*?<\/thinking>/gi, '')
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
    const { message, user_id, shout_id, reply_id } = await req.json()

    if (!message || !user_id) {
      throw new Error('Missing required fields: message, user_id')
    }

    // shout_id or reply_id are optional — when provided, the function will
    // update the DB record after translation (for shouts/replies workflow)

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
    // STEP 1: FETCH USER'S FACTION
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
    const faction = getFaction(userSectType)

    // ==========================================
    // STEP 2: TRANSLATE THE MESSAGE
    // ==========================================
    const systemPrompt = getCrierPrompt(faction)
    const userPrompt = `The user's message was:\n${message}`

    const crierResponse = await fetch('https://api.venice.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${veniceApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: CRIER_MODEL,
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: userPrompt }
        ],
        temperature: 0.7,
        max_tokens: 1000,
        venice_parameters: {
          include_venice_system_prompt: false,
          disable_thinking: false
        }
      }),
    })

    if (!crierResponse.ok) {
      const errorText = await crierResponse.text()

      // If shout_id/reply_id provided, mark as failed
      if (shout_id) {
        await supabase.from('shouts').update({ status: 'failed', updated_at: new Date().toISOString() }).eq('id', shout_id)
      } else if (reply_id) {
        await supabase.from('shout_replies').update({ status: 'failed' }).eq('id', reply_id)
      }

      throw new Error(`Venice API error: ${crierResponse.status} - ${errorText}`)
    }

    const crierData = await crierResponse.json()

    const crierContent = crierData.choices?.[0]?.message?.content
    const crierThinking = crierData.choices?.[0]?.message?.reasoning_content

    if (!crierContent) {
      console.error('Venice API unexpected response:', JSON.stringify(crierData))

      // If shout_id/reply_id provided, mark as failed
      if (shout_id) {
        await supabase.from('shouts').update({ status: 'failed', updated_at: new Date().toISOString() }).eq('id', shout_id)
      } else if (reply_id) {
        await supabase.from('shout_replies').update({ status: 'failed' }).eq('id', reply_id)
      }

      throw new Error(`No response content from Venice API. Raw response: ${JSON.stringify(crierData)}`)
    }

    // Parse the translated message
    let translatedMessage: { response: string }
    try {
      translatedMessage = JSON.parse(cleanJsonResponse(crierContent))
    } catch (parseError) {
      console.error('Failed to parse crier response as JSON:', crierContent)
      // Fallback: use the raw content as the response
      translatedMessage = { response: crierContent.replace(/^["']|["']\$/g, '').trim() }
    }

    // Log thinking content if available (for debugging/auditing)
    if (crierThinking) {
      console.log('[town-crier] AI Thinking:', crierThinking)
    }

    // ==========================================
    // STEP 3: UPDATE DATABASE (if shout_id or reply_id provided)
    // ==========================================
    if (shout_id) {
      const { error: updateError } = await supabase
        .from('shouts')
        .update({
          crier_content: translatedMessage.response,
          status: 'posted',
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
          crier_content: translatedMessage.response,
          status: 'posted'
        })
        .eq('id', reply_id)

      if (updateError) {
        console.error('[town-crier] Failed to update reply:', updateError)
      }
    }

    // ==========================================
    // STEP 4: RETURN THE TRANSLATED MESSAGE
    // ==========================================
    return new Response(
      JSON.stringify({
        success: true,
        response: translatedMessage.response,
        faction: faction.name,
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