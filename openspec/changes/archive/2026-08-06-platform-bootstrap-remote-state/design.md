## Context

The repository is greenfield: `platform/` contains a README and nothing else. Two things must exist
before any OpenTofu in this repo can run at all — a state backend, and a management-group tree to
place scopes under. Both are described in prose in `docs/azure-organization.md` ("Platform bootstrap
and ownership split") and constrained by `D8`; neither exists as code.

The binding constraints, in the order they force decisions:

- `D8` — OpenTofu + `azurerm`, remote state in Azure Storage in `sub-platform`, **Entra/OIDC auth, no
  access keys**, one container per application-environment, native state **and plan** encryption with
  `enforced = true`, guardrails via Azure Policy and resource locks (never Deployment Stacks).
- `P3` — no standing credentials. `P4` — reproducible from source. `P0` — stay inside Microsoft 365 /
  Azure / GitHub / Entra. `P9`/`P10` — managed, default, GA only. `P1` — the whole thing is close to
  free.
- `AGENTS.md` — the repository is published. No real tenant, subscription, organization, or account
  name may be committed.

The last constraint is sharper here than anywhere else in the backlog: a backend block is exactly
where real identifiers normally get hard-coded.

## Goals / Non-Goals

**Goals:**

- One documented, idempotent, hand-run bootstrap that creates the smallest set of resources that
  cannot create themselves, and nothing more.
- `platform/` is a working OpenTofu root: `tofu init && tofu plan` against remote state, zero drift.
- The management-group tree from `docs/azure-organization.md` exists as code, with `sandboxes` as the
  tenant's default management group for new subscriptions.
- The committed configuration contains **no** real identifier — a reader clones the repo, supplies
  their own values out-of-band, and it works.

**Non-Goals:**

- Subscriptions and their vending (**P-02**) — this change builds the tree, not its contents.
- CI identities, OIDC federation, and per-container RBAC assignments (**P-06**). Containers get
  created here; who may read each one is granted there.
- The PR `fmt`/`validate`/scan/`plan` workflow and the nightly drift job (`D8`) — both need P-06's
  identities. This change makes the checks *runnable locally*; wiring them into GitHub is M2.
- Azure Policy assignments on the hierarchy. The tree is the place policy will sit; putting policy
  there is separate work.
- Private endpoints or network restriction on the state account (see Decisions).

## Decisions

### 1. The bootstrap creates four things, by `az` CLI, and stops

Hand-created: the resource group `rg-platform-tfstate-<region>`, the storage account, the
**platform's own** state container, and a Key Vault holding the state-encryption key. Everything
else — the remaining containers, the resource lock, the management-group tree — is OpenTofu.

*Why these four:* each is required by `tofu init` itself. The Key Vault is in the set only because
`enforced = true` encryption means OpenTofu cannot write its first byte of state without a
key-encryption key to wrap it with (see §5).

*Why `az` CLI and not a second OpenTofu root with local state:* a local-state root is still state —
it has to be committed or lost, and a committed state file is exactly the credential-leak surface
this repo must not have. A shell script that is safe to re-run has no state at all.

*Alternative considered:* Terraform Cloud / a hosted state backend. Rejected on `P0` (outside the
approved tooling) and `P1`.

### 2. Idempotence by existence check, not by `--force`

Every step is "does it exist → if not, create it", so a partial failure is repaired by re-running.
The script is `set -euo pipefail`, prints what it did and what it skipped, and ends by printing the
`backend.hcl` values the operator needs. It never deletes or reconfigures an existing resource —
reconfiguration is OpenTofu's job once the account is adopted.

### 3. The backend block is partial; identifiers arrive via `-backend-config`

`platform/backend.tf` commits only the non-identifying half:

```hcl
terraform {
  backend "azurerm" {
    container_name   = "tfstate-platform"
    key              = "platform.tfstate"
    use_azuread_auth = true
  }
}
```

`storage_account_name`, `resource_group_name`, `subscription_id`, and `tenant_id` come from a
git-ignored `platform/backend.hcl`, with `platform/backend.hcl.example` committed as placeholders.
Initialization is `tofu init -backend-config=backend.hcl`.

*Why:* it is the only way to satisfy "reproducible from source" and "no real identifier in a public
repo" at once. It also makes the repo genuinely reusable — a reader supplies their own tenant.

*Alternative considered:* commit zero-GUIDs and have readers edit `backend.tf`. Rejected: an edited
tracked file shows up in every diff and will eventually be committed for real.

### 4. `use_azuread_auth = true` everywhere, and shared keys are switched off at the account

The account is created with `allowSharedKeyAccess = false`, so key-based access is impossible rather
than merely unused (`P3`, `D8`). Consequently the `azurerm` provider is configured with
`storage_use_azuread = true`; without it, provider operations against the account fail in a way that
reads like a permissions bug. Locally this resolves to the signed-in developer (`D2`'s
"`Active Directory Default`"); in CI it will resolve to the federated identity from P-06.

### 5. State encryption: `azure_vault` key provider + `aes_gcm`, `enforced = true`

OpenTofu's GA key providers are `pbkdf2`, `aws_kms`, `gcp_kms`, `azure_vault`, and `openbao` (plus an
experimental `external`). `azure_vault` wraps the data-encryption key with a key held in Azure Key
Vault and **always authenticates with Entra ID**, which makes it the only option that satisfies `P3`
outright — there is no passphrase, so there is no stored secret to fetch, export, or leak:

