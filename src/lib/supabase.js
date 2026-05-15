import { createClient } from '@supabase/supabase-js'

/**
 * Supabase client singleton
 * 
 * @description
 * This module initializes and exports a single Supabase client instance.
 * It uses environment variables for configuration.
 * 
 * @requires @supabase/supabase-js
 * @see {@link https://supabase.com/docs/reference/javascript/introduction}
 */

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

if (!supabaseUrl || !supabaseAnonKey) {
  console.warn('[Supabase] Missing environment variables. Please check your .env file.')
}

export const supabase = createClient(supabaseUrl, supabaseAnonKey)
