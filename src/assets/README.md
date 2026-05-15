# Assets Directory

This directory contains static visual assets for the application.

## Structure

```
assets/
├── sprites/     # Game sprites and character graphics
├── icons/       # UI icons and symbols
├── backgrounds/ # Background images
└── fonts/       # Custom fonts (if needed)
```

## Guidelines for AI Agents

1. **Naming**: Use kebab-case for all asset files (e.g., `player-sprite.png`)
2. **Imports**: Import assets in Vue components using relative paths
3. **Optimization**: Keep asset sizes minimal for GitHub Pages performance
4. **Format**: Prefer SVG for icons, WebP/PNG for sprites

## Usage Example

```vue
<script setup>
import playerSprite from '../assets/sprites/player.png'
</script>

<template>
  <img :src="playerSprite" alt="Player" />
</template>
```
