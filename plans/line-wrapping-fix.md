# Terminal Line Wrapping Fix — Analysis & Plan

## Problem

Line wrapping in the console view only handles up to **2 wrapped visual lines** per logical line (`<div class="term-line">`). When the window is narrowed such that a logical line wraps to 3+ visual lines, text **spills over** (visually overlaps) into the next logical line below it.

## Root Cause

The issue is in [`TerminalWindow.vue`](src/components/organisms/Terminal/TerminalWindow.vue:350-355), specifically the `.term-line` CSS:

```css
.term-line {
  min-height: 1.3em;
  white-space: pre-wrap;
  word-break: break-all;
}
```

Two interacting problems:

### 1. `min-height: 1.3em` is mismatched with `line-height: 1.55`

- `.term-window` sets `line-height: 1.55` (line 264), so one visual line = `1.55 × font-size`
- But `min-height: 1.3em` = `1.3 × font-size` — significantly smaller than even ONE visual line
- In a flex column layout (`.term-content` is `display: flex; flex-direction: column`), this undersized `min-height` causes the browser's flex algorithm to miscalculate the intrinsic size of the flex item when content wraps to many lines. The browser uses the smaller `min-height` value rather than the content's natural height during layout calculation, causing the next flex item to be positioned too close — resulting in visual overlap.

### 2. `word-break: break-all` is overly aggressive

- `break-all` breaks words at **any character boundary**, which produces ugly wrapping and can trigger edge-case layout bugs where the browser struggles to calculate line-break opportunities.
- Combined with `white-space: pre-wrap`, this creates an unusually complex line-breaking scenario that flex height calculation doesn't always handle correctly across all browsers.

### Why 2 lines works but 3+ doesn't

With `font-size: 0.8125rem` and `line-height: 1.55`:
- 1 visual line = `0.8125rem × 1.55 = 1.259rem`
- 2 visual lines = `2.519rem`
- 3 visual lines = `3.778rem`

`min-height: 1.3em` = `1.056rem`. For 1-2 lines, the natural content height dwarfs the `min-height`, so the browser correctly sizes the flex item. But at 3+ lines, the cumulative height discrepancy (`3.778rem` actual vs `1.056rem` minimum) crosses a threshold where the flex sizing algorithm misbehaves — likely due to the browser using the `min-height` as a "preferred" size hint in its flex-base calculation rather than fully deferring to the content's natural size.

## Plan

### Step 1: Fix `.term-line` CSS in `TerminalWindow.vue`

**Before (line 350-355):**
```css
.term-line {
  min-height: 1.3em;
  white-space: pre-wrap;
  word-break: break-all;
}
```

**After:**
```css
.term-line {
  white-space: pre-wrap;
  word-break: break-word;
  overflow-wrap: break-word;
}
```

Changes:
- **Remove `min-height` entirely.** Empty lines are already handled by the template's `.term-line-spacer` with `&nbsp;`, so a minimum height is unnecessary. Removing it lets the flex layout use the content's natural height for all calculations.
- **Replace `break-all` with `break-word`.** `break-word` only breaks words when they would otherwise overflow, producing cleaner text. This also avoids the edge-case layout bugs that `break-all` triggers with `pre-wrap`.

### Step 2: (Optional safety) Ensure `.term-content` flex children grow properly

No change needed — `display: flex; flex-direction: column` with default `align-items: stretch` already allows children to grow to fit content. Removing `min-height` is the key.

## Impact

- ✅ Any number of wrapped lines per logical line will display correctly
- ✅ Text wrapping is cleaner (words aren't broken mid-character)
- ✅ No layout overlap at any window width
- ✅ Empty/blank lines still display via the existing `&nbsp;` spacer
- ✅ Zero risk — pure CSS change, no JS/state logic affected

## Files Changed

| File | Change |
|------|--------|
| [`src/components/organisms/Terminal/TerminalWindow.vue`](src/components/organisms/Terminal/TerminalWindow.vue:350) | Fix `.term-line` CSS (3 lines) |