## 1. Repository scaffolding

- [x] 1.1 Create `platform/versions.tf`: `required_version` pin for OpenTofu, `azurerm` and `azapi`
      pinned with `~>`, and a `provider "azurerm"` block with `features {}`, `storage_use_azuread = true`,
      and `subscription_id` from a variable (design §4, §12).
- [x] 1.2 Add `platform/.tofu-version` recording the OpenTofu version, matching the `required_version` pin.
- [x] 1.3 Create `platform/variables.tf`: `tenant_id`, `platform_subscription_id`, `location`,
      `state_storage_account_name`, `state_key_vault_name`, `state_key_vault_uri`, plus the
      application-environment list used to generate state containers. No defaults that encode a real
      identifier.
- [x] 1.4 Add `platform/backend.hcl` to `.gitignore` (create `.gitignore` if absent) and verify with
      `git check-ignore platform/backend.hcl`.

## 2. Bootstrap script and its documentation

- [x] 2.1 Write `platform/bootstrap/bootstrap.sh`: `set -euo pipefail`, arguments for subscription and
      region, and existence-check-then-create for the resource group, storage account, the
      `tfstate-platform` container, and the Key Vault (design §1, §2).
- [x] 2.2 Create the storage account with `--allow-shared-key-access false`, `--min-tls-version TLS1_2`,
      `--allow-blob-public-access false`, LRS, and the `stplatformtfstate<suffix>` name with a
      generated suffix (design §4, §9). Satisfies *State backend uses identity, never keys*.
- [x] 2.3 Enable blob versioning and 30-day blob and container soft delete on the account
      (*The state account is durable against accidental loss*).
- [x] 2.4 Create the Key Vault with the **RBAC** permission model (`D2`), soft delete, and purge
      protection enabled (design §5).
- [x] 2.5 **Before creating any key or blob**, grant the running operator the data-plane roles the
      remaining steps depend on — **Storage Blob Data Contributor** on the storage account and **Key
      Vault Crypto Officer** on the vault — and wait for propagation. Creating an RBAC-model resource
      grants the creator control-plane rights only; no data-plane access comes with it, so this must
      precede 2.2's container creation and 2.6. Verify by reading back the role assignments.
- [x] 2.6 Create the RSA key `tofu-state-kek` in the vault, only if a key of that name does not
      already exist. Do **not** create a symmetric key — symmetric requires Managed HSM, which
      breaches `P1` (design §5).
- [x] 2.7 Print a ready-to-paste `backend.hcl` and the vault URI as the script's final output. There
      is no passphrase and no `TF_ENCRYPTION` export — `azure_vault` authenticates with the caller's
      Entra identity.
- [x] 2.8 Verify idempotence: run the script twice against the same subscription; the second run must
      exit 0, report every resource as already existing, and create nothing — including not creating a
      second key version (*Re-run is a no-op*).
- [x] 2.9 Verify partial-failure recovery **without touching live state**. The original form of this
      task — "delete the container, re-run" — is unsafe once the container holds real state; deleting
      it to test a recovery path would destroy the thing being protected. Instead, run the script
      against a **second, disposable subscription or resource group**, interrupt it partway (e.g.
      after the storage account, before the key), and confirm a re-run creates only what is missing.
      Tear that scratch group down afterwards.
      *Verified:* run 1 against `rg-scratch-2p9-eus` with a deliberately invalid `--key-vault` name
      failed after creating the group and storage account; run 2 skipped both and created only the
      five missing resources, reusing the orphaned storage account via its `purpose` tag rather than
      generating a second one. Scratch group deleted. Required adding `--resource-group` to the
      script, which is a real capability, not test scaffolding.
- [x] 2.10 Verify the bootstrap creates nothing beyond the four documented resources: list everything
      in `sub-platform` after a clean run and compare against the set in the spec
      (*Nothing outside the documented set is hand-created*).

## 3. Backend and state encryption

- [x] 3.1 Create `platform/backend.tf` with the partial `backend "azurerm"` block —
      `container_name`, `key`, `use_azuread_auth = true` only (design §3).
- [x] 3.2 Create `platform/backend.hcl.example` with placeholder values for every field the partial
      block omits, and reference it from `platform/README.md`.
- [x] 3.3 Add the `encryption` block to `platform/versions.tf`: `key_provider "azure_vault" "state"`
      with `vault_uri`, `vault_key_name = "tofu-state-kek"`, `key_length = 32`, and
      `encrypted_metadata_alias` set so the provider can be renamed later without breaking decryption;
      `method "aes_gcm"`; and `enforced = true` on **both** `state` and `plan` (design §5). Satisfies
      *State and plan artifacts are encrypted client-side*.
- [x] 3.4 Confirm `required_version` in 1.1 pins an OpenTofu release that includes the `azure_vault`
      key provider, and record the minimum version in `platform/README.md`.
- [x] 3.5 Verify no-secret operation: with no encryption environment variable set and no secret on
      disk, run `tofu plan` as a signed-in operator holding Key Vault Crypto User and confirm it
      succeeds (*No passphrase is required anywhere in the loop*).
- [x] 3.6 Verify enforcement: point the encryption block at a key the caller cannot access (or remove
      the role) and confirm the run fails rather than writing plaintext
      (*Enforced encryption rejects unencrypted state*, *A caller without the key role cannot read state*).
