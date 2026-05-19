# Electric Monk — UI Style Guide

> Standardized spatial rules, border-radius, and component sizing across all views.

## Border Radius Scale

All UI components use a tight, professional radius scale. No pill-shaped cards or over-rounded containers.

| Token | Value | Usage |
|-------|-------|-------|
| `rounded-sm` / `4px` | Minimal rounding | Scrollbar thumbs, tiny badges |
| `rounded-md` / `6px` | Small components | Stat cells, small inner cards, mini-badges |
| `rounded-lg` / `8px` | **Default card radius** | Cards, panels, sections, input fields, error/success banners, modal content |
| `rounded-xl` / `12px` | Featured cards | Hero cards, active prayer card, faction diamond shell, modal containers |
| `rounded-full` / `999px` | Pills & circles only | Avatar orbs, segmented controls, rank badges, progress bar tracks, scrollbar tracks |

### ❌ Forbidden Patterns
- `rounded-[20px]`, `rounded-[22px]`, `rounded-[24px]`, `rounded-[28px]` — these were de-bubbled
- `rounded-2xl` (16px) — too round for cards; use `rounded-lg` (8px) or `rounded-xl` (12px)
- `rounded-3xl` (24px) — never appropriate for rectangular containers
- CSS `border-radius: 1.2rem+` on cards — these were reduced to 8–12px

### ✅ Correct Replacements
| Before | After |
|--------|-------|
| `rounded-[20px]` | `rounded-lg` |
| `rounded-[22px]` | `rounded-lg` |
| `rounded-[24px]` | `rounded-xl` |
| `rounded-[28px]` | `rounded-xl` |
| `rounded-[16px]` | `rounded-lg` |
| `rounded-[14px]` | `rounded-md` |
| `rounded-[12px]` | `rounded-md` |
| `rounded-2xl` | `rounded-lg` |
| CSS `border-radius: 1.45rem+` | `border-radius: 8px` |
| CSS `border-radius: 2.25rem` | `border-radius: 12px` |

## Component Spacing Standards

### Header Bars
All view headers use consistent vertical padding:

```html
<header class="border-b surface-divider bg-theme-panel/50 backdrop-blur-sm">
  <div class="app-frame py-5">
```

- `py-5` (1.25rem) — standard header padding
- `py-6` was reduced to `py-5` for tighter headers (KarmaShopView, AkashicRecordsView, LeaderboardView)
- `backdrop-blur-sm` — standard blur, not `backdrop-blur-[16px]`

### Main Content
```html
<main class="app-frame py-8 lg:py-10">
```

### Cards & Panels
- Outer card padding: `p-5 sm:p-6` (was often `p-6 sm:p-7` or `p-8`)
- Inner card padding: `p-4` for content cards
- Grid gaps: `gap-5` for card grids, `gap-3` for tight lists

### Resource Chips (Header)
```html
<div class="chip gap-2 px-4 py-2 text-sm ...">
```

### Stat Cells (Small inner cards)
```html
<div class="rounded-md border border-theme-border/30 bg-theme-panel/30 p-2 text-center">
```

### Error/Warning Banners
```html
<div class="rounded-lg border border-theme-purgatory/25 bg-theme-purgatory/10 p-3 ...">
```

### Section Cards (Vatican, Synod, etc.)
```html
<div class="rounded-lg border border-theme-border bg-theme-panel/35 p-4">
```

### Icon Containers
```html
<span class="flex h-14 w-14 items-center justify-center rounded-lg border ...">
```
- Was `rounded-2xl` or `rounded-[20px]` — now `rounded-lg`

## Max-Width Constraints

- Submission panels: `lg:sticky lg:top-28` with grid layout
- Modals: `width: min(92vw, 34rem)`
- Faith columns grid: `grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-5`

## Files Modified

| View | Changes |
|------|---------|
| `AltarView.vue` | Template: `rounded-[22px]`→`rounded-xl`, `rounded-[20px]`→`rounded-xl`, `rounded-[24px]`→`rounded-xl`, `p-6 sm:p-7`→`p-5 sm:p-6`, `mb-8`→`mb-6`, error banners→`rounded-lg`. CSS: `border-radius: 24px`→`12px`, mobile overrides→`12px` |
| `VaticanView.vue` | Template: ~25x `rounded-[20px]`→`rounded-lg`, `rounded-[22px]`→`rounded-lg`, `rounded-[12px]`→`rounded-md`, `rounded-2xl`→`rounded-lg` |
| `SynodHallView.vue` | Template: `rounded-[20px]`→`rounded-lg`, `rounded-[16px]`→`rounded-lg`, `rounded-[14px]`→`rounded-md`. CSS: card radii reduced |
| `PurgatoryView.vue` | Template: `rounded-[20px]`→`rounded-lg`, `rounded-[24px]`→`rounded-lg` (sm). CSS: `border-radius: 24px`→`12px`, `20px`→`10px` |
| `ReliquaryView.vue` | Template: `rounded-[20px]`→`rounded-lg`, `rounded-[16px]`→`rounded-lg`, `rounded-[14px]`→`rounded-md` |
| `HolyWarView.vue` | Template: `rounded-[20px]`→`rounded-lg`, `rounded-[16px]`→`rounded-lg`, `rounded-[12px]`→`rounded-md` |
| `LoginView.vue` | Template: `rounded-[20px]`→`rounded-lg` |
| `KarmaShopView.vue` | Template: `rounded-2xl`→`rounded-lg`. Header: `py-6`→`py-5`, `backdrop-blur-[16px]`→`backdrop-blur-sm` |
| `CatacombsView.vue` | Template: `rounded-2xl`→`rounded-lg` |
| `AkashicRecordsView.vue` | Template: `rounded-[18px]`→`rounded-lg`. Header: `py-6`→`py-5`, `backdrop-blur-[16px]`→`backdrop-blur-sm`. CSS: `border-radius: 26px`→`12px` |
| `LeaderboardView.vue` | Header: `py-6`→`py-5`, `backdrop-blur-[16px]`→`backdrop-blur-sm` |
| `FactionsView.vue` | CSS: All card/panel `border-radius` values reduced (`.faction-roster-card` 1.45rem→8px, `.faction-diamond-shell` 2.25rem→12px, `.faction-node-card` 1.45rem→8px, `.faction-detail-header` 1.75rem→10px, `.faction-section-card` 1.5rem→10px, `.faction-metric-card` 1.2rem→8px, `.faction-relationship-card` 1.3rem→8px, `.faction-member-row` 1.15rem→8px, `.faction-core-seal-icon` 1.4rem→8px, `.faction-roster-orb` 0.9rem→8px, mobile `28px`→`12px`) |

## Preserved Patterns

The following `border-radius: 999px` uses are **intentional** and were NOT changed:
- Pill-shaped segmented controls (`.segmented-shell`)
- Circular avatar orbs / halos
- Rank badges
- Progress bar tracks
- Scrollbar tracks/thumbs
- Icon discs (`.aether-icon`, `.aether-judgment-icon`)
- Karma display pills (`.aether-karma-display`)
- Loader bars

## No Script Logic Touched

This refactor was strictly `<template>` and `<style>` only. All `<script setup>` blocks, state management, Supabase RPC calls, and composable logic remain untouched.