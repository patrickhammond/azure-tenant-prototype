# Internal Application Platform — Reference Implementation

A worked, public example of how to run several internal business applications on **Microsoft Azure**:
each application with its own environments, sitting on top of shared platform infrastructure, with
**isolation, cost, identity, and delivery handled by construction rather than convention**.

Two example applications — **Lemon** and **Lime** — each with a **dev** and a **prod** environment,
share one **platform**. Everything lives in a single monorepo and is built spec-first with
[OpenSpec](https://github.com/Fission-AI/OpenSpec).

> This is a reference/prototype, not a live system, and it is intentionally **de-identified**: it
> contains no real organization, tenant, person, domain, or subscription. Adapt the placeholders
> (`org`, `example.com`, zero-GUIDs) to your own.

## Goals

- **Isolation by construction.** No database, managed identity, or security group is ever shared
  across applications or environments — separation is enforced by the topology, not by policy prose.
- **Cost as a constraint.** An entire application — both environments, all infrastructure — stays
  under **$30/month**.
- **No standing credentials.** Managed identities and federated (OIDC) identity throughout; no
  password lives in a pipeline or on a laptop.
- **Reproducible from source.** All infrastructure is OpenTofu; every deploy is build → migrate →
  apply, and promotion to production re-applies the exact image that was tested.
- **Access by who you are, not where you connect from.** Entra-authenticated users, authorized on
  coarse application roles.
- **Adoption is part of delivery.** Every application ships with operations docs, audit logging, and
  impact metrics — deploy continuously, release deliberately.

## Design docs

The design is captured as decision records under [`docs/`](docs/), which is the authority for how and
why things are built:

- [`docs/adr/`](docs/adr/README.md) — the 17 architecture decision records (`D1`–`D17`).
- [`docs/principles.md`](docs/principles.md) — the principles (`P0`–`P10`) every record defers to.
- [`docs/azure-organization.md`](docs/azure-organization.md) — subscriptions, management-group
  hierarchy, resource-group layout, naming, and the platform bootstrap.
- [`docs/building-an-application.md`](docs/building-an-application.md) — the onboarding checklist and
  go-live gates.

## Repository layout

```
apps/<app>/           # per-application: infra/ (OpenTofu) and docs/ (operations, decisions)
platform/             # shared-platform OpenTofu: subscriptions, registry, DNS, remote state
.github/workflows/    # one deployment pipeline per application
docs/                 # the decision records and platform docs above
openspec/             # spec-driven change proposals and specs
```

The repo is currently greenfield; the layout above is the target as implementations land.

## Dependencies

You need the following to work with this repository:

- **[Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)** — install it, then
  [get started / sign in](https://learn.microsoft.com/en-us/cli/azure/get-started-with-azure-cli?view=azure-cli-latest)
  with `az login`. Access flows from Entra group membership; nothing is copied to your machine.
- **[OpenTofu](https://opentofu.org/docs/intro/install/)** — the infrastructure-as-code tool
  (`azurerm` provider), used for all platform and application infrastructure.
- **[OpenSpec](https://github.com/Fission-AI/OpenSpec)** — the spec-driven change workflow
  (`npm install -g openspec`).
- A **GitHub** account with access to this repository — CI/CD runs on GitHub Actions and authenticates
  to Azure with OIDC (no stored credentials).
- An **Azure tenant and subscriptions** with the management-group hierarchy from
  [`docs/azure-organization.md`](docs/azure-organization.md), if you intend to deploy.

## Getting started

1. Install the [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) and
   [sign in](https://learn.microsoft.com/en-us/cli/azure/get-started-with-azure-cli?view=azure-cli-latest):
   `az login`.
2. Read [`docs/adr/README.md`](docs/adr/README.md) and
   [`docs/principles.md`](docs/principles.md) to understand the model.
3. Follow the platform bootstrap sequence in
   [`docs/azure-organization.md`](docs/azure-organization.md), then the onboarding checklist in
   [`docs/building-an-application.md`](docs/building-an-application.md).

Contributors: see [`AGENTS.md`](AGENTS.md) for repository conventions, the de-identification rules,
and the OpenSpec workflow.
