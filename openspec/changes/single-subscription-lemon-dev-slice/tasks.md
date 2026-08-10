## 1. Clear the abandoned shape out of the way

- [x] 1.1 Delete `platform/subscriptions.tf` and `platform/placement.tf`, and add `platform/removed.tf`
      forgetting what they created — `removed` blocks with `lifecycle { destroy = false }`.

      **Deleting the files alone would have been wrong**, and in a way this project already measured:
      `prevent_destroy` does not survive deletion of the block it is written in, so removing the
      resource definitions plans a **silent destroy** of two real subscriptions. Destroy here means
      *cancel*, and a cancelled subscription ID is never reusable. Forgetting also preserves
      `sub-platform`'s placement under the `platform` management group, which destroying the
      association would have undone — re-introducing drift this repository just fixed.
      Verified: `Plan: 0 to add, 0 to change, 0 to destroy, 3 to forget.`
- [x] 1.2 Confirm `platform/management-groups.tf` is **untouched** — removing it destroys six live
      management groups and has an ordering dependency (the platform subscription sits under one, the
      tenant default-management-group setting points at another). Separate change
- [x] 1.3 Run `tofu plan` and read it: expect **`to forget`, never `to destroy`**. Any `destroy` line
      against a subscription or an association means a `removed` block is missing or its
      `destroy = false` was dropped — stop and fix the configuration rather than applying.
      Do **not** expect `prevent_destroy` to catch this: it is gone along with the resource blocks,
      which is precisely why the `removed` blocks exist
- [x] 1.4 Hand the apply to the human, then confirm the plan is clean and that both subscriptions and
      the `sub-platform` placement still exist in the tenant

## 2. Platform: the shared plane

- [x] 2.1 Add `rg-platform-dev-shared` per the documented naming convention (no region suffix; see
      design.md for why `rg-platform-tfstate-eus` is grandfathered)
- [x] 2.2 Add the dev Container Apps environment (Consumption; no workload profiles, so no fixed charge)
- [x] 2.3 Add the dev Log Analytics workspace and wire the Container Apps environment to it
- [x] 2.4 Plan, read for unexpected destroys, hand the apply to the human

## 3. Platform: the guardrail

- [x] 3.1 Add the custom role definition carrying exactly one action,
      `Microsoft.App/managedEnvironments/join/action`, scoped to the subscription as its assignable
      scope
- [x] 3.2 Add the Azure Policy definition and assignment denying subscription-scoped assignment of
      Owner, Contributor, and User Access Administrator
- [x] 3.3 Add the alert that fires when that policy assignment is deleted or exempted
- [x] 3.4 Plan and hand the apply to the human
- [x] 3.5 **Now VERIFIED WORKING — after first being verified failing.** Attempted `Contributor` at subscription
      scope for the Lemon dev runtime identity. It **succeeded**. No policy denial, no error; the
      assignment was created and had to be deleted by hand.

      Evidence gathered:
      - The stored policy rule matches the created assignment field for field: `type`,
        `roleDefinitionId` (identical string), and `scope` (identical string).
      - `enforcementMode: Default`, `notScopes: null` — nothing exempting it.
      - Policy assignment created 21:43:15Z, test ran 22:25:15Z — **42 minutes**, beyond the
        documented ~30-minute propagation window. Propagation is not a sufficient explanation.

      Two candidate causes, not yet distinguished:
      1. `Microsoft.Authorization/roleAssignments/scope` appears in the provider alias list but is not
         evaluatable in a condition, so the third clause never matches and `allOf` never fires. The
         Azure/azure-policy issue requesting this field was closed in 2018 with no recorded resolution.
      2. Azure Policy does not enforce `deny` on role-assignment creation at all, in which case no rule
         shape works and the mechanism must be replaced rather than fixed.

      Distinguishing test: assign a deliberately broad variant with the `scope` clause removed and
      attempt a resource-group-scoped assignment. Denial implicates the field; no denial implicates
      the mechanism. Costs a propagation wait and temporarily blocks legitimate assignments.

      **RESOLVED by diagnostic (23:24:39Z).** The same rule with the `scope` clause removed **did
      deny** a resource-group-scoped assignment. So Azure Policy evaluates role assignments and
      enforces `deny` correctly — cause 1 is confirmed and cause 2 is ruled out. The
      `Microsoft.Authorization/roleAssignments/scope` alias appears in the provider's alias list but
      never matches; any condition built on it silently does nothing.

      **Guardrail rebuilt without it.** The rule now denies privileged assignments everywhere, and the
      assignment carries `not_scopes` listing the resource groups the platform vended. That is
      stronger than the original intent: privileged grants are refused at subscription scope *and* in
      any resource group the platform did not create. The list stays closed because an application
      cannot create a resource group.

      **Re-tested 01:35:32Z, three attempts, all as expected:**
      - subscription scope → **DENIED**
      - `rg-lemon-dev-web` (vended, in `not_scopes`) → **ALLOWED**
      - `rg-platform-tfstate-eus` (real group, deliberately not vended) → **DENIED**

      Three rather than one on purpose. A deny at subscription scope proves the policy fires but not
      that it fires *narrowly* — a policy blocking everything looks identical from that single test
      and would break every deploy identity in the platform. The second rules that out; the third
      proves `not_scopes` is doing the work rather than the policy being inert in some new way.

      The whole episode is the argument for the task's original wording: the first implementation
      looked correct, reviewed correct, and did nothing
