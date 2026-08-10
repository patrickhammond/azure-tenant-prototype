# Vending an application-environment: the platform creates its resource groups empty with role
# assignments attached, and the application fills them.
#
# Not a style choice — creating a resource group needs write at subscription scope, which the
# guardrail denies to applications. Layout and rationale: docs/azure-organization.md.

locals {
  # Application-environments vended so far. Narrower than var.application_environments:
  # vending is a change, not a side effect of naming an application.
  vended = toset([
    for ae in var.application_environments :
    ae if contains(var.vended_application_environments, ae)
  ])

  vended_components = {
    for pair in setproduct(local.vended, ["shared", "web"]) :
    "${pair[0]}-${pair[1]}" => {
      application_environment = pair[0]
      component               = pair[1]
      environment             = element(split("-", pair[0]), length(split("-", pair[0])) - 1)
    }
  }
}

resource "azurerm_resource_group" "application" {
  for_each = local.vended_components

  name     = "rg-${each.value.application_environment}-${each.value.component}"
  location = var.location

  tags = {
    purpose                 = "application"
    application-environment = each.value.application_environment
    environment             = each.value.environment
    managed-by              = "platform"
  }
}

# --------------------------------------------------------------------------------------------
# Deploy identity: user-assigned managed identity with a GitHub federated credential (P3, D9).
#
# Lives in a PLATFORM group. In the application's own group, its Contributor could edit the
# identity's federated credentials and widen which GitHub refs may assume it.
# --------------------------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "deploy" {
  for_each = local.vended

  name                = "id-deploy-${each.key}"
  resource_group_name = azurerm_resource_group.environment_shared[local.vended_components["${each.key}-web"].environment].name
  location            = var.location

  tags = {
    purpose                 = "deploy-identity"
    application-environment = each.key
    managed-by              = "platform"
  }
}

resource "azurerm_federated_identity_credential" "deploy" {
  for_each = local.vended

  name                      = "github-${each.key}"
  user_assigned_identity_id = azurerm_user_assigned_identity.deploy[each.key].id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"

  # Scoped to the GitHub environment, not the branch: a run can only assume this identity once
  # GitHub has admitted it to that environment, which is where the prod reviewer gate sits (D9).
  subject = "repo:${var.github_repository}:environment:${local.vended_components["${each.key}-web"].environment}"
}

# --------------------------------------------------------------------------------------------
# What the deploy identity may do
#
# Contributor on its own two resource groups, and nothing else anywhere. Contributor deliberately
# EXCLUDES creating role assignments, so an application cannot grant itself anything even inside the
# groups it owns. Escalation requires a platform change.
# --------------------------------------------------------------------------------------------

resource "azurerm_role_assignment" "deploy_contributor" {
  for_each = local.vended_components

  scope                = azurerm_resource_group.application[each.key].id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.deploy[each.value.application_environment].principal_id

  # The exemption must exist before the grant it exempts, or the guardrail denies its own platform's
  # apply. Policy changes take minutes to propagate, so a fresh vend may still need a re-apply.
  depends_on = [azurerm_subscription_policy_assignment.deny_subscription_scoped_privileged_grants]
}

# Join the shared Container Apps environment — scoped to the ENVIRONMENT RESOURCE, not its resource
# group and not the subscription. Scoping to the resource group would hand the application read and
# join across everything else the platform puts there.
resource "azurerm_role_assignment" "deploy_join_environment" {
  for_each = local.vended

  scope              = azurerm_container_app_environment.environment[local.vended_components["${each.key}-web"].environment].id
  role_definition_id = azurerm_role_definition.container_app_environment_joiner.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.deploy[each.key].principal_id
}

# --------------------------------------------------------------------------------------------
# Runtime identity and Key Vault.
#
# The vending boundary: the platform creates anything requiring a role assignment, the application
# creates everything else. Both live in a PLATFORM group — in the application's own group its
# Contributor could add federated credentials to the identity, or switch the vault out of RBAC and
# self-grant. Applications get narrow rights scoped to the resource, never the group.
# --------------------------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "runtime" {
  for_each = local.vended

  name                = "id-run-${each.key}"
  resource_group_name = azurerm_resource_group.environment_shared[local.vended_components["${each.key}-web"].environment].name
  location            = var.location

  tags = {
    purpose                 = "runtime-identity"
    application-environment = each.key
    managed-by              = "platform"
  }
}

resource "azurerm_key_vault" "application" {
  for_each = local.vended

  # Key Vault names are globally unique and capped at 24 characters. The suffix is derived rather
  # than random so the name is stable across rebuilds without needing a random provider.
  name                = substr("kv-${each.key}-${substr(sha1(var.platform_subscription_id), 0, 6)}", 0, 24)
  resource_group_name = azurerm_resource_group.environment_shared[local.vended_components["${each.key}-web"].environment].name
  location            = var.location
  tenant_id           = var.tenant_id

  sku_name = "standard"

  # RBAC, not access policies. Access policies are the legacy model, and mixing the two would mean
  # two answers to "who can read this secret".
  rbac_authorization_enabled = true

  soft_delete_retention_days = local.soft_delete_days
  purge_protection_enabled   = true

  tags = {
    purpose                 = "application-secrets"
    application-environment = each.key
    managed-by              = "platform"
  }
}

# Runtime: read secrets, in its own vault, and nothing else anywhere.
resource "azurerm_role_assignment" "runtime_secrets_user" {
  for_each = local.vended

  scope                = azurerm_key_vault.application[each.key].id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.runtime[each.key].principal_id
}

# Deploy: manage secrets in that vault, so the pipeline can seed them. Data plane only — the
# application still cannot reconfigure the vault itself.
resource "azurerm_role_assignment" "deploy_secrets_officer" {
  for_each = local.vended

  scope                = azurerm_key_vault.application[each.key].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azurerm_user_assigned_identity.deploy[each.key].principal_id
}

# Deploy: attach the runtime identity to a container app. Managed Identity Operator carries read and
# assign, scoped to the one identity — not the group it lives in.
resource "azurerm_role_assignment" "deploy_identity_operator" {
  for_each = local.vended

  scope                = azurerm_user_assigned_identity.runtime[each.key].id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azurerm_user_assigned_identity.deploy[each.key].principal_id
}

# Application state encryption (D8) needs Crypto User on the KEK, which an application cannot grant
# itself. Scoped to the KEY, not the vault — vault scope would expose every key the platform keeps.
resource "azurerm_role_assignment" "deploy_state_kek" {
  for_each = local.vended

  scope                = data.azurerm_key_vault_key.state.resource_versionless_id
  role_definition_name = "Key Vault Crypto User"
  principal_id         = azurerm_user_assigned_identity.deploy[each.key].principal_id
}

output "application_scaffold" {
  description = "What the platform vended per application-environment, for the application root to resolve by name."
  value = {
    for ae in local.vended : ae => {
      runtime_identity_name = azurerm_user_assigned_identity.runtime[ae].name
      key_vault_name        = azurerm_key_vault.application[ae].name
      shared_resource_group = azurerm_resource_group.application["${ae}-shared"].name
      web_resource_group    = azurerm_resource_group.application["${ae}-web"].name
    }
  }
}

output "deploy_identity_client_ids" {
  description = "Client IDs for each vended deploy identity, for the GitHub workflow's azure/login step."
  value       = { for k, v in azurerm_user_assigned_identity.deploy : k => v.client_id }

  # Tenant-identifying, and this repository is published.
  sensitive = true
}
