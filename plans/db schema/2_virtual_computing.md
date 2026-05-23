# Virtual Computing

This module defines the virtual infrastructure, hardware configurations, and filesystems for in-game computing environments.

## Related Helper Functions (RPCs)

| Function | Parameters | Returns | Description |
|----------|------------|---------|-------------|
| `calculate_vm_encryption(p_machine_id)` | `UUID` | INT | Calculates total encryption level for a VM (base 100 + security chip bonus). |

---

## `virtual_machines`

Infrastructure for in-game computing environments. Performance metrics are derived from linked hardware.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `machine_id` | UUID | PRIMARY KEY DEFAULT gen_random_uuid() | Unique hardware identifier |
| `owner_identity_id` | UUID | FK → players(id) ON DELETE SET NULL | The player who owns the machine |
| `ip_address` | inet | UNIQUE DEFAULT allocate_network_address('virtual_machines') | Public IP of the virtual computer (base encryption 100 + security chip bonus) |
| `machine_name` | VARCHAR | NOT NULL | Display name / hostname |
| `case_id` | TEXT | NOT NULL | Reference to `catalog_cases` |
| `power_supply_id` | TEXT | NOT NULL | Reference to `catalog_power_supplies` |
| `created_at` | TIMESTAMPTZ | DEFAULT now() | |

**RLS Policy:** Service role only (managed via Edge Functions).

**Triggers:**
- `update_vm_encryption_on_ip_trigger`: Automatically calculates and updates encryption_level in network_addresses when a VM gets an IP assigned or when security chips are equipped.

---

## `virtual_machine_hardware`

Links specific hardware components to a virtual machine.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PRIMARY KEY DEFAULT gen_random_uuid() | |
| `machine_id` | UUID | NOT NULL, FK → virtual_machines(machine_id) ON DELETE CASCADE | Parent machine |
| `hardware_type` | VARCHAR | NOT NULL | e.g., `cpu`, `memory`, `storage`, `network_card`, `security_chip` |
| `catalog_id` | TEXT | NOT NULL | Reference to the specific catalog item ID |
| `slot_index` | INT | DEFAULT 0 | Logical slot position (for UI/constraints) |
| `created_at` | TIMESTAMPTZ | DEFAULT now() | |

**Indexes:**
- `idx_vmh_machine` on `(machine_id, hardware_type)`

**RLS Policy:** Service role only.

**Triggers:**
- `update_vm_encryption_trigger`: When a security_chip is inserted/updated, recalculates the VM's encryption_level in network_addresses based on the chip's encryption_bonus.

---

## `virtual_files`

The filesystem for `virtual_machines`.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `file_id` | UUID | PRIMARY KEY DEFAULT gen_random_uuid() | Unique file identifier |
| `machine_id` | UUID | NOT NULL, FK → virtual_machines(machine_id) ON DELETE CASCADE | Parent machine |
| `file_path` | VARCHAR | NOT NULL | Directory path |
| `file_name` | VARCHAR | NOT NULL | Filename with extension |
| `file_size_mb` | INT | NOT NULL DEFAULT 0 | Storage impact |
| `file_content` | TEXT | DEFAULT '' | Actual file data |
| `created_at` | TIMESTAMPTZ | DEFAULT now() | |

**Indexes:**
- `idx_vfiles_machine_path` on `(machine_id, file_path)`

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
