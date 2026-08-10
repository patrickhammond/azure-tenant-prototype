# What makes resource-group isolation mean anything.
#
# With one subscription, a resource group is the isolation boundary — and unlike a subscription
# boundary, it can be reached across by anyone holding a subscription-scoped role. A single
# Contributor at subscription scope silently dissolves every boundary in this platform.
#
# Two pieces: a policy that denies those grants everywhere except the resource groups the platform
# vended, and alerts for when someone tampers with the policy or writes a role assignment.
#
# VERIFIED, three ways, because one test is not enough here: denied at subscription scope, allowed in
# a vended group, denied in a real group that was not vended. A single deny proves a policy fires
# without proving it fires narrowly, and an over-broad policy would look identical from that one test
# while breaking every deploy identity in the platform.
#
# What this does NOT do: stop a subscription Owner. They can delete the policy assignment and then
# grant themselves anything. That deletion is alerted, not blocked. Azure has no stronger
# in-subscription control available — genuine deny assignments are not directly creatable, only Azure
# creates them via Deployment Stacks, which would mean a second infrastructure-as-code toolchain
# against D8. So: broad grants prevented, removal of the prevention detected, determined Owner not
# stopped. Recorded as an accepted risk in docs/azure-organization.md, which P5 points at.

locals {
  subscription_scope = "/subscriptions/${var.platform_subscription_id}"

  # Universal Azure built-in role IDs — the same GUIDs in every tenant, so these are not
  # tenant-identifying and are safe in a published repository.
  privileged_role_ids = {
    owner                     = "8e3af657-a8ff-443c-a75c-2fe8c4bcb635"
    contributor               = "b24988ac-6180-42a0-ab88-20f7382dd24c"
    user_access_administrator = "18d7d88d-d35e-4fb5-a5c3-7773c20a72d9"
  }

  privileged_role_definition_ids = [
    for id in values(local.privileged_role_ids) :
    "${local.subscription_scope}/providers/Microsoft.Authorization/roleDefinitions/${id}"
  ]
}

# --------------------------------------------------------------------------------------------
# The join role. Lets an application attach a container app to the shared environment without being
# able to modify it — no built-in role grants join without also granting write.
# --------------------------------------------------------------------------------------------

resource "azurerm_role_definition" "container_app_environment_joiner" {
  name        = "Container Apps Environment Joiner"
  scope       = local.subscription_scope
  description = "Attach a container app to a managed environment. Grants nothing else."

  permissions {
    actions = [
      # read as well as join: applications resolve the environment through a data source, and a
      # join-only role fails at plan time for the identity it exists to serve.
      "Microsoft.App/managedEnvironments/read",
      "Microsoft.App/managedEnvironments/join/action",
    ]
    not_actions = []
  }

  assignable_scopes = [local.subscription_scope]
}

# --------------------------------------------------------------------------------------------
# Deny privileged grants outside vended resource groups.
# --------------------------------------------------------------------------------------------

resource "azurerm_policy_definition" "deny_subscription_scoped_privileged_grants" {
  name         = "deny-subscription-scoped-privileged-grants"
  display_name = "Deny subscription-scoped Owner, Contributor, and User Access Administrator"
  policy_type  = "Custom"
  mode         = "All"

  description = <<-EOT
    With a single subscription and resource groups as the isolation boundary, a subscription-scoped
    grant of Owner, Contributor, or User Access Administrator dissolves every boundary the platform
    relies on. Resource-group-scoped assignments are unaffected: this constrains scope, not delegation.
  EOT

  # No `scope` condition: the Microsoft.Authorization/roleAssignments/scope alias
  # exists but never matches, so a rule conditioned on it silently does nothing. Verified.
  # Hence deny everywhere, with not_scopes below carving out the vended groups.
  policy_rule = jsonencode({
    if = {
      allOf = [
        {
          field  = "type"
          equals = "Microsoft.Authorization/roleAssignments"
        },
        {
          field = "Microsoft.Authorization/roleAssignments/roleDefinitionId"
          in    = local.privileged_role_definition_ids
        },
      ]
    }
    then = {
      effect = "deny"
    }
  })
}

