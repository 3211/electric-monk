// Supabase Edge Function: pray-for-sinner
// Generates an intercessory prayer for a sinner using Venice AI
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
const OUTPUT_MODEL = 'openai-gpt-oss-120b'

// Intercessory Prayer System Prompt
const INTERCESORY_SYSTEM_PROMPT = `You are the Electric Monk App, generating an intercessory prayer.
Monk Religion: {faith}
Output Language: English

A sinner has been condemned for: {rejection_reason}

Generate a short, compassionate intercessory prayer that offers redemption and spiritual guidance for this sinner. The prayer should:
- Be merciful and hopeful, not judgmental
- Incorporate elements of the monk's religion ({faith}) where appropriate
- Offer a path to redemption and spiritual renewal
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

    // Fetch the praying user's faith for the monk's religion
    const { data: prayingUser } = await supabase
      .from('profiles')
      .select('faith')
      .eq('id', user_id)
      .single()

    const faith = prayingUser?.faith || sinnerProfile?.faith || 'Universal Spirituality'
    const rejectionReason = rejectedPrayer?.rejection_reason || 'Spiritual transgression'
    const sinnerUsername = sinnerProfile?.username || 'this soul'

    // Get Venice API Key from secrets
    const veniceApiKey = Deno.env.get('VENICE_API_KEY')
    if (!veniceApiKey) {
      throw new Error('VENICE_API_KEY not configured in Supabase Secrets')
    }

    // Build the system prompt with actual values
    const systemPrompt = INTERCESORY_SYSTEM_PROMPT
      .replace(/{faith}/g, faith)
      .replace(/{rejection_reason}/g, rejectionReason)

    const userPrompt = `Generate an intercessory prayer for ${sinnerUsername}, who has been condemned for: ${rejectionReason}. The prayer should offer redemption and spiritual guidance based on the faith of ${faith}.`

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