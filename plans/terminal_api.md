# Terminal API Reference

This document defines the capabilities and API of the Holy War Online text console. Use these methods to build interactive features without creating "spaghetti code."

**Last updated:** 2026-05-23

---

## The `useTerminal` Composable

The terminal is managed via the `useTerminal` composable (`src/composables/useTerminal.js`). Each instance maintains its own state, history, and command registry.

### Core State
- `lines`: Reactive array of line objects `{ text, class, id, segments, _typing }`.
- `busy`: Boolean. When true, user input is typically blocked (except for interactive sessions).
- `activeSession`: Reactive object containing the current `readLine`, `readKey`, or `readMenu` state. Null when no session is active.
- `location`: Ref string representing the current environment or IP address.
- `history`: Reactive array of previously entered command strings.
- `historyIndex`: Ref number tracking current position in command history navigation.
- `isTyping`: Ref boolean. True while a `typewrite` animation is in progress.
- `processingCommand`: Ref boolean. True while a command handler is executing.
- `activeProgressBars`: Reactive object mapping progress bar IDs to their controller instances.

---

## Output Methods

### `write(input)`
Appends a single line to the terminal.
- `input`: String or Object `{ text, class, id }`.
- Classes: `term-text`, `term-dim`, `term-brass`, `term-ally`, `term-enemy`, `term-success`, `term-gilded`, `term-holy`, `term-steel`, `term-muted`, `term-prompt`.

### `writeAll(inputArr)`
Appends multiple lines at once. Each element follows the same format as `write`.

### `clear()`
Empties the terminal buffer and tears down any active progress bar controllers to prevent "zombie" updates from ghosting back into the display.

### `typewrite(text, options)`
Simulates typing text character-by-character. Returns a `Promise` that resolves when the animation completes.
- `options`: `{ speed: 28, class: '', id: null }`.
- Emoji surrogate pairs are preserved intact during animation.

### `typewriteSequence(entries)`
Types multiple entries sequentially. Each entry can be a string or an options object `{ text, speed, class, id }`.

---

## Line Manipulation

### `getLine(lineId)`
Returns the line object `{ text, class, id, segments }` for the given ID, or null if not found.

### `updateLine(lineId, content)`
Updates an existing line by its ID. If the ID doesn't exist, creates a new line with that ID.
- `content`: String or Object `{ text, class, segments }`.
- The `segments` property accepts an array of `{ text, class }` objects for inline multi-styled text.

### `removeLine(lineId)`
Removes a line from the buffer by its ID.

### `highlightPattern(lineId, regex, className)`
Highlights portions of a line that match a regular expression by splitting the line into styled segments.
- `regex`: Regular expression to match.
- `className`: CSS class to apply to matched segments.

### `setLocation(newLocation)`
Updates the terminal's location state, which changes the prompt display (e.g. `/[newLocation]>`). Default location is `0.0.0.0`.

---

## Progress & Spinners

### `createProgressBar(id, options)`
Creates a stateful controller for a progress bar. This is the preferred way to handle "puppetry" (e.g., changing colors or labels mid-progress).
- **Options**: `{ width: 32, label: '', format: '  [{bar}] {percent}%', class: 'term-steel', chars: { filled: '█', empty: '░' } }`
- **Returns**: A controller object with:
  - `id`: The progress bar's line ID.
  - `update(percent, newOptions)`: Update progress (0-100) or override options (like `class`, `label`, `format`, `width`, `chars`). Pass `null` for percent to keep the current value while only changing options.
  - `finish(finalOptions)`: Jumps to 100% and sets class to `term-ally` by default. Accepts optional overrides.
  - `remove()`: Removes the line from the terminal and cleans up the controller.
- **Zombie-proof**: If the line is cleared externally (e.g. via `clear()`), further updates become no-ops automatically.

### `showProgress(progressId, percent, label, options)`
Quick-fire method to render or update a progress bar line. Backward-compatible with legacy 3-arg signature.
- `percent`: 0 to 100.
- `label`: Text to display before the bar (legacy arg, can also be passed in options).
- `options`: Supports the same options as `createProgressBar`.

### `removeProgress(progressId)`
Removes the progress bar line and destroys its controller if one exists.

