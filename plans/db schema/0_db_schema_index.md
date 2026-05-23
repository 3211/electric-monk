# Database Schema Index

This index provides a modular view of the Holy War Online database schema. For the authoritative, single-file reference, see [`db_schema.md`](./db_schema.md).

## Schema Modules

- [**Core Tables & Player Identity**](./core_tables.md)
  - `network_addresses`
  - `sects`
  - `players`
  - *RPCs: Signup, Onboarding, Network Allocation*
- [**Virtual Computing**](./virtual_computing.md)
  - `virtual_machines`
  - `virtual_machine_hardware`
  - `virtual_files`
  - `virtual_logs`
  - *RPCs: Encryption Calculation*
- [**Network & Connection Tracking**](./network_connections.md)
  - `connection_logs`
  - *RPCs: Connection Analysis*
- [**Hardware Catalogs**](./hardware_catalogs.md)
  - `hardware_shops`
  - `catalog_cpus`, `catalog_memory`, `catalog_storage`, etc.

## Reference
- [Authoritative Source (Full File)](./db_schema.md)
- [Migration Status](../migrations.md)
