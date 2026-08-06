# D2 · Secrets and configuration

**Status:** Accepted · **Group:** Foundations

## Decision

**One Azure Key Vault per application per environment**, on the **Azure RBAC permission model**, set
deliberately at creation rather than left to a tooling default. Legacy access policies let anyone
with Contributor on the vault grant themselves data access by rewriting the policy.

## Required — where a value comes from depends on what it is

| Kind of value | Source |
| ------------- | ------ |
| Access to an Azure resource | Managed identity in Azure, signed-in developer locally. **Nothing stored.** |
| A secret that must be stored (e.g. a third-party API key) | **Key Vault** |
| Non-secret configuration | A file **committed** to the repository |
| A credential that only works on one developer's machine | A local `.env`, git-ignored |

`.env` is permitted **only** for the last row. Test: *nothing in a `.env` should still work if the
file were posted publicly.*

## Required — migrating off legacy access policies

Any vault still on the legacy access-policy model moves to RBAC before the vendor's API retirement.
Enabling RBAC stops access policies being honored immediately, so **assign the Azure roles first,
then switch the model** — otherwise you lock yourself out.
