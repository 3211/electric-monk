# Terminal API Reference

This document defines the capabilities and API of the Holy War Online text console. Use these methods to build interactive features without creating "spaghetti code."

**Last updated:** 2026-05-23

---

## The `useTerminal` Composable

The terminal is managed via the `useTerminal` composable (`src/composables/useTerminal.js`). Each instance maintains its own state, history, and command registry.

### Core State
- `lines`: Reactive array of line objects `{ text, class, id }`.
- `busy`: Boolean. When true, user input is typically blocked (except for interactive sessions).
- `activeSession`: Reactive object containing the current `readLine`, `readKey`, or `readMenu` state.

---

## Output Methods

### `write(input)`
Appends a single line to the terminal.
- `input`: String or Object `{ text, class, id }`.
- Classes: `term-text`, `term-dim`, `term-brass`, `term-ally`, `term-enemy`, `term-success`, `term-gilded`, etc.

### `writeAll(inputArr)`
Appends multiple lines at once.

### `clear()`
Empties the terminal buffer and cleans up any active progress bar controllers to prevent "zombie" updates.

### `typewrite(text, options)`
Simulates typing text character-by-character. Returns a `Promise`.
- `options`: `{ speed: 28, class: '', id: null }`.

### `typewriteSequence(entries)`
Types multiple entries sequentially.

---

## Line Manipulation

### `updateLine(lineId, content)`
Updates an existing line by its ID. If the ID doesn't exist, it creates a new line.
- `content`: String or Object `{ text, class }`.

### `removeLine(lineId)`
Removes a line from the buffer by its ID.

---

## Progress & Spinners

### `createProgressBar(id, options)`
Creates a stateful controller for a progress bar. This is the preferred way to handle "puppetry" (e.g., changing colors or labels mid-progress).
- **Options**: `{ width: 32, label: '', format: '  [{bar}] {percent}%', class: 'term-steel', chars: { filled: '█', empty: '░' } }`
- **Returns**: A controller object:
  - `update(percent, newOptions)`: Update progress (0-100) or override options (like `class`).
  - `finish(finalOptions)`: Jumps to 100% and sets class to `term-ally` by default.
  - `remove()`: Removes the line from the terminal.

### `showProgress(progressId, percent, label, options)`
Quick-fire method to render or update a progress bar line.
- `percent`: 0 to 100.
- `label`: Text to display before the bar (legacy support).
- `options`: Supports the same options as `createProgressBar`.

### `removeProgress(progressId)`
Removes the progress bar line and destroys its controller if one exists.

### `startSpinner(spinnerId, label, options)`
Starts an interactive terminal spinner. Returns a `stop` function.
- `options`: `{ speed: 80, class: 'term-steel' }`.

---

## Text Animation

### `purifyLine(lineId, pureText, options)`
Animates a line from a "glitched" or corrupted state back to clean text.
- `pureText`: The final target string.
- **Options**:
  - `glitchPrefix / purePrefix`: Text shown before the glitched/clean content.
  - `glitchClass / pureClass`: CSS classes for the two states.
  - `steps`: Number of recovery steps (default: 6).
  - `stepDelay`: MS between steps (default: 150).

---

## Interactive Input (Blocking)

These methods return a `Promise` that resolves when the user provides input. While active, they intercept keyboard events.

### `readLine(promptText)`
Prompts the user for a line of text.
- `promptText`: Optional text displayed before the input area.

### `readKey(message)`
Waits for a single key press.

### `readMenu(promptText, options)`
Displays an interactive arrow-key selection menu.
- `options`: Array of strings or objects `{ label, value }`.
- Returns the `value` of the selected option.

---

## Command System

Commands are registered in `src/terminal/commands.js` (Global) or `src/terminal/tabCommands.js` (Tab-specific).

### Command Definition
```javascript
commandName: {
  help: 'Single-line description for /help.',
  usage: '/commandName <args>',
  hidden: false, // If true, won't show in /help
  async handler(args, ctx) {
    // args: Array of string arguments
    // ctx: { terminal, tab, registry }
    
    // Return an array of lines to be printed, or null.
    return [{ text: 'Command executed.', class: 'term-success' }];
  }
}
```

### Context (`ctx`)
- `terminal`: The `useTerminal` instance.
- `tab`: (Optional) Tab management object. Contains:
    - `setTitle(title)`: Update the current tab's display name.
    - `newTab()`: Open a new terminal tab.
    - `closeThis()`, `closeOthers()`, `closeAll()`: Tab lifecycle management.
- `registry`: The full command registry (for recursive calls or help lookups).

---

## Events

The terminal instance emits events that can be listened to via `terminal.on(event, callback)`.

| Event | Payload | Description |
|-------|---------|-------------|
| `lineAdded` | `line` | Emitted when a new line is written. |
| `lineUpdated` | `{ id, line }` | Emitted when a line is updated via `updateLine`. |
| `lineRemoved` | `{ id }` | Emitted when a line is removed. |
| `clear` | — | Emitted when the buffer is cleared. |
| `focusRequest` | — | Emitted when a component should focus the terminal input. |
| `sessionStart` | `{ type }` | Emitted when an interactive session (`readLine`, etc) starts. |
| `sessionEnd` | `{ type }` | Emitted when an interactive session ends. |
| `command` | `{ command }` | Emitted when a command is processed. |

---

## Best Practices
1. **Update Tab Titles:** Every command or major operation (like onboarding or boot sequences) should strictly set the tab title at the start of the operation using `ctx.tab.setTitle("Title")` or `terminal.tab.setTitle("Title")`. This ensures the UI reflects the current context.
2. **Use IDs:** When creating lines that need to be updated (like progress bars or status updates), always provide a unique `id`.
3. **Handle `busy`:** Set `terminal.busy = true` during long-running async operations to prevent users from spamming commands.
4. **Clean Up Sessions:** Interactive sessions (`readLine`, `readMenu`) automatically clean up their state, but manual line updates should be removed if they are temporary.
5. **Theming:** Use established CSS classes from `src/style.css` to maintain visual consistency.
