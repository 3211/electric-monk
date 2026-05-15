# Views Directory

This directory contains page-level container components (full views/screens).

## Guidelines for AI Agents

1. **One Per Route**: Each view corresponds to one application route
2. **Composition**: Views compose organisms/components, not atoms
3. **Data Fetching**: Use composables for all data operations
4. **Naming**: Use PascalCase and descriptive names (e.g., `Dashboard.vue`, `Settings.vue`)

## Example Structure

```vue
<script setup>
/**
 * HomeView - Main landing page
 * @module views/HomeView
 */

import { useAppData } from '../composables/useAppData'
import HeaderOrganism from '../components/organisms/HeaderOrganism.vue'

const { data, loading } = useAppData()
</script>

<template>
  <div class="min-h-screen">
    <HeaderOrganism />
    <!-- Main content -->
  </div>
</template>
