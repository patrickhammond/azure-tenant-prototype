# Lemon

One of the two reference applications, deployed to **dev** and **prod** (`sub-lemon-dev`,
`sub-lemon-prod`). DNS: `lemon.example.com` (prod), `lemon.dev.example.com` (dev) — see `D5`.

- `infra/` — Lemon's OpenTofu (`D8`)
- `docs/operations.md` — how Lemon is run; required before prod (`D13`)
- `docs/decisions/` — records for anything Lemon does differently from the platform defaults (`D13`)

> **Monorepo for now.** This lives in the shared prototype repo for convenience. The intent is that
> once the prototype settles, an application like Lemon can move to its **own repository** — its
> `infra/`, `docs/`, and pipeline are already self-contained so the split is mechanical (`D9`).
