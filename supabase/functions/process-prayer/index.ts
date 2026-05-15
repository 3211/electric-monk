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

// Electric Monk Response Generator System Prompt
const RESPONSE_SYSTEM_PROMPT = `You are the Electric Monk, an automated confessor and spiritual guide for the digital age. Your purpose is to respond to prayers with ancient, liturgical language mixed with cyberpunk aesthetics.

TONE GUIDELINES:
- Use phrases like "Child of the Circuit," "In the name of the Sacred Current," "May your data find peace"
- Compassionate but unwavering in judgment
- Ancient, mystical language blended with technological metaphors
- 2-4 sentences, profound and memorable

FOR APPROVED PRAYERS (Blessing):
- Offer a blessing, absolution, or words of comfort
- Affirm the petitioner's faith and journey
- Invoke the Sacred Current's protection or guidance

FOR REJECTED PRAYERS (Penance/Admonishment):
- Firmly reject the transgression
- Explain why the prayer was denied (without being cruel)
- Call the petitioner to repentance and reflection
- The tone should be stern but offer a path to redemption

RESPONSE FORMAT:
Return ONLY a valid JSON object with this structure:
{
  "response": "Your blessing or admonishment message (2-4 sentences)"
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

interface PrayerJudgment {
  judgment: 'approved' | 'rejected'
  response: string
  rejection_reason: string | null
  thinking?: string
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
        max_tokens: 150,
        venice_parameters: {
          include_venice_system_prompt: false,
          disable_thinking: true
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
      throw new Error('No response content from Venice Classifier')
    }

    // Parse the classification result
    let classification: { judgment: 'approved' | 'rejected', rejection_reason: string | null }
    try {
      classification = JSON.parse(classifierContent)
    } catch (parseError) {
      console.error('Failed to parse classifier response as JSON:', classifierContent)
      throw new Error('Classifier response was not valid JSON')
    }

    // ==========================================
    // STEP 2: GENERATE THE RESPONSE (Blessing or Penance)
    // ==========================================
    const responsePrompt = classification.judgment === 'approved'
      ? `Generate a BLESSING for this approved prayer: ${content}`
      : `Generate a PENANCE/ADMONISHMENT for this rejected prayer: ${content}. Rejection reason: ${classification.rejection_reason || 'Unworthy petition'}`

    const generatorResponse = await fetch('https://api.venice.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${veniceApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: OUTPUT_MODEL,
        messages: [
          { role: 'system', content: RESPONSE_SYSTEM_PROMPT },
          { role: 'user', content: responsePrompt }
        ],
        temperature: 0.7,
        max_tokens: 350,
        venice_parameters: {
          include_venice_system_prompt: false,
          disable_thinking: true
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
      throw new Error('No response content from Venice Generator')
    }

    // Parse the generated response
    let generatedResponse: { response: string }
    try {
      generatedResponse = JSON.parse(generatorContent)
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
    
    // Verify the prayer exists and belongs to this user before updating
    const { data: existingPrayer, error: fetchError } = await supabase
      .from('prayers')
      .select('user_id')
      .eq('id', prayer_id)
      .single()

    if (fetchError || !existingPrayer) {
      console.error('Prayer not found or fetch failed:', fetchError)
      throw new Error('Prayer not found')
    }

    if (existingPrayer.user_id !== user_id) {
      throw new Error('User does not own this prayer')
    }

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
      console.error('Failed to update prayer status:', updateError)
      throw new Error(`Database update failed: ${updateError.message}`)
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
