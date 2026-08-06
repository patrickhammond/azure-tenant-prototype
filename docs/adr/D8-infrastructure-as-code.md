# D8 · Infrastructure as code

**Status:** Accepted · **Group:** Delivery

## Decision

**OpenTofu**, `azurerm` provider, remote state in **Azure Storage in `sub-platform`** with Entra and
OIDC authentication and **no access keys**, directory per environment, native state and plan
encryption with `enforced = true`.

## Required

- **Two repository classes:** the platform code, and each application's own `infra/` directory (`D9`
  draws the line). In this monorepo both live in the same repo but stay in separate directories with
  separate state.
- The **shared module is versioned and pinned by tag or commit SHA**. Never float `main`.
- **PR** runs `fmt`, `validate`, a security scan, and `plan`, posting the plan to the PR. **Merge**
  runs `apply` behind the environment gate.
- **Nightly `plan -detailed-exitcode`** with the read-only identity; exit code 2 opens a drift issue.
- **One storage account, one container per application-environment**, each apply identity reaching
  only its own container. This is `P6` one layer down: the boundary that stops a person with dev
  access from reaching prod also stops a dev pipeline reading prod state.
- **Do not mix in Azure Deployment Stacks.** Applied over resources OpenTofu also manages, they fail
  apply in ways that look nothing like the permissions problem they are. Our guardrails are Azure
  Policy and resource locks.
- **Prefer rebuilding hand-built resources over importing them.** Import only where a rebuild would
  lose data or force an outage that cannot be scheduled.

## Why client-side encryption

State records every resource and its settings, including values that were secret going in.
Encryption at rest protects against someone obtaining the disk, not someone with read access to the
storage account.

## Tradeoff

Terraform compatibility keeps this cheap to reverse; the cost is that some Microsoft tooling assumes
the `terraform` binary. We pin to features present in both.
