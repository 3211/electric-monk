# API Reference (RPCs)

This document provides usage examples and technical details for the Supabase Remote Procedure Calls (RPCs) used in Holy War Online.

**Last updated:** 2026-05-22

---

## JavaScript/TypeScript Usage Examples

All RPCs are called via the `supabase.rpc()` method. Ensure you are using an authenticated client where required.

```typescript
// Get player status (Profile + Onboarding state + Network identity)
const { data } = await supabase.rpc('get_player_status');
console.log(data.username, data.ip_address, data.sect_name, data.onboarding_complete);

// Update username (Validates and saves)
const { data } = await supabase.rpc('update_player_username', { 
  p_new_username: 'NewName_123' 
});
if (!data.success) console.error(data.error);

// Choose a sect (Sets faction affiliation)
const { data } = await supabase.rpc('choose_player_sect', { 
  p_sect_id: 'gilded_path' 
});

// Complete onboarding (Marks profile as ready)
const { data } = await supabase.rpc('complete_player_onboarding');

// Get all available sects (Returns data for selection UI)
const { data: sects } = await supabase.rpc('get_available_sects');
// Each sect object includes: id, name, ip_address, emoji, description, principles, tone_description
```

---

## Function Reference

### `allocate_network_address(p_entity_type TEXT) → inet`

Allocates a random unique IPv4 address from the `network_addresses` master registry. Loops on unique violation until a free IP is found. Used as the `DEFAULT` for `players.ip_address`.

- **Security:** `SECURITY DEFINER`, `VOLATILE`
- **Grants:** `service_role`, `postgres`

### `create_player_on_signup() → TRIGGER`

Auto-creates a `players` row when a new user signs up via Supabase Auth. Sets `username=NULL`, `sect_id=NULL`, `onboarding_complete=false`. The `ip_address` is auto-assigned via the column DEFAULT.

- **Security:** `SECURITY DEFINER`, `SET search_path = ''`
- **Grants:** `service_role`, `postgres`

### `update_player_username(p_new_username TEXT) → JSON`

Validates format (3-16 chars, `^[a-zA-Z0-9_]+$`), checks uniqueness, and updates the player's username. Returns `{success, username}` or `{success, error}`.

- **Security:** `SECURITY DEFINER`, `SET search_path = ''`
- **Grants:** `service_role`, `authenticated`

### `choose_player_sect(p_sect_id TEXT) → JSON`

Validates the sect ID exists in `sects`, then sets the player's `sect_id`. Returns `{success, sect_id}` or `{success, error}`.

- **Security:** `SECURITY DEFINER`, `SET search_path = ''`
- **Grants:** `service_role`, `authenticated`

### `complete_player_onboarding() → JSON`

Verifies the player has both a `username` and `sect_id` set, then marks `onboarding_complete = true`. Returns `{success, onboarding_complete}` or `{success, error}`.

- **Security:** `SECURITY DEFINER`, `SET search_path = ''`
- **Grants:** `service_role`, `authenticated`

### `get_player_status() → JSON`

Returns the authenticated player's profile joined with sect data. Response shape:
```json
{
  "id": "uuid",
  "username": "string",
  "ip_address": "inet",
  "sect_id": "string",
  "sect_name": "string",
  "sect_emoji": "string",
  "onboarding_complete": "boolean"
}
```

- **Security:** `SECURITY DEFINER`, `SET search_path = ''`
- **Grants:** `service_role`, `authenticated`, `anon`

### `get_available_sects() → JSONB`

Returns all sects ordered by `display_order`, including `ip_address`. Response is a JSONB array of sect objects:
```json
[
  {
    "id": "gilded_path",
    "name": "The Gilded Path",
    "ip_address": "77.77.77.77",
    "emoji": "✨",
    "description": "...",
    "principles": ["Wealth", "..."],
    "tone_description": "..."
  }
]
```

- **Security:** `SECURITY DEFINER`, `SET search_path = ''`
- **Grants:** `service_role`, `authenticated`, `anon`

---

## Technical Security Note

All RPC functions use `SECURITY DEFINER` with `SET search_path = ''` to prevent PostgreSQL search-path hijacking attacks. 

Permissions are managed via explicit `GRANT` statements to the `authenticated` and `service_role` roles. Refer to [`plans/migrations.md`](./migrations.md) for details on the `service_role` requirement for Edge Functions.