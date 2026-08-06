# .github/workflows/

CI/CD (`D9`). **One deployment pipeline per application** (e.g. `lemon.yml`, `lime.yml`), each
triggered by changes under its application's path, plus a platform pipeline for shared infrastructure.

Every pipeline authenticates to Azure with **OIDC workload-identity federation — no stored
credentials**. On deploy it: builds the image and captures its digest, runs migrations to a terminal
state where the schema changed (`D7`), then `tofu apply` with that digest. **Promotion to prod
re-applies the same digest**, never a rebuild.

Branch → environment (GitFlow): `develop` / `release/*` → dev; `main` → prod behind a reviewer gate;
`hotfix/*` → prod under the same gate. Each apply identity's federated credential is scoped to a
**GitHub Environment**, never a branch.
