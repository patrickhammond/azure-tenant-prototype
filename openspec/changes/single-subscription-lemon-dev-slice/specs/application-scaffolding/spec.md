## ADDED Requirements

### Requirement: The platform vends resource groups; applications never create them

The platform SHALL create every application-environment's resource groups, empty, with their role
assignments already attached. An application's own configuration SHALL NOT create resource groups.

Creating a resource group requires write at subscription scope, which is exactly the privilege the
subscription-scope guardrail denies to application identities. The resource group is therefore the
unit of vending, playing the role a subscription played before.

#### Scenario: An application-environment is vended before it is built

- **WHEN** a new application-environment is onboarded
- **THEN** the platform has created its resource groups and role assignments, and the application's
  configuration creates only resources inside them

#### Scenario: An application cannot create a resource group

- **WHEN** an application's deploy identity attempts to create a resource group
- **THEN** the attempt fails, because it holds no subscription-scoped write

### Requirement: Every application-environment gets its own isolated objects

Each application-environment SHALL have its own resource groups, SQL logical server, database,
database principal, managed identity, and Key Vault. None of these SHALL be shared with another
application or another environment.

Data SHALL live in a resource group separate from the compute that uses it, so that an application's
compute resource group is safe to delete and rebuild without taking the data with it.

#### Scenario: Nothing is shared across applications or environments

- **WHEN** the resources belonging to two different application-environments are compared
- **THEN** they have no resource group, SQL server, database, database principal, managed identity, or
  Key Vault in common

#### Scenario: Deleting compute does not delete data

- **WHEN** an application-environment's compute resource group is deleted
- **THEN** its database and the data in it still exist

### Requirement: The shared plane is platform-owned and application-writable only by joining

The Container Apps environment and Log Analytics workspace SHALL be shared per **environment**,
owned by the platform, and held in a platform resource group. Application identities SHALL hold no
write access to that resource group.

An application SHALL be able to attach a container app to the shared environment through a role
granting **only** the join action, and SHALL NOT hold any role that permits modifying the shared
environment. A role permitting modification would let one application reconfigure the plane every
other application in that environment runs on.

#### Scenario: An application can attach to the shared environment

- **WHEN** an application's deploy identity creates a container app referencing the shared Container
  Apps environment in another resource group
- **THEN** the deployment succeeds

#### Scenario: An application cannot modify the shared plane

- **WHEN** an application's deploy identity attempts to write to the platform's shared resource group
- **THEN** the attempt fails

### Requirement: The platform creates anything requiring a role assignment

The vending boundary SHALL be: **the platform creates every resource whose use requires a role
assignment; the application creates everything else.** This is not a division of labour chosen for
convenience — it follows from the requirement below, that an application cannot grant itself access.
An application therefore cannot create a resource that only becomes usable once someone grants access
to it.

Concretely, the platform vends the resource groups, the deploy identity, the **runtime identity**, and
the **Key Vault**, together with the assignments binding them. The application creates its SQL
logical server, database, database principal, and container app — none of which require an Azure role
assignment to become usable.

Resources the platform vends SHALL live in a platform-owned resource group, not the application's.
An application holding write access over the group containing its own runtime identity could add
federated credentials to that identity, widening who may assume it; over the group containing its own
Key Vault, it could switch the vault out of role-based access control and grant itself data access.
Both are self-escalation reached through resource configuration rather than through a role assignment.

The application SHALL receive the narrow rights it needs on those resources **scoped to the resource,
never to the group that holds them**.

#### Scenario: An application receives a usable scaffold it did not create

- **WHEN** an application-environment has been vended
- **THEN** its runtime identity and Key Vault exist, the runtime identity can read that vault, and the
  application created neither

#### Scenario: An application cannot reconfigure its vended resources

- **WHEN** an application's deploy identity attempts to modify its own runtime identity or its own Key
  Vault's configuration
- **THEN** the attempt fails, because those resources are in a resource group it has no write access to

#### Scenario: Rights on vended resources are resource-scoped

- **WHEN** the roles an application holds on vended resources are enumerated
- **THEN** each is scoped to an individual resource, and none is scoped to the platform resource group
  containing it

### Requirement: An application cannot grant itself additional access

An application's deploy identity SHALL hold no role that permits creating role assignments, even
within its own resource groups. Escalation SHALL require a platform change.

#### Scenario: Self-escalation is refused

- **WHEN** an application's deploy identity attempts to create a role assignment in its own resource
  group
- **THEN** the attempt fails

### Requirement: Application roots do not read platform state

An application's configuration SHALL resolve what it needs from the naming convention and from data
sources, and SHALL NOT read the platform's OpenTofu state. Reading platform state from an application
root would give every application read access to the platform's state file.

#### Scenario: No cross-root state coupling

- **WHEN** an application's configuration is inspected
- **THEN** it contains no remote-state data source pointing at the platform's state

### Requirement: The boundary is verified by a constrained identity

The application root SHALL be applied by its deploy identity, not by an operator. Verification of the
isolation boundary SHALL be performed as that identity.

An operator holding subscription Owner bypasses every boundary this capability defines, so a
successful apply by an operator demonstrates nothing about whether the boundary exists.

#### Scenario: Verification uses the constrained principal

- **WHEN** the isolation boundary is verified
- **THEN** each check was performed as the application's deploy identity, and the negative checks
  failed as expected rather than being skipped
