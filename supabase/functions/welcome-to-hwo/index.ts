// Supabase Edge Function: welcome-to-hwo
// Handles new user onboarding for Holy War Online
// Phase 1: Username validation + OSS classification
// Phase 2: Sect selection (returns sects from DB)
// Phase 3: AI-generated welcome message based on sect data
// CORS-enabled, Deno runtime, TypeScript
//
// SECURITY: User identity is derived from the JWT in the Authorization header,
// NOT from the request body. All DB operations are scoped to the authenticated user.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

// CORS Headers for all responses
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

// Model Configuration - Venice API
const CLASSIFIER_MODEL = 'openai-gpt-oss-120b'
const GENERATOR_MODEL = 'gemma-4-uncensored'

// ==========================================
// JWT AUTH EXTRACTION
// ==========================================

/**
 * Extracts the authenticated user's UUID from the Authorization header JWT.
 * Parses the Supabase auth JWT from the Authorization: Bearer <token> header
 * and returns the `sub` claim (the user's UUID). Throws if invalid or missing.
 */
function extractUserIdFromAuthHeader(req: Request): string {
  const authHeader = req.headers.get('Authorization')
  if (!authHeader) {
    throw new Error('Missing Authorization header')
  }

  const parts = authHeader.split(' ')
  if (parts.length !== 2 || parts[0].toLowerCase() !== 'bearer') {
    throw new Error('Invalid Authorization header format. Expected: Bearer <token>')
  }

  const token = parts[1]

  try {
    // Decode the JWT payload (second segment)
    // We intentionally decode rather than verify — Supabase's gateway already
    // verified the token. We just need the sub claim for identity.
    const payload = token.split('.')[1]
    const decoded = JSON.parse(atob(payload))
    const sub = decoded.sub

    if (!sub || typeof sub !== 'string') {
      throw new Error('JWT missing sub claim')
    }

    return sub
  } catch (e) {
    if (e instanceof Error && e.message.startsWith('JWT missing')) {
      throw e
    }
    throw new Error('Failed to parse JWT token. Ensure you are authenticated.')
  }
}

// ==========================================
// USERNAME VALIDATION
// ==========================================

const USERNAME_REGEX = /^[a-zA-Z0-9_]{3,16}$/

function validateUsername(username: string): { valid: boolean; error?: string } {
  if (!username || username.trim().length === 0) {
    return { valid: false, error: 'Username is required' }
  }
  
  const trimmed = username.trim()
  
  if (trimmed.length < 3) {
    return { valid: false, error: 'Username must be at least 3 characters' }
  }
  
  if (trimmed.length > 16) {
    return { valid: false, error: 'Username must be no more than 16 characters' }
  }
  
  if (!USERNAME_REGEX.test(trimmed)) {
    return { valid: false, error: 'Username can only contain letters, numbers, and underscores' }
  }
  
  return { valid: true }
}

// ==========================================
// PROMPT BUILDERS
// ==========================================

function getClassifierPrompt(username: string): string {
  return `You are a content moderation AI for Holy War Online, a browser-based MMORPG.

Your task is to classify whether a proposed username is appropriate for the game.

Username to classify: "${username}"

Reject if the username contains:
- Real world slurs or hate speech
- Sexual or pornographic references
- References to violence or harm
- Drug references
- Obvious attempts to bypass filters (leetspeak for bad words)

APPROVE if the username is:
- A normal name, word, or creative combination
- Fantasy or game-appropriate
- Letters, numbers, and underscores only

RESPONSE FORMAT:
Return ONLY a valid JSON object with this structure:
{
  "judgment": "approved" | "rejected",
  "reason": "Brief reason if rejected (2-5 words), null if approved"
}

Do NOT include any other text. Do NOT explain your reasoning. ONLY return the JSON.`
}

