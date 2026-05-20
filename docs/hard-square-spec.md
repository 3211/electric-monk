# Hard-Square Master Specification: Electric Monk

## 1. Geometric Hardening
*   **Global Radius Limit:** No rectangular element (card, button, input, panel) shall exceed a `2px` border-radius.
*   **Capsule Removal:** All "pill" or "capsule" buttons (`rounded-full`) are deprecated. Buttons must be sharp rectangles.
*   **PFPs (Avatars):** PFPs are no longer circular. They must be square (`rounded-sm`) and encased in **Durable Frames**.
*   **Durable Frames:** PFPs and key status indicators must feature a "layered" border look:
    *   Outer 2px border (Faction-specific color).
    *   Inner 1px inset ring (translucent white/black) to simulate a beveled stone or metal edge.
*   **Borders:** 1px solid borders are mandatory for all containers. Use high-contrast "edge-lighting" (e.g., a slightly brighter top border) to simulate physical depth.

## 2. Diegetic Typography
*   **Primary UI Font:** `JetBrains Mono` (or system `monospace`) is now the default for ALL interface text, including:
    *   Buttons & Navigation
    *   Labels & Metadata
    *   Resource Readouts
    *   Form Inputs
*   **Headlines:** Retain the display serif font but remove all soft glows/shadows. Use sharp colors and tight letter-spacing.
*   **Information Density:** Reduce line-height and letter-spacing for monospaced elements to maximize screen real estate.

## 3. Surface & Texture (The Grain)
*   **SVG Noise Filter:** A global noise filter (`#grain`) must be applied to all `glass-panel` and `bg-theme-panel` elements.
*   **Glassmorphism:** Retain translucency but reduce `backdrop-blur` from `20px` to `4px-8px`. The goal is "dirty plastic/glass," not "frosted luxury."
*   **Scanlines:** Use subtle repeated linear gradients on headers or large panels to simulate CRT/Terminal displays.

## 4. Information Density & Layout
*   **Padding Reduction:** Global reduction of `p-` and `py-` classes by at least 25%.
*   **Compact Grids:** Data like "Economic Modifiers" must use a tight grid or a justified list:
    *   `[LABEL] VALUE` (Justified space-between)
*   **Horizontal Packing:** On desktop, prioritize horizontal distribution over vertical stacking. Avoid "big cards for small strings."

## 5. Visual Effects
*   **Shadows:** Replace soft `box-shadow` with sharp "Hard-Shadows" (e.g., `4px 4px 0px rgba(0,0,0,0.2)`).
*   **Glows:** Replace radial glows with 1px inset "Neon" borders or sharp linear accent lines.
*   **Transitions:** Reduce transition durations. Interactions should feel "clicky" and immediate, not "soupy" and slow.
