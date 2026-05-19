# Dev Notes

> Parent: [`documentation-index.md`](docs/documentation-index.md)

---

- **All mutations are RPCs** — no direct table INSERT/UPDATE from frontend
- **RLS** prevents direct writes; SECURITY DEFINER functions bypass RLS
- **Cron** is the sole resource generator — frontend only reads
- **Venice AI** handles all prayer text generation server-side (API key never reaches client)
- **`src/lib/supabase-schema.sql`** is legacy; migrations in `supabase/migrations/` are authoritative
- **Blessing config** is duplicated in `src/config/blessings.json` (frontend display) and `blessing_types` table (server authority)
- **`plans/` directory** contains NO current planning files — all are obsolete. Current planning happens in Exodus migration series