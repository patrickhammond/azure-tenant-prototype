# Target Azure organization

How subscriptions, management groups, and resource groups are laid out. (Playbook Section 3, with
the platform bootstrap and ownership split that the ADRs depend on folded in.)

## Subscriptions

Every combination of application and environment gets its **own subscription** — `sub-lemon-dev`,
`sub-lemon-prod`, `sub-lime-dev`, `sub-lime-prod` — plus `sub-platform` for shared services.

**Why.** A resource group and a subscription are the same kind of scope; the reasons to split are
operational: cost and quota roll up per subscription; the Container Apps grant and the Azure SQL free
offer are per subscription, so splitting multiplies them; "who has production access?" becomes one
query; and environment-specific policy has somewhere to sit.

## Management-group hierarchy

Follows Microsoft's Azure landing-zone reference architecture.

```
Tenant Root Group
└── org
    ├── platform          → sub-platform          shared services
    ├── landing-zones
    │   └── corp          → sub-lemon-dev          business applications
    │                        sub-lemon-prod
    │                        sub-lime-dev
    │                        sub-lime-prod
    ├── sandboxes         → sub-sbx-<yyyy>-<event>   (D17)
    └── decommissioned
```

- **Why an intermediate root (`org`).** Policy assigned at the Tenant Root Group applies to
  everything in the tenant permanently, including whatever arrives later. `org` gives a ceiling we
  control.
- **Why dev and prod share a management group.** Rules should be identical across environments and
  only *access* should differ. One management group keeps one copy of the rules, so a control that
  production depends on is exercised in development too.
- Set the **default management group for new subscriptions to `sandboxes`** so nothing arrives at the
  Tenant Root Group by accident.

## Inside a subscription

One resource group per application, plus one per environment for shared infrastructure. *Shared*
means within one environment, never across them.

```
sub-lime-prod
├── rg-lime-prod-shared     Container Apps environment, Log Analytics workspace,
│                           SQL logical server and every database on it
├── rg-lime-prod-web        container app, managed identity, Key Vault, DNS record
└── rg-lime-prod-worker     container app and job, managed identity, Key Vault
```

**Databases live in the shared resource group, not the application component's.** Data outlives
compute: an application's resource group must be safe to delete and rebuild, and deleting it must not
take the data with it.

## Naming

| Thing                | Pattern                        | Example                    |
| -------------------- | ------------------------------ | -------------------------- |
| Subscription         | `sub-<app>-<env>`              | `sub-lime-prod`            |
| Sandbox subscription | `sub-sbx-<yyyy>-<event>`       | `sub-sbx-2026-summerhack`  |
| Resource group       | `rg-<app>-<env>-<component>`   | `rg-lime-prod-web`         |
| Resource             | `<type>-<app>-<env>-<region>`  | `ca-lime-prod-eus`, `kv-lime-prod-eus` |

Never name a subscription after an application component. **Every resource-group name carries an
environment marker.**

## Platform bootstrap and ownership split

The platform exists first; the dependency between platform and applications is resolved by
**sequence**. Two things create infrastructure, and they never overlap:

| Platform pipeline — **once**                        | Application pipeline — **every deploy**       |
| --------------------------------------------------- | --------------------------------------------- |
| Management groups and subscriptions                 | The application's resource group              |
| The container registry                              | Its container app                             |
| Container Apps environments                         | Its Key Vault                                 |
| Log Analytics workspaces                            | Its managed identity and role assignments     |
| SQL logical server + each app's **empty** database  | Its DNS record                                |
| The DNS zone (`example.com`)                        | Its alerts                                     |
| OpenTofu state storage account and encryption key   | Its database schema and migrations (`D7`)     |
| Access-reconciliation job + `app-standard` module   |                                               |
| Each app's GitHub identities and federated creds    |                                               |

- An application's deploy identity is **created by the platform** — an identity cannot create itself,
  and an apply identity should not be able to grant itself more permission. An app's apply identity
  therefore never needs write access to the shared resource group.
- The **state storage account is a genuine bootstrap**: it cannot be created by the OpenTofu that
  stores its state in it. Create it once, by hand or a short script, before anything else. The same
  script creates the **Key Vault and key-encryption key** that state encryption depends on — `D8`
  requires `enforced = true`, so OpenTofu cannot write its first byte of state without a key to wrap
  it with. Those four resources — resource group, storage account, state container, vault and key —
  are the *whole* manual surface; everything else is code.

- A **fresh subscription registers almost no resource providers**, and the failure is mislabelled:
  creating a storage account under an unregistered `Microsoft.Storage` returns
  **`SubscriptionNotFound`**, pointing at the one thing that is fine. Register the providers first.
- **Creating a resource does not grant its data plane.** Owner on the subscription confers no blob
  or Key Vault data access; the operator's data-plane roles must be assigned *before* the first
  container or key is created, not after.
- **Role assignments at the Tenant Root Group take minutes to take effect.** A 403 immediately
  after granting a role is usually propagation, not the wrong role — but verify which by checking
  whether the role actually carries the action, since the two look identical.

**Start-up sequence:** resource providers → state storage account and encryption key → platform
pipeline → onboard an application (`docs/building-an-application.md`) → that application's pipeline
can run.
