# Target Azure organization

How subscriptions, management groups, and resource groups are laid out. (Playbook Section 3, with
the platform bootstrap and ownership split that the ADRs depend on folded in.)

> **⚠ Partially revised.** The single-subscription shape below is current and was built. Still
> stale: `D1`, `D4`, `D6`, `D7`, and `D17` reference subscriptions in ways this document no longer
> supports, and the live tenant still holds six unused management groups and two surplus
> subscriptions. Both are scheduled, not overlooked. `docs/principles.md` is authoritative where
> anything disagrees.

## Residual risk: scope isolation inside one subscription

A subscription boundary cannot be reached across. A resource-group boundary can, by anyone holding a
subscription-scoped role. With one subscription, that difference is the platform's main isolation
weakness, and `P5` points here rather than claiming it away.

**What isolation still holds by construction.** Every application-environment gets its own resource
group, database, database principal, managed identity, and Key Vault, and every environment gets its
own Container Apps environment and SQL logical server. These are separate objects, not separate
names; nothing short of an explicit grant reaches across them. This is the isolation `P5` and `P6`
mostly rest on, and it is unaffected by the loss of the subscription boundary.

**What compensates at the scope layer.** Role assignments are made at resource-group scope, and an
Azure Policy **denies** assignment of **Owner**, **Contributor**, and **User Access Administrator**
everywhere except the resource groups the platform has vended. An activity-log alert fires on any
role assignment written at subscription scope, and on tampering with the policy itself.

The exclusion list is what makes this workable, and it stays closed for a structural reason: an
application cannot create a resource group — that needs write at subscription scope, which this same
policy denies — so it cannot add itself to the list. Any group the platform did not create refuses
privileged grants outright.

**How it was verified.** The first implementation of this control conditioned on
`Microsoft.Authorization/roleAssignments/scope`. It reviewed as correct and did **nothing**: a
subscription-scoped `Contributor` assignment succeeded 42 minutes after the policy went live. That
alias appears in the provider's alias list but never matches. The rebuilt control was then tested
three ways — denied at subscription scope, allowed in a vended group, denied in a real group that was
not vended — because a single deny proves a policy fires without proving it fires narrowly, and a
policy that blocked everything would look identical while breaking every deploy identity in the
platform.

**What remains exposed, and is accepted.** A subscription **Owner** can delete the policy assignment
and then grant themselves any scope. That deletion is alerted, not blocked. Genuine *deny
assignments* — the one mechanism that would stop an Owner — are not directly creatable; only Azure
creates them, via Deployment Stacks, which would mean a second infrastructure-as-code toolchain
alongside OpenTofu and contradict `D8`.

So the guarantee is: **broad grants are prevented, and removing the thing that prevents them is
detected. A determined subscription Owner is not stopped.**

*Revisit when* a second subscription becomes available, an application takes on regulated data, or
the set of people holding subscription Owner grows beyond those known to each other.

## Subscriptions

**One subscription. Permanently.** Every application and every environment lives in it, separated by
resource group rather than by subscription.

**Why, and it is a constraint rather than a preference.** The billing account is a Microsoft Customer
Agreement purchased through Azure.com, which caps subscriptions at **five per billing account** and
**one created per 24 hours**.¹ Four application-environments plus a platform subscription is exactly
five — no room for a sandbox (`D17`) or a Restricted-data subscription (`D6`), and four serialized
days to stand up. Raising the cap needs a support request granted on consumption history. The
decision was to stop paying that cost and design for one.

**What that gives up.** A subscription boundary cannot be reached across; a resource-group boundary
can, by anyone holding a subscription-scoped role. That difference is the platform's main isolation
weakness and is recorded above rather than argued away.

**What it does not give up.** Cost and quota still roll up — by tag and resource group rather than by
subscription. The Azure SQL free offer is **10 databases per subscription**, not one, so four
application-environments would fit — **but the platform does not currently use it**: opting in needs
`useFreeLimit`, which the pinned provider does not expose. Databases are billed today, and the real
figure is measured rather than assumed. Container Apps environments carry no fixed charge and SQL logical
servers are free, so per-environment and per-application-environment separation cost nothing. The one
one finite resource is the Container Apps compute grant — 180,000 vCPU-seconds per subscription
per month — which no longer multiplies across subscriptions and is worth watching.

