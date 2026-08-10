# Provider and version pinning for the shared platform (D8).
#
# Versions are pinned rather than floated: the platform root is the one place where an unexpected
# provider upgrade can strand every application's state. Upgrades are their own change.

terraform {
  # The `azure_vault` state-encryption key provider (below) is a hard floor, not a preference —
  # an older OpenTofu cannot decrypt this state at all.
  required_version = "~> 1.12"

  # State and plan encryption (D8).
  #
  # The key-encryption key lives in Azure Key Vault and `azure_vault` always authenticates with
  # Entra ID, so there is no passphrase, no environment variable, and no stored secret anywhere in
  # the loop — P3 holds by construction rather than by discipline.
  #
  # The key is RSA in a standard vault, NOT symmetric: azure_vault supports symmetric keys only in
  # Managed HSM, whose monthly floor breaches P1 by three orders of magnitude.
  #
  # Reading or writing state requires Key Vault Crypto User on the key. That is deliberately the
  # same population that can read the state blobs — this protects data at rest from someone who
  # obtains the storage, not from someone with access.
  encryption {
    key_provider "azure_vault" "state" {
      vault_uri      = var.state_key_vault_uri
      vault_key_name = var.state_key_name
      key_length     = 32

      # Lets the provider be renamed later without stranding already-encrypted state.
      encrypted_metadata_alias = "platform-state-kek"
    }

    method "aes_gcm" "state" {
      keys = key_provider.azure_vault.state
    }

    # enforced = true: a misconfigured run fails instead of quietly writing plaintext. There is
    # deliberately no `fallback` to an unencrypted method — a fallback would silently accept the
    # very thing this is here to prevent.
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
    # Used only for the tenant default-management-group setting, which azurerm does not model.
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.11"
    }
  }
}

provider "azurerm" {
  # PRIMARY guard against cancelling a real subscription (P-02).
  #
  # Destroying an azurerm_subscription otherwise CANCELS the subscription: irrecoverable after 90
  # days, and its subscription ID can never be reused. This makes destroy drop the alias instead.
  #
  # It is primary, not redundant, because it is the only guard that survives the resource block
  # being deleted. `lifecycle { prevent_destroy }` on the subscriptions is the secondary guard and
  # was MEASURED on OpenTofu 1.12.5 to cover less than it appears to:
  #
  #   block present, -destroy/-replace  → plan fails         (protected)
  #   block removed from configuration  → plans a destroy    (NOT protected)
  #
  # So the likeliest accident — a refactor that deletes the resource — is caught only here. Do not
  # remove this on the grounds that prevent_destroy already covers it. It does not.
  features {
    subscription {
      prevent_cancellation_on_destroy = true
    }
  }

  subscription_id = var.platform_subscription_id
  tenant_id       = var.tenant_id

  # The state account has shared-key access disabled (P3, D8). Without this the provider tries to
  # reach blob data with an account key and fails in a way that reads like a permissions bug.
  storage_use_azuread = true
}

provider "azapi" {
  subscription_id = var.platform_subscription_id
  tenant_id       = var.tenant_id
}
