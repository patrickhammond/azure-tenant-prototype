## Context

`P-01` built the management-group tree and deliberately left `local.subscription_placement` in
`platform/management-groups.tf` as the hook for this change — a map from subscription class to
management-group ID, so that "which management group does this go under?" has one answer in one
place. This change consumes that hook.

The tenant's capabilities were established empirically before designing anything, because the
answer changes the shape of the change entirely:

| Fact | Value | How established |
| --- | --- | --- |
| Billing agreement | Microsoft Customer Agreement, `Individual`, `Direct` | `az billing account list` |
| Azure Plan | Enabled (`skuId 0001`) | `az billing profile list` |
| Invoice section | One, `Active` | `az billing invoice section list` |
| Caller's billing role | Billing account owner, at account scope | `az billing role-assignment list` |
| Programmatic vending | **Supported** — `provisioningState: Succeeded` | `az account alias create`, actually run |

That last row is the load-bearing one. The backlog was written assuming vending might be impossible
here (a pay-as-you-go tenant cannot vend), which would have made this change "create in the portal,
then adopt". It was proven possible by creating a real subscription rather than by reading
documentation about account types, per the repo's verify-don't-assert convention. The side effect of
that proof — a real `sub-lemon-dev` — is an input to this design, not a mistake to undo.

Provider capabilities were likewise checked against the **pinned** provider schema
(`azurerm ~> 4.81`, OpenTofu 1.12.5) rather than assumed:

- `azurerm_subscription` — `subscription_name` (required), `alias`, `billing_scope_id`,
  `subscription_id`, `workload`.
- `azurerm_management_group_subscription_association` — exists; `management_group_id` and
  `subscription_id` both required.
- `azurerm_billing_mca_account_scope` — data source exists, composes the billing scope from account,
  profile, and invoice-section names.
- `features { subscription { prevent_cancellation_on_destroy } }` — exists in this provider version.

## Goals / Non-Goals

**Goals**

- Four application-environment subscriptions exist, correctly named, under `corp`.
- `sub-platform` sits under `platform`, matching `docs/azure-organization.md`.
- Placement is re-checked on every `tofu plan`, so misplacement is detected, not discovered.
- Cancelling a subscription by refactor is prevented at two independent layers.
- No real tenant, billing, or subscription identifier enters the repository.

**Non-Goals**

- **No RBAC.** Who can do what inside these subscriptions is `P-06`. This change creates empty
  scopes and stops.
- **No policy assignments.** Guardrails at `corp` are their own change.
- **No budgets or cost alerts.** `D4`/`P1` machinery comes later; empty subscriptions bill nothing.
- **No resources inside the subscriptions.** They are deliberately empty when this lands.
- **No sandbox or decommissioned subscriptions.** `D17`'s lifecycle is out of scope.

## Decisions

### Vend with `azurerm_subscription`, not `azapi`

The alias API is what `az account alias create` used, and `azurerm_subscription` wraps it directly.
`azapi` is reserved in this repo for things azurerm genuinely does not model (currently only the
tenant default-management-group setting). Using the typed resource keeps the destroy-safety features
below available, which `azapi` would not give.

*Alternative considered:* `azapi_resource` on `Microsoft.Subscription/aliases`. Rejected — no
cancellation guard, and no reason to reach past the typed resource.

### Placement via association resources, not `subscription_ids` and not create-time placement

Three ways exist to place a subscription. Only one is continuously verified:

| Mechanism | Re-checked each plan? | Verdict |
| --- | --- | --- |
| Alias `managementGroupId` at create time | No — create-only, invisible afterwards | Rejected |
| `azurerm_management_group.subscription_ids` | Yes, but it fights the association resource | Rejected |
| `azurerm_management_group_subscription_association` | Yes | **Chosen** |

Create-time placement is the tempting one and the wrong one: it would produce a correct tenant today
and a silently-wrong one the first time someone moved a subscription in the portal, because nothing
would ever look again. The association resource turns that into a plan diff.

`subscription_ids` on `azurerm_management_group` is `Optional + Computed` in the pinned schema, so
`P-01`'s existing management groups — which do not set it — will not fight the association
resources. This is a real constraint on future changes, not just a note: setting `subscription_ids`
on any group in this tree would produce two resources claiming the same association and a permanent
plan diff.

**The two ID shapes do not match, and the wrong one is the obvious one.** The association's
`subscription_id` expects a subscription *resource path* — `/subscriptions/<guid>`, which is what
the `azurerm_subscription` **data source**'s `.id` returns. But the `azurerm_subscription`
**resource**'s `.id` is the *alias* resource ID
(`/providers/Microsoft.Subscription/aliases/<name>`), because the resource models the alias rather
than the subscription. Wiring `azurerm_subscription.app[k].id` therefore reads correctly and is
wrong. The subscription GUID is available as `.subscription_id`, so the association must be built as
`"/subscriptions/${azurerm_subscription.app[k].subscription_id}"`. Verified against the pinned
schema, where `subscription_id` is documented as "The GUID of the Subscription".

