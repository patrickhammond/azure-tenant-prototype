## ADDED Requirements

### Requirement: Manual bootstrap of the state backend

The platform SHALL provide a single, documented, re-runnable bootstrap procedure that creates, in
`sub-platform`, exactly the resources OpenTofu cannot create for itself: the resource group, the
state storage account, the platform's own state container, and the Key Vault and key-encryption key
that enforced state encryption requires. It SHALL be executed once by a signed-in human identity
before any OpenTofu runs, SHALL be the **only** infrastructure created outside OpenTofu, and
`platform/README.md` SHALL state its prerequisites, its exact commands, and what it deliberately
does not create.

Alongside those resources it SHALL perform the two prerequisites they cannot exist without, and
nothing else: **registering the resource providers** the subscription needs, and **granting the
operator the data-plane roles** required by the later steps. Neither creates infrastructure, and
both are unavoidable on a fresh subscription.

#### Scenario: First run on an empty subscription

- **WHEN** an operator with the documented permissions runs the bootstrap against a `sub-platform`
  that has no state resources
- **THEN** the resource group, storage account, platform state container, Key Vault, and key-
  encryption key all exist with the required configuration, and the command prints the backend and
  encryption values needed by `platform/`

#### Scenario: Nothing outside the documented set is hand-created

- **WHEN** the bootstrap has completed and the resources in `sub-platform` are compared against the
  set named in this requirement
- **THEN** no additional resource exists that was created outside OpenTofu

#### Scenario: Re-run is a no-op

- **WHEN** the bootstrap is run a second time against a subscription where it has already succeeded
- **THEN** it completes successfully, creates and deletes nothing, and reports that each resource
  already exists

#### Scenario: Partial failure is recoverable

- **WHEN** a bootstrap run fails after creating the resource group but before creating the container
- **THEN** re-running it creates only the missing resources and leaves the existing ones untouched

### Requirement: State backend uses identity, never keys

Access to the state storage account SHALL be authorized by Entra identity. Shared-key authorization
SHALL be disabled on the account, which also disables account and service SAS since both are signed
with the account key. No access key, connection string, or SAS token SHALL appear in the repository,
in a pipeline, or in the backend configuration (`P3`, `D8`).

*Note:* a user-delegation SAS remains possible, because it is signed by an Entra identity the caller
already holds and grants nothing that identity does not already have. `P3` prohibits standing
credentials, not Entra-backed delegation.

#### Scenario: Shared-key access is refused

- **WHEN** any caller attempts to authenticate to the state account with an account key, or with an
  account or service SAS signed by one
- **THEN** the request is refused by the account configuration, regardless of the caller's identity

#### Scenario: Backend authenticates as the signed-in operator

- **WHEN** an operator with the required data-plane role runs `tofu init` in `platform/` with no
  credentials configured
- **THEN** the backend authenticates via their signed-in Entra identity and initializes successfully

#### Scenario: No credential material in the diff

- **WHEN** the change is inspected before commit
- **THEN** no access key, connection string, SAS token, real subscription ID, or tenant ID is present

### Requirement: One state container per application-environment

The state account SHALL hold one container per application-environment plus one for the platform, so
that a state boundary exists for every apply identity that will later be created. Containers SHALL
be named to identify their application and environment unambiguously, and no two
application-environments SHALL share a container (`P5`, `P6`, `D8`).

#### Scenario: Containers exist for every planned scope

- **WHEN** the platform OpenTofu has been applied
- **THEN** a distinct container exists for the platform and for each of `lemon-dev`, `lemon-prod`,
  `lime-dev`, and `lime-prod`

#### Scenario: A new application-environment adds a container, not a key prefix

- **WHEN** a further application-environment is introduced
- **THEN** it receives its own container rather than an additional key within an existing one

### Requirement: State and plan artifacts are encrypted client-side

The `platform/` root SHALL configure OpenTofu state and plan encryption with `enforced = true`, so
that an unencrypted state or plan file is rejected rather than silently written (`D8`). The
key-encryption key SHALL be held in Azure Key Vault and reached through a key provider that
authenticates with Entra ID, so that no passphrase or other stored secret is required to read or
write state (`P3`).

#### Scenario: Enforced encryption rejects unencrypted state

- **WHEN** OpenTofu is asked to read or write state that is not encrypted with the configured method
- **THEN** the operation fails rather than falling back to plaintext

#### Scenario: No passphrase is required anywhere in the loop

- **WHEN** an operator with the required Key Vault role runs `tofu plan` with no encryption
  environment variable set and no secret on disk
- **THEN** the run succeeds, having unwrapped the data key with the operator's own Entra identity

#### Scenario: A caller without the key role cannot read state

- **WHEN** a caller who can read the state blob but holds no role on the key-encryption key attempts
  a `tofu plan`
- **THEN** decryption fails and no state content is disclosed

#### Scenario: Plan files are encrypted too

- **WHEN** a plan is saved to a file for later apply
- **THEN** that file is encrypted with the same enforced configuration

### Requirement: The state account is durable against accidental loss

The state account SHALL have blob versioning and soft delete enabled for blobs and containers, and
SHALL be protected against deletion, so that a mistaken write or delete of state is recoverable.
The Key Vault holding the key-encryption key SHALL have soft delete and **purge protection**
enabled, because destroying that key renders every state file permanently unreadable.

#### Scenario: A deleted state blob is recoverable

- **WHEN** a state blob is deleted
- **THEN** its prior contents remain retrievable for the configured retention period, and restoring
  them returns the byte-identical blob

*Mechanism note:* with versioning enabled, deleting a blob retains the previous content as a
non-current **version** rather than flagging the blob `deleted`. Recovery is therefore "read the
prior version", not "undelete" — verify it that way.

#### Scenario: The account cannot be deleted casually

- **WHEN** a caller attempts to delete the state storage account or its resource group
- **THEN** the attempt is blocked by the configured protection

#### Scenario: The key-encryption key cannot be purged

- **WHEN** a caller deletes the Key Vault or the key-encryption key and attempts to purge it
- **THEN** the purge is refused and the key remains recoverable for the soft-delete retention period

### Requirement: The bootstrapped account is adopted into OpenTofu without drift

The platform OpenTofu SHALL describe the hand-created state resources so that they are managed as
code from the first apply onward. This is the single sanctioned exception to preferring rebuild over
import (`D8`), because rebuilding the account would destroy the state it holds. After adoption,
`tofu plan` for `platform/` SHALL report no changes.

#### Scenario: Plan is clean after bootstrap and adoption

- **WHEN** `tofu init && tofu plan` is run in `platform/` following the documented bootstrap and
  import steps
- **THEN** the plan reports zero changes to add, change, or destroy

#### Scenario: Configuration drift is detected, not absorbed

- **WHEN** the state account's configuration is changed outside OpenTofu
- **THEN** the next `tofu plan` reports the difference rather than silently accepting it
