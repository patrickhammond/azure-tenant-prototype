## ADDED Requirements

### Requirement: Every application-environment has its own subscription

Each combination of application and environment SHALL have exactly one dedicated Azure subscription,
managed as code. No subscription SHALL be shared between two applications or between two
environments of the same application.

The set of subscriptions SHALL be derived from the same declared list of application-environments
that governs the platform's state containers, so that a new application-environment cannot exist in
one and be absent from the other.

#### Scenario: Each application-environment is isolated by subscription

- **WHEN** the platform configuration is applied
- **THEN** `sub-lemon-dev`, `sub-lemon-prod`, `sub-lime-dev`, and `sub-lime-prod` each exist as
  distinct subscriptions, and no two application-environments resolve to the same subscription

#### Scenario: Adding an application-environment cannot be done by halves

- **WHEN** an application-environment is added to the platform's declared list
- **THEN** the plan proposes both a subscription and a state container for it, rather than allowing
  one to exist without the other

### Requirement: Subscription names follow the documented convention

Subscription display names and alias names SHALL both be `sub-<app>-<env>` as defined by
`docs/azure-organization.md`, and SHALL be identical to each other so that the portal and the
configuration cannot disagree about what a subscription is called. No subscription name SHALL encode
a real organization, client, tenant, or person.

#### Scenario: Name and alias agree

- **WHEN** any subscription managed by this capability is inspected
- **THEN** its display name and its alias are the same string, in the form `sub-<app>-<env>`

#### Scenario: Names are de-identified

- **WHEN** every subscription name in the configuration is enumerated
- **THEN** each uses the placeholder application names, and no real organization name appears

### Requirement: Placement is continuously verified, not set once

Every subscription's management-group placement SHALL be re-evaluated on every plan, so that a
subscription moved out of band is reported as drift. Placement SHALL NOT depend on a value that is
only read when a subscription is created, because such a value cannot detect a later move.

Placement SHALL have exactly one authority in the configuration: the management group for each
subscription is resolved from the hierarchy's existing placement map rather than restated, and no
second mechanism declares the same relationship from the other direction.

#### Scenario: A subscription moved out of band is detected

- **WHEN** a subscription is moved to a different management group outside OpenTofu
- **THEN** the next plan reports the difference, and applying restores the documented placement

#### Scenario: Placement is not defined twice

- **WHEN** the configuration is inspected
- **THEN** each subscription's placement is declared in exactly one place, and no management group
  separately declares its own member subscriptions

#### Scenario: Placement survives a no-op run

- **WHEN** placement has been applied and nothing has changed in the tenant
- **THEN** the next plan is clean, rather than proposing to re-establish placement every run

### Requirement: Application subscriptions are placed under corp

Every application-environment subscription SHALL be placed under the `corp` management group,
regardless of environment, so that one copy of the rules applies to dev and prod alike and only
*access* differs (`P6`).

#### Scenario: Dev and prod share a management group

- **WHEN** placement is applied
- **THEN** all four application-environment subscriptions are children of `corp`, and no
  environment-specific management group exists

#### Scenario: A vended subscription does not remain where it landed

- **WHEN** a newly vended subscription is initially created in the tenant's default management group
- **THEN** applying this capability moves it to `corp`, and it is no longer a child of `sandboxes`

### Requirement: An existing subscription is adopted rather than recreated

A subscription that already exists SHALL be brought under management by import, and SHALL NOT be
cancelled and re-created. Cancelling a subscription to replace it with an identical one destroys a
real subscription, reserves its ID for 90 days, and cannot be fully completed for 72 hours — costs
that adoption avoids entirely.

The import SHALL be verified by a plan showing **no changes** to the imported subscription before any
apply proceeds, so that a configuration mismatch surfaces as a diff rather than as a replacement.

#### Scenario: Adoption produces no changes

- **WHEN** an already-existing subscription is imported and a plan is run
- **THEN** the plan reports no changes for that subscription, and in particular proposes no
  replacement

#### Scenario: Adoption never proposes destruction

- **WHEN** the plan for this capability is reviewed
- **THEN** it contains no destroy or replace action against any subscription

### Requirement: A subscription cannot be cancelled by accident

The configuration SHALL make subscription cancellation unreachable through ordinary tooling, and
SHALL NOT rely on a per-resource lifecycle guard alone. Destroying a managed subscription cancels a
real subscription irrevocably once its reactivation window closes, and its ID is never reusable.

The protection that survives a resource block being deleted SHALL be treated as the primary one. A
per-resource lifecycle guard SHALL additionally be present, and its known limitation — that it
disappears together with the block it is written in — SHALL be recorded alongside it so that it is
not mistaken for complete coverage.

#### Scenario: A forced replacement is refused

- **WHEN** a plan is run that would destroy or replace an existing subscription while its
  configuration is present
- **THEN** the plan fails rather than proposing the destruction

#### Scenario: Protection survives removal of the resource

- **WHEN** a subscription's resource block is deleted from the configuration entirely, so that the
  plan proposes a destroy
- **THEN** applying it does not cancel the subscription

#### Scenario: The limitation is documented, not implied

- **WHEN** the guards are inspected
- **THEN** it is stated that the per-resource guard does not survive deletion of its own block, and
  which guard covers that case instead

### Requirement: Real billing and tenant identifiers stay out of the repository

The billing scope used to vend subscriptions SHALL be supplied through configuration that is not
committed, and SHALL be represented in committed example configuration by an obvious placeholder. A
billing scope that is malformed or does not exist SHALL fail at plan time, before any subscription
is created.

#### Scenario: No real billing identifier is committed

- **WHEN** the repository is inspected
- **THEN** no real billing account, billing profile, invoice section, tenant, or subscription
  identifier appears in any tracked file

#### Scenario: A malformed billing scope fails early

- **WHEN** the billing scope is configured incorrectly
- **THEN** the failure occurs at plan time, before any subscription is created

### Requirement: Subscriptions are created empty

This capability SHALL create subscriptions and their placement only. It SHALL NOT assign roles,
policies, or budgets, and SHALL NOT create resources inside the subscriptions; those belong to later
changes.

#### Scenario: No access is granted by vending

- **WHEN** subscription vending has been applied
- **THEN** no role assignment or policy assignment has been created by this capability, and each new
  subscription contains no resources