```hcl
key_provider "azure_vault" "state" {
  vault_uri      = var.state_key_vault_uri
  vault_key_name = "tofu-state-kek"
  key_length     = 32
}
```

`aws_kms`/`gcp_kms` are the wrong cloud, `openbao` is outside `P0`, `external` is experimental
(`P10`), and `pbkdf2` means a passphrase — a stored secret, which `D2` would then push into a Key
Vault anyway, arriving at a worse version of the same thing.

**Asymmetric RSA in a standard vault, not symmetric AES.** `azure_vault` supports symmetric AES keys
only in Managed HSM, whose floor is a four-figure monthly bill — untenable against `P1`. An RSA key
in a standard Key Vault (RSA-OAEP-256 wrapping an AES-GCM data key) costs cents and is the
`P9`-boring choice.

`state` and `plan` both set `enforced = true`, so a misconfigured run fails instead of quietly
writing plaintext. Access to the key is Azure RBAC on the vault — **Key Vault Crypto User** is
enough to unwrap, and is what P-06's apply identities will receive.

*Trade-off accepted:* anyone holding Crypto User on the key can decrypt state. That is by design the
same population as those who can read the state blob, so the encryption is doing what `D8` says it
is for — protecting data at rest from someone who obtains the storage, not from someone with access.

### 6. The state account is adopted with `import` blocks that stay in the repository

The four hand-created resources are described in `platform/` and adopted with declarative `import`
blocks rather than one-off `tofu import` commands. The blocks are kept, not deleted after first
apply.

*Why keep them:* `import` blocks are no-ops once state contains the resource, and keeping them means
the documented path from "empty tenant" to "clean plan" is entirely in source (`P4`) instead of
half-in-source and half-in-a-README-someone-followed-once. The identifiers they reference come from
variables, so nothing real is committed.

This is the one sanctioned exception to `D8`'s "prefer rebuilding hand-built resources over
importing them" — rebuilding the account would destroy the state it holds, which is precisely the
"a rebuild would lose data" carve-out that record already allows.

**Amended during implementation — the key is read, not imported.** Four of the five bootstrapped
resources are adopted by `import` blocks; the key-encryption key is not. A Key Vault key's resource
ID includes its *version*, which is not knowable when the configuration is written, and pinning one
would break on any rotation. The key is therefore referenced by a `data` source that asserts its
existence and fails the plan loudly if it is missing. Its attributes (RSA 3072, `wrapKey`/`unwrapKey`)
are set by the bootstrap and documented in `platform/README.md` rather than enforced in code — the
one place in this change where a property is not reproducible from source.

### 7. Deletion protection is a `CanNotDelete` lock on the resource group

`D8` names Azure Policy and resource locks as the guardrails and rules out Deployment Stacks. A
`CanNotDelete` lock on `rg-platform-tfstate-<region>` covers the account and its blobs. Recovery of
individual blobs is blob versioning plus 30-day blob and container soft delete.

### 8. Containers, not key prefixes, per application-environment

Five containers: `tfstate-platform`, `tfstate-lemon-dev`, `tfstate-lemon-prod`, `tfstate-lime-dev`,
`tfstate-lime-prod`. A container is the smallest scope Azure RBAC can be assigned at, so
"one container per application-environment" is what makes `P6` mechanically true later — prefixes
within one container cannot be separated by role assignment. P-06 grants **Storage Blob Data
Contributor** on exactly one container per apply identity.

### 9. Naming, given the storage-account character set

`docs/azure-organization.md` gives `<type>-<app>-<env>-<region>`, which storage accounts cannot use
(3–24 chars, lowercase alphanumeric, globally unique). The de-hyphenated form plus a short random
suffix — `stplatformtfstate<suffix>` — keeps the convention legible while satisfying the constraint
and the global-uniqueness requirement. The suffix is generated once by the bootstrap and recorded in
the operator's `backend.hcl`; it never enters the repository. Everything else follows the documented
pattern: `rg-platform-tfstate-<region>`, `kv-platform-tfstate-<region>`.

