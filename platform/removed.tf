# Stop managing the resources of the abandoned multi-subscription shape WITHOUT destroying them.
#
# Deleting the resource blocks alone would plan a silent destroy: `prevent_destroy` disappears with
# the block it is written in (measured, OpenTofu 1.12.5). For a subscription, destroy means cancel.
# Destroying the platform association would also undo sub-platform's placement.
#
# `destroy = false` makes the plan report "to forget" rather than "to destroy". Blocks are kept after
# apply, per the convention in imports.tf. Surplus subscriptions: tenant-cleanup change.

removed {
  from = azurerm_subscription.app

  lifecycle {
    destroy = false
  }
}

removed {
  from = azurerm_management_group_subscription_association.app

  lifecycle {
    destroy = false
  }
}

removed {
  from = azurerm_management_group_subscription_association.platform

  lifecycle {
    destroy = false
  }
}
