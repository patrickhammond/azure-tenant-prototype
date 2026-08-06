# The tenant scope tree, exactly as docs/azure-organization.md draws it.
#
#   Tenant Root Group
#   └── org
#       ├── platform          → sub-platform
#       ├── landing-zones
#       │   └── corp          → the application-environment subscriptions
#       ├── sandboxes         → sub-sbx-<yyyy>-<event>  (D17)
#       └── decommissioned
#
# Subscriptions are vended into this tree by P-02, not here.

locals {
  tenant_root_group_id = "/providers/Microsoft.Management/managementGroups/${var.tenant_id}"

  # Where each class of subscription belongs. P-02 reads this rather than rediscovering it, so
  # that "which management group does this go under?" has exactly one answer in one place.
  #
  # Note that dev and prod both land under `corp`. That is deliberate: rules should be identical
  # across environments and only *access* should differ (P6), so one management group means one
  # copy of the rules, and a control production depends on is exercised in development too.
  subscription_placement = {
    platform         = azurerm_management_group.platform.id
    application_dev  = azurerm_management_group.corp.id
    application_prod = azurerm_management_group.corp.id
    sandbox          = azurerm_management_group.sandboxes.id
    decommissioned   = azurerm_management_group.decommissioned.id
  }
}

# The intermediate root. Policy assigned at the Tenant Root Group applies to everything in the
# tenant permanently, including whatever arrives later; `org` is a ceiling we control. Nothing in
# this repository assigns policy or roles above this scope.
resource "azurerm_management_group" "org" {
  name                       = "org"
  display_name               = "org"
  parent_management_group_id = local.tenant_root_group_id
}

resource "azurerm_management_group" "platform" {
  name                       = "platform"
  display_name               = "platform"
  parent_management_group_id = azurerm_management_group.org.id
}

resource "azurerm_management_group" "landing_zones" {
  name                       = "landing-zones"
  display_name               = "landing-zones"
  parent_management_group_id = azurerm_management_group.org.id
}

resource "azurerm_management_group" "corp" {
  name                       = "corp"
  display_name               = "corp"
  parent_management_group_id = azurerm_management_group.landing_zones.id
}

resource "azurerm_management_group" "sandboxes" {
  name                       = "sandboxes"
  display_name               = "sandboxes"
  parent_management_group_id = azurerm_management_group.org.id
}

resource "azurerm_management_group" "decommissioned" {
  name                       = "decommissioned"
  display_name               = "decommissioned"
  parent_management_group_id = azurerm_management_group.org.id
}

# --------------------------------------------------------------------------------------------
# Tenant default management group
#
# A subscription created outside the vending process must land in the least-privileged scope, not
# at the Tenant Root Group where policy cannot safely be assigned.
#
# azurerm has no resource for management-group settings, so this goes through azapi. The settings
# resource hangs off the ROOT group, not `org` — it is a tenant-wide setting.
# --------------------------------------------------------------------------------------------

resource "azapi_resource" "management_group_settings" {
  type      = "Microsoft.Management/managementGroups/settings@2021-04-01"
  name      = "default"
  parent_id = local.tenant_root_group_id

  body = {
    properties = {
      # The management group NAME, not its resource ID. The API accepts a full ID on write but
      # always reads back the short name, so sending the ID produces drift on every single plan.
      defaultManagementGroup = azurerm_management_group.sandboxes.name

      # Group creation stays available to the platform team; requiring authorization would mean
      # every new management group needs an explicit grant. Revisit if the tenant grows past one
      # team owning this tree.
      requireAuthorizationForGroupCreation = false
    }
  }

  depends_on = [azurerm_management_group.sandboxes]
}