### Adopt `sub-lemon-dev` by import; do not cancel and re-vend

Cancel-and-re-vend would destroy a real subscription in order to obtain an identical one. The
provider's own documentation is explicit about the cost: a destroyed subscription goes to
**cancelled**, is reactivatable for 90 days, is irrevocably deleted after that, and its subscription
ID can never be reused. Manual deletion is possible only after 72 hours. None of that buys anything
the import does not.

An earlier draft of this design claimed the *alias name* is also held for that window, which would
have made import the only workable option rather than merely the better one. That claim is not
supported by any source consulted and has been removed rather than left in as convenient
justification — the decision stands on cost and reversibility, which are documented.

**This extends `D8`'s carve-out rather than fitting inside it, and says so.** `D8` prefers rebuilding
hand-built resources and permits import "only where a rebuild would lose data or force an outage that
cannot be scheduled". `sub-lemon-dev` is empty — a rebuild would lose no data and cause no outage, so
the literal exception does not apply. The argument here is a third cost of the same severity: a
rebuild permanently burns an **irrecoverable identifier**. A subscription ID cannot be reused, ever,
and that is as unrecoverable as lost data. Recorded explicitly so a reader comparing this against
`D8` sees a reasoned extension rather than a misapplied citation. If `D8` should say this, it gets
amended when this change lands.

Import is also representative: the playbook needs an adoption path for existing estate, and this
exercises it on a real subscription instead of leaving it theoretical. `imports.tf` already
establishes the convention of keeping import blocks after the first apply, so the empty-tenant path
stays entirely in source (`P4`).

Because the subscriptions are created with `for_each` over the application-environment list, the
import block must address the specific **instance** — `azurerm_subscription.app["lemon-dev"]`, not
`azurerm_subscription.app`. An unkeyed address against a `for_each` resource is an error, not a
silent mis-target, but it is an easy one to write.

### Two guards against cancellation — and only one of them covers the likely accident

Destroying an `azurerm_subscription` resource **cancels a real subscription**: the provider attempts
cancellation on destroy, and a cancelled subscription is irrevocably deleted after 90 days with its
ID never reusable. A rename or module refactor that drops a resource is an ordinary mistake with an
extraordinary blast radius here, so it gets defence in depth:

1. `features { subscription { prevent_cancellation_on_destroy = true } }` on the provider — destroy
   drops the alias instead of cancelling the subscription. **Provider-wide, so it survives deletion
   of the resource block.** This is the primary guard.
2. `lifecycle { prevent_destroy = true }` on each subscription — fails any plan that would destroy
   or replace it *while the block is present*. Secondary.

The ordering matters, and it is the opposite of the intuitive one. `prevent_destroy` was **measured**
against OpenTofu 1.12.5 rather than assumed, and it does not do what the obvious reading suggests:

| Situation | Result |
| --- | --- |
| Block present, `-destroy` or `-replace` | Plan **fails** — `prevent_destroy set, but the plan calls for it to be destroyed` |
| **Resource block removed from config** | Plans a destroy, **silently** — `(because … is not in configuration)` |

So `prevent_destroy` protects against a forced replacement or a deliberate destroy, but gives **no**
protection against the exact scenario that motivated it — a refactor that deletes the resource
block, which deletes the guard along with it. Only the provider-level setting covers that case.

This limitation is recorded here and in the spec rather than papered over, because a guard believed
to be stronger than it is is worse than a guard known to be partial: it invites exactly the refactor
it fails to stop. Anyone tempted to drop the provider setting as "redundant" should read the table
above first.

Because the provider setting is load-bearing, it is **proved empirically** (task 4.6) rather than
accepted on documentation.

It was originally scheduled *first*, on the reasoning that a negative result should arrive before
four subscriptions depend on it. That was reversed once subscription creation turned out to be
throttled to the point of scarcity (see the risk below): spending a creation attempt and a burned
subscription ID on a throwaway, ahead of the three subscriptions the change actually needs, is the
wrong trade when attempts are the binding constraint. The test now runs at the end against
`sub-lime-prod`, the least depended-on real subscription.

The cost of that reordering is explicit: if the guard turns out to be fiction, one real subscription
is cancelled and must be re-vended against a throttled API, and the guard ordering above is wrong.
That is a worse failure than the throwaway version — accepted deliberately, because the alternative
was blocking all progress on an API that would not answer.

