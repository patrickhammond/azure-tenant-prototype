# D17 · Sandboxes and disposable environments

**Status:** Accepted · **Group:** Beyond a single application

## Decision

Experimentation runs in **short-lived subscriptions** under `sandboxes`, one per event.

## Required

- Participants get **Owner on that subscription only**.
- Policy **denies VNet peering outside the sandbox**, and denies VPN gateways, ExpressRoute gateways,
  and Virtual WAN hubs.
- **No production data, ever.** Synthetic or masked only.
- A **budget at creation**, alerting at 50/80/100%. Budgets alert; they do not stop spend. The 100%
  alert triggers a runbook.
- An **expiry date agreed at creation**. Cancelling the subscription on that date is manual for now.

## Graduation

A sandbox artifact is **never promoted in place**. The **design and the container image graduate; the
infrastructure does not.** It deploys into a development subscription under the full policy set,
identity is redone from scratch, and data is classified (`D6`) before any of it moves. Then the
onboarding checklist (`docs/building-an-application.md`).

## Why

Hackathons fail two ways: governed into uselessness, or quietly becoming production. Making promotion
a rebuild forces the graduation review.

**Revisit** when rebuild friction kills good ideas; the answer is a templated scaffold, not a weaker
wall.