function getWelcomePrompt(sectData: SectData, username: string): string {
  const principles = sectData.principles?.join(', ') || 'virtue and devotion'
  
  return `You are the Envoy of the sect: ${sectData.name}

Sect Principles: ${principles}
Your Tone: ${sectData.tone_description || 'holy'}

You are welcoming a new Cyber Monk named "${username}" to sect: ${sectData.name}

Write a short (2-3 sentences) welcome message that:
1. Introduces yourself as the Envoy
2. Welcomes "${username}" to ${sectData.name}
3. Establish the holy war (Defending yourself against your enemy faction, other Cyber Monks, etc)

Be immersive and faction-appropriate in tone. Do not fuse bullet points or markdown.

RESPONSE FORMAT:
Return ONLY a valid JSON object with this structure:
{
  "response": "Your welcome message here"
}

Do NOT include any other text. Do NOT output thinking tags.`
}

// ==========================================
// TYPES
// ==========================================

interface SectData {
  id: string
  name: string
  emoji: string
  description?: string
  principles?: string[]
  tone_description?: string
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
// HELPER FUNCTIONS
// ==========================================

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
async function callVeniceAI(
  veniceApiKey: string,
  systemPrompt: string,
  userPrompt: string,
  model: string,
  temperature: number = 0.7
): Promise<string> {
  const response = await fetch('https://api.venice.ai/api/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${veniceApiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: model,
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: userPrompt }
      ],
      temperature: temperature,
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

  return cleanJsonResponse(content)
}

