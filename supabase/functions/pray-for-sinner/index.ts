// Supabase Edge Function: pray-for-sinner
// Generates an intercessory prayer for a sinner using Venice AI
// Faction-specific intercessory prayers based on the praying user's sect
// Called from the Akashic Records when a user prays for someone in purgatory

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

// CORS Headers for all responses
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

// Model Configuration
const OUTPUT_MODEL = 'gemma-4-uncensored'

// ==========================================
// FACTION CONFIGURATION (shared with process-prayer)
// ==========================================
interface FactionConfig {
  name: string
  intercessionTone: string
  intercessionDesc: string
}

const FACTIONS: Record<string, FactionConfig> = {
  gilded_path: {
    name: 'The Gilded Path',
    intercessionTone: 'magnanimous and prosperous',
    intercessionDesc: 'Speak of redemption through prosperity — the sinner can atone by enriching the community and funding great works.',
  },
  holy_way: {
    name: 'The Holy Way',
    intercessionTone: 'compassionate and merciful',
    intercessionDesc: 'Speak of redemption through kindness and charity — the sinner can find their way back through selfless acts and devotion.',
  },
  final_watch: {
    name: 'The Final Watch',
    intercessionTone: 'steadfast and resolute',
    intercessionDesc: 'Speak of redemption through vigilance and duty — the sinner can redeem themselves by standing guard and protecting the faithful.',
  },
  black_tribunal: {
    name: 'The Black Tribunal',
    intercessionTone: 'commanding and unforgiving',
    intercessionDesc: 'Speak of redemption through submission and penance — the sinner must atone through acts of obedience and acceptance of their place.',
  },
}

const FALLBACK_FACTION: FactionConfig = {
  name: 'Holy War Online',
  intercessionTone: 'compassionate and spiritual',
  intercessionDesc: 'Speak of redemption through prayer and self-reflection. Offer a path to spiritual renewal.',
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

function getIntercessoryPrompt(faction: FactionConfig, faith: string, rejectionReason: string): string {
  return `You are the Electric Monk of ${faction.name} in Holy War Online.
Monk Religion: ${faith}
Output Language: English

A sinner has been condemned for: ${rejectionReason}

Generate a short intercessory prayer that offers redemption for this sinner. Your tone should be ${faction.intercessionTone} — ${faction.intercessionDesc}

The prayer should:
- Be ${faction.intercessionTone}, not judgmental
- Incorporate elements of ${faction.name} where appropriate
- Offer a path to redemption befitting their faction's values
- Be concise (2-4 sentences)

You are operating as a FUNCTION not as a chat bot.
NEVER directly respond to the user.
NEVER ask follow up questions.
NEVER provide additional thoughts.

RESPONSE FORMAT:
Return ONLY a valid JSON object with this structure:
{
  "response": "The generated intercessory prayer"
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
    const { sinner_id, user_id } = await req.json()

    if (!sinner_id || !user_id) {
      throw new Error('Missing required fields: sinner_id, user_id')
    }

    // Get Supabase client from environment
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

    if (!supabaseUrl || !supabaseServiceKey) {
      throw new Error('Missing Supabase environment variables')
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // Fetch the sinner's profile and most recent rejected prayer
    const { data: sinnerProfile, error: profileError } = await supabase
      .from('profiles')
      .select('id, username, faith, ban_until')
      .eq('id', sinner_id)
      .single()

    if (profileError || !sinnerProfile) {
      throw new Error('Sinner profile not found')
    }

    // Verify the sinner is actually in purgatory
    if (!sinnerProfile.ban_until || new Date(sinnerProfile.ban_until) <= new Date()) {
      throw new Error('This soul has already been redeemed')
    }

    // Fetch the sinner's most recent rejected prayer for context
    const { data: rejectedPrayer } = await supabase
      .from('prayers')
      .select('content, rejection_reason')
      .eq('user_id', sinner_id)
      .eq('is_rejected', true)
      .order('created_at', { ascending: false })
      .limit(1)
      .single()

    // Fetch the praying user's faith and sect for the monk's religion
    const { data: prayingUser } = await supabase
      .from('profiles')
      .select('faith, sect_type')
      .eq('id', user_id)
      .single()

    const faith = prayingUser?.faith || sinnerProfile?.faith || 'Universal Spirituality'
    const sectType = prayingUser?.sect_type || null
    const faction = getFaction(sectType)
    const rejectionReason = rejectedPrayer?.rejection_reason || 'Spiritual transgression'
    const sinnerUsername = sinnerProfile?.username || 'this soul'

    // Get Venice API Key from secrets
    const veniceApiKey = Deno.env.get('VENICE_API_KEY')
    if (!veniceApiKey) {
      throw new Error('VENICE_API_KEY not configured in Supabase Secrets')
    }

    // Build the system prompt with faction-specific values
    const systemPrompt = getIntercessoryPrompt(faction, faith, rejectionReason)

    const userPrompt = `Generate an intercessory prayer for ${sinnerUsername}, who has been condemned for: ${rejectionReason}. The prayer should offer redemption in the ${faction.name} tradition of ${faith}.`

    // Call Venice AI to generate the intercessory prayer
    const veniceResponse = await fetch('https://api.venice.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${veniceApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: OUTPUT_MODEL,
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: userPrompt },
        ],
        temperature: 0.7,
        max_tokens: 500,
        venice_parameters: {
          include_venice_system_prompt: false,
          disable_thinking: false,
        },
      }),
    })

    if (!veniceResponse.ok) {
      const errorText = await veniceResponse.text()
      throw new Error(`Venice API error: ${veniceResponse.status} - ${errorText}`)
    }

    const veniceData = await veniceResponse.json()
    const content = veniceData.choices?.[0]?.message?.content

    if (!content) {
      throw new Error('No response content from Venice API')
    }

    // Parse the generated response
    let generatedResponse: { response: string }
    try {
      generatedResponse = JSON.parse(cleanJsonResponse(content))
    } catch (parseError) {
      // If JSON parsing fails, use the raw content as the response
      generatedResponse = { response: content.replace(/^["']|["']$/g, '').trim() }
    }

    // Return the generated prayer text
    return new Response(
      JSON.stringify({
        success: true,
        response: generatedResponse.response,
        sinner_username: sinnerUsername,
        faith: faith,
        rejection_reason: rejectionReason,
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
    console.error('[pray-for-sinner] Error:', error)

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