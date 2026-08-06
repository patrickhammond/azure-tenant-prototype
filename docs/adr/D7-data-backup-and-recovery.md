# D7 · Data, backup, and recovery

**Status:** Accepted · **Group:** The application

## Decision

**Azure SQL Database**, one per application per environment, on a **logical server per application**.
The platform creates the server and an empty database; the application owns the schema inside it.
**Entra-only authentication; SQL authentication disabled at the server.**

| Setting | Development | Production |
| ------- | ----------- | ---------- |
| Tier | Free offer (GP serverless, auto-pause) | Standard **S0** |
| PITR retention | 7 days | 35 days |
| Backup redundancy | Geo-redundant | Geo-redundant |
| Long-term retention | None | Only where a retention obligation exists |
| Access | Entra groups + managed identities as contained database users | Same |

**Why serverless works in dev and not prod.** Auto-pause requires zero sessions for the entire delay
window, and an idle pooled connection is a session. Nothing runs overnight in dev, so the pause
fires; in prod it does not, and a database that never pauses costs an order of magnitude more than
S0.

## Recovery — required

- **Default RTO: one week**, unless an application states otherwise in writing. Do not write "RPO:
  one week" anywhere; point-in-time restore gives roughly ten-minute granularity, so the practical
  RPO is under an hour.
- **Geo-redundant backup storage plus point-in-time restore, and nothing else.** Geo-replication,
  failover groups, long-term retention, a DNS alias on the logical server, and SQL Data Sync all
  defeat auto-pause and break the cost model. Each is a review item, not a default.
- **Restore drills** are the application's own scheduled Job, running in its own subscription against
  its own database: restore production to a side database, assert row counts and a checksum, drop it.
  Monthly for the first three; quarterly once three consecutive drills pass. A failed drill is an
  incident.

## Schema migration — required

- Migrations run as a **manual Container Apps Job**, triggered by the pipeline and **gated before the
  revision rolls**, using the same image with a **separate migration identity holding DDL rights the
  runtime identity does not**.
- Scripts are **versioned and idempotent**.
- The gate **polls to a terminal state**. Starting a job is not waiting for it. Treating "job
  started" as success ships the revision against an unmigrated database. **Fail on failure or
  timeout; a timeout is not a pass.**

**Never** on application startup (replicas race, and the app would need schema rights it should not
hold), as an init container (those run per replica), or from the CI runner (that breaks the day the
database moves behind a private endpoint).

**Revisit** when a database exceeds 250 GB or needs zone redundancy or a Hyperscale path. That moves
it to the vCore General Purpose model, off the legacy DTU tiers.
