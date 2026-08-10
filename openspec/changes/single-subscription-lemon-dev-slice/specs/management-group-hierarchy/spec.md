## REMOVED Requirements

### Requirement: The tenant scope tree is defined as code

**Reason**: The platform targets exactly one subscription and no management-group hierarchy. A tree
whose purpose is to organize many subscriptions and to give policy a ceiling above them has nothing
left to organize.

**Migration**: Policy is assigned at subscription scope instead. Isolation moves to resource groups
and the roles scoped to them (`application-scaffolding`), with subscription-scoped privileged grants
denied (`subscription-scope-guardrail`). The six management groups still exist in the live tenant and
are removed by a separate change — deleting them has an ordering dependency, because the platform
subscription is currently placed under one of them and the tenant default-management-group setting
points at another.

### Requirement: Nothing arrives at the Tenant Root Group by accident

**Reason**: The setting exists to catch *newly created* subscriptions. No further subscriptions will
be created, so it protects against an event that cannot occur.

**Migration**: None needed for new subscriptions. The one placement concern this requirement was
extended to cover — that no subscription sits directly at the Tenant Root Group — becomes moot when
the hierarchy is removed and the subscription returns to the root by definition.

### Requirement: Policy has a ceiling below the tenant root

**Reason**: The ceiling was the `org` management group, which is being removed. With one subscription,
the subscription is itself the ceiling: policy assigned there applies to everything the platform owns
and nothing it does not.

**Migration**: Assign policy at subscription scope. The rule this requirement protected — that the
platform never assigns policy or roles at a scope it does not own — still holds, and now holds
trivially.

### Requirement: Every class of subscription has a defined home

**Reason**: There is one subscription and no homes to assign. Application-environment separation is
now expressed by resource group, not by placement in a tree.

**Migration**: `application-scaffolding` defines where each application-environment's resources live.
The principle this encoded — that dev and prod sit under the same rules and differ only in access —
survives as the per-environment shared plane plus resource-group-scoped RBAC.

### Requirement: Management-group names follow the documented convention

**Reason**: No management groups, no names to govern.

**Migration**: The resource-group naming convention in `docs/azure-organization.md` carries the
de-identification requirement forward. It applies to every resource group this platform creates.
