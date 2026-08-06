# OpenTofu remote state — the storage account, its containers, and the key that encrypts them (D8).
#
# The resource group, storage account, platform container, and Key Vault here were created by
# bootstrap.sh and are adopted by the import blocks in imports.tf. Their configuration must match
# what the script applied, or the first plan is not clean.

resource "azurerm_resource_group" "tfstate" {
  name     = "rg-platform-tfstate-${local.location_short}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_storage_account" "tfstate" {
  name                = var.state_storage_account_name
  resource_group_name = azurerm_resource_group.tfstate.name
  location            = azurerm_resource_group.tfstate.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  access_tier              = "Hot"

  # The P3 control, and the one that matters most here: with shared keys off, account keys and any
  # account or service SAS signed by them stop working for everyone. A user-delegation SAS still
  # works, and should — it is signed by an Entra identity the caller already holds.
  shared_access_key_enabled = false

  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false

  # No private endpoint: P2 says access is decided by who you are, not where you connect from, and
  # a private endpoint plus its DNS is real monthly cost against P1 for a second layer that
  # Entra-only auth already carries.
  public_network_access_enabled = true

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = local.soft_delete_days
    }

    container_delete_retention_policy {
      days = local.soft_delete_days
    }
  }

  tags = local.tags
}

# The platform's own container — bootstrapped, because the backend needs it before OpenTofu runs.
resource "azurerm_storage_container" "platform" {
  name               = "tfstate-platform"
  storage_account_id = azurerm_storage_account.tfstate.id
}

# One container per application-environment. NOT key prefixes inside a shared container: a
# container is the smallest scope Azure RBAC can be assigned at, so this is what lets P-06 give a
# dev pipeline access to dev state and nothing else. That is P6, one layer down.
resource "azurerm_storage_container" "application" {
  for_each = toset(var.application_environments)

  name               = "tfstate-${each.value}"
  storage_account_id = azurerm_storage_account.tfstate.id
}

# --------------------------------------------------------------------------------------------
# Key Vault and the state key-encryption key
# --------------------------------------------------------------------------------------------

resource "azurerm_key_vault" "tfstate" {
  name                = var.state_key_vault_name
  resource_group_name = azurerm_resource_group.tfstate.name
  location            = azurerm_resource_group.tfstate.location
  tenant_id           = var.tenant_id
  sku_name            = "standard"

  # RBAC, set deliberately at creation (D2). Legacy access policies would let anyone with
  # Contributor on the vault grant themselves data access by rewriting the policy.
  rbac_authorization_enabled = true

  # Irreversible once enabled, which is the point: destroying this key makes every state file in
  # the account permanently unreadable. This vault is a tier-0 asset.
  purge_protection_enabled   = true
  soft_delete_retention_days = local.vault_retention_days

  tags = local.tags
}

# The key-encryption key is READ, not managed.
#
# It cannot be an OpenTofu resource: the encryption block in versions.tf needs it to exist before
# `tofu init` can read state at all, so bootstrap.sh must create it. It cannot be adopted by an
# import block either — a key's resource ID includes its version, which is not knowable when the
# config is written, and pinning one would break on any rotation.
#
# bootstrap.sh creates it as RSA 3072 with wrapKey/unwrapKey. This data source asserts it exists
# and fails the plan loudly if it does not.
data "azurerm_key_vault_key" "state" {
  name         = var.state_key_name
  key_vault_id = azurerm_key_vault.tfstate.id
}

# --------------------------------------------------------------------------------------------
# Deletion protection
#
# D8 names Azure Policy and resource locks as the guardrails, and rules out Deployment Stacks.
# --------------------------------------------------------------------------------------------

resource "azurerm_management_lock" "tfstate" {
  name       = "tfstate-no-delete"
  scope      = azurerm_resource_group.tfstate.id
  lock_level = "CanNotDelete"
  notes      = "Holds all OpenTofu state. Deleting this group would strand every application."
}
