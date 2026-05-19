# Social Messaging (Shouts)

> Parent: [`documentation-index.md`](documentation-index.md)

---

## Overview

Shouts are social messages posted through the Town Crier — an AI edge function that translates user input into faction-appropriate language, soft-censors real-world slurs/threats/doxxing, and rewrites content within the game universe.

## Mechanics

- **Global Shouts**: Cost 100 gold (personal). Visible to all players in the Akashic Records under the "Shouts" tab → "Global" sub-tab.
- **Sect Shouts**: Visible only to members of the same sect. Shown in the Akashic Records under "Shouts" tab → "My Sect" sub-tab. These are global shouts filtered by `sect_type`.
- **Synod Forum**: Private to the synod. Leader/officers pay 50 gold from the **synod vault**. Regular members pay 100 gold (personal). Shown in the Synod Hall → "Forum" tab.
- **Replies**: Cost 50 gold (personal). Each reply is also filtered through the Town Crier. Replies can be blessed.
- **Blessings**: Same blessing types as prayers (Golden Light, Holy Flame, Dove of Peace, Divine Crown). Applied to shouts or replies. Deducts karma, awards rebate + receiver karma, grants Divine Shield.
- **Permanence**: Shouts and replies cannot be deleted. The Akashic Record is permanent.
- **Pricing config**: All costs stored in `game_config` table (`shout.global_cost`, `shout.reply_cost`, `shout.synod_leader_cost`, `shout.synod_member_cost`).

## Flow

1. Player writes a message and clicks "Shout It!" (or "Post to Forum" for synod)
2. `submit_shout` RPC deducts gold, creates a `shouts` row with `status='pending'`
3. Frontend invokes `town-crier` edge function with `shout_id`
4. Town Crier translates the message to faction-appropriate style
5. Town Crier updates the `shouts` row: sets `crier_content` and `status='posted'` (or `status='failed'`)
6. Frontend refreshes the shout feed

For replies, the same flow applies using `submit_shout_reply` RPC and `reply_id` parameter.

## Tables

### `shouts`
| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | |
| `user_id` | UUID → profiles.id | |
| `content` | TEXT | Original user text |
| `crier_content` | TEXT | Town Crier translated text |
| `context` | TEXT CHECK | `global` or `synod` |
| `synod_id` | UUID → synods.id | NULL for global shouts |
| `sect_type` | TEXT CHECK | Set for global shouts (for sect filtering) |
| `status` | TEXT CHECK | `pending`, `posted`, `failed` |
| `created_at` | TIMESTAMPTZ | |
| `updated_at` | TIMESTAMPTZ | |

RLS: SELECT public. INSERT own. No UPDATE/DELETE (permanent record).

### `shout_replies`
| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | |
| `shout_id` | UUID → shouts.id | |
| `user_id` | UUID → profiles.id | |
| `content` | TEXT | Original user text |
| `crier_content` | TEXT | Town Crier translated text |
| `status` | TEXT CHECK | `pending`, `posted`, `failed` |
| `created_at` | TIMESTAMPTZ | |

RLS: SELECT public. INSERT own. No UPDATE/DELETE (permanent record).

### `shout_blessings`
| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | |
| `shout_id` | UUID → shouts.id | |
| `reply_id` | UUID → shout_replies.id | NULL for shout-level blessing |
| `blessing_type_id` | TEXT → blessing_types.id | Reuses prayer blessing types |
| `giver_id` | UUID → profiles.id | |
| `receiver_id` | UUID → profiles.id | |
| `created_at` | TIMESTAMPTZ | |

UNIQUE(shout_id, COALESCE(reply_id, nil), blessing_type_id, giver_id). RLS: SELECT public. INSERT own.

## RPC Functions

| Function | Returns | Notes |
|----------|---------|-------|
| `submit_shout(TEXT, TEXT)` | JSONB | Deducts gold, creates pending shout. Context: `global` or `synod`. Synod leaders/officers billed from vault. |
| `submit_shout_reply(UUID, TEXT)` | JSONB | Deducts 50 gold, creates pending reply. |
| `get_shouts(INT, INT, TEXT)` | JSONB | Paginated shout feed. Filter: `global`, `sect`, `synod`. Includes author info + blessing aggregates + reply count. |
| `get_shout_replies(UUID, INT, INT)` | JSONB | Shout detail with paginated replies. Includes blessing aggregates. |
| `grant_shout_blessing(UUID, TEXT, UUID)` | JSONB | Bless a shout or reply. Deducts karma, awards rebate + receiver karma, grants Divine Shield. |
| `get_shout_blessings(UUID[])` | JSONB | Batch blessing aggregates for multiple shouts. |

## Edge Functions

| Function | Purpose |
|----------|---------|
| `town-crier` | Translates shouts/replies into faction-appropriate language. Accepts `shout_id` or `reply_id` to update DB after translation. Soft-censors slurs, threats, doxxing. |

## Views

| View | Tab | Purpose |
|------|-----|---------|
| `AkashicRecordsView.vue` | "Shouts" sub-tab | Global + Sect shout feeds with submission form |
| `SynodHallView.vue` | "Forum" tab | Synod-private shout feed with synod-vault pricing |

## Components

| Component | Type | Purpose |
|-----------|------|---------|
| `ShoutCard.vue` | Molecule | Shout card with author, crier content, blessing badges, reply count |
| `ShoutDetailModal.vue` | Organism | Full shout detail with replies, reply form, and inline blessing picker |

## Composables

| Composable | Tables | Key RPCs |
|------------|--------|----------|
| `useShouts.js` | shouts, shout_replies, shout_blessings | `submit_shout`, `submit_shout_reply`, `get_shouts`, `get_shout_replies`, `grant_shout_blessing` |