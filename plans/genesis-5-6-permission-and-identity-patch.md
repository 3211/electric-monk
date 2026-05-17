# Genesis 5 & 6: Permission Fix + Identity/PFP/Sect Rename Patch

## Background

Browser console errors show 403 Forbidden on `prayers` and `profiles` tables when accessed by the `authenticated` role. The root cause is missing `GRANT` statements in `genesis_4.sql` — RLS policies exist but PostgreSQL blocks access at the GRANT layer first.

Additionally, the user wants to:
- Rename sect internal keys to custom nomenclature
- Add PFP (profile picture) system
- Add username change with karma cost
- Merge ProfileCompletionModal + SectSelectionModal into a unified onboarding flow

---

## genesis_5.sql — Permission Fix Patch

### Phase 1: GRANT Permissions

| Table | Role | Permission | Reason |
|-------|-----|-----------|--------|
| `prayers` | `authenticated` | SELECT, INSERT, UPDATE | Frontend reads own prayers, updates prayer state, submits prayers |
| `prayers` | `service_role` | ALL | Completeness |
| `profiles` | `authenticated` | SELECT, INSERT, UPDATE | Frontend reads profile, upserts username/faith, updates tokens/ban |
| `profiles` | `service_role` | ALL | Already existed, confirming |
| `indulgences` | `authenticated` | SELECT, INSERT | RPC inserts, frontend may query |
| `indulgences` | `service_role` | ALL | Missing, adding |

### Phase 2: Missing RLS Policies

| Table | Policy | Operation | Check |
|-------|--------|-----------|-------|
| `profiles` | "Users can insert own profile" | INSERT | `auth.uid() = id` |
| `profiles` | "Users can update own profile" | UPDATE | `auth.uid() = id` (USING + WITH CHECK) |
| `indulgences` | "Users can view own indulgences" | SELECT | `auth.uid() = user_id` |

### Frontend Access Audit (confirmed)

- `usePrayers.js:74` — `.from('prayers').select('*')` → needs SELECT
- `usePrayers.js:136` — `.from('profiles').upsert(...)` → needs INSERT + UPDATE
- `usePrayers.js:186` — `.from('profiles').update(...)` → needs UPDATE
- `usePrayers.js:284` — `.from('prayers').select('*')` → needs SELECT
- `usePrayers.js:334` — `.from('prayers').update(...)` → needs UPDATE
- `usePrayers.js:399` — `.from('prayers').update(...)` → needs UPDATE
- `usePrayers.js:428` — `.from('prayers').update(...)` → needs UPDATE
- `usePrayers.js:456` — `.from('prayers').update(...)` → needs UPDATE
- `useAkashicRecords.js:137` — `.from('prayers').select('*')` → needs SELECT
- `useAkashicRecords.js:175` — `.from('prayers').select('*')` → needs SELECT
- `useBanTimer.js:112` — `.from('profiles').select(...)` → needs SELECT
- `useBanTimer.js:137` — `.from('profiles').update(...)` → needs UPDATE
- `useBanTimer.js:199` — `.from('profiles').update(...)` → needs UPDATE
- `useVassalage.js:248` — `.from('profiles').select(...)` → needs SELECT

---

## genesis_6.sql — Sect Rename, PFP, Username Change

### Phase 1: Sect Renaming Data Migration

**Rename mapping:**
- `prosperity_gospel` → `gilded_path`
- `ascetic_order` → `holy_way`
- `doomsday_preppers` → `final_watch`
- `inquisition` → `black_tribunal`

**Steps:**
1. Drop CHECK constraints on `profiles.sect_type`, `shop_items.sect_restriction`, `shop_items.sect_exclusion`
2. UPDATE `profiles` SET `sect_type` with new values
3. UPDATE `shop_items` SET `sect_restriction` and `sect_exclusion` with new values
4. UPDATE `game_config` keys: replace `sect.prosperity_gospel.` → `sect.gilded_path.`, etc.
5. Add new CHECK constraints with renamed values
6. Update `choose_sect()` function to accept new names

### Phase 2: PFP Schema

1. `ALTER TABLE profiles ADD COLUMN pfp_index INT DEFAULT 0;`
2. `ALTER TABLE profiles ADD COLUMN unlocked_pfps JSONB DEFAULT '[0]'::jsonb;`

### Phase 3: Username Security

1. `CREATE UNIQUE INDEX IF NOT EXISTS profiles_username_unique ON profiles(username) WHERE username IS NOT NULL;`
2. Create `change_username(p_new_username TEXT)` RPC:
   - Check username uniqueness
   - Verify user has >= 1000 karma
   - Deduct 1000 karma
   - Update username transactionally

### Phase 4: GRANT for new function

- `GRANT EXECUTE ON FUNCTION change_username(TEXT) TO authenticated;`

---

## Frontend Changes

### 1. Unified IdentityModal.vue

Merge `ProfileCompletionModal.vue` + `SectSelectionModal.vue` into a single forced onboarding modal:
- PFP display (square container, decorative medieval frame, loaded from `/public/pfp/0.png`)
- Username input with validation
- Four sect selection cards with new names:
  - The Gilded Path (gilded_path)
  - The Holy Way (holy_way)
  - The Final Watch (final_watch)
  - The Black Tribunal (black_tribunal)
- Cannot dismiss until both username + sect are submitted
- On submit: upsert profile (username), then call `choose_sect` RPC

### 2. Update `useSects.js`

- Update `sectInfo` map with new keys and display names
- Remove emojis from sect descriptions per user requirement
- The `chooseSect()` function already calls `choose_sect` RPC — just need to pass new key names

### 3. Username Change Modal (KarmaShop/Altar)

- Add "Change Username" action in Altar settings area
- Display warning: costs 1000 Karma
- Input field for new username
- Call `change_username` RPC
- Handle error responses (username taken, insufficient karma)

### 4. Update `App.vue`

- Replace separate `SectSelectionModal` + `ProfileCompletionModal` with unified `IdentityModal`
- Show modal when `!username || !sectType`
- Remove old modal imports