**If you are reading this for a tenant on a different agreement**, check first: the cap applies to
Microsoft Customer Agreement purchased through Azure.com and to the Microsoft Online Services
Program. An enterprise MCA signed through a Microsoft representative, an Enterprise Agreement, or a
partner agreement do not carry it, and the subscription-per-application-environment shape the earlier
version of this document described is available to you. Determine which with
`az billing account list` — the fields are `agreementType` and `accountType`.

¹ [Message appears when you try to create multiple subscriptions](https://learn.microsoft.com/en-us/azure/cost-management-billing/troubleshoot-subscription/create-subscriptions-deploy-resources)

## Management groups

**None.** The platform uses no management-group hierarchy.

A tree exists to organize many subscriptions and to give policy a ceiling above them. With one
subscription there is nothing to organize, and the subscription is itself the ceiling: policy
assigned there covers everything the platform owns and nothing it does not.

Policy is therefore assigned at subscription scope, and the isolation the hierarchy was going to
express is expressed by resource groups and the roles scoped to them.

## Inside the subscription

Resource groups carry the separation the subscription used to. Three kinds:

```
sub-platform  (the only subscription)
│
├── rg-platform-tfstate-eus      state account, Key Vault, key-encryption key
│
├── rg-platform-dev-shared       PLATFORM-OWNED, per environment:
│                                Container Apps environment, Log Analytics workspace,
│                                each application's runtime identity and Key Vault
│
├── rg-lemon-dev-shared          SQL logical server and its databases
└── rg-lemon-dev-web             container app
```

**The shared plane is per environment and platform-owned.** One Container Apps environment and one
Log Analytics workspace serve every application in that environment. Applications hold no write
access to this group — only a single-action custom role letting them *join* the environment. That is
what keeps dev and prod apart now that both live in one subscription.

**The SQL server is per application-environment, not per environment.** A database cannot live in a
different resource group from its logical server, so a shared server would drag every application's
database into a platform-owned group and take database ownership away from application teams.
Logical servers are free, so there is no reason to share one.

**Databases live in the shared resource group, not the application component's.** Data outlives
compute: an application's resource group must be safe to delete and rebuild, and deleting it must not
take the data with it.

**The platform creates anything that requires a role assignment; the application creates everything
else.** That is why the runtime identity and Key Vault sit in the platform's group rather than the
application's. It follows from applications holding Contributor, which cannot create role
assignments — an application cannot grant its own identity access to its own vault. Putting those
resources in the application's group would also let it add federated credentials to its own identity,
or switch its vault out of role-based access control and self-grant. Applications receive the narrow
rights they need **scoped to the individual resource**, never to the group holding it.

**Applications cannot create resource groups.** Creating one requires write at subscription scope,
which the guardrail denies them. The platform vends resource groups the way it used to vend
subscriptions.

## Naming

| Thing                | Pattern                        | Example                    |
| -------------------- | ------------------------------ | -------------------------- |
| Resource group       | `rg-<app>-<env>-<component>`   | `rg-lime-prod-web`         |
| Platform resource group | `rg-platform-<env>-<component>` | `rg-platform-dev-shared` |
| Resource             | `<type>-<app>-<env>-<region>`  | `ca-lime-prod-eus`, `kv-lime-prod-eus` |

**Every resource-group name carries an environment marker.** There is one subscription, so its name
carries no application or environment; `sub-platform` is the whole convention.

Resource-group names take **no region suffix** — the platform runs in one region by design, so it
would be redundant on every name. `rg-platform-tfstate-eus` predates this rule and cannot be renamed
without rebuilding the state backend it holds. It is grandfathered, and is the only exception.

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

- **Register `Microsoft.App` before anything Container Apps.** A fresh subscription registers almost
  no resource providers, and Container Apps is not among the defaults even when Storage, SQL, Key
  Vault, Managed Identity, and Insights already are. Creating a managed environment then fails
  `409 MissingSubscriptionRegistration`, which at least names the namespace — unlike the storage
  version of the same problem below.
- A **fresh subscription registers almost no resource providers**, and the failure is mislabelled:
  creating a storage account under an unregistered `Microsoft.Storage` returns
  **`SubscriptionNotFound`**, pointing at the one thing that is fine. Register the providers first.
- **Creating a resource does not grant its data plane.** Owner on the subscription confers no blob
  or Key Vault data access; the operator's data-plane roles must be assigned *before* the first
  container or key is created, not after.
- **Role assignments at the Tenant Root Group take minutes to take effect.** A 403 immediately
  after granting a role is usually propagation, not the wrong role — but verify which by checking
  whether the role actually carries the action, since the two look identical.

## Learned the hard way

Measured against a live tenant while building this, and preserved here because each one cost real
time and none is discoverable from the documentation you would naturally read first.

- **Subscription creation is rationed and fails silently.** On a Microsoft Customer Agreement bought
  through Azure.com the limit is one per 24 hours. Exceeding it first returns
  `TooManyRequests: Subscription is not created`, then stops erroring and simply **hangs until the
  client's 30-minute timeout** — which presents as broken tooling rather than a quota.

- **Importing a subscription can propose cancelling it.** `azurerm_subscription` models the *alias*,
  and the alias API returns neither `workload` nor `billingScope`. `workload` is force-new, so an
  imported subscription plans as a **replacement** — cancel and re-create — for a resource whose ID
  can never be reused. `ignore_changes = [workload, billing_scope_id]` fixes it. Generally: *an
  import whose resource has force-new attributes the API cannot return is a cancel-and-recreate
  waiting to happen.*

- **`prevent_destroy` does not survive deletion of its own block.** Measured on OpenTofu 1.12.5:
  with the block present, `-destroy` or `-replace` fails the plan; with the resource **removed from
  configuration**, a destroy is planned silently, because the lifecycle rule went with it. Deleting a
  resource block is the likeliest accident and the one it does not cover. Use `removed` blocks with
  `lifecycle { destroy = false }` to stop managing something without destroying it — the plan then
  reports `to forget` rather than `to destroy`.

- **A vended subscription lands in the tenant default management group**, not where it belongs.
  Placement is always a separate managed step, never a create-time argument — a create-time value is
  never read again, so a later move goes undetected.

- **`Microsoft.Authorization/roleAssignments/scope` appears in the policy alias list but never
  matches.** A deny policy conditioned on it silently does nothing; the same rule without that clause
  denies correctly. Anything built on that field needs testing before it is trusted.

- **GitHub's OIDC subject claim is not `repo:owner/repo:...`.** It qualifies both with numeric IDs —
  `repo:owner@424944/repo@1329211848:environment:dev` — so the claim survives a rename. A federated
  credential built from the plain names is refused with `AADSTS700213: No matching federated identity
  record found`, which reads like a permissions problem rather than a string mismatch. Read the real
  prefix instead of assembling it:
  `gh api repos/OWNER/REPO/actions/oidc/customization/sub --jq .sub_claim_prefix`.

- **`ARM_SUBSCRIPTION_ID` in the environment breaks state encryption.** The `azure_vault` key
  provider is a data-plane call needing only a tenant, but the SDK forwards the subscription as well
  and the credential refuses both: `Please specify only one of subscription and tenant, not both`
  (opentofu/opentofu#3520, upstream). Pass the subscription through the provider block and
  `-backend-config`, never the environment. `backend.hcl.example` records the same error for the
  backend's `tenant_id` — same root cause, opposite field.

- **`DevTest` workload is refused** on an Individual MCA (`InvalidSku`).

- **A saved plan file does not carry `-parallelism`.** The flag lives on the `apply` invocation, so
  swapping an interactive apply for a plan-file apply silently drops it.

**Start-up sequence:** resource providers → state storage account and encryption key → platform
pipeline → onboard an application (`docs/building-an-application.md`) → that application's pipeline
can run.