Note the two guards collide during this test: `prevent_destroy` refuses the very destroy that
exercises `prevent_cancellation_on_destroy`. The task therefore lowers the secondary guard only, and
only after it has been separately verified.

*Alternative considered:* a `CanNotDelete` management lock on each subscription. Rejected — locks
govern resource deletion within a subscription, not cancellation of the subscription itself, so it
would add ceremony without covering the gap.

### Naming: alias name = subscription display name

Both are `sub-<app>-<env>` per `docs/azure-organization.md`. Letting them diverge would mean the
portal and the code disagree about what a subscription is called. The subscriptions are derived from
the existing `var.application_environments` list rather than a new hand-written list, so
`lemon-dev` cannot exist as a state container without a matching subscription.

### `workload = "Production"` everywhere, including dev

`DevTest` is not merely undesirable here, it is **rejected by the API**. Measured while vending the
guard probe:

```
InvalidSku: Can't create DevTest Azure plans for individual billing account.
```

So on an Individual MCA the choice does not exist — useful to know before someone "optimises" dev
subscriptions onto DevTest rates and discovers this mid-change. Even where it is available, `P6` says
rules should be identical across environments and only *access* should differ: a different
subscription workload type for dev is exactly the kind of environment-shaped divergence that record
exists to prevent. The already-vended `sub-lemon-dev` was
created as `Production`, so this also keeps the import clean. Both `workload` and `alias` are
force-new, so getting this wrong is expensive to correct.

### Billing scope is a variable, never a literal

The billing account, profile, and invoice-section names are real, tenant-identifying values. They
join `tenant_id` and `platform_subscription_id` in git-ignored `terraform.tfvars`, with obvious
placeholders in `terraform.tfvars.example`. Composed via the `azurerm_billing_mca_account_scope`
data source rather than string-concatenating an ARM path, so a malformed scope fails at plan time.

## Risks / Trade-offs

- **A destroy reaches a real subscription** → Provider-level cancellation guard, plus
  `prevent_destroy` for the cases it does cover, plus reviewing every `tofu plan` in this change
  specifically for `destroy` and `replace` lines. The residual gap — a refactor that removes a
  resource block — is closed only by the provider setting, which is why it is primary.
- **Import of `sub-lemon-dev` mismatches the config and the provider proposes replace** → Replace
  means cancel-and-recreate. The import is verified by a plan that must show **no changes** for that
  resource before any apply proceeds; `workload`, `alias`, and `subscription_name` are matched to
  what was actually created. Only those three are force-new, so only they can escalate a mismatch
  into a replacement.
- **The import proposed cancelling a real subscription — confirmed, and worse than predicted** →
  `billing_scope_id` was flagged in review as unlikely to read back on import. It doesn't. But the
  more dangerous field was missed: the alias API returns **neither `billingScope` nor `workload`**,
  and `workload` is **force-new**. So the first plan after adding the import block reported:

  ```
  # azurerm_subscription.app["lemon-dev"] must be replaced
  + workload = "Production" # forces replacement
  Plan: 1 to import, 4 to add, 0 to change, 1 to destroy.
  ```

  A replacement here means *cancelling* `sub-lemon-dev` and vending a new one — against an API that
  is throttled, for a subscription ID that could never be recovered. `prevent_destroy` refused the
  plan, which is the first time in this change a guard has caught a real defect rather than a
  hypothetical one.

  Remedy: `ignore_changes = [workload, billing_scope_id]`. Safe because neither can legitimately
  change once a subscription exists, and `ignore_changes` does not affect creation, so newly vended
  subscriptions still get `workload = "Production"`. After it, the plan is
  `1 to import, 3 to add, 0 to change, 0 to destroy`.

  The general lesson, worth more than the fix: **an import whose resource has force-new attributes
  the API cannot return is a cancel-and-recreate waiting to happen.** Reviewing the plan is what
  catches it; "the import succeeded" is not the same as "the import is clean".
- **`sub-platform` moves while the platform state lives inside it** → Moving a subscription between
  management groups does not touch resources within it; the storage account, Key Vault, and state
  containers are unaffected. The risk is instead to *inherited role assignments* — none exist yet
  (`P-06` has not run), which makes now the cheapest possible moment to do this. Because this
  reasoning is an expectation rather than a measurement, the move is followed by an explicit check
  that state is still readable and writable, rather than inferring it from a clean plan.
