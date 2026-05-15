# Components Directory

This directory contains Vue 3 components organized by atomic design principles.

## Directory Structure

```
components/
├── atoms/       # Smallest UI units (buttons, inputs, icons)
├── molecules/   # Combinations of atoms (search bars, form fields)
├── organisms/   # Complex UI sections (headers, sidebars)
└── test/        # Diagnostic and testing components
```

## Guidelines for AI Agents

1. **Hyper-Modular**: Each component should do ONE thing
2. **Props Definition**: Always define props explicitly with types/validation
3. **Emits**: Document all emitted events
4. **No Direct Supabase Calls**: Use composables for data fetching
5. **Styling**: Use Tailwind utility classes, avoid scoped CSS unless necessary

## Component Template

```vue
<script setup>
/**
 * ComponentName - Brief description
 * @module components/atoms/ComponentName
 */

import { defineProps, defineEmits } from 'vue'

const props = defineProps({
  label: { type: String, required: true }
})

const emit = defineEmits(['click'])
</script>

<template>
  <!-- Template here -->
</template>
