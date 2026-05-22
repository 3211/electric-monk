# Holy War Online — Database Schema (The Ought)

This document defines the intended architectural state of the Holy War Online database. It serves as the single source of truth for table structures, relationships, and server-side logic.

**Implementation Status:** See [`docs/migrations.md`](./migrations.md) for the current migration status.  
**Last updated:** 2026-05-21

---

## Core Tables

### `sects`

Faction metadata that drives AI generation and game mechanics. This table is **read-only for players** and populated by seed data.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | TEXT | PRIMARY KEY | Slug identifier: `gilded_path`, `holy_way`, `final_watch`, `black_tribunal` |
| `name` | TEXT | UNIQUE NOT NULL | Display name of the faction |
| `emoji` | TEXT | NOT NULL | Visual icon for the faction |
| `description` | TEXT | | Lore description of the faction |
| `principles` | TEXT[] | NOT NULL DEFAULT '{}' | Array of faction principles used for AI prompts |
| `tone_description` | TEXT | | Tone descriptor for AI generation (e.g., "opulent and grand") |
| `created_at` | TIMESTAMPTZ | DEFAULT now() | |
| `updated_at` | TIMESTAMPTZ | DEFAULT now() | |

**RLS Policy:** Public read-only. Only service role can modify.

**Seed Data:**
| id | name | emoji | principles |
|----|------|-------|------------|
| `gilded_path` | The Gilded Path | ✨ | Wealth, Prosperity, Ambition, Capital, Grandeur |
| `holy_way` | The Holy Way | 🕊️ | Compassion, Charity, Devotion, Selflessness, Healing |
| `final_watch` | The Final Watch | 🛡️ | Vigilance, Protection, Endurance, Loyalty, Defense of the faithful |
| `black_tribunal` | The Black Tribunal | 🗡️ | Conquest, Eradicating heresy, Ruthlessness, Selfishness, Personal gain |

---

### `players`

Core player data linked to `auth.users`. Tracks username, sect affiliation, and onboarding state.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PRIMARY KEY, FK → auth.users(id) | References Supabase auth user |
| `username` | TEXT | UNIQUE | Player name (3-16 chars, alphanumeric + underscore) |
| `sect_id` | TEXT | FK → sects(id) ON DELETE SET NULL | Current faction affiliation |
| `onboarding_complete` | BOOLEAN | DEFAULT false | TRUE when player has completed name + sect selection |
| `created_at` | TIMESTAMPTZ | DEFAULT now() | |
| `updated_at` | TIMESTAMPTZ | DEFAULT now() | |

**Constraints:**
- `players_username_check`: `^[a-zA-Z0-9_]+$` (3-16 chars)

**RLS Policy:**
- SELECT: Authenticated users can read all players
- UPDATE/INSERT: Users can only modify their own row (`auth.uid() = id`)

---

### `game_config`

Central key-value store for all game balance parameters. Read by RPCs and the cron heartbeat for production calculations.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `key` | TEXT | PRIMARY KEY | Dot-notation identifier: e.g., `tick.production_divisor` |
| `value` | NUMERIC | NOT NULL | The balance value |
| `description` | TEXT | | Human-readable description of what this config does |
| `category` | TEXT | DEFAULT 'production' | Logical grouping: `production`, `karma`, `combat`, `vassalage`, `social`, `sect_bonus` |
| `created_at` | TIMESTAMPTZ | DEFAULT now() | |
| `updated_at` | TIMESTAMPTZ | DEFAULT now() | |

**Key Categories:**
- `karma`: Prayer reward tuning
- `production`: Engine speed & tick rates
- `vassalage`: Tithe and subjugation rules
- `social`: Synod and shout costs
- `combat`: PvP and Holy War tuning

---

### `faction_relationships`

Defines enemy/ally/neutral status between sects for combat bonuses and narrative flavor.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PRIMARY KEY DEFAULT gen_random_uuid() | |
| `sect_key` | TEXT | UNIQUE, FK → sects(id) | The faction this row describes |
| `enemy_sect` | TEXT | NOT NULL, FK → sects(id) | The faction they are at war with |
| `ally_sect` | TEXT | NOT NULL, FK → sects(id) | The faction they are allied with |
| `neutral_sect` | TEXT | NOT NULL, FK → sects(id) | The faction they are neutral toward |
| `rationale_enemy` | TEXT | | Lore explanation for the enmity |
| `rationale_ally` | TEXT | | Lore explanation for the alliance |
| `rationale_neutral` | TEXT | | Lore explanation for the neutrality |

---

## Helper Functions (RPCs)

Detailed usage patterns can be found in [`docs/api_reference.md`](./api_reference.md).

### Player Management

| Function | Parameters | Returns | Description |
|----------|------------|---------|-------------|
| `create_player_on_signup()` | — | TRIGGER | Auto-creates player row on auth.users INSERT |
| `update_player_username(p_new_username)` | `TEXT` | JSON | Validates and updates username |
| `choose_player_sect(p_sect_id)` | `TEXT` | JSON | Sets player's faction |
| `complete_player_onboarding()` | — | JSON | Marks onboarding complete |
| `get_player_status()` | — | JSON | Returns player profile + onboarding state |
| `get_available_sects()` | — | JSONB | Returns all sects for selection |

---

## Future Expansions

The following tables are planned for future development:

| Table | Purpose |
|-------|---------|
| `shop_items` | Purchasable buildings, prayer slots, research |
| `player_buildings` | Player-owned buildings and production |
| `prayers` | Active and completed prayers |
| `synods` | Player alliances/guilds |
| `shouts` | Global chat messages |
| `relics` | Unique global artifacts |
| `research_nodes` | Tech tree for light/dark research |