- **Vending is capped at ONE subscription per 24 hours** → This is a documented Microsoft billing
  limit, not a transient throttle, and it is the single most important operational fact about
  vending on this account type. For an MCA purchased through Azure.com, the defaults are **five
  subscriptions per billing account** and **one new subscription per 24-hour period**; raising either
  requires a support request, with no self-service path.

  Every symptom this change hit is explained by that one rule:

  | Observation | Explanation |
  | --- | --- |
  | `sub-lemon-dev` created, then three `TooManyRequests` | day's allowance spent |
  | `sub-lemon-prod` created in 2m13s next day, `lime-dev`/`lime-prod` hung 30 min in the same apply | one per day — the other two could never succeed |
  | serialized retry of `lime-dev` hung identically | not contention; the day's allowance was already gone |

  Two consequences the design must carry. **A four-subscription reference implementation takes four
  days to stand up on this account type** — the walking skeleton is gated by billing policy, not by
  engineering. And the four application subscriptions plus `sub-platform` come to exactly **five**,
  which is the default ceiling: this repo's shape fits, with nothing spare. A third application
  would need a support request.

  Also note the failure is *silent* once the daily allowance is spent — the API stops returning
  `TooManyRequests` and simply hangs until the client's 30-minute timeout. An operator who has not
  read this will conclude the tooling is broken.

  Sources: [Create an MCA subscription](https://learn.microsoft.com/en-us/azure/cost-management-billing/manage/create-subscription),
  [Message appears when you try to create multiple subscriptions](https://learn.microsoft.com/en-us/azure/cost-management-billing/troubleshoot-subscription/create-subscriptions-deploy-resources).

  Consequences, in order of importance:
  1. Creation runs with `-parallelism=1`. Concurrent creates would multiply the problem.
  2. A throttled apply is a **normal outcome to plan for**, not an exception. The recovery path in
     the tasks is on the main road.
  3. `TooManyRequests` arrived *before* creation, so nothing was stranded — verified by
     `az account alias list`. But that is the benign shape of this failure. The dangerous shape is a
     throttle or timeout *after* the alias is created, which leaves the tenant ahead of state.
     Never infer from the error text that nothing was created — check.
  4. Vending may need to be spread across several applies. That is tedious, not incorrect.

- **Alias creation is asynchronous and can time out client-side** → A create that times out locally
  can still succeed in Azure, leaving a subscription the state file does not know about. A plain
  retry then attempts an alias that already exists. Reconciling `az account alias list` against
  `tofu state list` before retrying is what makes this recoverable.
- **A future change sets `subscription_ids` on a management group** → Permanent plan diff.
  Recorded in the spec as a prohibition rather than left as folklore.
- **Cost** → This change intentionally creates no metered resources, so it should contribute nothing
  to `P1`'s ceiling. Stated as an expectation rather than a measured bill: it is confirmed by
  verifying the subscriptions are empty after apply, not by asserting a number here.

## Migration Plan

1. Add the billing-scope variable and provider `features` guard; confirm `tofu plan` still clean.
2. Add subscription resources for all four, plus the import block for `sub-lemon-dev`.
3. **Plan and read it.** Expect: three creates, one import with no changes, zero destroys.
4. Human applies (subscription creation is a gated operation).
5. Add the five association resources — four application subscriptions to `corp`, `sub-platform` to
   `platform`. **Read this plan too**: expect five creates and zero destroys. No separate step is
   needed to remove the old placement — an association replaces whatever parent the subscription
   currently has.
6. Verify placement independently of OpenTofu, via `az account management-group entities list`, and
   confirm `sub-lemon-dev` is no longer under `sandboxes` and `sub-platform` no longer under the
   Tenant Root Group.
7. Re-run `tofu plan`; it must be clean.

Associations are applied *after* subscriptions rather than in one apply so that step 3's plan is
readable and the vending step can be verified on its own.

**Rollback:** placement is reversible — delete an association or re-point it, no data is at risk.
Vending is effectively **not** reversible on a useful timescale: the only remedy for an unwanted
subscription is cancellation, which cannot be completed for 72 hours, keeps the subscription in the
reactivation lifecycle for 90 days, and permanently burns its subscription ID. This asymmetry is why
step 3 exists.

## Open Questions

- `docs/azure-organization.md:39` **already** states that the default management group is `sandboxes`
  "so nothing arrives at the Tenant Root Group by accident" — an earlier draft of this design claimed
  that fact was undocumented, which was simply wrong. The genuine gap is narrower: the doc does not
  say that a vended subscription *transiently sits in the default group until placement is applied as
  a separate step*, which is what makes placement a distinct managed resource rather than a create-
  time argument. Confirm during implementation and correct in the same change per AGENTS.md.
- Should `sub-platform` also carry `prevent_destroy` once it is under OpenTofu-managed association?
  It is not an `azurerm_subscription` resource here — only its association is managed — so there is
  nothing for OpenTofu to cancel. Revisit if `sub-platform` is ever adopted as a full resource.