- [x] 3.7 Run `tofu init -backend-config=backend.hcl` as a signed-in operator with no credentials
      configured and confirm it succeeds (*Backend authenticates as the signed-in operator*).

## 4. Adopting the bootstrapped resources

- [x] 4.1 Describe the resource group, storage account, `tfstate-platform` container, Key Vault, and
      the `tofu-state-kek` key in `platform/state.tf`, matching the configuration the bootstrap script
      applied exactly — including the vault's purge protection and RBAC permission model.
- [x] 4.2 Add `platform/imports.tf` with `import` blocks for those resources, plus a header
      comment explaining why the blocks are kept rather than deleted (design §6).
- [x] 4.3 Run `tofu plan` and reconcile every reported difference by correcting the OpenTofu
      description — not by changing the resource — until the plan is empty for these resources.

## 5. State containers and deletion protection

- [x] 5.1 Create the remaining containers from the application-environment variable:
      `tfstate-lemon-dev`, `tfstate-lemon-prod`, `tfstate-lime-dev`, `tfstate-lime-prod`
      (*One state container per application-environment*).
- [x] 5.2 Add a `CanNotDelete` management lock on `rg-platform-tfstate-<region>` (design §7).
      Satisfies *The account cannot be deleted casually*.
- [x] 5.3 Verify the lock: attempt to delete the resource group and confirm the attempt is refused.
- [x] 5.4 Verify soft delete: delete a test blob in `tfstate-platform` and confirm it is listable and
      restorable (*A deleted state blob is recoverable*).
- [x] 5.5 Verify purge protection: attempt to purge the soft-deleted Key Vault (or key) and confirm
      the purge is refused (*The key-encryption key cannot be purged*).

## 6. Management-group hierarchy

- [x] 6.1 Create `platform/management-groups.tf` with `org` parented to the Tenant Root Group and
      children `platform`, `landing-zones`, `sandboxes`, `decommissioned`, plus `corp` under
      `landing-zones` — names exactly as `docs/azure-organization.md` gives them.
- [x] 6.2 Add a comment block, or a `locals` map, recording where each class of subscription belongs
      (`sub-platform` → `platform`; application-environments → `corp`; sandboxes → `sandboxes`;
      retired → `decommissioned`) so P-02 has an unambiguous target
      (*Every class of subscription has a defined home*).
- [x] 6.3 Set the tenant's default management group for new subscriptions to `sandboxes` via the
      `azapi` resource for `Microsoft.Management/managementGroups/settings` (design §10). Satisfies
      *Nothing arrives at the Tenant Root Group by accident*.
- [x] 6.4 Verify 6.3 against a real tenant. If the resource does not behave as expected, implement the
      documented fallback instead: a manual step in `platform/README.md` plus a check in
      `bootstrap.sh` that warns when the setting is wrong — and record the deviation in the design's
      Open Questions.
- [x] 6.5 Grep the configuration to confirm no policy assignment, role assignment, or resource targets
      the Tenant Root Group (*No assignment targets the tenant root*).
- [x] 6.6 Verify drift detection: rename a management group in the portal, confirm `tofu plan` reports
      it, and apply to restore (*A hand-made change is reverted by the next apply*).

## 7. Documentation

- [x] 7.1 Rewrite `platform/README.md`'s bootstrap section into the concrete procedure: prerequisites
      and the temporary permissions required, the script invocation, writing `backend.hcl`, and
      `init` → `plan` → `apply` → `plan` (*Manual bootstrap of the state backend*).
- [x] 7.2 Document in `platform/README.md` what the bootstrap deliberately does **not** create, the
      Key Vault roles a human or pipeline needs to run OpenTofu at all (**Crypto User** to unwrap,
      **Crypto Officer** only to bootstrap), and that the vault is a tier-0 asset — destroy the key
      and every state file is permanently unreadable.
- [x] 7.3 Record the chosen platform region in `platform/README.md` (design Open Questions).
- [x] 7.4 Amend `docs/azure-organization.md` so the bootstrap set includes the state-encryption Key
      Vault and key alongside the storage account, with the one-line reason (`D8` enforced encryption)
      — per `AGENTS.md`, `docs/` gets fixed in the same change that reveals it is silent.

## 8. Verification and close-out

- [x] 8.1 Run `tofu fmt -check -recursive` and `tofu validate` in `platform/`; both clean.
- [x] 8.2 Run `tofu init -backend-config=backend.hcl && tofu plan` from a clean checkout and confirm
      **zero** changes to add, change, or destroy — the change's done-when
      (*Plan is clean after bootstrap and adoption*).
- [x] 8.3 Confirm shared-key access is refused: attempt an account-key operation, and an account-SAS
      operation, against the state account and confirm both fail (*Shared-key access is refused*).
- [x] 8.4 Grep the full diff for leaked identifiers — real organization or client names, tenant IDs,
      subscription GUIDs, storage account or vault names, vault URIs, access keys, connection strings,
      SAS tokens (*No credential material in the diff*, *Names are de-identified*).
- [x] 8.5 Record the running cost estimate (storage + Key Vault operations + management groups)
      against the `P1` ceiling in `platform/README.md`, confirming no Managed HSM is in use.
- [x] 8.6 Tick **P-01** in `BACKLOG.md`.
