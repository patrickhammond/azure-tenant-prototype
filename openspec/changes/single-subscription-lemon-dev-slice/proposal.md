## Why

The platform now targets **exactly one Azure subscription, permanently**, with **no management-group
hierarchy**. Nothing in the repository yet demonstrates that shape working — `platform/` still
contains code for the abandoned one, and `openspec/specs/management-group-hierarchy` still describes
a tree the platform is walking away from.

The cause was measured, not read. Subscription creation on a Microsoft Customer Agreement purchased
through Azure.com is capped at **five subscriptions per billing account and one created per 24
hours**. Four application subscriptions plus the platform subscription is exactly five, leaving no
room for `D17` sandboxes or `D6`'s own-subscription Restricted store, and taking four serialized days
to stand up. Raising the cap needs a support request granted on consumption history; the decision was
not to pursue one.

This slice proves the replacement shape **end to end for one application in one environment**, and
corrects only the documentation it actually exercises. Doing it as a vertical slice rather than a
paper redesign is deliberate: this project has repeatedly found that reality contradicts the
playbook, and six ADR rewrites written ahead of a working example would risk a second round of
assumptions.

## What Changes

- **Resource groups become the unit of vending.** Creating a resource group requires write at
  subscription scope, which the guardrail below denies to application identities. So the platform
  creates application resource groups **empty, with role assignments already attached**, and the
  application fills them. This is the role the subscription used to play.
- **A per-environment shared plane, platform-owned.** `rg-platform-dev-shared` holds the dev Container
  Apps environment and Log Analytics workspace. Applications get no write access to it — only a
  single-action custom role permitting them to *join* the environment.
- **A per-application-environment data group.** `rg-lemon-dev-shared` holds Lemon dev's SQL logical
  server, database, and database principal. Per-application servers rather than a shared one, because
  a SQL database cannot live in a different resource group from its server, and a shared server would
  force every application's database into a platform-owned group.
- **The guardrail that makes resource-group isolation mean anything.** Azure Policy denies
  subscription-scoped assignments of Owner, Contributor, and User Access Administrator; an alert fires
  if that policy assignment is deleted or exempted.
- **The slice is applied by the deploy identity, never by an operator.** A subscription Owner bypasses
  every boundary under test, so applying by hand would demonstrate nothing.
- **BREAKING: the management-group hierarchy is abandoned.** The `management-group-hierarchy`
  capability is removed. The live management groups are *not* deleted here — that has an ordering
  trap and gets its own change.
- **Removed:** `platform/subscriptions.tf` and `platform/placement.tf`, both written for the abandoned
  shape.

## Capabilities

### New Capabilities

- `application-scaffolding`: how an application-environment is vended — the resource groups the
  platform creates for it, the identities it gets, the roles those identities hold and at what scope,
  and the boundary that an application cannot cross from inside its own groups.
- `subscription-scope-guardrail`: the policy that denies subscription-scoped privileged role
  assignments, the alert that fires when that policy is tampered with, and the explicitly accepted
  residual risk that a subscription Owner can still remove it.

### Modified Capabilities

- `management-group-hierarchy`: **removed in full.** The platform no longer uses management groups.
  Every requirement in it — the tree, the tenant default management group, the policy ceiling, the
  placement map, the naming rules — describes a structure that will not exist.

## Impact

- **`platform/`** — new resource groups, the custom join role, the deny policy and its alert, the
  deploy identity and federated credential. `subscriptions.tf` and `placement.tf` deleted;
  `management-groups.tf` deliberately untouched.
- **`apps/lemon/infra/`** — created: container app on a digest-pinned public image, managed identity,
  Key Vault, SQL server, database, database principal.
- **`.github/workflows/`** — a minimal workflow that applies the application root as the deploy
  identity. Required, not optional: it is the only way to test the boundary as a constrained principal.
- **`openspec/specs/`** — `management-group-hierarchy` retired; two capabilities added.
  `platform-remote-state` is untouched, and its five state containers survive the pivot intact — they
  were always per application-environment, never per subscription.
- **`docs/`** — `azure-organization.md`'s *Subscriptions*, *Management-group hierarchy*, *Inside a
  subscription*, and *Naming* sections rewritten; its mid-revision banner narrowed to what remains
  stale. `D10` corrected from "one Log Analytics workspace per subscription" to per environment, which
  under one subscription would otherwise mean one workspace for dev and prod together.
- **Still knowingly stale after this change:** `D1`, `D4`, `D6`, `D7`, and `D17` continue to reference
  subscriptions, and the live tenant still has six management groups and two surplus subscriptions.
  Both remain flagged rather than quietly left.
- **Cost** — expected at or near zero, and verified by observation rather than asserted.