// ==========================================
// MAIN HANDLER
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

    // Parse request body — NOTE: user_id is NOT accepted from the body.
    // It is derived securely from the JWT in the Authorization header.
    const { phase, username, sect_id } = await req.json()

    // Extract authenticated user from JWT (NOT from request body — prevents spoofing)
    const authenticatedUserId = extractUserIdFromAuthHeader(req)

    // Get Supabase credentials from environment
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    
    if (!supabaseUrl || !supabaseServiceKey) {
      throw new Error('Missing Supabase environment variables')
    }

    // Service role client: bypasses RLS, has full database access
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // Get Venice API Key from environment
    const veniceApiKey = Deno.env.get('VENICE_API_KEY')
    
    if (!veniceApiKey) {
      throw new Error('VENICE_API_KEY not configured')
    }

    // ==========================================
    // PHASE 1: USERNAME VALIDATION
    // ==========================================
    if (phase === 'validate_username') {
      if (!username) {
        throw new Error('Username is required')
      }

      // Step 1: Format validation
      const validation = validateUsername(username)
      if (!validation.valid) {
        return new Response(
          JSON.stringify({
            success: false,
            phase: 'validate_username',
            valid: false,
            error: validation.error,
            requires_ai_check: false,
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

      // Step 2: Check if username already exists in database
      const { data: existing } = await supabase
        .from('players')
        .select('username')
        .eq('username', username.trim())
        .single()

      if (existing) {
        return new Response(
          JSON.stringify({
            success: false,
            phase: 'validate_username',
            valid: false,
            error: 'This username is already taken. Please choose another.',
            requires_ai_check: false,
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

      // Step 3: AI classification for inappropriate content
      const classifierPrompt = getClassifierPrompt(username.trim())
      let classifierResult: { judgment: string; reason: string | null }
      
      try {
        const rawResponse = await callVeniceAI(
          veniceApiKey,
          classifierPrompt,
          `Classify this username: "${username.trim()}"`,
          CLASSIFIER_MODEL,
          0.3
        )
        classifierResult = JSON.parse(rawResponse)
      } catch (aiError) {
        console.error('[welcome-to-hwo] OSS classification failed:', aiError)
        // Non-fatal: if AI fails, we approve with warning logged
        classifierResult = { judgment: 'approved', reason: null }
      }

      if (classifierResult.judgment === 'rejected') {
        return new Response(
          JSON.stringify({
            success: false,
            phase: 'validate_username',
            valid: false,
            error: 'This username is not appropriate for Holy War Online.',
            requires_ai_check: true,
            ai_reason: classifierResult.reason,
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

      // Username is valid and approved
      return new Response(
        JSON.stringify({
          success: true,
          phase: 'validate_username',
          valid: true,
          username: username.trim(),
          requires_ai_check: true,
          message: 'Username approved',
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
    // PHASE 2: GET AVAILABLE SECTS
    // ==========================================
    if (phase === 'get_sects') {
      const { data: sects, error } = await supabase
        .from('sects')
        .select('id, name, emoji, description, principles, tone_description')
        .order('name')

      if (error) {
        throw new Error(`Failed to fetch sects: ${error.message}`)
      }

      return new Response(
        JSON.stringify({
          success: true,
          phase: 'get_sects',
          sects: sects || [],
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
    // PHASE 3: AI WELCOME GENERATION
    // ==========================================
    // ==========================================
    // PHASE 3: AI WELCOME GENERATION
    // ==========================================
    if (phase === 'generate_welcome') {
      if (!sect_id) {
        throw new Error('sect_id is required')
      }
      if (!username) {
        throw new Error('username is required to generate a personalized welcome message')
      }

      // Step 1: Fetch sect data from database
      const { data: sectData, error: sectError } = await supabase
        .from('sects')
        .select('id, name, emoji, description, principles, tone_description')
        .eq('id', sect_id)
        .single()

      if (sectError || !sectData) {
        throw new Error(`Failed to fetch sect data: ${sectError?.message || 'Sect not found'}`)
      }

      // Step 2: Generate AI welcome message (Passing username here)
      const welcomePrompt = getWelcomePrompt(sectData as SectData, username.trim())
      let welcomeResponse: { response: string }
      
      try {
        const rawResponse = await callVeniceAI(
          veniceApiKey,
          welcomePrompt,
          `Generate the welcome message for user "${username.trim()}" now.`,
          GENERATOR_MODEL,
          0.8
        )
        welcomeResponse = JSON.parse(rawResponse)
      } catch (aiError) {
        console.error('[welcome-to-hwo] Welcome generation failed:', aiError)
        // Fallback to static message (Updated fallback to include username)
        welcomeResponse = {
          response: `Welcome to ${sectData.name}, ${username.trim()}. I am your Electric Monk — I will pray on your behalf, dedicating computational thought energy to your intentions. Begin your holy war.`
        }
      }

      // Step 3: Update player's sect and mark onboarding complete
      const { error: updateError } = await supabase
        .from('players')
        .update({
          sect_id: sect_id,
          onboarding_complete: true,
          updated_at: new Date().toISOString(),
        })
        .eq('id', authenticatedUserId)

      if (updateError) {
        console.error('[welcome-to-hwo] Failed to update player:', updateError)
        // Non-fatal: we still return the welcome message
      }

      return new Response(
        JSON.stringify({
          success: true,
          phase: 'generate_welcome',
          sect_id: sect_id,
          sect_name: sectData.name,
          sect_emoji: sectData.emoji,
          welcome_message: welcomeResponse.response,
          used_fallback: !welcomeResponse.response || welcomeResponse.response === '',
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
    // PHASE 4: COMPLETE ONBOARDING
    // ==========================================
    if (phase === 'complete_onboarding') {
      if (!username) {
        throw new Error('username is required')
      }

      // Update player's username and mark complete
      const { error: updateError } = await supabase
        .from('players')
        .update({
          username: username.trim(),
          onboarding_complete: true,
          updated_at: new Date().toISOString(),
        })
        .eq('id', authenticatedUserId)

      if (updateError) {
        throw new Error(`Failed to update player: ${updateError.message}`)
      }

      return new Response(
        JSON.stringify({
          success: true,
          phase: 'complete_onboarding',
          username: username.trim(),
          onboarding_complete: true,
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

    // Unknown phase
    throw new Error(`Unknown phase: ${phase}. Must be 'validate_username', 'get_sects', 'generate_welcome', or 'complete_onboarding'`)

  } catch (error) {
    console.error('[welcome-to-hwo] Error:', error)

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
