# Lime · infra

Lime's OpenTofu (`azurerm`). Provisions the application's own resources, per environment: its
resource group, container app, user-assigned managed identity, Key Vault, DNS record, and alerts
(`D8`, and the ownership split in `../../../docs/azure-organization.md`).

Remote state lives in `sub-platform`, one state container per app-environment, reached only by this
application's apply identity (`D8`).

Applied by Lime's pipeline as its last step: build image → capture digest → migrate to a terminal
state (where the schema changed) → `tofu apply` with that digest (`D9`).
