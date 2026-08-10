## 1. Billing scope and destroy guards

- [x] 1.1 Add `billing_account_name`, `billing_profile_name`, and `invoice_section_name` variables to
      `platform/variables.tf`, with validation and no real defaults
- [x] 1.2 Add placeholder values for all three to `platform/terraform.tfvars.example`
- [x] 1.3 Add the real values to git-ignored `platform/terraform.tfvars` (human-supplied; from
      `az billing account list` / `profile list` / `invoice section list`)
- [x] 1.4 Add `subscription { prevent_cancellation_on_destroy = true }` to the `features` block of the
      `azurerm` provider in `platform/versions.tf`. Comment it as the **primary** cancellation guard,
      recording that it is the only one that survives a resource block being deleted
- [x] 1.5 Run `tofu plan` and confirm it is still clean — no changes from the variable and features
      additions alone
- [x] 1.6 **Measured:** `DevTest` workload is refused on this Individual MCA —
      `InvalidSku: Can't create DevTest Azure plans for individual billing account`. Confirms the
      `workload = "Production"` decision empirically rather than by argument. Recorded in `design.md`
- [x] 1.7 **Measured:** subscription creation is throttled hard. Three attempts returned
      `TooManyRequests: Subscription is not created`, including two spaced apart, and a *failed*
      attempt appears to count against the limit. `az account alias list` confirmed nothing was
      created by any of them. Recorded in `design.md`; section 2 is planned around it

      **Consequence — the guard probe moved to 4.6.** The original plan proved
      `prevent_cancellation_on_destroy` on a throwaway subscription *before* building on it. That
      reasoning assumed creation was cheap. It is not: creation attempts are the scarcest resource in
      this change, and spending one plus a burned subscription ID on a throwaway ahead of the three
      subscriptions actually needed is the wrong trade. The test still happens, against a real
      subscription, at 4.6

## 2. Vend the subscriptions

- [x] 2.1 Add `platform/subscriptions.tf` with an `azurerm_billing_mca_account_scope` data source
      composing the billing scope from the three variables
- [x] 2.2 Add `azurerm_subscription` resources for the four application-environments, keyed off
      `var.application_environments`, with `subscription_name` = alias = `sub-<app>-<env>` and
      `workload = "Production"`
- [x] 2.3 Add `lifecycle { prevent_destroy = true }` to the subscription resources, with a comment
      stating plainly that it does **not** survive deletion of the block and that 1.4 is what covers
      that case
- [x] 2.4 Add an import block for the already-existing `sub-lemon-dev` at
      `/providers/Microsoft.Subscription/aliases/sub-lemon-dev`, following the retain-the-block
      convention documented in `platform/imports.tf`. The `to` address MUST name the `for_each`
      instance — `azurerm_subscription.app["lemon-dev"]`, not the bare resource address, which is an
      error against a `for_each`'d resource
- [x] 2.5 **Done, and it caught a real defect.** The first plan reported
      `1 to import, 4 to add, 0 to change, 1 to destroy` — it wanted to **replace** (cancel and
      re-vend) `sub-lemon-dev`, because the alias API returns neither `workload` nor `billingScope`
      and `workload` is force-new. `prevent_destroy` refused the plan rather than letting it through.
      Fixed with `ignore_changes = [workload, billing_scope_id]`; `billing_scope_id` alone would not
      have been enough. Final plan: `1 to import, 3 to add, 0 to change, 0 to destroy`
- [ ] 2.6 Vend the three remaining subscriptions. **Attempt 1 (concurrent) partially failed** and is
      worth recording in full, because it demonstrates the failure mode this task is designed around:

      The saved plan was applied *without* `-parallelism=1` — a plan file does not carry that flag,
      and it was lost when the interactive apply was replaced with a plan-file apply. All three
      creates therefore ran concurrently. Result: `sub-lemon-prod` completed in **2m13s**, while
      `sub-lime-dev` and `sub-lime-prod` hung for the full **30-minute** timeout and failed with
      `context deadline exceeded`, never registering an alias server-side.

      **Attempt 2 falsified the obvious explanation.** One fast success and two indefinite hangs
      looks like contention, so `sub-lime-dev` was retried alone — `-parallelism=1`, single
      `-target`, nothing else in flight. It hung identically for the full 30 minutes. Concurrency was
      **not** the cause.

      What fits the evidence is a creation quota on this Individual MCA, not a per-request rate
      limit: `sub-lemon-dev` created, then three explicit
      `TooManyRequests: Subscription is not created`, then `sub-lemon-prod` created in 2m13s, then
      nothing but silent 30-minute hangs. Successes are rationed, and once the budget is spent the
      API stops erroring cleanly and simply hangs — the same limit wearing a worse disguise. Billing
      was ruled out: profile `Active`, spending limit `Off`, Azure Plan enabled.

      **So the lever is time, not flags.** Space creates by hours and vend one at a time. Serializing
      with `-target` is still worth doing — a `-parallelism` flag silently disappears when an
      interactive apply is swapped for a plan-file apply, which is how attempt 1 went concurrent —
      but treat it as hygiene, not as the fix. Record how many attempts each subscription took