- [x] 3.6 **VERIFIED end to end, incidentally.** Deleting the diagnostic policy assignment at
      23:24:41Z produced exactly the operation the tamper alert watches —
      `Microsoft.Authorization/policyAssignments/delete`, status `Succeeded`, confirmed present in the
      activity log. So the alert's trigger condition occurred under normal use without removing the
      real guardrail, which answers the question the task asked: it *can* be exercised safely.

      **Delivery confirmed:** `"Azure Monitor alert 'alert-guardrail-tampered' was activated for
      'DIAGNOSTIC-any-scope' at August 9, 2026 23:24 UTC"`, received ~3 minutes after the event. Event
      → rule match → delivery, all three links observed rather than inferred.

      **Flaw found in the sibling alert while confirming this.** `scopes` on an activity-log alert is
      the scope being *monitored*, not a filter on the role assignment's own scope — so the
      role-assignment alert fires on every assignment written anywhere in the subscription, including
      the resource-group-scoped ones the platform makes legitimately. No criteria field can express
      "only assignments whose scope is the subscription": the same gap that broke the policy, in a
      different service. Renamed to `alert-role-assignment-written` so the name matches the behaviour

## 4. Platform: vend the Lemon dev resource groups and identities

- [x] 4.1 Create `rg-lemon-dev-shared` and `rg-lemon-dev-web`, empty
- [x] 4.2 Create the Lemon dev deploy identity with its GitHub OIDC federated credential, scoped to the
      `dev` environment (`D9`)
- [x] 4.3 Assign Contributor to the deploy identity on **each of the two Lemon groups only**
- [x] 4.4 Assign the custom join role to the deploy identity on the **dev Container Apps environment
      resource** — not the resource group, not the subscription
- [x] 4.5 Confirm no application principal holds a role on any `rg-platform-*` **resource group**.
      The deploy identity does hold the single-action join role on the Container Apps environment,
      which *lives inside* `rg-platform-dev-shared` — scoped to that one resource, deliberately not to
      the group. Group scope would grant read and join across everything the platform later puts
      there. Verified in `vending.tf`: the only two `scope` arguments are an application resource
      group and the environment resource
- [x] 4.6 Plan and hand the apply to the human

## 5. Application: Lemon dev

- [x] 5.1 Create `apps/lemon/infra/` with its own backend config pointing at the `tfstate-lemon-dev`
      container
- [x] 5.2 Resolve the resource groups and the shared Container Apps environment by **name, via data
      sources**. No remote-state data source pointing at platform state
