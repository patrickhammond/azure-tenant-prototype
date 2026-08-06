# D3 · Shared platform components

**Status:** Accepted · **Group:** Foundations

## Decision

Where two applications would need the same thing, **the platform owns one instance**. Nothing on this
list is rebuilt per application.

| Component | What it does | Where |
| --------- | ------------ | ----- |
| Access-reconciliation job | Turns group membership into app-role assignments (`D1`) | `sub-platform` |
| `app-standard` OpenTofu module | The standard application scaffold, called by every application | Platform code |
| Operations-document template | The headings in `D13` | Platform code |
| Impact-dashboard template | A starting shape for `D15` | Platform code |

The platform is a **target, not a description of today**. Each row earns its place the moment a
second application would otherwise copy it; until then, building it out is work with no reader.

## The access-reconciliation job (why one, and its safety property)

Entra ID Free cannot assign a group to an app role, so a single platform job reads the membership of
the Entra security groups named in its configuration and the app-role assignments currently on each
application's service principal, computes the difference, and adds/removes assignments to match. It
touches **nothing else** — no application database, no Azure resource, no group membership, no user
account. It cannot grant Azure RBAC.

- **Runs hourly and is idempotent**, so a failed run is corrected by the next.
- Each application-environment is a **separate entry with its own service principal**, so a person
  can hold a role in dev and nothing in prod — `P6` in the application layer.
- **Safety property:** a group that is renamed, deleted, or unreadable is **logged and skipped**. The
  job never interprets "I could not read the source of truth" as "the source of truth is empty" — a
  reconciliation loop that did would revoke everyone's access at three in the morning.
- Applications have **no runtime dependency** on it. If it stops, existing access is unaffected and
  new joiners wait for the next run. An outage is a Sev2, not a page.

## Accepted risk

The job's permission, `AppRoleAssignment.ReadWrite.All`, can grant **any** app role to **any**
principal in the tenant, and Graph offers no scoped version. One job rather than one per application
keeps that exposure in one place. Its identity is a **tier-0 asset**: platform-team deploy only,
reviewed configuration, and it refuses to act on any service principal not in that configuration.

**Revisit** when Entra ID P1 is purchased — at which point the job is deleted and the same groups are
assigned directly to the same app roles.