### `startSpinner(spinnerId, label, options)`
Starts an animated terminal spinner. Returns a `stop` function.
- `options`: `{ speed: 80, class: 'term-steel' }`.
- The spinner cycles through `|`, `/`, `-`, `\` frames.

---

## Text Animation

### `purifyLine(lineId, pureText, options)`
Animates a line from a "glitched" or corrupted state back to clean text. Returns a `Promise` that resolves when the animation completes.
- `pureText`: The final target string.
- **Options**:
  - `glitchPrefix` (default: `''`): Text shown before the glitched content (e.g. `'  [ERR]  '`).
  - `purePrefix` (default: `''`): Text shown once purified (e.g. `'  [OK]   '`).
  - `glitchClass` (default: `'term-enemy'`): CSS class during corruption.
  - `pureClass` (default: `'term-ally'`): CSS class once purified.
  - `intensity` (default: `0.75`): Initial corruption intensity (0–1).
  - `steps` (default: `12`): Number of recovery steps.
  - `stepDelay` (default: `60`): Milliseconds between recovery steps.
  - `fixChance` (default: `0.35`): Probability per corrupted character to fix per step.
  - `glitchFn` (default: internal `_glitchText`): Custom glitch function `(text, intensity) => string`.
  - `highlightRegex` (default: `null`): After purification, highlight portions matching this regex.
  - `highlightClass` (default: `'term-brass'`): CSS class for highlighted segments.

---

## Interactive Input (Blocking)

These methods return a `Promise` that resolves when the user provides input. While active, they intercept keyboard events and block normal command processing.

### `readLine(promptText)`
Prompts the user for a line of text.
- `promptText`: Optional text displayed before the input area.
- Resolves with the raw input string (not trimmed).

### `readKey(message)`
Waits for a single key press.
- `message`: Optional text displayed while waiting.
- Resolves with the first character of the input.

### `readMenu(promptText, options)`
Displays an interactive arrow-key selection menu.
- `promptText`: Text displayed above the menu.
- `options`: Array of strings or objects `{ label, value }`.
- Returns the `value` of the selected option.
- Navigation keys: ArrowUp/ArrowDown, WASD, IJKL, numpad 8/2/4/6, and various punctuation keys.
- The menu cleans up its option lines after selection, replacing them with a static "Selected:" line.

### `getInput(prompt)`
Convenience method. Calls `readLine` and trims the result.
- Returns the trimmed input string.

### `hasActiveSession()`
Returns `true` if an interactive session (`readLine`, `readKey`, or `readMenu`) is currently active.

### `handleInteractiveKey(key)`
Internal method that processes keystrokes during interactive sessions. Called automatically by the UI layer. Returns `true` if the key was consumed.

### `endSession()`
Forcefully ends any active interactive session, emitting the `sessionEnd` event.

---

---

## Command System

Commands are registered in `src/terminal/commands.js` (Global), `src/terminal/tabCommands.js` (Tab-specific), `src/terminal/systems/connection.js` (Connection), `src/terminal/systems/faction.js` (Faction UI), `src/terminal/systems/player.js` (Player Cards), `src/terminal/systems/processManager.js` (Process Management), or `src/terminal/akashicScannerCommand.js` (Akashic Mining).

### Command Definition
```javascript
commandName: {
  help: 'Single-line description for /help.',
  usage: '/commandName <args>',       // Optional
  hidden: false,                       // If true, won't show in /help
  async handler(args, ctx) {
    // args: Array of string arguments
    // ctx: { terminal, tab, registry, connected_ip, connection_type, machine_id, machine_access }
    
    // Return an array of lines to be printed, or null.
    return [{ text: 'Command executed.', class: 'term-success' }];
  }
}
```

### Context (`ctx`)
- `terminal`: The `useTerminal` instance.
- `tab`: (Optional) Tab management object. Contains:
    - `paneId`: The ID of the pane this tab belongs to.
    - `tabId`: The ID of this tab.
    - `setTitle(title)`: Update the current tab's display name.
    - `newTab(initialCommand)`: Open a new terminal tab, optionally running a command.
    - `closeThis()`: Close this tab.
    - `closeOthers()`: Close all other tabs in this pane.
    - `closeAll()`: Close every terminal tab across all panes.
- `registry`: The full command registry (for recursive calls or help lookups).
- `connected_ip`: (string|null) The IP the terminal is currently connected to via `/connect`.
- `connection_type`: (string|null) One of `'faction'`, `'player'`, `'machine'`, or null.
- `machine_id`: (UUID|null) The UUID of the connected virtual machine (if `connection_type === 'machine'`).
- `machine_access`: (string|null) Access level on the connected machine: `'admin'` (auto-authenticated owner), `'pending'` (needs /auth).

### Command Processing

#### `processCommand(raw)`
Processes a raw input string. Handles interactive sessions, command parsing, and execution. Called automatically by the UI layer.

#### `buildRegistry(ctx)`
Builds the command registry for this terminal instance. Injects context so commands can access `terminal`, `tab`, and `registry`. Called lazily on first command if not already built.

#### `startup()`
Writes the default welcome message to the terminal.

#### `navigateHistory(direction)`
Returns a historical command string for up/down navigation. Returns `null` if no history exists in that direction.

---

## Boot & Onboarding

### `runBootSequence(terminal, duration)`
Runs the themed terminal boot animation. Exported from `src/terminal/boot.js`.
- `duration`: Total duration in milliseconds (default: 3500).
- Loads sacred texts in parallel with database requests.
- Extends the boot cycle count for new players who need onboarding.

### `checkOnboardingStatus(supabase)`
Checks if the current player needs onboarding. Exported from `src/terminal/boot.js`.
- Returns: `{ needsOnboarding: boolean, player: Object|null, error: any }`.
- Calls the `get_player_status` Supabase RPC function.

### `getAvailableSects(supabase)`
Fetches available sects from the database. Exported from `src/terminal/boot.js`.
- Returns: Array of sect objects, or empty array on error.

### `runOnboarding(terminal, player)`
Runs the interactive onboarding flow for new players. Exported from `src/terminal/onboarding.js`.
- Handles username selection with client-side and server-side validation.
- Handles sect selection with interactive arrow-key menu.
- Streams AI-generated welcome messages.
- Returns: `true` if onboarding completed successfully, `false` on error.

---

## Events

The terminal instance emits events that can be listened to via `terminal.on(event, callback)`. Returns an unsubscribe function.

| Event | Payload | Description |
|-------|---------|-------------|
| `lineAdded` | `line` | Emitted when a new line is written. |
| `lineUpdated` | `{ id, line }` | Emitted when a line is updated via `updateLine`. |
| `lineRemoved` | `{ id }` | Emitted when a line is removed. |
| `clear` | — | Emitted when the buffer is cleared. |
| `focusRequest` | — | Emitted when a component should focus the terminal input. |
| `sessionStart` | `{ type }` | Emitted when an interactive session starts. |
| `sessionEnd` | `{ type }` | Emitted when an interactive session ends. |
| `command` | `{ command }` | Emitted when a command is processed. |

### Event Methods
- `on(event, callback)`: Subscribe to an event. Returns an unsubscribe function.
- `off(event, callback)`: Unsubscribe from an event.
- `emit(event, payload)`: Emit an event to all subscribers.

---

## CSS Classes Reference

| Class | Usage |
|-------|-------|
| `term-text` | Default body text color |
| `term-dim` | Dimmed/muted secondary text |
| `term-muted` | Muted text (slightly brighter than dim) |
| `term-brass` | Gold/brass accent (headings, important labels) |
| `term-steel` | Steel/blue-gray (neutral emphasis) |
| `term-ally` | Green-tinted positive feedback |
| `term-enemy` | Red-tinted negative feedback / errors |
| `term-success` | Bright green success messages |
| `term-gilded` | Bright gold for sacred/important text |
| `term-holy` | Holy/divine accent color |
| `term-prompt` | Prompt text styling |

---

## Best Practices

1. **Update Tab Titles:** Every command or major operation (like onboarding or boot sequences) should set the tab title at the start using `ctx.tab.setTitle("Title")` or `terminal.tab.setTitle("Title")`. This ensures the UI reflects the current context.

2. **Use IDs:** When creating lines that need to be updated (like progress bars or status updates), always provide a unique `id`.

3. **Handle `busy`:** Set `terminal.busy = true` during long-running async operations to prevent users from spamming commands. Set it back to `false` when done, or before calling `readLine`/`readMenu` so the user can actually type.

4. **Clean Up Sessions:** Interactive sessions (`readLine`, `readMenu`) automatically clean up their state, but manual line updates should be removed if they are temporary.

5. **Progress Bar Lifecycle:** Always call `bar.remove()` or `removeProgress()` when done with a progress bar. The `clear()` method handles this automatically, but individual bars should be cleaned up in their own scope.

6. **Theming:** Use established CSS classes to maintain visual consistency. See the CSS Classes Reference table above.

7. **Emoji Safety:** The terminal uses grapheme-aware splitting (`Intl.Segmenter`) to preserve emoji surrogate pairs. When manipulating text programmatically, use `Array.from(text)` instead of `text.split('')` to avoid breaking multi-codepoint characters.

8. **Error Handling in Commands:** Wrap async operations in try/catch blocks. The command processor will catch errors and display them, but explicit handling gives you control over the error message and class.