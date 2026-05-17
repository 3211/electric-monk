# Fix: Economy Resources Showing 0 After Genesis 9 Migration

## Symptoms
- Mana, Gold, Food, Heresy, Dogma all display as **0** in the frontend
- Manually changing values in the database has no effect on the frontend
- Values persist correctly in the database (the data is safe)
- This broke after applying `genesis_9.sql`

## Root Cause Analysis

### Data Flow
1. `App.vue` calls `economy.fetchEconomy()` on auth
2. `fetchEconomy()` calls `supabase.rpc('get_player_economy')` 
3. The RPC returns JSON with `mana`, `gold`, `food`, etc.
4. `useEconomy.js` maps these to reactive refs
5. Components render the refs

### What Changed in Genesis 9

The `get_player_economy()` RPC was **replaced** (lines 512-722) to add one new field: `synod_relics`.

The new function now calls `public.get_synod_relics(v_user_id)` at **line 666** and includes it in the return JSON at **line 718**.

### The Bug

The `get_synod_relics()` function (defined at line 368) queries the `relics` table:

```sql
FROM relics r
LEFT JOIN profiles p ON p.id = r.holder_id
WHERE ...
```

If `get_synod_relics()` **throws an error** for any reason (permissions issue on the `relics` table, missing columns, migration partially applied, etc.), the entire `get_player_economy()` function **crashes and throws**. 

Back in `useEconomy.js`:

```javascript
async function fetchEconomy() {
    try {
      const { data, error: rpcError } = await supabase.rpc('get_player_economy')
      if (rpcError) throw rpcError
      // ... data.mana, data.gold, etc.
    } catch (err) {
      error.value = err.message
      console.error('[useEconomy] Fetch error:', err)
      // mana/gold/food remain at their default: 0
    }
}
```

The error is caught silently — `mana`, `gold`, `food`, etc. all stay at their **default value of 0** because the RPC never returned successfully.

### Why You're Seeing 0 for Everything

| Step | What happens |
|------|-------------|
| 1 | `fetchEconomy()` calls `get_player_economy()` RPC |
| 2 | RPC runs, reaches `get_synod_relics(v_user_id)` call |
| 3 | `get_synod_relics()` throws (permissions/column/missing-function issue) |
| 4 | Entire `get_player_economy()` throws, returns nothing |
| 5 | JS catches the error, values stay at `0` |
| 6 | UI renders `economy.mana` → `0`, `economy.gold` → `0`, etc. |

## Diagnosis Steps (to confirm)

1. Open browser **F12 console** — look for `[useEconomy] Fetch error:` message
2. Check Supabase logs for the `get_player_economy()` RPC call and the specific error

## Fix Plan

### Phase 1: Make `get_player_economy()` Resilient

The `get_synod_relics()` call should be wrapped in an **exception block** so it never crashes the main economy function:

```sql:

```sql
-- Instead of:
v_synod_relics := public.get_synod_relics(v_user_id);

-- Use:
BEGIN
    v_synod_relics := public.get_synod_relics(v_user_id);
EXCEPTION WHEN OTHERS THEN
    v_synod_relics := '[]'::jsonb;
    -- Log: RAISE WARNING 'get_synod_relics failed: %', SQLERRM;
END;
```

This ensures that even if `get_synod_relics()` fails, the rest of the economy data (mana, gold, food, etc.) is returned correctly.

### Phase 2: Check `get_synod_relics()` Itself

After Phase 1 restores the economy display, we can debug `get_synod_relics()` separately to understand what's actually failing. Likely causes:

1. **RLS on `relics` table** blocking reads — even though the function is SECURITY DEFINER, check if the function owner has proper permissions
2. **Migration partially applied** — `get_synod_relics` function wasn't created, so `get_player_economy` references a non-existent function
3. **Column mismatch** — the `relics` table structure differs from what the function expects

## File Changes Required

### 1. `supabase/migrations/genesis_9.sql` (CREATE migration fix)

Create a new migration `genesis_9_hotfix.sql` that:
- Replaces `get_player_economy()` with the resilient version wrapping `get_synod_relics()` in a `BEGIN/EXCEPTION` block

### OR: Direct SQL Fix

Alter just the `get_player_economy()` function to wrap the `get_synod_relics` call:

```sql
CREATE OR REPLACE FUNCTION public.get_player_economy()
RETURNS JSONB AS $$
DECLARE
    -- ... existing variables unchanged ...
    v_synod_relics JSONB;
BEGIN
    -- ... everything up to v_synod_relics assignment unchanged ...
    
    -- WRAPPED: Graceful fallback if get_synod_relics fails
    BEGIN
        v_synod_relics := public.get_synod_relics(v_user_id);
    EXCEPTION WHEN OTHERS THEN
        v_synod_relics := '[]'::jsonb;
    END;
    
    -- ... rest of function unchanged ...
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

No frontend changes needed.