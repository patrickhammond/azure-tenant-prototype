# Remote state for Lemon dev (D8).
#
# Its own state container, not a key prefix in a shared one: a container is the smallest scope Azure
# RBAC can be assigned at, which is what lets one application-environment's state be readable by
# exactly one deploy identity.
#
# Partial by design, for the same reason as the platform's — the values identify a real tenant and
# this repository is published (AGENTS.md).
#
#     tofu init -backend-config=backend.hcl

terraform {
  backend "azurerm" {
    container_name = "tfstate-lemon-dev"
    key            = "lemon-dev.tfstate"

    use_azuread_auth = true
  }
}
