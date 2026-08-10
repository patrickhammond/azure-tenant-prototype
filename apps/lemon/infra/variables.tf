# Inputs for Lemon dev.
#
# Nothing here defaults to a real tenant, subscription, or resource name — this repository is
# published (AGENTS.md). Real values come from git-ignored terraform.tfvars, or from the pipeline.

variable "subscription_id" {
  description = "The single subscription everything lives in."
  type        = string
}

variable "tenant_id" {
  description = "Entra tenant ID."
  type        = string
}

variable "location" {
  description = <<-EOT
    Azure region. Must match the platform's var.location — this root reconstructs shared resource
    names from it, so a mismatch resolves to resources that do not exist.

    Not eastus: SQL provisioning is restricted there on this subscription, and the restriction is
    only visible via `az sql db list-editions -l <region> --available`.
  EOT
  type        = string
  default     = "centralus"
}

variable "application" {
  description = "Application name, as it appears in resource-group names."
  type        = string
  default     = "lemon"
}

variable "environment" {
  description = "Environment name. Determines which shared plane this application joins."
  type        = string
  default     = "dev"
}

variable "state_key_vault_uri" {
  description = <<-EOT
    Vault URI for the state key-encryption key (D8). Passed as a variable rather than derived,
    because the encryption block is evaluated before providers and data sources exist.
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

variable "container_image" {
  description = <<-EOT
    The image to run, PINNED BY DIGEST (D9). Promotion re-applies the same digest rather than
    rebuilding, so a tag here would silently break the guarantee that what was tested is what ships.

    No default: the pipeline supplies the digest it just built. A placeholder default would be a tag
    in disguise the first time someone ran this by hand.
  EOT
  type        = string

  validation {
    condition     = can(regex("@sha256:[0-9a-f]{64}$", var.container_image))
    error_message = "container_image must be pinned by digest, ending @sha256:<64 hex chars>."
  }
}
