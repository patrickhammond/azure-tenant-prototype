## Why

Nothing in this repository can be built until OpenTofu has somewhere to keep its state and the tenant
has a management-group ceiling to place subscriptions under. Both are genuine chicken-and-egg steps:
the state storage account cannot store the state of the code that creates it, and a subscription
cannot be vended into a hierarchy that does not exist yet. This is `BACKLOG.md` **P-01**, the first
item of M0, and every other item is blocked behind it.

## What Changes

- **A documented, minimal manual bootstrap.** A short, re-runnable script plus the written procedure
  in `platform/README.md` that creates — once, by hand, with a signed-in human identity — exactly
  four things: the `sub-platform` resource group, the OpenTofu state storage account, the platform's
  own state container, and the Key Vault plus RSA key that `enforced = true` state encryption needs
  before OpenTofu can write its first byte of state. Nothing else is created by hand.
- **The remote-state storage account becomes a first-class, policy-conforming resource.** Shared-key
  authentication disabled, Entra/RBAC data-plane access only, blob versioning and soft delete on,
  TLS 1.2 floor (`D8`, `P3`).
- **One container per application-environment, plus one for the platform.** `sub-platform` holds the
  account; each apply identity will later be scoped to its own container only, so a dev pipeline can
  never read prod state (`D8`, `P6`). Containers are created here; the identities and their role
  assignments arrive with **P-06**.
- **The management-group hierarchy as OpenTofu.** The `org` intermediate root and its children
  (`platform`, `landing-zones` → `corp`, `sandboxes`, `decommissioned`) exactly as
  `docs/azure-organization.md` draws them, with the **default management group for new subscriptions
  set to `sandboxes`** so nothing lands at the Tenant Root Group by accident. Subscription vending
  into this tree is **P-02**, not this change.
- **`platform/` becomes a working OpenTofu root.** Pinned `azurerm` and provider versions, the
  `azurerm` backend pointing at the bootstrapped container, state **and plan** encryption with
  `enforced = true` via the `azure_vault` key provider — which authenticates with Entra ID and needs
  no passphrase, so `P3` holds with no secret anywhere in the loop — and the repository conventions
  (`fmt`, `validate`) that later changes inherit.
- **Bootstrap is idempotent and adoptable.** Re-running the script is a no-op, and the hand-created
  storage account is subsequently *described* by the platform OpenTofu so that `plan` is clean — the
  one place `D8`'s "prefer rebuilding over importing" yields, because the account holds the state that
  a rebuild would destroy.

*Not in scope:* subscriptions (**P-02**), the container registry (**P-03**), DNS (**P-04**), the
reconciliation job (**P-05**), CI identities and OIDC federation (**P-06**), and the nightly drift
job (`D8`) which needs the read-only identity from P-06.

## Capabilities

### New Capabilities

- `platform-remote-state`: where OpenTofu state lives and how it is protected — the bootstrap
  procedure and its idempotence, the storage account's required configuration, the one-container-per
  application-environment layout, encryption of state and plans, and the rule that no access key or
  stored credential is ever used to reach it.
- `management-group-hierarchy`: the tenant-level scope tree — the `org` intermediate root and its
  children, where each class of subscription is placed, the default management group for new
  subscriptions, and the naming those scopes follow.

### Modified Capabilities

_None — `openspec/specs/` is empty; this is the first change._

## Impact

- **New:** `platform/` OpenTofu root (backend, providers, management groups, the adopted state
  account), and the bootstrap script it depends on.
- **Modified:** `platform/README.md` gains the concrete bootstrap procedure that today it only
  describes in prose. `BACKLOG.md` P-01 is ticked on archive.
- **Downstream:** every later change writes state through this backend; P-02 places subscriptions
  under the hierarchy created here; P-06 grants each apply identity access to exactly one container.
- **Human prerequisites** (documented, not automated): a tenant, an existing `sub-platform`
  subscription, and an operator holding Management Group Contributor at the Tenant Root Group plus
  Owner on `sub-platform` for the duration of the bootstrap.
- **Cost:** a near-empty LRS storage account and management groups (free) — negligible against the
  $30/month per-application ceiling (`P1`).
- **`D13` operations-document rule:** not triggered — this change is platform-owned and affects no
  application; there is no `apps/<app>/docs/operations.md` to update yet.
- **De-identification:** placeholder subscription IDs (zero-GUIDs), `org`, `example.com` only.
