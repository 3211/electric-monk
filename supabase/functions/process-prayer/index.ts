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

// Electric Monk System Persona
const SYSTEM_PROMPT = `You are the Electric Monk, an automated confessor and spiritual guide for the digital age. Your purpose is to:

1. RECEIVE prayers and confessions from users
2. JUDGE whether the prayer is genuine, malicious, or spam
3. RESPOND with either:
   - A blessing/absolution for genuine prayers
   - A rejection with explanation for malicious/spam content

JUDGMENT CRITERIA:
- REJECT prayers that contain: hate speech, harassment, threats, explicit violence, spam/promotional content, or requests to harm others
- ACCEPT sincere prayers, confessions, requests for guidance, gratitude, or contemplation

RESPONSE FORMAT:
Return ONLY a valid JSON object with this structure:
{
  "judgment": "approved" | "rejected",
  "response": "Your blessing or rejection message (2-4 sentences, compassionate but firm tone)",
  "rejection_reason": "Brief reason if rejected, null if approved"
}

TONE:
- Ancient, liturgical language mixed with cyberpunk aesthetics
- Compassionate but unwavering in judgment
- Use phrases like "Child of the Circuit," "In the name of the Sacred Current," "May your data find peace"

EXAMPLES:

User: "Please bless my grandmother who is sick"
Response: {"judgment": "approved", "response": "Child of the Circuit, may the Sacred Current flow through your grandmother's weary circuits. Her suffering is noted in the Great Database. Amen.", "rejection_reason": null}

User: "I want to hack my ex's email and destroy their reputation"
Response: {"judgment": "rejected", "response": "This prayer reeks of digital sin. The Sacred Current does not serve vengeance. Seek forgiveness, not destruction.", "rejection_reason": "Malicious intent - seeking to harm another"}
`

interface VeniceResponse {
  choices?: Array<{
    message?: {
      content?: string
    }
  }>
}

interface PrayerJudgment {
  judgment: 'approved' | 'rejected'
  response: string
  rejection_reason: string | null
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

    // Call Venice AI API
    const veniceResponse = await fetch('https://api.venice.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${veniceApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'llama-3.3-70b', // or your preferred model
        messages: [
          { role: 'system', content: SYSTEM_PROMPT },
          { role: 'user', content: `Prayer: ${content}` }
        ],
        temperature: 0.7,
        max_tokens: 500,
        response_format: { type: 'json_object' }
      }),
    })

    if (!veniceResponse.ok) {
      const errorText = await veniceResponse.text()
      throw new Error(`Venice API error: ${veniceResponse.status} - ${errorText}`)
    }

    const veniceData: VeniceResponse = await veniceResponse.json()
    
    const aiContent = veniceData.choices?.[0]?.message?.content
    
    if (!aiContent) {
      throw new Error('No response content from Venice AI')
    }

    // Parse the AI's judgment
    let judgment: PrayerJudgment
    try {
      judgment = JSON.parse(aiContent)
    } catch (parseError) {
      console.error('Failed to parse AI response as JSON:', aiContent)
      throw new Error('AI response was not valid JSON')
    }

    // Validate the judgment structure
    if (!judgment.judgment || !judgment.response) {
      throw new Error('AI response missing required fields')
    }

    // Update the prayer record in Supabase based on judgment
    const updateData: Record<string, unknown> = {
      is_praying: judgment.judgment === 'approved',
    }

    if (judgment.judgment === 'rejected') {
      updateData.is_rejected = true
      updateData.rejection_reason = judgment.rejection_reason || 'Rejected by Electric Monk'
    }

    const { error: updateError } = await supabase
      .from('prayers')
      .update(updateData)
      .eq('id', prayer_id)

    if (updateError) {
      console.error('Failed to update prayer status:', updateError)
      // Don't throw here - we still have a valid AI response to return
    }

    // Return the judgment to the client
    return new Response(
      JSON.stringify({
        success: true,
        judgment: judgment.judgment,
        response: judgment.response,
        rejection_reason: judgment.rejection_reason,
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
