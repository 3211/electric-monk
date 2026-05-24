# Virtual Computing

This module defines the virtual infrastructure, hardware configurations, and filesystems for in-game computing environments.

## Related Helper Functions (RPCs)

| Function | Parameters | Returns | Description |
|----------|------------|---------|-------------|
| `calculate_vm_encryption(p_machine_id)` | `UUID` | INT | Calculates total encryption level for a VM (base 100 + security chip bonus). Reads `security_chip_id` directly from [`virtual_machines`](#virtual_machines). |
| `generate_secure_password()` | — | TEXT | Generates a 16-character alphanumeric + special-character password. Used as DEFAULT for `admin_password` and `user_password`. |

---

## `virtual_machines`

Infrastructure for in-game computing environments. Hardware is stored flat on the row (no join table). Ownership is IP-based for maximum flexibility.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `machine_id` | UUID | PRIMARY KEY DEFAULT gen_random_uuid() | Unique machine identifier |
| `owner_identity` | inet | NOT NULL | IP address of the owning entity (player IP, sect IP, or another VM's IP) |
| `ip_address` | inet | UNIQUE DEFAULT allocate_network_address('virtual_machines') | Unique public IP of this machine (base encryption 100 + security chip bonus) |
| `machine_name` | VARCHAR | NOT NULL | Display name / hostname |
| `cpu_id` | TEXT | NOT NULL | Reference to [`catalog_cpus`](4_hardware_catalogs.md) |
| `memory_id` | TEXT | NOT NULL | Reference to [`catalog_memory`](4_hardware_catalogs.md) |
| `storage_id` | TEXT | NOT NULL | Reference to [`catalog_storage`](4_hardware_catalogs.md) |
| `network_card_id` | TEXT | NOT NULL | Reference to [`catalog_network_cards`](4_hardware_catalogs.md) |
| `case_id` | TEXT | NOT NULL | Reference to [`catalog_cases`](4_hardware_catalogs.md) |
| `power_supply_id` | TEXT | NOT NULL | Reference to [`catalog_power_supplies`](4_hardware_catalogs.md) |
| `security_chip_id` | TEXT | NULLABLE | Reference to [`catalog_security_chips`](4_hardware_catalogs.md). NULL = no chip installed. |
| `admins` | inet[] | NOT NULL DEFAULT '{}' | Pre-approved IP addresses with admin-level access. Owner IP auto-added on creation. |
| `users` | inet[] | NOT NULL DEFAULT '{}' | Pre-approved IP addresses with user-level access. Owner IP auto-added on creation. |
| `admin_password` | TEXT | NOT NULL DEFAULT generate_secure_password() | Auto-generated 16-char password for admin login (plaintext for gameplay). |
| `user_password` | TEXT | NOT NULL DEFAULT generate_secure_password() | Auto-generated 16-char password for user login (plaintext for gameplay). |
| `created_at` | TIMESTAMPTZ | DEFAULT now() | |
| `updated_at` | TIMESTAMPTZ | DEFAULT now() | |

**Indexes:**
- `idx_vm_owner` on `owner_identity`
- `idx_vm_ip` on `ip_address`
- `idx_vm_admins` on `admins` (GIN)
- `idx_vm_users` on `users` (GIN)

**RLS Policies:**
- ALL: Service role only
- SELECT: Authenticated users can view VMs where `owner_identity` matches their player IP

**Triggers:**
- `update_vm_encryption_trigger`: When `security_chip_id` or `ip_address` changes, recalculates encryption_level in [`network_addresses`](1_core_tables.md#network_addresses) based on the chip's `encryption_bonus`.

---

## `virtual_files`

The filesystem for [`virtual_machines`](#virtual_machines). Supports IP-level ownership tracking.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `file_id` | UUID | PRIMARY KEY DEFAULT gen_random_uuid() | Unique file identifier |
| `machine_id` | UUID | NOT NULL, FK → virtual_machines(machine_id) ON DELETE CASCADE | Parent machine |
| `owner_identity` | inet | NULLABLE | IP address of the entity that created/owns this file |
| `file_path` | VARCHAR | NOT NULL | Directory path |
| `file_name` | VARCHAR | NOT NULL | Filename with extension |
| `file_size_mb` | INT | NOT NULL DEFAULT 0 | Storage impact |
| `file_content` | TEXT | DEFAULT '' | Actual file data |
| `created_at` | TIMESTAMPTZ | DEFAULT now() | |

**Indexes:**
- `idx_vfiles_machine_path` on `(machine_id, file_path)`
- `idx_vfiles_owner` on `owner_identity`

**RLS Policy:** Service role only (managed via Edge Functions).

---

## `virtual_logs`

Audit trail for actions performed on or by virtual machines.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `log_id` | UUID | PRIMARY KEY DEFAULT gen_random_uuid() | |
| `machine_id` | UUID | NOT NULL, FK → virtual_machines(machine_id) ON DELETE CASCADE | Target machine |
| `timestamp` | TIMESTAMPTZ | DEFAULT now() | |
| `source_ip` | inet | NOT NULL | Originating IP of the action |
| `action_type` | VARCHAR | NOT NULL | e.g., `LOGIN`, `DELETE`, `DOWNLOAD` |
| `details` | TEXT | | Payload or context for the log entry |
| `is_spoofed` | BOOLEAN | DEFAULT false | Whether the source IP was masked |
| `trace_resistance_applied` | INT | DEFAULT 0 | Amount of resistance applied at log time |

**Indexes:**
- `idx_vlogs_machine_time` on `(machine_id, timestamp DESC)`

**RLS Policy:** Service role only (managed via Edge Functions).