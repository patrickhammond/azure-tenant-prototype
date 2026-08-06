# D12 · Alerting

**Status:** Accepted · **Group:** Operations

## Decision

Alert on **symptoms users feel**, route by severity, hold the noise floor.

| Signal | Why it pages |
| ------ | ------------ |
| Synthetic availability check on each entrypoint | The clearest signal we have |
| Request failure rate and P95 latency breaching the stated SLO | The user-visible contract |
| `RestartCount` climbing on a revision | Proxy for crashloops; Container Apps exposes no probe-failure metric |
| Replicas pinned at max, or at zero when they should not be | Scaling exhausted or wedged |
| Dependency (database) failure rate | Where internal applications break |
| Azure Service Health and Resource Health for our regions | It is not always us |
| Log Analytics ingestion anomaly | Cost protection |

**We do not alert on:** CPU or memory percentage (scaling inputs, not incidents); individual
exceptions (rate of change only); readiness-probe failures (normal during every deploy); anything
without a runbook. If the answer is "look at it tomorrow," it is a dashboard, not an alert.

## Default

Availability tests at **five locations, 30-minute frequency, production only**. Development gets none.
Tighten only where a stated SLO justifies it, and record the number in `operations.md`.

## Required — health probes

Replace the default TCP probes with **real HTTP endpoints**. **Liveness** checks only the process;
**readiness** checks the dependencies this replica cannot serve without. **Never check dependencies
in liveness** — a brief database blip becomes a cascade of restarts. Be deliberate in readiness too,
since a shared dependency there can make the whole fleet go unready at once.

## Routing

**One action group per severity tier, not per rule.** Sev0/1 to the on-call path; Sev2+ to the
application's channel. Maintenance windows use **alert processing rules on a schedule**, never
disabled rules (which do not get re-enabled).
