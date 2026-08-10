# Inputs for the shared platform root.
#
# No variable here carries a default that encodes a real tenant, subscription, or resource name.
# This repository is published (AGENTS.md); real values are supplied out of band, the same way
# backend.hcl supplies the backend's. Copy terraform.tfvars.example and fill it in.

variable "tenant_id" {
  description = "Entra tenant ID. Also the ID of the Tenant Root Group, which `org` is parented to."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.tenant_id))
    error_message = "tenant_id must be a GUID."
  }
}

variable "platform_subscription_id" {
  description = "Subscription ID of sub-platform, which holds the state account and Key Vault."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.platform_subscription_id))
    error_message = "platform_subscription_id must be a GUID."
  }
}

variable "location" {
  description = "Azure region for platform resources. One region for the whole platform."
  type        = string
}

variable "state_storage_account_name" {
  description = <<-EOT
    Name of the bootstrapped state storage account. Created by bootstrap.sh, adopted here by an
    import block. Storage accounts cannot carry hyphens, so this is the de-hyphenated form of the
    naming convention plus the uniqueness suffix the bootstrap generated.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.state_storage_account_name))
    error_message = "Storage account names are 3-24 characters, lowercase letters and digits only."
  }
}

variable "state_key_vault_name" {
  description = "Name of the bootstrapped Key Vault holding the state key-encryption key."
  type        = string
}

variable "state_key_vault_uri" {
  description = <<-EOT
    Vault URI (https://<name>.vault.azure.net) for the azure_vault state-encryption key provider.
    Passed separately because the encryption block is evaluated before providers and data sources
    are available, so it cannot be derived from the vault resource.
  EOT
  type        = string

  validation {
    condition     = can(regex("^https://.+\\.vault\\.azure\\.net/?$", var.state_key_vault_uri))
    error_message = "state_key_vault_uri must look like https://<name>.vault.azure.net."
  }
}

variable "state_key_name" {
  description = "Name of the RSA key-encryption key inside the vault."
  type        = string
  default     = "tofu-state-kek"
}

variable "vended_application_environments" {
  description = <<-EOT
    Application-environments the platform has vended resource groups and a deploy identity for.
    Narrower than application_environments: vending is a change someone makes, not a side effect of
    naming an application in a list.
  EOT
  type        = list(string)
  default     = ["lemon-dev"]
}

variable "github_repository" {
  description = <<-EOT
    The GitHub repository deploy identities federate to, as `owner/repo`. Used to build the federated
    credential subject; a wrong value here means the workflow cannot assume the identity, which is the
    correct failure direction.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.github_repository))
    error_message = "github_repository must be owner/repo."
  }
}

variable "alert_email" {
  description = <<-EOT
    Where guardrail-tampering alerts go. A real address, so it is supplied out of band like every
    other real value (AGENTS.md) and never committed.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", var.alert_email))
    error_message = "alert_email must be an email address."
  }
}

variable "active_environments" {
  description = <<-EOT
    Environments the platform has stood up a shared plane for, as opposed to those the
    application-environment list implies. These differ on purpose: an environment costs a Container
    Apps environment and a Log Analytics workspace, and standing one up is a change someone makes.

    Widen this to add an environment. It must be a subset of the environment suffixes appearing in
    application_environments; anything else is silently ignored.
  EOT
  type        = list(string)
  default     = ["dev"]
}

variable "application_environments" {
  description = <<-EOT
    Every application-environment that gets its own OpenTofu state container. One container each,
    never a shared container with key prefixes: a container is the smallest scope Azure RBAC can be
    assigned at, so this is what makes P6 mechanically enforceable when P-06 grants the apply
    identities their access.
  EOT
  type        = list(string)
  default = [
    "lemon-dev",
    "lemon-prod",
    "lime-dev",
    "lime-prod",
  ]
}
