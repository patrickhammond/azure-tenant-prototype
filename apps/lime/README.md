# Lime

One of the two reference applications, deployed to **dev** and **prod** (`sub-lime-dev`,
`sub-lime-prod`). DNS: `lime.example.com` (prod), `lime.dev.example.com` (dev) — see `D5`.

- `infra/` — Lime's OpenTofu (`D8`)
- `docs/operations.md` — how Lime is run; required before prod (`D13`)
- `docs/decisions/` — records for anything Lime does differently from the platform defaults (`D13`)

> **Monorepo for now.** This lives in the shared prototype repo for convenience. The intent is that
> once the prototype settles, an application like Lime can move to its **own repository** — its
> `infra/`, `docs/`, and pipeline are already self-contained so the split is mechanical (`D9`).