- [ ] 5.3 **REOPENED — marked done for work that was not done.** The server and database exist; the
      **database principal does not**. `main.tf` creates no contained user, so the runtime identity has
      no path to the database and the container app receives a `SQL_SERVER_FQDN` it cannot
      authenticate against. The comment claiming the Entra admin exists "so the pipeline can create
      database users" describes an intention, not code.
      Also missing: no `azurerm_mssql_firewall_rule`, so with `public_network_access_enabled = true`
      and an empty rule set **nothing** can reach the server — not the container app, not CI. Task 6.1
      would have surfaced this; the review found it first
- [x] 5.4 **Moved to the platform root — the original task was impossible.** It asked the application
      to grant its own runtime identity access to its own Key Vault, but the deploy identity holds
      Contributor, which cannot create role assignments. That is requirement 4 of
      `application-scaffolding` working as intended, not a gap.
      The vending boundary is now explicit: *the platform creates anything requiring a role
      assignment; the application creates everything else.* Runtime identity and Key Vault are vended
      into the platform's resource group — if they sat in the application's, its Contributor could add
      federated credentials to the identity or switch the vault out of RBAC and self-grant. The
      application gets `Managed Identity Operator` on the identity and `Key Vault Secrets Officer` on
      the vault, both **resource-scoped**; the runtime identity gets `Key Vault Secrets User`
- [x] 5.5 Add the container app in `rg-lemon-dev-web`, referencing the shared environment by fully
      qualified ID, running a **digest-pinned public image** — pinning by digest exercises `D9` even
      without a registry
- [x] 5.6 Add `.github/workflows/lemon.yml` applying this root as the deploy identity, triggered by its
      own path (`D9`)

## 6. Verify — as the deploy identity, and expect the failures

The negative checks are the deliverable. Everything succeeding proves the platform works, not that a
boundary exists. Run all of these **as the deploy identity**, never as an operator: a subscription
Owner bypasses every boundary under test.

- [ ] 6.1 The workflow applies `apps/lemon/infra` successfully
- [ ] 6.2 The container app answers 200 on its default Container Apps FQDN
- [ ] 6.3 **FAIL expected** — deploy identity attempts to create a resource group. Record the error
- [ ] 6.4 **FAIL expected** — deploy identity attempts to create a role assignment inside its own
      resource group. Record the error
- [ ] 6.5 **FAIL expected** — deploy identity attempts to write to `rg-platform-dev-shared`. Record the
      error
- [ ] 6.6 Confirm both Lemon groups are populated and no `rg-platform-*` group changed
- [ ] 6.7 Record actual cost after a week and compare against `P1`. Report the number, not "as expected"

## 7. Documentation — only what this slice exercised

- [x] 7.1 Rewrite `docs/azure-organization.md` *Subscriptions*, *Management-group hierarchy*, *Inside a
      subscription*, and *Naming* for the single-subscription layout
- [x] 7.2 Narrow the mid-revision banner in that file to what is **still** stale (`D1`, `D4`, `D6`,
      `D7`, `D17`, and the live tenant), removing what this slice fixed
- [x] 7.3 Correct `docs/adr/D10-observability.md`: "one Log Analytics workspace per subscription"
      becomes per environment — under one subscription the current wording means dev and prod share a
      workspace
- [ ] 7.4 Record the answer to the open question on per-environment Log Analytics cost, or restate it
      as unresolved with what is still unknown
- [x] 7.5 Fold the measured findings from the archived `subscription-vending` change into `docs/` — the
      MCA caps and their silent-hang failure mode, the import-forces-replacement trap, and
      `prevent_destroy` not surviving deletion of its own block. They are currently preserved only in
      an archived proposal
- [x] 7.6 Grep the full diff for leaked tenant, billing, subscription, or organization identifiers.
      Clean against: billing account/profile/invoice-section IDs, all four subscription GUIDs, tenant
      GUID, both identity principal/client IDs, the Key Vault suffix, and the real organization,
      person, and application names from the source playbook. **Re-run before the actual commit** —
      this is a point-in-time check, not a property of the repository
- [x] 7.7 Update `BACKLOG.md` to reflect the single-subscription shape