- [x] 2.7 **Ran after the attempt-1 partial failure; result was clean.** `az account alias list`
      showed exactly `sub-lemon-dev` and `sub-lemon-prod`; `tofu state list` showed the same two.
      Tenant and state agreed, so no import was needed and a plain retry was safe. The timeout fired
      before Azure created anything — the benign shape. Checking is still what distinguishes that
      from the dangerous shape; the check is the point, not the result.

      Procedure, retained for the next partial failure:
      Ordinarily a re-run is safe: OpenTofu records each instance as it completes, so `for_each`
      retries only the missing ones. The dangerous case is an alias that exists in the **tenant** but
      not in **state** — plausible here because alias creation is asynchronous, so a create that times
      out client-side can still succeed in Azure. A plain retry then tries to create an alias that
      already exists.
      So: run `az account alias list` and compare against `tofu state list` before re-applying. Import
      any alias present in the tenant but absent from state, then re-plan and confirm it proposes only
      the genuinely missing subscriptions
- [ ] 2.8 Verify with `az account list --refresh` that all four subscriptions exist and are `Enabled`

## 3. Place every subscription

- [x] 3.1 Add `azurerm_management_group_subscription_association` resources for the four application
      subscriptions, resolving the target from `local.subscription_placement.application_dev` /
      `application_prod` rather than naming `corp` directly.
      **`subscription_id` must be the subscription resource path, not the alias ID**:
      `"/subscriptions/${azurerm_subscription.app[each.key].subscription_id}"`. Using
      `azurerm_subscription.app[each.key].id` is wrong — that attribute is the *alias* resource ID
      (`/providers/Microsoft.Subscription/aliases/...`), while this argument expects
      `/subscriptions/<guid>`
- [x] 3.2 Add an association placing `sub-platform` under `platform`, resolved from
      `local.subscription_placement.platform`, with
      `subscription_id = "/subscriptions/${var.platform_subscription_id}"`
- [x] 3.3 Confirm no management group in `platform/management-groups.tf` sets `subscription_ids`
- [ ] 3.4 Run `tofu plan`, confirm five association creates and zero destroys, then hand the apply to
      the human

## 4. Verify against the tenant, not against the plan

- [ ] 4.1 Run `az account management-group entities list` and confirm all four application
      subscriptions have `corp` as parent
- [ ] 4.2 Confirm `sub-lemon-dev` is no longer a child of `sandboxes`
- [ ] 4.3 Confirm `sub-platform` has `platform` as parent and is no longer a direct child of the
      Tenant Root Group
- [ ] 4.4 Confirm no subscription in the tenant is a direct child of the Tenant Root Group
- [ ] 4.5 Verify the destroy guard with the resource block **left in place**: run
      `tofu plan -replace='azurerm_subscription.app["lime-dev"]'` and confirm the plan **fails** with
      `prevent_destroy set, but the plan calls for it to be destroyed`. Record the observed error.
      Do NOT verify by commenting the resource out — that deletes the guard along with the block and
      plans a silent destroy, which was measured on OpenTofu 1.12.5 and is why 1.4 exists
- [ ] 4.6 **Prove the primary cancellation guard, against a real subscription.** Note the two guards
      collide here by design: `prevent_destroy` (2.3) will refuse this destroy, which is 4.5's whole
      point. So the procedure is deliberate and must be followed in order:
      1. Confirm 4.5 has already passed, so the secondary guard is known good.
      2. Temporarily set `prevent_destroy = false` on the subscription resource — and **only** that.
         `prevent_cancellation_on_destroy` (1.4) stays `true`; it is what is under test.
      3. Run `tofu destroy -target='azurerm_subscription.app["lime-prod"]'` — `sub-lime-prod`, the
         least depended-on subscription.
      4. Restore `prevent_destroy = true` immediately afterwards, pass or fail.
      Expected: the alias disappears, `az account list --refresh` still reports the subscription
      `Enabled`. Then re-add it via the import block and confirm a clean plan.
      **If instead the subscription goes to `Disabled`/`Warned`, the guard is fiction:** the design's
      guard ordering is wrong and must be rewritten, and that subscription needs re-vending against a
      throttled API. Record the observed result verbatim either way — a negative here is the most
      valuable single output of this change
- [ ] 4.7 Confirm the platform state backend is still readable and writable after `sub-platform`
      moved management group: run `tofu plan` and confirm it reaches the backend and reports clean,
      rather than inferring backend health from the absence of errors elsewhere
- [ ] 4.8 Confirm each new subscription contains no resources
      (`az resource list --subscription <id>` returns empty), substantiating the `P1` cost claim by
      observation rather than assertion
- [ ] 4.9 Confirm vending granted no access: run
      `az role assignment list --scope /subscriptions/<id>` for each new subscription and confirm
      nothing was created by this change. This is the only check for the spec's "no access is granted
      by vending" scenario — without it that requirement is asserted, not verified
- [ ] 4.10 Re-run `tofu plan` and confirm it is clean

## 5. Documentation and de-identification

- [ ] 5.1 Update `docs/azure-organization.md` to record that placement is a **separate managed step**
      applied after vending, so a freshly created subscription sits in the default management group
      until it runs. Do NOT restate that the default group is `sandboxes` — line 39 already says that,
      and duplicating it is the failure mode this task exists to avoid
- [ ] 5.2 Grep the full diff for leaked tenant, billing, subscription, or organization identifiers
      before anything is staged
- [ ] 5.3 Confirm `platform/terraform.tfvars` and `platform/backend.hcl` are still untracked
- [ ] 5.4 Tick `P-02` in `BACKLOG.md`
