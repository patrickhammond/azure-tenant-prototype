# management-group-hierarchy

## Purpose

The tenant scope tree: the `org` intermediate root and its children, where each class of
subscription is placed, the default management group that catches subscriptions created outside the
vending process, and the ceiling below which all policy and role assignments sit.

Subscriptions are vended into this tree by a later change; this capability defines the tree itself.

Established by change `platform-bootstrap-remote-state` (backlog P-01). See `D1`, `P5`, `P6`, and
`docs/azure-organization.md`.

## Requirements

### Requirement: The tenant scope tree is defined as code

The platform OpenTofu SHALL create and own the management-group hierarchy exactly as
`docs/azure-organization.md` defines it: an `org` intermediate root beneath the Tenant Root Group,
with children `platform`, `landing-zones` (itself parent of `corp`), `sandboxes`, and
`decommissioned`. No management group in this tree SHALL be created or reparented by hand.

#### Scenario: Hierarchy matches the documented tree

- **WHEN** the platform OpenTofu has been applied to a tenant with no prior hierarchy
- **THEN** every management group in the documented tree exists with the documented parent, and no
  additional management groups are created by this change

#### Scenario: A hand-made change is reverted by the next apply

- **WHEN** a management group in the tree is renamed or reparented outside OpenTofu
- **THEN** the next `tofu plan` reports the difference and applying restores the documented tree

### Requirement: Nothing arrives at the Tenant Root Group by accident

The tenant's **default management group for new subscriptions** SHALL be set to `sandboxes`, so that
a subscription created outside the vending process lands in the least-privileged scope rather than
at the Tenant Root Group where policy cannot be safely assigned.

#### Scenario: An unplaced subscription lands in sandboxes

- **WHEN** a subscription is created in the tenant without an explicit management-group placement
- **THEN** it appears under `sandboxes`, not under the Tenant Root Group

### Requirement: Policy has a ceiling below the tenant root

The `org` management group SHALL be the highest scope this platform assigns **policy or role
assignments** at, so that the platform's controls never apply to scopes it does not own.

Two things at the Tenant Root Group are permitted, because neither is a control that inherits
downward and both are unavoidable: **parenting** `org` to it, and the **tenant default-management-
group setting**, which exists precisely to keep unplaced subscriptions out of that scope. Anything
else targeting the Tenant Root Group is prohibited.

#### Scenario: No assignment targets the tenant root

- **WHEN** the platform configuration is inspected
- **THEN** no policy assignment and no role assignment has the Tenant Root Group as its scope

#### Scenario: The permitted exceptions are the only ones

- **WHEN** every reference to the Tenant Root Group in the platform configuration is enumerated
- **THEN** each one is either the parent of `org` or the tenant default-management-group setting

### Requirement: Every class of subscription has a defined home

The hierarchy SHALL define, before any subscription exists, where each class of subscription is
placed: `sub-platform` under `platform`; every application-environment subscription under `corp`;
sandbox subscriptions under `sandboxes`; and retired subscriptions under `decommissioned`. Dev and
prod subscriptions SHALL sit under the **same** management group so that one copy of the rules
applies to both and only access differs (`P6`).

#### Scenario: Dev and prod share a management group

- **WHEN** an application's dev and prod subscriptions are later vended
- **THEN** both are placed under `corp`, and any control applied there is exercised in dev as well as
  prod

#### Scenario: Placement is unambiguous for a new subscription

- **WHEN** a new subscription of any defined class is to be created
- **THEN** the hierarchy specifies exactly one management group it belongs under, with no default of
  "wherever it landed"

### Requirement: Management-group names follow the documented convention

Management-group display names and identifiers SHALL use the de-identified names from
`docs/azure-organization.md` (`org`, `platform`, `landing-zones`, `corp`, `sandboxes`,
`decommissioned`) and SHALL NOT encode a real organization, client, tenant, or person.

#### Scenario: Names are de-identified

- **WHEN** the hierarchy configuration is inspected
- **THEN** every management-group name is one of the documented placeholders and no real
  organization name appears
