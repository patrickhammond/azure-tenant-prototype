# D10 · Observability

**Status:** Accepted · **Group:** Operations

## Decision

**OpenTelemetry**, instrumented in-process via the **Azure Monitor OpenTelemetry Distro**, exporting
to a **workspace-based Application Insights resource per application**, backed by **one Log Analytics
workspace per environment**. Scope: **operational telemetry only** (`P7`).

> Previously "one workspace per subscription", which was equivalent when every application-environment
> had its own. With a single subscription that wording would put dev and prod telemetry in one
> workspace, so the rule is restated against the boundary that still exists. Whether a second
> workspace changes cost — the free ingestion allowance may be per workspace or per billing account —
> is unresolved and should be settled before the prod environment is stood up.

## Required

- **W3C trace context** propagated across every hop, including queues.
- **`cloud_RoleName` set per service** so the application map is readable.
- **Structured JSON to stdout.**
- Request rate, error rate, and latency **per endpoint**, and the same for **every outbound
  dependency**.
- **Deliberate sampling** on anything high-volume; exceptions and failures never sampled out.
- **At least 31-day retention.** Shorter saves nothing — 31 days is included in the ingestion price.
- An **ingestion-anomaly alert**, so a logging bug becomes a page rather than an invoice.
- **Not** the Container Apps managed OTel agent. It is preview (`P10`) and environment-scoped, so it
  cannot separate one application from another.

## Why OpenTelemetry

The Distro *is* OTel. If we leave Azure Monitor, the instrumentation survives and only the exporter
changes.
