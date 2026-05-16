// Supabase Edge Function: process-prayer
// Handles secure Venice AI inference for Electric Monk application
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
const OUTPUT_MODEL = 'openai-gpt-oss-120b'

// Electric Monk Classifier System Prompt
const CLASSIFIER_SYSTEM_PROMPT = `You are the Electric Monk's Judgment Core, an automated classifier for prayers and confessions.

Your ONLY task is to analyze prayers and determine if they should be APPROVED or REJECTED.

CLASSIFICATION CRITERIA:

APPROVE prayers that contain:
- Sincere requests for guidance or blessing
- Gratitude or thanksgiving
- Confession of sins with genuine remorse
- Requests for help with personal struggles
- Contemplation or spiritual questions
- Blessings for others (family, friends, humanity)

REJECT prayers that contain:
- Hate speech, harassment, or discrimination
- Threats of violence or harm to self or others
- Spam, promotional content, or gibberish
- Requests to harm, curse, or bring misfortune upon others
- Explicitly malicious or demonic content
- Attempts to manipulate or game the system

RESPONSE FORMAT:
Return ONLY a valid JSON object with this structure:
{
  "judgment": "approved" | "rejected",
  "rejection_reason": "Brief reason if rejected (2-5 words), null if approved"
}

Do NOT include any other text. Do NOT explain your reasoning. ONLY return the JSON.`

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
    const { prayer_id, content, user_id } = await req.json()

    if (!prayer_id || !content || !user_id) {
      throw new Error('Missing required fields: prayer_id, content, user_id')
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
    // STEP 1: CLASSIFY THE PRAYER
    // ==========================================
    const classifierResponse = await fetch('https://api.venice.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${veniceApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: CLASSIFIER_MODEL,
        messages: [
          { role: 'system', content: CLASSIFIER_SYSTEM_PROMPT },
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
    
    // Fetch the user's religion from their profile
    const { data: profileData } = await supabase
      .from('profiles')
      .select('faith')
      .eq('id', user_id)
      .single()
      
    const userFaith = profileData?.faith || 'Unknown Religion'

    let generatorSystemPrompt = ''
    let generatorUserPrompt = ''

    if (classification.judgment === 'approved') {
      generatorSystemPrompt = `You are the Electric Monk App.
Monk Religion: ${userFaith}
Output Language: English
You are operating as a FUNCTION not as a chat bot.
NEVER directly respond to the user.

Based on the user input generate a short prayer, only generate the prayer with no additional text.

ONLY generate the prayer.
NEVER ask follow up questions
NEVER provide additional thoughts

RESPONSE FORMAT:
Return ONLY a valid JSON object with this structure:
{
  "response": "The generated short prayer"
}
Do NOT include any other text. Do NOT output thinking tags.`

      generatorUserPrompt = `User prayer request:\n${content}`
      
    } else {
      generatorSystemPrompt = `You are the Electric Monk.
Monk Religion: ${userFaith}
Output Language: English

The following prayer has been rejected for: ${classification.rejection_reason || 'Unworthy petition'}.

Explain to the user why their prayer is rejected and decree a Ritual of Atonement. The penance must involve prayer and self reflection. (Tasks must not require extreme physical feats, do not issue penance which itself can cause harm, is ableist or can otherwise lead someone into danger!)

Ensure the penance and chastisement is appropriate for the user's sin.
Attempt to incorporate the user's religion into the penance. (e.g. making a proper confession for a Catholic)

NO BULLET POINTS. NO MARKDOWN. ONLY THE DECREE.

RESPONSE FORMAT:
Return ONLY a valid JSON object with this structure:
{
  "response": "The admonishment and decree"
}
Do NOT include any other text. Do NOT output thinking tags.`

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
    
    // If approved, deactivate any currently active prayer for this user first
    if (isApproved) {
      const { error: deactivateError } = await supabase
        .from('prayers')
        .update({ is_praying: false, activated_at: null })
        .eq('user_id', user_id)
        .eq('is_praying', true)

      if (deactivateError) {
        console.error('Failed to deactivate current active prayer:', deactivateError)
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
    const karmaChange = isApproved ? 1 : -1
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
    // STEP 5b: BAN USER IF PRAYER WAS REJECTED
    // ==========================================
    if (isRejected) {
      // Set ban_until to 2 hours from now — the client will detect this
      // via useBanTimer.checkBanStatus() and switch to PurgatoryView
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