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

**Bootstrap.** The state storage account is created **once, by hand**, before anything else — it
cannot store the state of the OpenTofu that would create it. Then the platform pipeline runs, then
applications onboard.

> **Monorepo for now.** The platform lives in the shared prototype repo for convenience. The intent
> is that once the prototype settles, the platform can move to its **own repository**, separate from
> the applications it serves — the boundary between platform-owned and application-owned resources is
> already drawn (`../docs/azure-organization.md`).
