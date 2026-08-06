# D11 · Audit logging

**Status:** Accepted · **Group:** Operations

## Decision

Every application maintains an **audit log — who did what — in its own database**, separate from
telemetry (`P7`). Telemetry pipelines are designed to drop data, and a sampled audit log is not an
audit log. Log Analytics also keeps 31 days against an obligation measured in years and does not
restore with the database. It receives a **copy for operational search**; the **database is the
system of record**.

## Required

- **Append-only.** No update or delete path exists in application code.
- Every entry records **actor** (Entra object ID and display name at the time of the action),
  **action**, **target**, **UTC timestamp**, **outcome**, and **source** (UI, API, or background job).
- **Always audited:** authorization denials; role, permission, and relationship-assignment changes;
  any **read of Restricted data** (`D6`); exports and bulk downloads; any change to a record of
  record.
- **Before and after values** where the field is one a person might later dispute.
- **Retention is set by the application's obligation**, recorded in `operations.md`, never driven by
  log cost.

## Granularity

Reads of **Standard** data are **not** audited — that produces a traffic log and buries what matters.
Reads of **Restricted** data are audited **individually**.

## Example entry

```
timestamp   2026-08-04T14:22:07Z
actor       a1b2c3d4-… (display name as at the time of the action)
action      read
target      restricted_record:8841
outcome     allowed
source      UI
context     role=RestrictedDataAdministrator
```

**Revisit** when an application requires tamper-evident audit.
