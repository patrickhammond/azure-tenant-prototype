## MODIFIED Requirements

### Requirement: Nothing arrives at the Tenant Root Group by accident

The tenant's **default management group for new subscriptions** SHALL be set to `sandboxes`, so that
a subscription created outside the vending process lands in the least-privileged scope rather than
at the Tenant Root Group where policy cannot be safely assigned.

Additionally, **no subscription SHALL remain a direct child of the Tenant Root Group.** The default
management group governs where *new* subscriptions arrive but says nothing about subscriptions
already parented at the root — including `sub-platform`, which predates the hierarchy. Every
subscription in the tenant SHALL be placed under a management group in the documented tree, so that
the ceiling described by *"Policy has a ceiling below the tenant root"* actually contains everything
rather than merely most things.

#### Scenario: An unplaced subscription lands in sandboxes

- **WHEN** a subscription is created in the tenant without an explicit management-group placement
- **THEN** it appears under `sandboxes`, not under the Tenant Root Group

#### Scenario: No subscription is parented at the tenant root

- **WHEN** the tenant's management-group entities are enumerated
- **THEN** every subscription has a management group from the documented tree as its parent, and none
  is a direct child of the Tenant Root Group

#### Scenario: The platform subscription sits under platform

- **WHEN** `sub-platform` is inspected
- **THEN** its parent is the `platform` management group, as `docs/azure-organization.md` requires
