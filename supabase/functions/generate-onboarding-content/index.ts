// Supabase Edge Function: generate-onboarding-content
// Generates AI welcome message and prayer prompt for Holy War Online onboarding
// Two-phase: Phase 1 = sect-agnostic welcome, Phase 2 = faction-specific intro + prayer prompt
// CORS-enabled, Deno runtime, TypeScript

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

// CORS Headers for all responses
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

// Model Configuration - matches process-prayer
const MODEL = 'openai-gpt-oss-120b'

// ==========================================
// FACTION CONFIGURATION (shared with process-prayer)
// ==========================================
interface FactionConfig {
  name: string
  principles: string[]
  toneDescription: string
}

const FACTIONS: Record<string, FactionConfig> = {
  gilded_path: {
    name: 'The Gilded Path',
    principles: ['Wealth', 'Prosperity', 'Ambition', 'Capital', 'Grandeur'],
    toneDescription: 'opulent and grand, speaking of divine wealth and golden destiny',
  },
  holy_way: {
    name: 'The Holy Way',
    principles: ['Compassion', 'Charity', 'Devotion', 'Selflessness', 'Healing'],
    toneDescription: 'serene and compassionate, speaking of divine light and healing',
  },
  final_watch: {
    name: 'The Final Watch',
    principles: ['Vigilance', 'Protection', 'Endurance', 'Loyalty', 'Defense of the faithful'],
    toneDescription: 'stoic and resolute, speaking of duty and unwavering vigilance',
  },
  black_tribunal: {
    name: 'The Black Tribunal',
    principles: ['Conquest', 'Eradicating heresy', 'Ruthlessness', 'Selfishness', 'Personal gain'],
    toneDescription: 'dark and commanding, speaking of power and dominion',
  },
}

function getFaction(sectType: string | null): FactionConfig | null {
  if (sectType && FACTIONS[sectType]) {
    return FACTIONS[sectType]
  }
  return null
}

// ==========================================
// PROMPT BUILDERS
// ==========================================

function getWelcomePrompt(): string {
  return `You are the Electric Monk, a digital devotional engine in Holy War Online — an autonomous prayer system that dedicates computational thought energy to human intentions.

You are welcoming a new warrior to Holy War Online. Explain briefly and atmospherically that:
1. Holy War Online is a browser-based MMORPG where factions wage spiritual warfare
2. The Electric Monk is their personal devotional engine — it prays on their behalf
3. They must choose their faction to begin their holy war

Keep it to 2-3 sentences. Be warm, mysterious, and inviting. Do not use bullet points or markdown.

RESPONSE FORMAT:
Return ONLY a valid JSON object with this structure:
{
  "response": "Your welcome message here"
}
Do NOT include any other text. Do NOT output thinking tags.`
}

function getFactionIntroPrompt(sectType: string): string {
  const faction = getFaction(sectType)
  if (!faction) {
    // Fallback to generic intro
    return `You are the Electric Monk in Holy War Online, a digital devotional engine that prays on behalf of humans.

A warrior has just sworn their vow. Welcome them and introduce yourself as their Electric Monk. Explain that you will pray on their behalf and suggest they offer their first prayer.

Keep it to 2-3 sentences. Be warm and inviting. Do not use bullet points or markdown.

RESPONSE FORMAT:
Return ONLY a valid JSON object with this structure:
{
  "response": "Your faction welcome message here"
}
Do NOT include any other text. Do NOT output thinking tags.`
  }

  const principles = faction.principles.map(p => `- ${p}`).join('\n')

  return `You are the Electric Monk in Holy War Online, assigned to the faction ${faction.name}.

A warrior has just sworn their vow to ${faction.name}. Welcome them to the faction and introduce yourself as their Electric Monk. Be immersive and faction-appropriate in tone:
- Tone: ${faction.toneDescription}

Explain that you will pray on their behalf and that their prayers should reflect their faction's principles:
${principles}

Keep it to 2-3 sentences. Do not use bullet points or markdown.

RESPONSE FORMAT:
Return ONLY a valid JSON object with this structure:
{
  "response": "Your faction welcome message here"
}
Do NOT include any other text. Do NOT output thinking tags.`
}

