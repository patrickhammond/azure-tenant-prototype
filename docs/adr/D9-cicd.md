# D9 · CI/CD

**Status:** Accepted · **Group:** Delivery

## Decision

**GitHub Actions**, authenticating to Azure with **OIDC workload-identity federation**. **No Azure
credentials are stored in GitHub, ever.** Branching follows **GitFlow**.

| Branch | Purpose | Deploys to |
| ------ | ------- | ---------- |
| `feature/*` | Work in progress | Nothing. PR runs build, test, and plan |
| `develop` | Integration | Development, on merge |
| `release/*` | Stabilization | Development, on push |
| `main` | Production | Production, on merge, behind a reviewer gate |
| `hotfix/*` | Urgent production fix | Merges to `main`, deploys under the same gate |

## Required — the gate

- **Two identities per environment:** a `plan` identity with Reader, and an `apply` identity with
  least-privilege write. Separation is enforced by Azure RBAC, not by which command the workflow runs.
- Each apply identity's **federated credential is scoped to a GitHub Environment, never to a branch**.
- The GitHub Environment carries the **deployment branch policy**: dev permits `develop` and
  `release/*`; prod permits `main` only.
- **Production requires a reviewer; development does not.**
- Third-party actions **pinned to a commit SHA**.

A workflow on `develop` therefore cannot obtain a production token, and a contributor cannot edit
around it. **Urgency does not remove the gate.**

## Required — what an application contains

Four things, in fixed locations, so any engineer can find them:

| Path | Holds | Record |
| ---- | ----- | ------ |
| `infra/` | This application's OpenTofu, mostly a call into `app-standard` | `D8` |
| `.github/workflows/` | One deployment pipeline, and only one | `D9` |
| `docs/operations.md` | The headings in `D13` | `D13` |
| `docs/decisions/` | Records for anything this application does differently | `D13` |

> **Monorepo adaptation.** The playbook assumes one repository per application. In this monorepo each
> application lives under its own directory (e.g. `apps/lime/` with its `infra/` and `docs/`), and
> the single `.github/workflows/` directory holds **one pipeline per application** (e.g.
> `lime.yml`), each triggered by changes under its app's path. The "one pipeline per application,
> only one" rule holds per application; the fixed locations become per-app subtrees.

## Required — one pipeline per application, OpenTofu as its last step

Every deployment:

1. **Build the image** and publish it to the registry. **Capture the digest.**
2. **Migrate**, where there is a schema change, waiting for a terminal state (`D7`).
3. **`tofu apply`**, passing that digest as a variable.

The image always exists before OpenTofu references it, so there is **no first-run special case, no
placeholder image, and no `ignore_changes` rule**.

**Promotion is a re-apply, not a rebuild.** Merge to `main` applies the **same digest** to
production. A rebuild produces different bits than the ones tested, however identical the source
looks.

## Tradeoff

Every deployment runs a full plan and apply, so routine changes take longer and unrelated drift
surfaces at deploy time. At a small number of applications that buys one pipeline shape, one tool,
and one audit trail.

**GitFlow governs deployment; feature flags govern release (`D14`).** Merging to `main` deploys the
code; flipping a flag releases the behavior.
