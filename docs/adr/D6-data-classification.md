# D6 · Data classification inside an application

**Status:** Accepted · **Group:** The application

## Decision

Application isolation is not sufficient. Within an application, data carries one of two tiers.

| Tier | Definition | Example |
| ---- | ---------- | ------- |
| **Standard** | The application's normal operating data | Records, assignments, activity |
| **Restricted** | Data whose exposure **inside its own application** would itself be a problem | Compensation, health information, investigation records |

## Required

- The general application identity holds **no grant that reaches Restricted data**.
- **Scrubbing is an ingestion-time projection, not a query-time filter.**
- Access to Restricted data is a **separate app role, a separate data path, and an audit event on
  every read** (`D11`).
- **Classification travels with copies.** A projection still carrying Restricted fields is Restricted
  wherever it lands.
- Fields are classified **at design time**, recorded in `operations.md` (`D13`), before the table
  exists.
- **A CI test asserts that the application identity cannot read the restricted schema.**
- **Every environment carries the same shape** — same schemas, same separate principals. A permission
  model that differs between dev and prod is tested in neither.
- **Non-production holds no real Restricted data.** The projection job runs in both environments so
  the scrubbing logic is exercised rather than asserted.

An application with no Restricted data has no restricted schema. Don't create an empty one for
symmetry.

## Separate database, or separate schema?

- **Separate databases** when things differ in lifecycle, ownership, restore point, or subscription.
  Point-in-time restore is per database, so tiers with different retention or legal hold need
  separate databases.
- **Separate schemas** when they differ only in *who may read them* — the Standard/Restricted case.

## How the tiers are separated

The application connects as a contained user with **no `SELECT` on the restricted schema**; the
ingest and restricted-data-administrator identities have it. Enforcement is the **database engine**,
so a bug or an injection cannot read across.

**What that covers:** the application — bugs, injection, app roles granted too broadly. **Not
operators** — control-plane access to a database is data access, because someone with Contributor can
restore a copy and make themselves administrator on it. Where stronger isolation is required, the
Restricted store gets its **own subscription**, not only its own schema — the only way to keep it from
the application's own operators.

**Revisit** when a third tier appears (e.g. legally privileged material). That gets its own database,
and possibly its own subscription.