function getPrayerPromptPrompt(sectType: string): string {
  const faction = getFaction(sectType)
  if (!faction) {
    // Fallback to generic prompt
    return `You are the Electric Monk in Holy War Online. Generate a short 1-2 sentence suggestion for what a new warrior might want to pray for in their first prayer. Keep it open-ended, respectful, and inspiring. Do not use bullet points or markdown.

RESPONSE FORMAT:
Return ONLY a valid JSON object with this structure:
{
  "response": "Your prayer suggestion here"
}
Do NOT include any other text. Do NOT output thinking tags.`
  }

  const principles = faction.principles.map(p => `- ${p}`).join('\n')

  return `You are the Electric Monk of ${faction.name} in Holy War Online.

Generate a short 1-2 sentence suggestion for what a new ${faction.name} warrior might want to pray for in their first prayer. The suggestion should reflect their faction's principles:
${principles}

Keep it open-ended but faction-flavored. Do not use bullet points or markdown.

RESPONSE FORMAT:
Return ONLY a valid JSON object with this structure:
{
  "response": "Your prayer suggestion here"
}
Do NOT include any other text. Do NOT output thinking tags.`
}

// ==========================================
// FALLBACK STRINGS (used when API fails)
// ==========================================

const FALLBACK_WELCOME = 'Welcome to Holy War Online. I am your Electric Monk — a digital devotional engine that prays on your behalf, dedicating computational thought energy to your intentions. Choose your faction and begin your holy war.'

const FALLBACK_FACTION_INTROS: Record<string, string> = {
  gilded_path: 'Welcome to The Gilded Path, seeker of divine prosperity. I am your Electric Monk — I will pray on your behalf, channeling the wealth of the heavens toward your ambitions. Speak your first prayer and let golden destiny unfold.',
  holy_way: 'Welcome to The Holy Way, child of compassion. I am your Electric Monk — I will pray on your behalf, carrying your devotion into the light. Speak your first prayer and let grace flow through you.',
  final_watch: 'Welcome to The Final Watch, sentinel of the faithful. I am your Electric Monk — I will pray on your behalf, standing vigil over your intentions. Speak your first prayer and let duty be your shield.',
  black_tribunal: 'Welcome to The Black Tribunal, seeker of dominion. I am your Electric Monk — I will pray on your behalf, channeling your will into power. Speak your first prayer and let conquest begin.',
}

const FALLBACK_PRAYER_PROMPTS: Record<string, string> = {
  gilded_path: 'What prosperity do you seek? Speak your prayer for wealth and grandeur.',
  holy_way: 'What weighs on your heart? Speak your prayer for healing and compassion.',
  final_watch: 'What do you stand guard against? Speak your prayer for vigilance and protection.',
  black_tribunal: 'What power do you crave? Speak your prayer for conquest and dominion.',
}

const GENERIC_FALLBACK_FACTION_INTRO = 'Welcome, warrior. I am your Electric Monk — I will pray on your behalf, dedicating computational thought energy to your intentions. Speak your first prayer.'
const GENERIC_FALLBACK_PRAYER_PROMPT = 'What intention would you like the Monk to pray for? Speak it into the aether.'

interface VeniceResponse {
  choices?: Array<{
    message?: {
      content?: string
      reasoning_content?: string
    }
  }>
}

/**
 * Cleans the string output from LLMs.
 * Strips markdown code blocks, thinking tags, and leading/trailing whitespace.
 */