### 10. The default-management-group setting uses `azapi`

`azurerm` has no resource for tenant management-group settings, so
`Microsoft.Management/managementGroups/settings` is set through the `azapi` provider (pinned), which
is the Microsoft-supported escape hatch for exactly this. The alternative — a one-line manual portal
step — would be the second hand-made thing in a change whose whole point is that there is only one.

**Confirmed against a live tenant.** The `azapi` resource is correct — it issues a valid PUT to
`/providers/Microsoft.Management/managementGroups/<tenant>/settings/default`. What it needs is a
role nobody expects: **Hierarchy Settings Administrator**, the only built-in role carrying
`Microsoft.Management/managementGroups/settings/write`. Management Group Contributor does not carry
it, and neither does the portal's "Access management for Azure resources" elevation, which grants
`Microsoft.Authorization/*` — a different provider namespace entirely. The documented fallback (a
manual step plus a bootstrap warning) is therefore not needed.

### 11. Public network access stays on

No private endpoint, no IP allow-list on the state account. `P2` — access is decided by who you are,
not where you connect from, and network controls are a second layer, never a substitute for
authorization — and a private endpoint plus its DNS is real monthly cost against `P1` for a second
layer that shared-key-disabled Entra auth already carries. Revisit if a compliance requirement
appears; the resource attribute is one line.

### 12. Versions are pinned, and only GA features are used

`required_version` pins OpenTofu — at a release that includes the `azure_vault` key provider, which
is a hard floor, not a preference. `azurerm` and `azapi` are pinned with `~>`. `.tofu-version` records
the version for humans and for M2's pipeline. State/plan encryption and every key provider used here
are GA; the `external` key provider is experimental and is not used (`P10`).

## Risks / Trade-offs

- **The `azapi` default-management-group resource may not behave as expected** → the task list
  verifies it against a real tenant before the change is archived; the documented fallback (manual
  step + bootstrap warning) preserves the requirement without blocking P-02.
- **A reader clones the repo and finds it does not run out of the box** — `backend.hcl` is
  deliberately absent → `platform/README.md` leads with the bootstrap, and `backend.hcl.example`
  names every value; the script prints the file's contents ready to paste.
- **The key-encryption key is a single point of loss: destroy it and every state file is unreadable**
  → the vault has soft delete and **purge protection** enabled (purge protection is irreversible once
  on, which is the point), and `platform/README.md` states plainly that the vault is a tier-0 asset.
- **Key rotation is not free.** Rotating the KEK means re-encrypting existing state, not just
  creating a new key version → out of scope here; the `encrypted_metadata_alias` option is set from
  the start so the provider can be renamed later without breaking decryption, and rotation gets its
  own change when a policy demands it.
- **Bootstrap requires elevated, temporary permissions** (Management Group Contributor at the tenant
  root, Owner on `sub-platform`) → documented as a prerequisite with the expectation that it is held
  for the bootstrap and then relinquished; nothing in steady-state operation needs tenant-root rights.
- **Import blocks kept in the repository are unusual** and may read as leftover scaffolding → a
  comment in the file states why they are there, pointing at this decision.
- **The management-group tree is created before any subscription exists**, so nothing exercises it
  until P-02 → accepted; the alternative is building the tree and the subscriptions in one
  unreviewable change.

## Migration Plan

There is nothing to migrate — this is the first infrastructure in the repository. The deployment
sequence is:

1. Operator obtains the temporary permissions and runs `platform/bootstrap/bootstrap.sh`.
2. Operator writes the printed values into `platform/backend.hcl` (git-ignored).
3. `tofu init -backend-config=backend.hcl`, then `tofu plan`, then `tofu apply` — the first apply
   adopts the four bootstrapped resources and creates the remaining containers, the lock, and the
   management-group tree.
4. `tofu plan` again: it must report zero changes. That is the change's done-when.

**Rollback.** Before the first apply, rollback is deleting the resource group and management groups
by hand (nothing depends on them yet). After it, rollback is the same plus removing the lock first —
and remains cheap only until P-02 puts subscriptions under the hierarchy, which is the point at
which this becomes load-bearing.

## Open Questions

- **Region.** Everything here is regional (`<region>` in the names) and nothing else in `docs/` pins
  one. Implementation picks a single region for the platform, records it in `platform/README.md`, and
  it becomes the default for later platform work unless a record says otherwise.
- **Does `docs/` need amending?** `docs/azure-organization.md` says the bootstrap creates "the state
  storage account"; this change adds a Key Vault to that set, for a reason (`D8`'s enforced
  encryption) that record does not currently mention. Per `AGENTS.md`, if building reveals the
  playbook is silent, `docs/` gets fixed in the same change — the task list includes that edit.
