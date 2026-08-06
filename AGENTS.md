# AGENTS.md

Guidance for AI coding agents (Claude Code, Codex, and others) working in this repository.
`CLAUDE.md` is a symlink to this file.

## What this repository is

A **public reference implementation** of an internal-application platform on Azure: how to run
several business applications, each with its own environments, alongside shared platform
infrastructure — with isolation, cost, and identity handled by construction rather than convention.

It is a worked example, not a live system. Two example applications, **Lemon** and **Lime**, each
with a **dev** and a **prod** environment, sit on top of one **shared platform**. Everything lives in
**one monorepo** for convenience. The build is done spec-first with **OpenSpec**. The repo is
currently greenfield — the layout below is the target, not the current state.

## Design docs — read before designing anything non-trivial

`docs/` is the de-identified playbook, and the **design authority** for this repo. Don't restate its
rules here or in code comments; link to the record. If this file and `docs/` ever disagree, `docs/`
wins and this file gets corrected.

- `docs/adr/` — the 17 architecture decision records (`D1`–`D17`); start at `docs/adr/README.md`.
- `docs/principles.md` — principles `P0`–`P10`, the tie-breakers every ADR defers to.
- `docs/azure-organization.md` — subscriptions, management-group hierarchy, resource-group layout,
  naming, and the platform bootstrap / ownership split.
- `docs/building-an-application.md` — the new-application checklist and go-live gates.

Appendices and the playbook's client-specific migration state are intentionally not carried over;
implementation notes get written as the implementations are built.

## Working in this repo

### Public-repo de-identification (load-bearing)

This repository will be published. It must contain **no reference to any real client, company,
person, tenant, domain name, or subscription ID.** Everything is the de-identified version. Apply
these mappings consistently and never reintroduce the originals:

| Real thing            | Use in this repo                                            |
| --------------------- | ---------------------------------------------------------- |
| The client/org name   | A generic placeholder (`org`, `example`) — never the real one |
| The two applications  | **Lemon** and **Lime**                                     |
| Non-production / production env | **dev** / **prod**                               |
| DNS zone              | `example.com` (`lemon.example.com`, `lemon.dev.example.com`) |
| Subscription IDs      | Zero-GUIDs / obvious placeholders                          |
| Tenant / people       | Placeholders only                                          |

Before committing, grep the diff for leaked real names. When unsure whether a name is generic enough,
make it more generic.

### OpenSpec

Non-trivial changes are spec-driven via **OpenSpec**. Use the installed `/opsx:*` commands and
`openspec-*` skills to propose, apply, archive, and sync changes — don't hand-drive the CLI or
hand-edit generated spec files. Project context and authoring rules for OpenSpec live in
[`openspec/config.yaml`](openspec/config.yaml).

### Monorepo layout (target)

The playbook assumes one repo per application; here each application is a subtree (see `D9`).

```
apps/<app>/           # e.g. apps/lemon, apps/lime
  infra/              # this app's OpenTofu (D8)
  docs/operations.md  # operations doc; required before prod (D13)
  docs/decisions/     # ADRs for anything this app does differently (D13)
platform/             # shared-platform OpenTofu: subscriptions, registry, DNS, state, etc. (D3, azure-organization)
.github/workflows/    # one deployment pipeline per app (e.g. lemon.yml), triggered by its path (D9)
docs/                 # the de-identified playbook (above)
openspec/             # spec-driven change proposals and specs
```

## Load-bearing constraints (each detailed in `docs/`)

The decisions most likely to be violated silently. Read the referenced record before working near one:

- **Isolation by construction** — no database, managed identity, or security group shared across
  applications or environments (`P5`, `azure-organization.md`).
- **dev ≠ prod access** — separate subscriptions, groups, and approval; enforced by RBAC (`P6`, `D1`).
- **No standing credentials** — managed / federated identity only; `Active Directory Default` locally
  (`P3`, `D1`, `D2`).
- **Authorize on the `roles` claim, never `groups`** — 3–7 coarse roles; anything finer resolved from
  app data; absent role = designed **Guest** (`D1`).
- **Standard vs Restricted data** — separate app role, data path, DB principal, and per-read audit;
  same shape in every environment (`D6`).
- **Deploy by digest** — build → capture digest → `tofu apply` with it; promotion re-applies the
  **same** digest, never a rebuild (`D9`).
- **Three measurements never conflated** — telemetry, audit, product metrics; all three required
  (`P7`, `D10`, `D11`, `D15`).
- **Cost ceiling** — one whole application, both environments, under **$30/month** (`P1`, `D4`, `D7`).
