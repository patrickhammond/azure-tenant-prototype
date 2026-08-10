# The per-environment shared plane: one Container Apps environment and Log Analytics workspace per
# environment, platform-owned. Applications get join rights only, never write.
#
# Why per environment here but per application-environment for SQL: docs/azure-organization.md.
# Cost note: the Container Apps compute grant is per SUBSCRIPTION, so it no longer multiplies.

locals {
  # Every environment the application-environment list implies. Derived rather than hand-written, so
  # an environment cannot appear in one list and be missing from the other.
  all_environments = toset([
    for ae in var.application_environments :
    element(split("-", ae), length(split("-", ae)) - 1)
  ])

  # ...intersected with the environments stood up so far. This is not the same
  # set: standing up `prod` is a separate change, and doing it here would create a second Log
  # Analytics workspace before the open question about whether per-environment workspaces change
  # cost has been answered. Widening var.active_environments is how prod arrives.
  environments = setintersection(local.all_environments, toset(var.active_environments))
}

resource "azurerm_resource_group" "environment_shared" {
  for_each = local.environments

  # rg-<app>-<env>-<component>, no region suffix (naming table in docs/azure-organization.md).
  name     = "rg-platform-${each.key}-shared"
  location = var.location

  tags = {
    purpose     = "environment-shared-plane"
    environment = each.key
    managed-by  = "platform"
  }
}

# Telemetry only (P7, D10). One workspace per environment — under a single subscription, D10's
# original "per subscription" would put dev and prod in one workspace.
resource "azurerm_log_analytics_workspace" "environment" {
  for_each = local.environments

  name                = "log-platform-${each.key}-${local.location_short}"
  resource_group_name = azurerm_resource_group.environment_shared[each.key].name
  location            = azurerm_resource_group.environment_shared[each.key].location

  sku = "PerGB2018"

  # P1. The scale here is ~5-100 users at light use; the default 30 days is more than the telemetry
  # question ("is it working") needs, and retention is the main cost lever on a workspace.
  retention_in_days = 30

  tags = azurerm_resource_group.environment_shared[each.key].tags
}

resource "azurerm_container_app_environment" "environment" {
  for_each = local.environments

  name                = "cae-platform-${each.key}-${local.location_short}"
  resource_group_name = azurerm_resource_group.environment_shared[each.key].name
  location            = azurerm_resource_group.environment_shared[each.key].location

  log_analytics_workspace_id = azurerm_log_analytics_workspace.environment[each.key].id

  tags = azurerm_resource_group.environment_shared[each.key].tags
}
