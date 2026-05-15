# Internal Documentation for AI Agents

## Project Overview: Electric Monk (Prayer App)
Electric Monk is a prayer tracking application with a token economy (Mana), karma system, and ban/indulgence mechanics. It uses Supabase for the backend and Venice AI for prayer processing.

## Database Schema Authority
The authoritative database schema is located in [`src/lib/supabase-schema.sql`](src/lib/supabase-schema.sql). A human-readable version with explanations is in [`docs/schema.md`](docs/schema.md).

**CRITICAL:** Do not rely on local Supabase CLI sync or `supabase/migrations`. The SQL file in `src/lib/` is the single source of truth.

## Key Systems

### 1. Token Economy (Mana)
- **Table:** `profiles`
- **Columns:** `tokens_spent_today`, `daily_token_limit`
- **Ratio:** 5 characters = 1 Mana (rounded up).
- **Logic:** Handled by the `submit_prayer` RPC function.

### 2. Prayer Counter
- **Table:** `prayers`
- **Columns:** `prayer_count`, `last_counted_at`, `activated_at`
- **Logic:** 
  - `activate_prayer(uuid)`: Deactivates current prayer (syncing count) and starts a new one.
  - `sync_prayer_count(uuid, elapsed)`: Incremental update while active.
  - `deactivate_prayer(uuid, elapsed)`: Final sync and stop.

### 3. Karma System
- **Table:** `profiles`
- **Column:** `karma`
- **Logic:** Updated via `update_karma(uuid, change)` RPC, typically called by Edge Functions after AI processing.

### 4. Ban & Indulgences
- **Table:** `profiles` (`ban_until`), `indulgences`
- **Logic:** `reduce_ban_time(uuid)` reduces `ban_until` by 15 minutes per indulgence record created.

## Development Constraints
- Use RPC functions for atomic operations involving tokens or counters.
- Row Level Security (RLS) is enabled on all tables.
- All prayers are linked to a Supabase Auth `user_id`.
