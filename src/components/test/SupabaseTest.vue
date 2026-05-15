<script setup>
/**
 * SupabaseTest Component
 * 
 * @description
 * A diagnostic component that verifies the Supabase connection.
 * Displays connection status and basic database info.
 * 
 * @module components/test/SupabaseTest
 */

import { ref, onMounted } from 'vue'
import { supabase } from '../../lib/supabase.js'

const status = ref('idle') // 'idle' | 'connecting' | 'connected' | 'error'
const errorMessage = ref('')
const latency = ref(null)

/**
 * Test the Supabase connection
 * Performs a simple query to verify connectivity
 */
async function testConnection() {
  status.value = 'connecting'
  const startTime = performance.now()
  
  try {
    // Simple test: try to get the current timestamp from Supabase
    const { data, error } = await supabase.from('_ping').select('*').limit(1)
    
    // Note: _ping table may not exist, so we also check for generic success
    // A better test is just checking if the client initialized
    if (error && error.code !== 'PGRST116') {
      throw error
    }
    
    status.value = 'connected'
    latency.value = Math.round(performance.now() - startTime)
  } catch (err) {
    // If _ping doesn't exist, that's okay - client still works
    if (err.message?.includes('relation') || err.code === 'PGRST116') {
      status.value = 'connected'
      latency.value = Math.round(performance.now() - startTime)
      errorMessage.value = 'Connected (no _ping table - this is normal)'
    } else {
      status.value = 'error'
      errorMessage.value = err.message
    }
  }
}

onMounted(() => {
  testConnection()
})
</script>

<template>
  <div class="bg-gray-800 rounded-lg p-6 max-w-md w-full border border-gray-700">
    <h2 class="text-xl font-semibold mb-4">Supabase Connection Test</h2>
    
    <div class="space-y-3">
      <!-- Status Indicator -->
      <div class="flex items-center gap-2">
        <div 
          class="w-3 h-3 rounded-full"
          :class="{
            'bg-gray-400': status === 'idle',
            'bg-yellow-400 animate-pulse': status === 'connecting',
            'bg-green-400': status === 'connected',
            'bg-red-400': status === 'error'
          }"
        />
        <span class="text-sm capitalize">{{ status }}</span>
      </div>
      
      <!-- Latency -->
      <div v-if="latency !== null" class="text-sm text-gray-400">
        Latency: {{ latency }}ms
      </div>
      
      <!-- Error Message -->
      <div v-if="errorMessage" class="text-sm text-yellow-400">
        {{ errorMessage }}
      </div>
      
      <!-- Retry Button -->
      <button
        @click="testConnection"
        class="w-full mt-4 px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded-md text-sm font-medium transition-colors"
        :disabled="status === 'connecting'"
      >
        {{ status === 'connecting' ? 'Testing...' : 'Test Again' }}
      </button>
    </div>
  </div>
</template>
