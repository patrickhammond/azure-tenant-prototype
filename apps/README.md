# apps/

One subtree per application. Each application is isolated by construction — its own subscriptions,
identities, security groups, databases, and pipeline. Nothing here is shared across applications or
environments (`P5`, `P6`).

- [`lemon/`](lemon/) — the Lemon reference application
- [`lime/`](lime/) — the Lime reference application

Each application directory holds:

- `infra/` — its OpenTofu (`D8`)
- `docs/` — its operations document and decision records (`D13`)

Adding a new application: follow the checklist in
[`../docs/building-an-application.md`](../docs/building-an-application.md).
