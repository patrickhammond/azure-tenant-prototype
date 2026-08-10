# Lemon, dev. Fills resource groups the platform vended; creates nothing that needs a role
# assignment, because Contributor cannot create them. See platform/vending.tf.

locals {
  application_environment = "${var.application}-${var.environment}"

  # From the naming convention, not from platform state — reading platform state would expose it to
  # every application.
  shared_resource_group = "rg-${local.application_environment}-shared"
  web_resource_group    = "rg-${local.application_environment}-web"
  platform_shared_group = "rg-platform-${var.environment}-shared"

  # Deliberately duplicated from platform/locals.tf, and must match it: an application cannot read
  # platform state, so shared names have to be reconstructed from the convention. An unknown region
  # fails here rather than producing a name that silently resolves to nothing.
  location_short_map = {
    eastus    = "eus"
    eastus2   = "eus2"
    centralus = "cus"
    westus2   = "wus2"
    westus3   = "wus3"
  }

  location_short = local.location_short_map[var.location]
}

data "azurerm_client_config" "current" {}

# Read of a platform-owned resource, permitted by the join role's read action.
data "azurerm_container_app_environment" "shared" {
  name                = "cae-platform-${var.environment}-${local.location_short}"
  resource_group_name = local.platform_shared_group
}

# Vended by the platform; readable via Managed Identity Operator on this one identity.
data "azurerm_user_assigned_identity" "runtime" {
  name                = "id-run-${local.application_environment}"
  resource_group_name = local.platform_shared_group
}

# Data, in the shared group so the compute group stays safe to rebuild.

resource "azurerm_mssql_server" "application" {
  name                = "sql-${local.application_environment}-${local.location_short}"
  resource_group_name = local.shared_resource_group
  location            = var.location
  version             = "12.0"

  # Entra-only: no administrator password to store, rotate, or leak (P3). Admin is the identity
  # running this apply.
  azuread_administrator {
    login_username              = "deploy-${local.application_environment}"
    object_id                   = data.azurerm_client_config.current.object_id
    tenant_id                   = var.tenant_id
    azuread_authentication_only = true
  }

  public_network_access_enabled = true
  minimum_tls_version           = "1.2"
}

resource "azurerm_mssql_database" "application" {
  name      = "sqldb-${local.application_environment}"
  server_id = azurerm_mssql_server.application.id

  # General Purpose serverless. NOTE: this is a BILLED database. The free offer requires
  # `useFreeLimit`, which azurerm 4.81 does not expose — verified against the pinned provider schema,
  # which has no free-offer attribute at all. So the P1 cost story is currently unsupported by this
  # code, and task 6.7 measures the real number rather than assuming it. Options are a provider bump,
  # creating the database through azapi, or accepting the cost knowingly.
  sku_name     = "GP_S_Gen5_2"
  min_capacity = 0.5
  max_size_gb  = 32

  # Scale to zero when idle. At ~5-100 users at light use, idle is the common case.
  auto_pause_delay_in_minutes = 60
}

resource "azurerm_container_app" "web" {
  name                         = "ca-${local.application_environment}-web"
  resource_group_name          = local.web_resource_group
  container_app_environment_id = data.azurerm_container_app_environment.shared.id
  revision_mode                = "Single"

  # Vended; the application holds assign rights on it and nothing more.
  identity {
    type         = "UserAssigned"
    identity_ids = [data.azurerm_user_assigned_identity.runtime.id]
  }

  template {
    min_replicas = 0
    max_replicas = 1

    container {
      name = "web"

      # Digest-pinned (D9).
      image = var.container_image

      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "AZURE_CLIENT_ID"
        value = data.azurerm_user_assigned_identity.runtime.client_id
      }

      env {
        name  = "SQL_SERVER_FQDN"
        value = azurerm_mssql_server.application.fully_qualified_domain_name
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = 80

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
}

output "url" {
  description = "Default Container Apps FQDN. No custom DNS in this slice."
  value       = "https://${azurerm_container_app.web.ingress[0].fqdn}"
}
