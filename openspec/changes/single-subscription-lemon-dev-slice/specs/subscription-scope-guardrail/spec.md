## ADDED Requirements

### Requirement: Subscription-scoped privileged grants are denied

Policy SHALL deny the assignment of **Owner**, **Contributor**, and **User Access Administrator** at
subscription scope. With one subscription and resource groups as the isolation boundary, a
subscription-scoped grant of any of these silently dissolves every boundary the platform relies on.

#### Scenario: A subscription-scoped privileged assignment is refused

- **WHEN** an assignment of Owner, Contributor, or User Access Administrator at subscription scope is
  attempted
- **THEN** it is denied by policy

#### Scenario: Resource-group-scoped assignments are unaffected

- **WHEN** a role is assigned at resource-group scope
- **THEN** the assignment succeeds, because the guardrail constrains scope rather than forbidding
  delegation

### Requirement: Tampering with the guardrail raises an alert

An alert SHALL fire when the guardrail's policy assignment is deleted or exempted. The guardrail can
be removed by anyone holding subscription Owner, so its own removal is a monitored event rather than
a silent one.

#### Scenario: Removal is detected

- **WHEN** the guardrail's policy assignment is deleted or an exemption is created for it
- **THEN** an alert fires

### Requirement: The residual risk is recorded, not implied

The platform SHALL state plainly what the guardrail does and does not guarantee: **accidental broad
grants are prevented, deliberate ones are detected, and a determined subscription Owner is not
stopped.**

Azure offers no stronger control the platform can adopt here — genuine deny assignments are not
directly creatable, and the mechanism that creates them would introduce a second
infrastructure-as-code toolchain contrary to `D8`. Because the guarantee is partial, it SHALL be
documented as an accepted risk with the conditions that would prompt revisiting it, rather than
described in terms that imply a boundary the platform does not have.

#### Scenario: The limitation is discoverable

- **WHEN** a reader follows `P5` to the residual risk
- **THEN** they find what still holds by construction, what compensates at the scope layer, what
  remains exposed, and when to revisit it

#### Scenario: No document overstates the guarantee

- **WHEN** the principles and the organization document are read together
- **THEN** neither claims that scope isolation is enforced against a subscription Owner
