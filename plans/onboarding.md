# Onboarding Flow

This document defines the interactive onboarding sequence for new players in Holy War Online.

---

## Technical Sequence

```
1. User signs up via Supabase Auth
   └─> Trigger `create_player_on_signup()` creates players row
       (username=NULL, sect_id=NULL, onboarding_complete=false)

2. User logs in → Terminal runs boot sequence
   └─> Client calls `get_player_status()` RPC
       └─> If onboarding_complete=false, start onboarding wizard

3. Interactive Username Entry (via terminal.readLine())
   └─> Wizard displays naming rules (3-16 chars, alphanumeric + _)
   └─> Wizard prompts: "Enter your username >"
   └─> Client-side format validation on input
   └─> Edge Function: `welcome-to-hwo` (phase: validate_username)
       - User identity from JWT Authorization header (NOT request body)
       - Format validation
       - Database availability check
       - OSS AI classification (openai-gpt-oss-120b)
   └─> On failure → Shows error, re-prompts
   └─> On success → Edge Function saves username (phase: complete_onboarding)

4. Interactive Sect Selection (via terminal.readLine())
   └─> Wizard displays all sects with emoji, description, principles
   └─> RPC: `get_available_sects()`
   └─> Wizard prompts: "Enter sect ID >"
   └─> Validates sect_id exists in list
   └─> Edge Function: `welcome-to-hwo` (phase: generate_welcome)
       - User identity from JWT Authorization header (NOT request body)
       - Fetch sect data (principles, tone) from DB
       - Venice API (gemma-4-uncensored) generates welcome message
       - Updates player.sect_id + onboarding_complete
   └─> On failure → Shows error, re-prompts

5. Welcome Message & Enter Game
   └─> AI-generated welcome displayed with faction-appropriate tone
   └─> Player enters main game terminal
   └─> "Type /help for available commands"
```

---

## Edge Function: `welcome-to-hwo`

The onboarding process relies on a secure Edge Function to handle AI generation and sensitive database updates that bypass standard client-side RLS where necessary (using the service role).

**Phases:**
- `validate_username`: Checks for profanity, availability, and format.
- `complete_onboarding`: Finalizes the player profile.
- `generate_welcome`: Uses Venice AI to create lore-accurate entry text.
