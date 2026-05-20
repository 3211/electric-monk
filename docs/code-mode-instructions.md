# Code Mode Implementation Instructions: Hard-Square Overhaul

## 1. Global Filter (`index.html`)

Insert the following SVG filter inside the `<body>` tag:

```html
<svg style="position: absolute; width: 0; height: 0; pointer-events: none;" aria-hidden="true">
  <filter id="grain">
    <feTurbulence type="fractalNoise" baseFrequency="0.65" numOctaves="3" stitchTiles="stitch" />
    <feColorMatrix type="saturate" values="0" />
    <feComponentTransfer>
      <feFuncA type="linear" slope="0.05" />
    </feComponentTransfer>
    <feBlend in="SourceGraphic" mode="multiply" />
  </filter>
</svg>
```

## 2. CSS Variable Overrides (`src/style.css`)

Update the `:root` variables to harden the geometry and typography:

```css
:root {
  /* ... existing ... */
  
  /* Typography - Mono focus */
  --font-body: "JetBrains Mono", "Cascadia Code", monospace;
  --font-ui: "JetBrains Mono", monospace;

  /* Hard Radii */
  --radius-panel: 2px;
  --radius-panel-soft: 2px;
  --radius-field: 1px;
  --radius-button: 2px;
  --radius-chip: 2px;

  /* Spacing Reductions */
  --spacing-tight: 0.75rem;
}

/* Apply Grain to Panels */
.glass-panel::before {
  content: "";
  position: absolute;
  inset: 0;
  filter: url(#grain);
  opacity: 0.4;
  pointer-events: none;
  z-index: 0;
}

/* Sharp Shadows */
.glass-panel {
  box-shadow: 4px 4px 0px rgba(0,0,0,0.15), inset 0 1px 0 var(--theme-glass-stroke-top);
  border-radius: var(--radius-panel);
}

/* Button Sharpening */
.btn-primary, .btn-secondary, .btn-ghost, .btn-danger {
  border-radius: var(--radius-button) !important;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  font-weight: 700;
}
```

## 3. Tailwind Configuration (`tailwind.config.js`)

Sync the theme tokens:

```javascript
theme: {
  extend: {
    fontFamily: {
      ui: ['"JetBrains Mono"', 'monospace'],
      mono: ['"JetBrains Mono"', 'monospace'],
    },
    borderRadius: {
      'panel': '2px',
      'btn': '2px',
      'lg': '4px',
      'md': '2px',
      'sm': '1px',
    },
    backdropBlur: {
      'glass': '4px', /* Reduced blur */
    }
  }
}
```

## 4. Component-Specific Refactoring Targets

### 1. `src/components/molecules/ResourceBar.vue`
- **Current:** `rounded-full` (999px), `p-0.25rem 0.5rem`, `gap-0.375rem`.
- **Target:** 
  - Change `.resource-chip` border-radius to `2px`.
  - Reduce padding to `0.125rem 0.25rem`.
  - Reduce gap to `0.125rem`.
  - Eliminate `.resource-label` (text) — keep only Emoji + Value for a dense ledger look.

### 2. `src/components/molecules/ShoutCard.vue`
- **Current:** `p-5` (1.25rem padding), `rounded-full` PFPs.
- **Target:**
  - Reduce padding to `p-3`.
  - **PFP Frames:** Change `rounded-full` to `rounded-sm`.
  - **Durable Layering:** Add a double-border "frame" to PFPs (e.g., `ring-1 ring-inset ring-white/10` inside a `border-2 border-theme-accent/20` box).
  - **Factional Tinting:** The PFP frame border color should match the `shout.author_sect_type` color (Gilded = Gold, Black Tribunal = Red, etc.).
  - Change all utility badges from `rounded-full` to `rounded-[2px]`.

### 3. All Views (`AltarView.vue`, `FactionsView.vue`, etc.)
- **Padding Reduction:** Global 25-30% reduction. `p-6` -> `p-4`, `p-8` -> `p-5`, `p-12` -> `p-6`.
- **Radius Purge:** Strict replacement of all `rounded-` utility classes with `rounded-sm` or `rounded-[2px]`. `rounded-xl` and `rounded-full` must be eliminated.
- **Font Purge:** Apply `font-mono` to all interactive and data-bearing elements.

## 5. GLM 5.1 Transition Plan (Complex Refactoring)

For high-complexity views, GLM 5.1 should be invoked to perform the following:

### `src/views/FactionsView.vue`
- Refactor the Ranking lists (lines 336, 380, 432). Replace `rounded-xl` with `rounded-sm`.
- Reduce `p-8` and `p-12` containers to `p-4` and `p-6` respectively.
- Condense the "Faith Columns Grid" (line 358) to use tighter gaps and smaller text.

### `src/views/AltarView.vue`
- Perform a systematic "radius-and-padding" sweep of the ritual interface.
- Ensure all "glass-bead" scrollbars are squared off.
