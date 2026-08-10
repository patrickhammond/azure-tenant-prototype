# Pinned to the same provider major as the platform root. An application inheriting a surprise
# provider upgrade is a deployment failure at the worst moment (D8).

terraform {
  required_version = "~> 1.12"

  # State and plan encryption (D8), the same shape and the same key as the platform root.
  #
  # This was missing at first, and the omission was invisible: an application root with no encryption
  # block writes plaintext state into the same storage account whose platform state is encrypted, and
  # nothing warns. D8 requires `enforced = true` for state, not for platform state specifically.
  #
  # `enforced = true` with no fallback means a misconfigured run FAILS instead of quietly writing
  # plaintext — a fallback would silently permit what this prevents.
  #
  # Using the key requires Key Vault Crypto User on the KEK. An application cannot grant itself that,
  # so the platform vends it (platform/vending.tf, azurerm_role_assignment.deploy_state_kek).
  encryption {
    key_provider "azure_vault" "state" {
      vault_uri      = var.state_key_vault_uri
      vault_key_name = var.state_key_name
      key_length     = 32

      encrypted_metadata_alias = "lemon-dev-state-kek"
    }

    method "aes_gcm" "state" {
      keys = key_provider.azure_vault.state
    }

    state {
      method   = method.aes_gcm.state
      enforced = true
    }

    plan {
      method   = method.aes_gcm.state
      enforced = true
    }
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
  }
}

provider "azurerm" {
  features {}

  subscription_id     = var.subscription_id
  tenant_id           = var.tenant_id
  storage_use_azuread = true
}
