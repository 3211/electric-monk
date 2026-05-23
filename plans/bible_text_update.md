# Plan: Update Bible Text Processing

The goal is to allow hyphenated names and apostrophes in Bible-related features by switching from regex-based cleaning to simple whitespace splitting for the source text.

## User Requirements
- Allow hyphens (`-`) and apostrophes (`'`) in words.
- Source text is pre-cleaned; use whitespace as the only delimiter.
- Ensure all usage of the Bible in the source follows this rule.

## Proposed Changes

### 1. `src/terminal/akashicScannerCommand.js`
- **Location**: `runScanner` function.
- **Change**: Replace the cleaning logic that strips non-alphanumeric characters.
- **Old Code**:
  ```javascript
  const cleaned = text.toLowerCase().replace(/[^\w\s]/g, '').trim()
  bibleWords = cleaned.split(/\s+/)
  ```
- **New Code**:
  ```javascript
  bibleWords = text.split(/\s+/).filter(w => w.length > 0)
  ```

### 2. `src/terminal/boot.js`
- **Location**: `loadSacredTexts` function.
- **Change**: Confirm it already uses whitespace splitting and ensure no hidden cleaning exists.
- **Current Status**: Appears to use `text.split(/\s+/).filter(w => w.length > 0)`, which matches requirements.

### 3. `src/terminal/akashic.js`
- **Location**: `scoreDecryptedText` function.
- **Change**: Update `isSpaced` logic if necessary to ensure it doesn't treat hyphens or apostrophes as word boundaries, but rather as part of the word itself.

## Verification Plan
- Run the Akashic Scanner in the terminal.
- Verify that words like "don't" or hyphenated names appear in the `[WORDS]` and `[BEST]` outputs.
- Ensure no regression in scoring for standard words.
