# Remote state for the shared platform (D8).
#
# This block is deliberately PARTIAL. `storage_account_name`, `resource_group_name`,
# `subscription_id`, and `tenant_id` identify a real tenant, and this repository is published
# (AGENTS.md) — they are supplied at init time from a git-ignored backend.hcl:
#
#     tofu init -backend-config=backend.hcl
#
# See backend.hcl.example for the shape. bootstrap.sh prints the real file ready to paste.

terraform {
  backend "azurerm" {
    container_name = "tfstate-platform"
    key            = "platform.tfstate"

    # Entra ID for the backend as well as the provider. The state account has shared-key access
    # disabled, so there is no key to fall back to even by accident (P3).
    use_azuread_auth = true
  }
}
