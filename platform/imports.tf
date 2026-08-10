# Adoption of the bootstrapped resources.
#
# These four were created by hand (platform/bootstrap/bootstrap.sh) because OpenTofu cannot create
# what it needs in order to run. D8 says "prefer rebuilding hand-built resources over importing
# them"; this is the carve-out that record already allows, because rebuilding the state account
# would destroy the state it holds.
#
# THE BLOCKS ARE KEPT, NOT DELETED after the first apply. They are no-ops once state contains the
# resource, and keeping them means the path from an empty tenant to a clean plan lives entirely in
# source (P4) rather than half in source and half in a README someone followed once.
#
# The key-encryption key is deliberately absent: a key's ID includes its version, which is not
# knowable when this file is written. See the data source in state.tf.

import {
  to = azurerm_resource_group.tfstate
  id = "/subscriptions/${var.platform_subscription_id}/resourceGroups/rg-platform-tfstate-${local.state_location_short}"
}

import {
  to = azurerm_storage_account.tfstate
  id = "/subscriptions/${var.platform_subscription_id}/resourceGroups/rg-platform-tfstate-${local.state_location_short}/providers/Microsoft.Storage/storageAccounts/${var.state_storage_account_name}"
}

import {
  to = azurerm_storage_container.platform
  id = "/subscriptions/${var.platform_subscription_id}/resourceGroups/rg-platform-tfstate-${local.state_location_short}/providers/Microsoft.Storage/storageAccounts/${var.state_storage_account_name}/blobServices/default/containers/tfstate-platform"
}

import {
  to = azurerm_key_vault.tfstate
  id = "/subscriptions/${var.platform_subscription_id}/resourceGroups/rg-platform-tfstate-${local.state_location_short}/providers/Microsoft.KeyVault/vaults/${var.state_key_vault_name}"
}