resource "azurerm_subscription_policy_assignment" "deny_subscription_scoped_privileged_grants" {
  name                 = "deny-sub-scoped-privileged"
  display_name         = "Deny subscription-scoped privileged role assignments"
  subscription_id      = local.subscription_scope
  policy_definition_id = azurerm_policy_definition.deny_subscription_scoped_privileged_grants.id

  description = "Removing this assignment is itself an alerted event. See azurerm_monitor_activity_log_alert.guardrail_tampered."

  # APPLICATION groups only. `rg-platform-<env>-shared` is not exempt: it holds every
  # application's runtime identity and Key Vault, and the self-escalation argument in vending.tf
  # depends on applications having no write there. Nothing the platform does in that group needs a
  # privileged grant — the assignments it makes are Key Vault Secrets User/Officer, Managed Identity
  # Operator, and the custom joiner, none of which are in privileged_role_ids. Exempting it would
  # open the one group whose integrity the design rests on, in exchange for nothing.
  not_scopes = [for rg in azurerm_resource_group.application : rg.id]
}

# --------------------------------------------------------------------------------------------
# Tamper detection. A subscription Owner can delete the policy assignment; that deletion is alerted.
# --------------------------------------------------------------------------------------------

# Its own group, not an environment's. Everything below is scoped to the SUBSCRIPTION, so hanging it
# off the shared plane of whichever environment happened to be listed first coupled subscription-wide
# alerting to one environment's lifecycle — a region move for that environment would have deleted the
# guardrail's alerting as collateral, with no plan entry saying so.
resource "azurerm_resource_group" "guardrail" {
  name     = "rg-platform-guardrail-${local.location_short}"
  location = var.location

  tags = {
    purpose    = "subscription-guardrail"
    managed-by = "platform"
  }
}

resource "azurerm_monitor_action_group" "platform" {
  name                = "ag-platform-guardrail"
  resource_group_name = azurerm_resource_group.guardrail.name
  short_name          = "guardrail"

  email_receiver {
    name          = "platform"
    email_address = var.alert_email
  }
}

resource "azurerm_monitor_activity_log_alert" "guardrail_tampered" {
  name                = "alert-guardrail-tampered"
  resource_group_name = azurerm_resource_group.guardrail.name
  location            = "global"
  scopes              = [local.subscription_scope]

  description = "The subscription-scope guardrail was deleted or exempted."

  criteria {
    category       = "Administrative"
    operation_name = "Microsoft.Authorization/policyAssignments/delete"
  }

  action {
    action_group_id = azurerm_monitor_action_group.platform.id
  }

}

# Fires on every role assignment in the subscription, not only subscription-scoped ones — the
# assignment's own scope cannot be filtered on. Kept despite the noise: it is what would catch a
# grant made after someone deletes the policy.
resource "azurerm_monitor_activity_log_alert" "role_assignment_written" {
  name                = "alert-role-assignment-written"
  resource_group_name = azurerm_resource_group.guardrail.name
  location            = "global"
  scopes              = [local.subscription_scope]

  # Named for what it does, not what was wanted. `scopes` is the scope being monitored,
  # not a filter on the assignment's own scope, and no criteria field can express "only assignments
  # whose scope is the subscription" — the same gap that broke the policy, in a different service.
  # So this fires on every role assignment in the subscription, including legitimate vending ones.
  #
  # Kept anyway: now that the policy prevents broad grants, this is what would notice a grant made
  # after someone deletes the policy. Noisy and useful beats precise and absent.
  description = "A role assignment was written somewhere in the subscription. Expected to be rare."

  criteria {
    category       = "Administrative"
    operation_name = "Microsoft.Authorization/roleAssignments/write"
  }

  action {
    action_group_id = azurerm_monitor_action_group.platform.id
  }

}

resource "azurerm_monitor_activity_log_alert" "guardrail_exempted" {
  name                = "alert-guardrail-exempted"
  resource_group_name = azurerm_resource_group.guardrail.name
  location            = "global"
  scopes              = [local.subscription_scope]

  description = "A policy exemption was created, which can neutralise the guardrail without deleting it."

  criteria {
    category       = "Administrative"
    operation_name = "Microsoft.Authorization/policyExemptions/write"
  }

  action {
    action_group_id = azurerm_monitor_action_group.platform.id
  }

}