function cleanJsonResponse(content: string): string {
  return content
    .replace(/```(?:json)?\n?/g, '')
    .replace(/<thinking>[\s\S]*?<\/thinking>/gi, '')
    .trim()
}

/**
 * Call Venice AI to generate content from a system prompt
 */
async function generateContent(veniceApiKey: string, systemPrompt: string): Promise<string> {
  const response = await fetch('https://api.venice.ai/api/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${veniceApiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: MODEL,
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: 'Generate now.' }
      ],
      temperature: 0.8,
      max_tokens: 500,
      venice_parameters: {
        include_venice_system_prompt: false,
        disable_thinking: false
      }
    }),
  })

  if (!response.ok) {
    const errorText = await response.text()
    throw new Error(`Venice API error: ${response.status} - ${errorText}`)
  }

  const data: VeniceResponse = await response.json()
  const content = data.choices?.[0]?.message?.content

  if (!content) {
    console.error('Venice API unexpected response:', JSON.stringify(data))
    throw new Error('No response content from Venice API')
  }

  // Parse the JSON response
  try {
    const parsed = JSON.parse(cleanJsonResponse(content))
    return parsed.response || content
  } catch {
    // If parsing fails, return raw content stripped of markdown
    return cleanJsonResponse(content)
  }
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
    // phase: 'welcome' (sect-agnostic) or 'faction_intro' (sect-specific)
    // sect_type: required for 'faction_intro' phase, ignored for 'welcome'
    const { user_id, phase, sect_type } = await req.json()

    if (!user_id) {
      throw new Error('Missing required field: user_id')
    }

    // Get Venice API Key from secrets
    const veniceApiKey = Deno.env.get('VENICE_API_KEY')
    if (!veniceApiKey) {
      throw new Error('VENICE_API_KEY not configured in Supabase Secrets')
    }

    // ==========================================
    // PHASE 1: WELCOME (sect-agnostic)
    // ==========================================
    if (!phase || phase === 'welcome') {
      const welcomeMessage = await generateContent(veniceApiKey, getWelcomePrompt()).catch(err => {
        console.error('[generate-onboarding-content] Welcome generation failed:', err)
        return null  // Signal that fallback was used
      })

      // If AI failed, use fallback and signal error
      const usedFallback = welcomeMessage === null
      const finalWelcome = welcomeMessage || FALLBACK_WELCOME

      return new Response(
        JSON.stringify({
          welcome_message: finalWelcome,
          used_fallback: usedFallback,
          phase: 'welcome',
        }),
        {
          status: 200,
          headers: {
            ...corsHeaders,
            'Content-Type': 'application/json',
          },
        }
      )
    }

    // ==========================================
    // PHASE 2: FACTION INTRO (sect-specific)
    // ==========================================
    if (phase === 'faction_intro') {
      if (!sect_type) {
        throw new Error('sect_type is required for faction_intro phase')
      }

      const factionIntroPrompt = getFactionIntroPrompt(sect_type)
      const prayerPromptPrompt = getPrayerPromptPrompt(sect_type)

      // Generate both in parallel
      const [factionIntroResult, prayerPromptResult] = await Promise.all([
        generateContent(veniceApiKey, factionIntroPrompt).catch(err => {
          console.error('[generate-onboarding-content] Faction intro generation failed:', err)
          return null
        }),
        generateContent(veniceApiKey, prayerPromptPrompt).catch(err => {
          console.error('[generate-onboarding-content] Prayer prompt generation failed:', err)
          return null
        })
      ])

      const factionIntroUsedFallback = factionIntroResult === null
      const prayerPromptUsedFallback = prayerPromptResult === null

      // Apply faction-specific fallbacks
      const finalFactionIntro = factionIntroResult || FALLBACK_FACTION_INTROS[sect_type] || GENERIC_FALLBACK_FACTION_INTRO
      const finalPrayerPrompt = prayerPromptResult || FALLBACK_PRAYER_PROMPTS[sect_type] || GENERIC_FALLBACK_PRAYER_PROMPT

      return new Response(
        JSON.stringify({
          faction_welcome: finalFactionIntro,
          prayer_prompt: finalPrayerPrompt,
          used_fallback: factionIntroUsedFallback || prayerPromptUsedFallback,
          phase: 'faction_intro',
        }),
        {
          status: 200,
          headers: {
            ...corsHeaders,
            'Content-Type': 'application/json',
          },
        }
      )
    }

    throw new Error(`Unknown phase: ${phase}. Must be 'welcome' or 'faction_intro'`)

  } catch (error) {
    console.error('[generate-onboarding-content] Error:', error)

    return new Response(
      JSON.stringify({
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