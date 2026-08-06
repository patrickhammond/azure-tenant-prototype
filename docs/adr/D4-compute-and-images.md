# D4 · Compute and images

**Status:** Accepted · **Group:** The application

## Decision

**Azure Container Apps**, workload-profiles (v2) environment, Consumption profile, one environment
per subscription. **One shared Azure Container Registry in `sub-platform`** with per-application
repository namespaces.

## Required

- **`minReplicas: 0`** by default.
- Image pull via **user-assigned managed identity**, scoped by an **ABAC condition** to the
  application's namespace. An assignment without a condition is registry-wide, which defeats `P5`.
- The **ACR admin account stays disabled**.
- Batch and scheduled work runs as **Container Apps Jobs**, not a permanently running app.
- **Deploy by digest, never by tag.**
- Pair any **non-HTTP workload** with an explicit scale rule or a Job. With ingress disabled and no
  scale rule, an application scales to zero with no way to wake up.

## Why

A Consumption-profile environment has no fixed monthly fee and each subscription carries a free
grant. One registry in its own resource group means deleting an application never destroys image
history.

## Network posture (the free controls, set at creation)

External ingress with Entra authentication enforced at the platform layer, plus free network
controls on the data tier (Container Apps' built-in auth only works with external ingress, and we
have no VPN — so we choose identity, `P2`). Default is **Tier 0, $0**:

- Entra-only authentication on SQL (no password exists to steal), Key Vault RBAC model, SQL firewall
  deny-all by default, VNet integration + service endpoints (SQL/Key Vault accept the app subnet
  only), and Container Apps IP ingress restrictions.
- **Never** use "Allow Azure services and resources to access this server" — it admits every resource
  in Azure, including other tenants.
- **Decided at creation:** create the environment with a **BYO VNet and a `/27` subnet**; the subnet
  size is immutable afterwards. Retrofitting means recreating the environment.

Move to **Tier 1** (private endpoints on SQL and Key Vault) only for an application holding Restricted
data (`D6`) or where a client requirement names it, and for that application only. Higher tiers force
SKU upgrades that each cost more than everything currently run, so they need a written reason and a
rejected alternative (`P1`).
