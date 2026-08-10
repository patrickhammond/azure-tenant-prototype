## Context

The platform targets **exactly one Azure subscription, permanently**, with **no management-group
hierarchy**. This replaces the subscription-per-application-per-environment target the repository was
built around.

The cause is a billing constraint, measured rather than read: the billing account is a Microsoft
Customer Agreement purchased through Azure.com, which caps subscriptions at **five per billing
account** and **one created per 24 hours**
([Microsoft docs](https://learn.microsoft.com/en-us/azure/cost-management-billing/troubleshoot-subscription/create-subscriptions-deploy-resources)).
Four application subscriptions plus the platform subscription is exactly five — no room for `D17`
sandboxes or `D6`'s own-subscription Restricted store, and a four-day serialized rollout. Raising the
cap requires a support request granted on consumption history; the decision was not to pursue one.

Consequences already landed:

- `P5` and `P6` in `docs/principles.md` rewritten; the residual risk recorded in
  `docs/azure-organization.md`.
- The `subscription-vending` change archived as superseded at 17/32 tasks, its measured findings
  preserved in its proposal banner.

This slice proves the replacement shape end to end for **one application in one environment**, and
corrects only the documentation it exercises. Breadth follows.

## Goals / Non-Goals

**Goals**

- A working Lemon dev application in the single-subscription layout.
- The resource-group boundary demonstrated to actually hold, by an identity that is genuinely
  constrained.
- The guardrail that makes that boundary meaningful, in place and exercised.
- Documentation corrected for what this slice ran, and honest about what it did not.

**Non-Goals**

- Prod, Lime, ACR, custom DNS, Entra app registration and app roles — later slices.
- Rewriting `D1`, `D4`, `D6`, `D7`, `D17`. They still reference subscriptions and stay flagged as
  known-stale.
- Deleting the management groups or cleaning the live tenant. Separate change; see Migration.

## Decisions

### One subscription, resource groups as the boundary

```
sub-platform  (the only subscription)
│
├── rg-platform-tfstate-eus        state account, Key Vault, KEK        [exists, P-01]
├── rg-platform-shared         ACR, DNS, policy assignments         [later slices]
│
├── rg-platform-dev-shared     Container Apps environment (dev)
│                                  Log Analytics workspace (dev)
│
├── rg-lemon-dev-shared        SQL logical server, database, DB principal
└── rg-lemon-dev-web           container app, managed identity, Key Vault
```

The shared *plane* is per environment and platform-owned; the shared *data* group stays per
application-environment.

### One Container Apps environment per environment; one SQL server per application-environment

Both cost effectively nothing — SQL logical servers are free, Container Apps environments carry no
fixed charge on the Consumption plan, and the Azure SQL free offer is
[10 free databases per subscription](https://learn.microsoft.com/en-us/azure/azure-sql/database/free-offer?view=azuresql),
not one. The only genuinely finite resource is the Container Apps compute grant — 180,000
vCPU-seconds per **subscription** per month, which no longer multiplies.

They are split differently because the consequences differ. A Container Apps environment is the
heavier object and container apps can reference one across resource groups, so sharing it per
environment is cheap and safe. **A SQL database cannot live in a different resource group from its
logical server**, so a shared per-environment server would force every application's database into a
platform-owned resource group, taking database ownership away from application teams. Per
application-environment servers cost nothing and avoid that.

*Alternative considered:* share one SQL server per environment. Rejected on the ownership
consequence above, not on cost.

### Resource-group names follow the documented convention, and the exception is recorded

`docs/azure-organization.md`'s naming table specifies `rg-<app>-<env>-<component>` with **no region
suffix** (`rg-lime-prod-web`). The one resource group that already exists — `rg-platform-tfstate-eus`,
created by the P-01 bootstrap — carries one. The two disagree, and the disagreement predates this
change.

This slice follows the **documented convention**: `rg-platform-dev-shared`, `rg-lemon-dev-shared`,
`rg-lemon-dev-web`. Renaming a resource group is not possible in Azure — it would mean rebuilding the
group and everything in it, and in this case that is the state backend. So `rg-platform-tfstate-eus`
is grandfathered.

The alternative — adding a region suffix to the convention so the existing name becomes correct —
was rejected because the platform runs in one region by design (`locals.tf`), making the suffix
redundant on every name to legitimise one. Recorded here so the inconsistency reads as a known,
reasoned exception rather than sloppiness.

### Identity and RBAC

Two identities per application-environment, never shared: a user-assigned **managed identity** for
runtime, and a **deploy identity** federated to GitHub OIDC (`D9`).

| Principal | Role | Scope |
| --- | --- | --- |
| lemon-dev deploy identity | Contributor | `rg-lemon-dev-web` |
| lemon-dev deploy identity | Contributor | `rg-lemon-dev-shared` |
| lemon-dev deploy identity | *custom:* Container Apps Environment Joiner | the dev environment resource only |
| lemon-dev runtime identity | Key Vault Secrets User | its own Key Vault only |

The custom role carries exactly one action, `Microsoft.App/managedEnvironments/join/action`. That
permission is required to attach a container app to an environment in another resource group —
without it the deployment fails `LinkedAuthorizationFailed` even with `containerApps/write`
([permissions reference](https://learn.microsoft.com/en-us/azure/role-based-access-control/permissions/containers)).
No built-in role grants join without also granting write, and write on the shared environment would
let one application reconfigure the plane every other application in that environment runs on.

Database access is absent from that table deliberately: it is a **database principal**, not an Azure
role. Contributor on the shared resource group therefore does not imply data access.

Platform-owned resource groups (`rg-platform-*`) carry **no application grants at all**.

### The guardrail

Deny privileged role assignments everywhere, with `not_scopes` carving out the resource groups the
platform vended. Stronger than denying only at subscription scope: grants are refused in any group
the platform did not create, and applications cannot widen the list because they cannot create
groups.

**The intuitive shape does not work.** Conditioning the rule on
`Microsoft.Authorization/roleAssignments/scope` produces a policy that reviews as correct and denies
nothing — the alias exists but never matches. Evidence and the three-way verification are in task
3.5; the trap itself is worth knowing before writing any policy over role assignments.

Genuine deny assignments would be stronger but need Deployment Stacks, a second IaC toolchain
against `D8`. So a subscription Owner can delete the policy; that deletion is alerted, not blocked.

### The resource group is the unit of vending

Creating a resource group requires write at subscription scope — exactly what the guardrail denies to
application identities. So **platform creates application resource groups empty, with role
assignments attached, and the application fills them.** This is the role the subscription used to
play.

```
platform/            → state container: tfstate-platform
  creates  rg-platform-dev-shared, the two Lemon-dev groups,
           the custom role, the deny policy, the alert

apps/lemon/infra/    → state container: tfstate-lemon-dev
  fills    both Lemon-dev groups
```

P-01's five state containers survive untouched — they were always per application-environment, never
per subscription.

**No cross-root state coupling.** The application root resolves resource-group names from the naming
convention and looks up the Container Apps environment by name. Reading platform state from an
application root would give every application read access to the platform's state file.

The deploy identity holds Contributor, which **cannot create role assignments**, so an application
cannot grant itself anything even inside its own groups.

### The slice is applied by the deploy identity, not by a human

Applying the application root with an operator's credentials would prove nothing: a subscription
Owner bypasses every boundary this design is built from. The RBAC model is the deliverable, and the
only way to test it is to run it as the identity that is actually constrained.

## Risks / Trade-offs

- **A subscription Owner can remove the deny policy** → Accepted and recorded. No stronger
  in-subscription control exists without contradicting `D8`.
- **Resource-group isolation is weaker than subscription isolation** → True. `P5` was amended rather
  than left to overclaim; the data and identity layer is still separate objects, not separate names.
- **The Container Apps compute grant no longer multiplies** → One 180,000 vCPU-second pool for the
  whole estate. At the documented scale (~100 users at very light use, or ~5 at light use) with
  scale-to-zero this is expected to suffice; it is a number to watch, not a reason to restructure.
- **Per-environment Log Analytics may change cost** → Unverified. The free ingestion allowance may be
  per workspace or per billing account. Check before prod doubles it.
- **The policy-removal alert may not be testable without removing the policy** → Unverified. If it
  cannot be exercised safely, say so in the task rather than marking it verified.
- **Application teams depend on platform to vend resource groups** → A new coupling, and the direct
  cost of the guardrail. Accepted: it is the same coupling that previously existed for subscriptions,
  at a faster cadence.

## Migration Plan

1. Delete `platform/subscriptions.tf` and `platform/placement.tf` — written for the abandoned shape.
2. Platform root: create the dev shared group, the two Lemon-dev groups, the custom role, the deny
   policy, the alert, and the deploy identity with its federated credential.
3. Application root: container app on a digest-pinned public image, managed identity, Key Vault, SQL
   server, database, database principal.
4. Apply the application root **as the deploy identity**, via the GitHub workflow.
5. Run the verification table below.
6. Correct the documentation this slice exercised.

**Rollback:** everything here is resource-group scoped and rebuildable; no subscription is created or
cancelled, and no state is at risk. This is the first change in the project whose rollback is
genuinely cheap.

**Deliberately not in this change:** `platform/management-groups.tf` and the live management groups.
Removing them makes OpenTofu destroy six groups, and there is an ordering trap — `sub-platform`
currently sits under the `platform` group and the tenant default-management-group setting points at
`sandboxes`; both need unwinding first. That is its own change.

## Verification

The negative checks are the deliverable. A slice where everything succeeds has shown that things
work, not that a boundary exists.

| Check | Expected |
| --- | --- |
| Container app answers on its default FQDN | 200 |
| Deploy identity applies `apps/lemon/infra` | succeeds |
| Deploy identity attempts to create a resource group | **fails** — no subscription-scoped write |
| Deploy identity attempts to create a role assignment | **fails** — Contributor excludes it |
| Deploy identity attempts to write to `rg-platform-dev-shared` | **fails** — no grant on the shared plane |
| Subscription-scoped Contributor assignment attempted | **denied by policy** |
| Both Lemon-dev groups populated; platform groups unchanged | true |
| Cost after one week | at or near zero |

## Documentation updated by this change

Only what the slice exercises:

- `docs/azure-organization.md` — *Subscriptions*, *Management-group hierarchy*, *Inside a
  subscription*, and *Naming* rewritten for the single-subscription layout; the mid-revision banner
  narrowed to what remains stale.
- `docs/adr/D10-observability.md` — "one Log Analytics workspace per subscription" becomes per
  environment. Under one subscription the existing wording would mean one workspace for dev and prod
  together.

Still stale and still flagged: `D1`, `D4`, `D6`, `D7`, `D17`.

## Open Questions

- Does a per-environment Log Analytics workspace change cost? Resolve before the prod slice.
- Can the policy-removal alert be exercised without removing the policy? If not, record it as
  unverified rather than assumed.
