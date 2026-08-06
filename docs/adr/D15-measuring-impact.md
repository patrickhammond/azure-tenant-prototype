# D15 · Measuring impact

**Status:** Accepted · **Group:** Adoption

## Decision

Every application defines its metrics **before it ships**, instruments them as part of the build, and
reviews them on a schedule. **No metric, no launch** (`P7`).

**Required: monthly active users, emitted by the application.** This is the one measure every
application reports — the denominator for cost-to-serve and the only figure that rolls up across the
estate. Everything else is the application's decision with its champion.

## A starting set of questions (not mandated)

| Question | Might be measured as | Source |
| -------- | -------------------- | ------ |
| Is it used? | Weekly and monthly active users as a share of the intended population | The application's own telemetry |
| Is it doing the job? | Completion rate and time-to-complete for the one or two core workflows | Product metrics over the `D10` pipeline |
| Did the outcome change? | The business measure the application exists to move | Owned by the user group, sometimes manual |
| What does it cost to serve? | Monthly Azure cost ÷ monthly active users | Cost Management |

## Required

- **Do not build adoption metrics on Entra sign-in logs.** On Entra ID Free those are kept seven days
  and Graph activity logs are unavailable. Each application emits its own usage events to Application
  Insights: one line at build time, an expensive retrofit later.
- **Baseline before you build.** Measure the current-state number, however roughly, before the first
  commit.
- **Denominators, not counts.** "400 sessions" means nothing; "62% of the 210 intended users, weekly"
  means something.
- **Instrument the outcome metric as a first-class feature.** If the application exists to shorten a
  cycle, it records cycle start and end.
- **One dashboard per application**, linked from the application and its operations document.
- **Quarterly review** with the champion. A metric that has never changed a decision gets retired.
- **Cost-to-serve is a product metric.** An application costing more per user than the time it returns
  is not a success.
