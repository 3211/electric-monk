# Composables Directory

This directory contains Vue 3 composable functions (logic reuse pattern).

## Guidelines for AI Agents

1. **Single Responsibility**: Each composable should handle one piece of functionality
2. **Naming**: Use `use<Feature>.js` naming convention (e.g., `useAuth.js`, `useDatabase.js`)
3. **No UI Logic**: Composables should not contain template/JSX logic
4. **Return Objects**: Always return an object with reactive refs and functions

## Example Structure

```js
// src/composables/useExample.js
import { ref } from 'vue'

export function useExample() {
  const data = ref(null)
  
  async function fetchData() {
    // fetch logic
  }
  
  return { data, fetchData }
}
```
