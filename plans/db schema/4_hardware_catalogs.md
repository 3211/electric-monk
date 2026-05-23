# Hardware Catalogs

This module defines the hardware vendors and the static catalog of components available for purchase and installation.

---

## `hardware_shops`

Defines hardware vendors/shops where components can be purchased.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | TEXT | PRIMARY KEY | Slug identifier: `public_hub`, `gilded_market`, `shadow_node` |
| `name` | TEXT | NOT NULL UNIQUE | Display name of the shop |
| `description` | TEXT | | Lore / utility description |

**RLS Policies:** Public read-only. Service role full access.

---

## `catalog_cpus`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | TEXT | PRIMARY KEY | |
| `name` | TEXT | NOT NULL | Display name |
| `base_price` | INT | NOT NULL | Cost in credits |
| `cores` | INT | NOT NULL | Number of CPU cores |
| `clock_speed_mhz` | INT | NOT NULL | Clock speed in MHz |
| `power_draw_watts` | INT | NOT NULL | Power consumption |
| `available_in_shops` | TEXT[] | NOT NULL DEFAULT '{}' | Array of shop IDs where available |

**RLS Policies:** Public read-only. Service role full access.

---

## `catalog_memory`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | TEXT | PRIMARY KEY | |
| `name` | TEXT | NOT NULL | Display name |
| `base_price` | INT | NOT NULL | Cost in credits |
| `capacity_gb` | INT | NOT NULL | Memory capacity in GB |
| `speed_mhz` | INT | NOT NULL | Memory speed in MHz |
| `power_draw_watts` | INT | NOT NULL | Power consumption |
| `available_in_shops` | TEXT[] | NOT NULL DEFAULT '{}' | Array of shop IDs where available |

**RLS Policies:** Public read-only. Service role full access.

---

## `catalog_storage`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | TEXT | PRIMARY KEY | |
| `name` | TEXT | NOT NULL | Display name |
| `base_price` | INT | NOT NULL | Cost in credits |
| `capacity_mb` | INT | NOT NULL | Storage capacity in MB |
| `read_speed_mbps` | INT | NOT NULL | Read throughput |
| `write_speed_mbps` | INT | NOT NULL | Write throughput |
| `power_draw_watts` | INT | NOT NULL | Power consumption |
| `available_in_shops` | TEXT[] | NOT NULL DEFAULT '{}' | Array of shop IDs where available |

**RLS Policies:** Public read-only. Service role full access.

---

## `catalog_network_cards`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | TEXT | PRIMARY KEY | |
| `name` | TEXT | NOT NULL | Display name |
| `base_price` | INT | NOT NULL | Cost in credits |
| `bandwidth_mbps` | INT | NOT NULL | Network bandwidth |
| `trace_resistance` | INT | NOT NULL | Reduces speed of hostile tracing algorithms |
| `power_draw_watts` | INT | NOT NULL | Power consumption |
| `available_in_shops` | TEXT[] | NOT NULL DEFAULT '{}' | Array of shop IDs where available |

**RLS Policies:** Public read-only. Service role full access.

---

## `catalog_security_chips`

Encryption modules that boost VM security levels.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | TEXT | PRIMARY KEY | |
| `name` | TEXT | NOT NULL | Display name |
| `base_price` | INT | NOT NULL | Cost in credits |
| `encryption_bonus` | INT | NOT NULL | Bonus added to base encryption level (100) |
| `power_draw_watts` | INT | NOT NULL | Power consumption |
| `available_in_shops` | TEXT[] | NOT NULL DEFAULT '{}' | Array of shop IDs where available |

**RLS Policies:** Public read-only. Service role full access.

---

## `catalog_cases`

Chassis that determine expansion capability.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | TEXT | PRIMARY KEY | |
| `name` | TEXT | NOT NULL | Display name |
| `base_price` | INT | NOT NULL | Cost in credits |
| `max_expansion_slots` | INT | NOT NULL | Maximum number of hardware slots |
| `available_in_shops` | TEXT[] | NOT NULL DEFAULT '{}' | Array of shop IDs where available |

**RLS Policies:** Public read-only. Service role full access.

---

## `catalog_power_supplies`

Power units that determine total available wattage.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | TEXT | PRIMARY KEY | |
| `name` | TEXT | NOT NULL | Display name |
| `base_price` | INT | NOT NULL | Cost in credits |
| `max_output_watts` | INT | NOT NULL | Maximum power output |
| `available_in_shops` | TEXT[] | NOT NULL DEFAULT '{}' | Array of shop IDs where available |

**RLS Policies:** Public read-only. Service role full access.
