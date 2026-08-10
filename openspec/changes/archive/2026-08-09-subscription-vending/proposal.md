> # ⚠ SUPERSEDED — archived incomplete (2026-08-09)
>
> **The platform now targets exactly one subscription, permanently, and no management-group
> hierarchy.** This change vends four subscriptions and places them in that hierarchy, so its premise
> no longer exists. It was archived at **17 of 32 tasks**, not completed. Its delta specs were
> **deliberately not synced** into `openspec/specs/` — they describe the abandoned shape.
>
> **What killed it.** Subscription creation on a Microsoft Customer Agreement purchased through
> Azure.com is capped at **five subscriptions per billing account and one created per 24 hours**. Four
> application subscriptions plus the platform subscription is exactly five, leaving no room for `D17`
> sandboxes or `D6`'s own-subscription Restricted store, and a four-subscription estate takes four
> days to stand up. The decision was to stop paying that cost and collapse to one subscription.
>
> **Read this change for its measured findings, not its design.** Everything below was learned against
> a live tenant and most of it outlives the shape it was learned in:
>
> - The **subscription cap and rate limit**, and that exhausting the daily allowance stops returning
>   `TooManyRequests` and instead **hangs silently** until the client's 30-minute timeout — which
>   presents as broken tooling.
> - **Importing an `azurerm_subscription` proposes a replacement**, i.e. cancelling a real
>   subscription, because the alias API returns neither `workload` nor `billingScope` and `workload`
>   is force-new. Fixed with `ignore_changes = [workload, billing_scope_id]`. The general form: *an
>   import whose resource has force-new attributes the API cannot return is a cancel-and-recreate
>   waiting to happen.*
> - **`prevent_destroy` does not survive deletion of its own resource block** (measured, OpenTofu
>   1.12.5): block present plus `-destroy`/`-replace` fails the plan, block removed plans a destroy
>   silently. Only the provider-level `prevent_cancellation_on_destroy` covers the refactor case.
> - **A newly vended subscription lands in the tenant default management group**, observed twice —
>   placement is always a separate managed step, never a create-time argument.
> - **`DevTest` workload is refused** on an Individual MCA (`InvalidSku`).
> - A **saved plan file does not carry `-parallelism`**, so the flag is silently lost when an
>   interactive apply is swapped for a plan-file apply.
>
> These belong in `docs/` and are not there yet. Whoever writes the single-subscription vertical slice
> should mine this change before deleting anything.
>
> **What it left in the live tenant:** `sub-lemon-dev` and `sub-lemon-prod` exist and sit in
> `sandboxes`; `sub-platform` was correctly moved under the `platform` management group, which was
> real drift worth fixing regardless. `platform/subscriptions.tf` and `platform/placement.tf` were
> written for this shape and need removing.

## Why

The management-group tree exists (`P-01`) but nothing lives in it. Every application-environment
needs its own subscription before any application infrastructure can be built, because the
subscription — not the resource group — is the isolation boundary this platform relies on (`P5`,
`D1`): separate subscriptions are what make "no database, identity, or security group shared across
applications or environments" true by construction rather than by convention, and what let dev and
prod carry genuinely different access (`P6`).

Two facts make this change bigger than "create four subscriptions". Subscriptions created in this
tenant land in the **default** management group (`sandboxes`), not where they belong — so placement
has to be owned explicitly or every new subscription is quietly misfiled. And `sub-platform`, which
`P-01` built the platform on, is currently parented to the **Tenant Root Group** rather than to
`platform` as `docs/azure-organization.md` requires. That is live drift against the documented tree,
and this is the change that owns subscription placement, so it is the change that fixes it.

## What Changes

- **Vend the four application-environment subscriptions** — `sub-lemon-dev`, `sub-lemon-prod`,
  `sub-lime-dev`, `sub-lime-prod` — as OpenTofu-managed subscription aliases against the tenant's
  Microsoft Customer Agreement billing scope.
- **Adopt the already-existing `sub-lemon-dev`** by import rather than re-creating it. It was
  created out-of-band while proving that programmatic vending works in this tenant at all.
  Cancelling it to re-vend would destroy a real subscription to obtain an identical one, and a
  cancelled subscription cannot be fully deleted for 72 hours and keeps its ID reserved for 90 days.
  Import avoids that entirely and exercises the adoption path the playbook needs anyway for existing
  estate.
- **Own subscription→management-group placement as explicit, drift-detectable resources**, rather
  than passing a management group at create time. A create-time argument is invisible to `tofu plan`
  forever after; an association resource is re-checked on every plan, which is what makes a
  misplaced subscription a detected condition instead of a discovered one.
- **Move `sub-platform` under the `platform` management group**, correcting the drift described
  above.
- **Guard against destroy-by-accident.** Destroying an `azurerm_subscription` resource *cancels a
  real subscription*. The primary guard is a provider-level setting that suppresses cancellation
  outright, because the obvious guard — a per-resource `prevent_destroy` — was measured and does
  **not** cover the most likely accident (see `design.md`).
- **No new variables carrying real identifiers reach the repository.** The billing scope is a real,
  tenant-specific identifier, so it joins `tenant_id` and `platform_subscription_id` as a variable
  supplied through git-ignored `terraform.tfvars`, with a placeholder in the committed example.

## Capabilities

### New Capabilities

- `subscription-vending`: how application-environment subscriptions come into existence — naming,
  billing scope, the one-subscription-per-application-per-environment rule, explicit management-group
  placement, adoption of subscriptions that already exist, and the lifecycle protections that keep a
  refactor from cancelling production.

### Modified Capabilities

- `management-group-hierarchy`: the existing requirement *"Nothing arrives at the Tenant Root Group
  by accident"* covers where **new** subscriptions land but says nothing about subscriptions that are
  already parented there. `sub-platform` is exactly that case. The requirement gains a scenario
  asserting that no subscription remains a direct child of the Tenant Root Group, which turns a
  documented intention into a checkable condition.

  *Why this requirement and not "Every class of subscription has a defined home":* that one is about
  the tree **declaring** a home for each class, which it already does correctly — `sub-platform`'s
  home is defined, it simply is not where the subscription sits. The defect is specifically that a
  subscription is at the Tenant Root Group, which is the subject of this requirement and of the
  ceiling requirement that depends on it.

## Impact

- **`platform/`** — new subscription and association configuration, new import block for
  `sub-lemon-dev`, one new variable (billing scope) in `variables.tf` and
  `terraform.tfvars.example`. `local.subscription_placement` in `management-groups.tf` was written by
  `P-01` as the hook for this change and is now consumed rather than extended.
- **Live tenant** — four subscriptions created (one already exists), five placements changed.
  Subscription creation and cancellation are gated operations: the human runs the apply.
- **Cost** — an empty subscription bills nothing; the `$30/month` ceiling (`P1`, `D4`) is unaffected
  by this change. What the subscriptions later hold is where that ceiling is spent.
- **Downstream** — unblocks `P-03` (registry), `P-06` (apply identities and per-container state
  access), and every application change, none of which have a scope to deploy into until this lands.
- **`docs/`** — `azure-organization.md` documents the vending process but not that new subscriptions
  land in the default management group first; if this change proves otherwise it gets corrected in
  the same change (AGENTS.md).
