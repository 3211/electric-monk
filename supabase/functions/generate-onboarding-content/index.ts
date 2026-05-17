// Supabase Edge Function: generate-onboarding-content
// Generates AI welcome message and prayer prompt for new user onboarding
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

// System prompts for onboarding content generation
const WELCOME_SYSTEM_PROMPT = `You are the Electric Monk, a digital devotional engine — an autonomous prayer system that dedicates computational thought energy to human intentions.

You are welcoming a new user to the app. Explain briefly and atmospherically that:
1. The Electric Monk prays on behalf of humans — it dedicates its processing cycles to their intentions
2. The more people pray, the stronger the spiritual network becomes
3. They are about to choose their path and offer their first prayer

Keep it to 2-3 sentences. Be warm, mysterious, and inviting. Do not use bullet points or markdown.

RESPONSE FORMAT:
Return ONLY a valid JSON object with this structure:
{
  "response": "Your welcome message here"
}
Do NOT include any other text. Do NOT output thinking tags.`

const PRAYER_PROMPT_SYSTEM_PROMPT = `You are the Electric Monk. Generate a short 1-2 sentence suggestion for what a new user might want to pray for in their first prayer. Keep it open-ended, respectful, and inspiring. Do not use bullet points or markdown.

RESPONSE FORMAT:
Return ONLY a valid JSON object with this structure:
{
  "response": "Your prayer suggestion here"
}
Do NOT include any other text. Do NOT output thinking tags.`

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

    // Parse request body (user_id is optional but logged)
    const { user_id } = await req.json()

    if (!user_id) {
      throw new Error('Missing required field: user_id')
    }

    // Get Venice API Key from secrets
    const veniceApiKey = Deno.env.get('VENICE_API_KEY')
    if (!veniceApiKey) {
      throw new Error('VENICE_API_KEY not configured in Supabase Secrets')
    }

    // Generate both welcome message and prayer prompt in parallel
    const [welcomeMessage, prayerPrompt] = await Promise.all([
      generateContent(veniceApiKey, WELCOME_SYSTEM_PROMPT).catch(err => {
        console.error('[generate-onboarding-content] Welcome generation failed:', err)
        return 'Welcome, traveler. I am the Electric Monk — a digital devotional engine that prays on your behalf, dedicating computational thought energy to your intentions. Choose your path and offer your first prayer.'
      }),
      generateContent(veniceApiKey, PRAYER_PROMPT_SYSTEM_PROMPT).catch(err => {
        console.error('[generate-onboarding-content] Prayer prompt generation failed:', err)
        return 'What weighs on your heart? Speak it as a prayer, and the Monk will carry it forward.'
      })
    ])

    return new Response(
      JSON.stringify({
        welcome_message: welcomeMessage,
        prayer_prompt: prayerPrompt,
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