# Electric Monk — UI Style Guide (Hard-Square Edition)

> Standardized spatial rules, sharp-radius, and high-density component sizing for the Diegetic War-Game interface.

## Border Radius Scale

All UI components use a sharp, technical radius scale. Over-rounded containers and pills are strictly forbidden.

| Token | Value | Usage |
|-------|-------|-------|
| `none` | `0px` | Perfectly sharp corners (Headers, Dividers) |
| `rounded-sm` | `1px` | Tiny technical elements |
| `rounded-md` / `rounded-[2px]` | **`2px`** | **Default card/button radius** |
| `rounded-lg` | `4px` | Max allowed radius for very large hero panels |
| `rounded-full` | `999px` | **Strictly reserved** for Progress Bars and Toggle Switches only |

### ❌ Forbidden Patterns
- `rounded-xl`, `rounded-2xl`, `rounded-[20px+]` — all replaced with `rounded-sm`.
- Pill-shaped buttons (`rounded-full` on buttons/badges) — all replaced with `rounded-sm` or `rounded-[2px]`.
- Soft radial glows on container edges.

## Typography

| Role | Font Family | Style |
|------|-------------|-------|
| **Headlines** | Serif Display (`Cormorant Garamond`) | Sharp, no shadows, tight tracking |
| **Interface** | **JetBrains Mono** | Primary UI, Buttons, Labels, Data |
| **Data** | **JetBrains Mono** | Resource values, Numbers, Stats |

## Component Spacing Standards (High Density)

### Header Bars
```html
<header class="border-b surface-divider bg-theme-panel/80">
  <div class="app-frame py-3"> <!-- Reduced from py-5 -->
```

### Main Content
```html
<main class="app-frame py-5 lg:py-6"> <!-- Reduced from py-8/10 -->
```

### Cards & Panels
- Outer card padding: `p-3 sm:p-4` (Reduced from `p-5/6`)
- Grid gaps: `gap-3` standard, `gap-1` for tight data lists.

### Durable Frames (PFPs & Indicators)
- **Geometry:** `rounded-sm` (2px).
- **Layering:** 2px outer border + 1px inset ring (`ring-1 ring-inset ring-white/10`).
- **Coloring:** Outer border uses faction-specific accent color (e.g., `border-theme-accent` for Gilded).

## Visual Implementation (The Grain)

Every glass panel includes the noise overlay via SVG filter:
```html
<!-- In index.html <body> -->
<svg style="position: absolute; width: 0; height: 0; pointer-events: none;" aria-hidden="true">
  <filter id="grain">
    <feTurbulence type="fractalNoise" baseFrequency="0.65" numOctaves="3" stitchTiles="stitch" />
    <feColorMatrix type="saturate" values="0" />
    <feComponentTransfer><feFuncA type="linear" slope="0.05" /></feComponentTransfer>
    <feBlend in="SourceGraphic" mode="multiply" />
  </filter>
</svg>
```

```css
/* Applied via ::before pseudo-element */
.glass-panel::before {
  content: "";
  position: absolute;
  inset: 0;
  filter: url(#grain);
  opacity: 0.4;
  pointer-events: none;
  z-index: 0;
  border-radius: inherit;
}
```

## Hard Shadows

All panels and buttons use sharp hard-shadows instead of soft glows:
```css
box-shadow: 4px 4px 0px rgba(0,0,0,0.15);
```

## Button Styling

All buttons (`btn-primary`, `btn-secondary`, `btn-ghost`, `btn-danger`) enforce:
- `border-radius: 2px` (via `--radius-button`)
- `text-transform: uppercase`
- `letter-spacing: 0.05em`
- `font-weight: 700`
- `font-family: "JetBrains Mono", monospace`

## Theme Overrides (Consistency)
- **Primary View:** Warm Ivory & Gold (Sharp Gold accents)
- **Evil View:** Dark Purple & Neon (Sharp Magenta accents)
- **War View:** Steel & Brass (Sharp Brass accents)

### Terminal Faction Tuning (The "Liquid" CRT)
The terminal supports various faction-based atmospheric tunings. The default (Standard/Neutral) tuning uses the **War View** base colors.

- **Neutral/Standard Tuning:**
  - Base Text: `--war-text` (Soft Blue-Grey)
  - Secondary/Dim: `--war-steel`, `--war-dim`
  - Highlights/Prompts: `--war-brass`, `--war-brass-light`
  - Success/Ally: `--war-ally`
  - Error/Enemy: `--war-enemy`

All themes must adhere to the `2px` radius rule regardless of color scheme.

## Implementation Status

### Completed Changes
- [x] `index.html` — SVG grain filter injected
- [x] `src/style.css` — Root variables hardened (2px radii, mono font), grain overlay, hard shadows
- [x] `tailwind.config.js` — Font family switched to JetBrains Mono, radius tokens capped at 4px, backdrop blur reduced to 4px
- [x] `ResourceBar.vue` — Ledger-style (emoji + value only), 2px radius, mono font, compressed padding
- [x] `ShoutCard.vue` — Durable framed PFPs, `rounded-[2px]` badges, compressed padding
- [x] All views — `rounded-xl` → `rounded-sm`, `rounded-2xl` → `rounded-sm`, `rounded-[20/24/28]px` → `rounded-sm`
- [x] All views — `rounded-lg` → `rounded-sm`, `rounded-md` → `rounded-sm`
- [x] All views — `rounded-full` on PFPs, badges, close buttons → `rounded-sm`
- [x] Progress bars and toggle switches retain `rounded-full` (per spec)
- [x] Buttons — Hard shadows, uppercase, mono font, 2px radius