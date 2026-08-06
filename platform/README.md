# platform/

The shared platform — infrastructure that exists **once** and underpins every application. It is
created by the platform pipeline before any application onboards (`D3`; ownership split and bootstrap
in [`../docs/azure-organization.md`](../docs/azure-organization.md)).

OpenTofu (`azurerm`) for:

- the management-group hierarchy and subscriptions;
- the shared container registry;
- the DNS zone (`example.com`);
- Log Analytics workspaces and the SQL logical servers with each application's **empty** database;
- the OpenTofu remote-state storage account;
- the access-reconciliation job (`D1`, `D3`);
- each application's GitHub deploy identities and federated credentials (`D9`).

> **Monorepo for now.** The platform lives in the shared prototype repo for convenience. The intent
> is that once the prototype settles, the platform can move to its **own repository**, separate from
> the applications it serves — the boundary between platform-owned and application-owned resources is
> already drawn (`../docs/azure-organization.md`).

**Region.** The platform is deployed to a single region, **`eastus`** (`eus` in resource names). To
use another, set `location` and add its abbreviation to `location_short_map` in `locals.tf`.

---

## Bootstrap

The state storage account cannot store the state of the OpenTofu that would create it. One hand-run
script resolves that, then everything else is code.

### What the bootstrap creates — and what it does not

It creates **exactly four things**, each of which OpenTofu needs before it can run at all:

| Created by hand | Why it cannot be OpenTofu |
| --------------- | ------------------------- |
| `rg-platform-tfstate-eus` | Holds the rest |
| The state storage account | Cannot store the state of the code that creates it |
| Container `tfstate-platform` | The backend must exist before `tofu init` |
| Key Vault + RSA key `tofu-state-kek` | `enforced = true` encryption means state cannot be written without a key to wrap it with |

Everything else is OpenTofu: the per-application state containers, the `CanNotDelete` lock, and the
whole management-group tree. The four above are then **adopted** by the import blocks in
`imports.tf`, so they are managed as code from the first apply onward.

### Prerequisites

- The `az` CLI and OpenTofu (see `.tofu-version`; `~> 1.12` is a hard floor — earlier versions lack
  the `azure_vault` state-encryption key provider and cannot read this state at all).
- An existing `sub-platform` subscription.
- Signed in as a **human identity** (`az login`) — the script grants that identity the data-plane
  roles the rest of the run needs, so it cannot run as a service principal.
- **Owner** on `sub-platform` for the duration of the bootstrap (it creates role assignments).
- At the Tenant Root Group, for the `tofu apply` that follows (not for the script itself):
  - **Hierarchy Settings Administrator** — the *only* built-in role carrying
    `Microsoft.Management/managementGroups/settings/write`, which the default-management-group
    setting needs. Management Group Contributor does **not** include it, and neither does the
    "Access management for Azure resources" elevation, which grants `Microsoft.Authorization/*`
    rather than `Microsoft.Management/*`.
  - **Management Group Contributor** — for managing the tree itself. Note that creating management
    groups does not strictly require it: by default any user in the tenant may create one.

Both elevated permissions are held for the bootstrap and then relinquished. Nothing in steady-state
operation needs tenant-root rights.

### Procedure

```bash
./bootstrap/bootstrap.sh --subscription <sub-platform-id>
```

It is safe to re-run: every step checks for existence first, so a partial failure is repaired by
running it again, and a complete run a second time changes nothing.

The first run also registers the `Microsoft.Storage`, `Microsoft.KeyVault`, and
`Microsoft.Management` resource providers, which a fresh subscription does not have. This is worth
knowing because the failure it prevents is badly mislabelled: creating a storage account under an
unregistered `Microsoft.Storage` returns **`SubscriptionNotFound`**, which sends you looking at the
subscription — the one thing that is definitely fine.

The script prints the contents of two files. Write them into `platform/`:

- **`backend.hcl`** — completes the partial backend block in `backend.tf`
- **`terraform.tfvars`** — the input variables

Both are **git-ignored**: they carry real tenant, subscription, and resource names, and this
repository is published (`../AGENTS.md`). The committed `backend.hcl.example` and
`terraform.tfvars.example` show the shape with placeholders.

Then:

```bash
tofu init -backend-config=backend.hcl
tofu plan     # adopts the four bootstrapped resources, creates the rest
tofu apply
tofu plan     # must report zero changes
```

That final clean plan is the goal — it means the hand-built resources and the code agree.

### No secret anywhere in the loop

State and plan encryption use OpenTofu's `azure_vault` key provider, which **always authenticates
with Entra ID**. There is no passphrase, no `TF_ENCRYPTION` export, and nothing to store or leak
(`P3`). Running OpenTofu needs **Key Vault Crypto User** on the key; only the bootstrap needs
**Crypto Officer**.

The key is RSA in a standard vault, not symmetric — `azure_vault` supports symmetric keys only in
Managed HSM, whose monthly floor breaches `P1` by three orders of magnitude.

> **The vault is a tier-0 asset.** Destroy `tofu-state-kek` and **every** state file becomes
> permanently unreadable — for every application, in every environment. Purge protection is enabled
> and is irreversible, which is deliberate. Key rotation means re-encrypting existing state, not
> just adding a key version; it gets its own change if a policy ever demands it.

### Cost

| Item | Approximate monthly cost |
| ---- | ------------------------ |
| Storage account (LRS, a few MB of state, versioned) | < $0.10 |
| Key Vault (standard) + a few thousand wrap/unwrap operations | < $0.10 |
| Management groups, resource lock | free |
| **Total** | **well under $1** |

No Managed HSM, no private endpoint. Comfortably inside the `$30/month` per-application ceiling
(`P1`), which this shared substrate barely touches.
