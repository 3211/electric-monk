# Migration History & Guarantees

This document tracks the evolution of the Holy War Online database and defines the standards for re-runnable migrations.

---

## Migration History

| Series | Files | Status | Description |
|--------|-------|--------|-------------|
| Genesis | `genesis_0.sql` | **ACTIVE** | Core player & sects foundation |
| Genesis Hotfix | `genesis_0_hotfix.sql` | **ACTIVE** | GRANT permissions + fix `get_available_sects()` ORDER BY |
| Genesis Hotfix | `genesis_0_hotfix_1.sql` | **ACTIVE** | Service role GRANTs for Edge Functions |
| Revelations | `revelations_0.sql` | **ACTIVE** | Faction seed data (four core sects) |

Run all `.sql` files in lexicographic order to rebuild the full database from scratch.

---

> **⚠️ Critical: Edge Functions & Service Role Permissions**
>
> On Supabase, Edge Functions using the `SERVICE_ROLE_KEY` operate under the PostgreSQL `service_role` role — **not** `supabase_admin`, `postgres`, or `authenticator`.
>
> **The bug:** `genesis_0_hotfix.sql` initially granted permissions to `supabase_admin`, `postgres`, and `authenticator`, which did **not** cover Edge Functions. This caused `permission denied for table players` errors at runtime.
>
> **The fix:** [`genesis_0_hotfix_1.sql`](../supabase/migrations/genesis_0_hotfix_1.sql) grants `ALL ON TABLE` and `EXECUTE ON FUNCTION` explicitly to `service_role`. Any future migration that creates new tables or functions **must** include `GRANT` statements for `service_role` if Edge Functions need to access them.
>
> **Pattern for new tables/functions:**
> ```sql
> GRANT ALL ON TABLE public.<table_name> TO service_role;
> GRANT EXECUTE ON FUNCTION public.<function_name>(<arg_types>) TO service_role;
> ```

---

## Re-runnability Guarantees

All migrations use the following patterns to ensure safe re-execution:

1. **`CREATE TABLE IF NOT EXISTS`** — Skips table creation if already exists
2. **`DROP POLICY IF EXISTS ... CREATE POLICY`** — Replaces RLS policies cleanly
3. **`DROP TRIGGER IF EXISTS ... CREATE TRIGGER`** — Replaces triggers cleanly
4. **`INSERT ... ON CONFLICT (key) DO UPDATE`** — Upserts seed data
5. **`CREATE OR REPLACE FUNCTION`** — Updates function definitions in place
6. **`CREATE INDEX IF NOT EXISTS`** — Skips index creation if already exists
