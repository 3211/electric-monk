Migration History & Guarantees

This document tracks the evolution of the Holy War Online database and defines the standards for re-runnable migrations.

**Last updated:** 2026-05-23

---

## Migration History

| Series | Files | Status | Description |
|--------|-------|--------|-------------|
| Genesis | `genesis_0.sql` | **ACTIVE** | Core network registry, player & sects foundation with IP allocation |
| Revelations | `revelations_0.sql` | **ACTIVE** | Faction seed data (four core sects with network identities) |
| Genesis | `genesis_1.sql` | **ACTIVE** | Virtual Machines, Hardware Links, Files, and Logs infrastructure |
| Revelations | `revelations_1.sql` | **ACTIVE** | Hardware Catalog & Shops seed data |
| Genesis | `genesis_1_1.sql` | **ACTIVE** | Encryption levels, security chips, and encryption calculation triggers |
| Genesis | `genesis_2.sql` | **ACTIVE** | Connection logs with combined encryption tracking and statistics RPCs |

Run all `.sql` files in lexicographic order to rebuild the full database from scratch.

---

> **⚠️ Critical: Edge Functions & Service Role Permissions**
>
> On Supabase, Edge Functions using the `SERVICE_ROLE_KEY` operate under the PostgreSQL `service_role` role — **not** `supabase_admin`, `postgres`, or `authenticator`.
>
> `genesis_0.sql` includes explicit `GRANT ALL ON TABLE` and `GRANT EXECUTE ON FUNCTION` statements for `service_role`, `supabase_admin`, `postgres`, and `authenticated` roles. Any future migration that creates new tables or functions **must** include `GRANT` statements for `service_role` if Edge Functions need to access them.
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

---

## Encryption System Migration Notes

The encryption system introduced in `genesis_1_1.sql` and `genesis_2.sql` establishes hard-locked encryption levels:

- **Players**: Fixed at 100 via `enforce_encryption_level_trigger`
- **Sects**: Fixed at 1000 via `enforce_encryption_level_trigger`
- **Virtual Machines**: Base 100 + security chip bonus from `catalog_security_chips`

**Key Functions:**
- `calculate_vm_encryption(p_machine_id UUID)` — Returns total VM encryption
- `calculate_encryption(p_ip1 inet, p_ip2 inet)` — Returns product of two IPs' encryption levels

**Connection Tracking:**
- `connection_logs` table stores `combined_encryption_level` as BIGINT (product of two INT values)
- Indexes on `combined_encryption_level` for efficient range queries
- `get_connections_by_encryption()` and `get_connection_stats()` RPCs for querying connection data