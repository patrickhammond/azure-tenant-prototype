locals {
  # Region abbreviation used in resource names (docs/azure-organization.md naming table).
  # Extend this map when the platform gains a region; an unknown region should fail loudly here
  # rather than silently produce a resource name that breaks the convention.
  location_short_map = {
    eastus        = "eus"
    eastus2       = "eus2"
    centralus     = "cus"
    westus2       = "wus2"
    westus3       = "wus3"
    westeurope    = "weu"
    northeurope   = "neu"
    uksouth       = "uks"
    australiaeast = "aue"
  }

  location_short = local.location_short_map[var.location]

  # The state resources sit in their own region, deliberately. See var.state_location.
  state_location_short = local.location_short_map[var.state_location]

  soft_delete_days     = 30
  vault_retention_days = 90

  # Must match the tags bootstrap.sh applies, or the first plan is not clean. The bootstrap
  # discovers its own resources by `purpose`, so this tag is load-bearing, not decorative.
  tags = {
    purpose    = "tofu-state"
    managed-by = "platform-bootstrap"
  }
}
