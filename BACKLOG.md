# Backlog

How we turn the playbook in [`docs/`](docs/) into a working reference implementation. This is the
**plan of record for what gets built and in what order** — the design authority stays in `docs/`; this
file only sequences the work against it.

Each item below is one **OpenSpec change** (`/opsx:propose` → `/opsx:apply` → `/opsx:archive`). It
names the ADRs it implements and a concrete *done-when*. Keep items thin: a change should be reviewable
and leave `main` deployable.

## Guiding approach

1. **Walking skeleton before breadth.** Get *one* application (Lemon) end-to-end — source → image →
   infra → running URL with auth — through *dev* before adding prod, before adding Lime, and before
   adding the operations/adoption layers. A thin vertical slice flushes out the platform seams early;
   breadth after that is repetition.
2. **Platform is the foundation, and it comes first.** Nothing an app needs (remote state, the
   registry, DNS, the reconciliation job) can be built by an app. Milestone 0 unblocks everything.
3. **Isolation by construction, from the first line.** Never introduce a shared database, identity, or
   security group "for now." Retrofitting isolation is a rebuild (`P5`). The topology in
   [`docs/azure-organization.md`](docs/azure-organization.md) is the target from commit one.
4. **Lime is (mostly) Lemon, parameterized.** Build Lemon's infra so Lime is a values file, not a
   fork. If a second app forces a copy-paste, that is a signal the shared module boundary is wrong.
5. **Every change stays de-identified.** `org`, `example.com`, zero-GUIDs only. Grep the diff before
   every commit (`AGENTS.md`).
6. **The apps are deliberately trivial.** Lemon and Lime are small **Next.js** apps. They exist to
   exercise the platform — auth, data tiers, telemetry, audit, a migration — not to be interesting
   products. Resist scope creep in the app; spend the effort on the platform around it.

Dependency order at a glance:

```
M0 Platform foundation ─┬─> M1 Lemon dev (walking skeleton) ─> M2 Delivery ─> M3 Lemon prod
                        │                                                          │
                        └────────────────────────────────────────> M4 Lime ──────┘
                                                                          │
   M5 Operations ── M6 Adoption ── M7 Beyond one app  <───────────────────┘
```

---

## M0 — Platform foundation

The shared substrate. Until this exists, no app can be deployed. Owned by the platform, lives in
`platform/`. ADRs: `D1`, `D2`, `D3`, `D5`, `D8`; topology in `docs/azure-organization.md`.

- [x] **P-01 · Bootstrap & remote state.** The one-time chicken-and-egg step: create the state storage
      account/container and the management-group hierarchy, then bring `platform/` OpenTofu under its
      own remote state. Document the manual bootstrap in `platform/README.md`.
      *Done when:* `tofu init && tofu plan` for `platform/` runs against remote state with zero drift.
      → `D8`, `azure-organization.md` (bootstrap sequence)
- [x] ~~**P-02 · Subscriptions & management groups.**~~ **Abandoned — the premise was wrong.**
      Subscription creation on this billing account is capped at five per account and one per 24
      hours, so four app subscriptions plus platform is exactly the ceiling with nothing spare, and no
      room for `D17` sandboxes or `D6`'s Restricted store. The platform now targets **one
      subscription and no management groups**. The change is archived as superseded at
      `openspec/changes/archive/2026-08-09-subscription-vending/`, whose proposal preserves what was
      measured. Replaced by P-02a.
- [ ] **P-02a · Single-subscription shape (Lemon dev slice).** Resource groups as the isolation
      boundary inside one subscription: a platform-owned per-environment shared plane, platform-vended
      application resource groups and identities, and a policy guardrail denying privileged role
      assignments outside vended groups. *Done when:* Lemon dev runs end to end and the deploy identity
      is **verifiably unable** to create a resource group, create a role assignment, or write to the
      platform's group. → `D1`, `P5`, `P6`; change `single-subscription-lemon-dev-slice`
- [ ] **P-03 · Shared container registry.** One ACR for all apps, with **ABAC-scoped pull**: each
      app-env identity can pull only its own repository. *Done when:* Lemon's dev identity can pull
      `lemon/*` and is denied `lime/*`. → `D3`, `D4`
- [ ] **P-04 · DNS zones.** Delegated `example.com` with the per-app/per-env record scheme
      (`lemon.example.com`, `lemon.dev.example.com`). *Done when:* zones resolve and app infra can
      add records into its own zone only. → `D5`
- [ ] **P-05 · Identity reconciliation job.** The platform job that assigns users to app roles
      individually (the Entra ID Free workaround for group→app-role) — the *bridge* half of per-app
      RBAC, per [`docs/entra-free-and-per-app-rbac.md`](docs/entra-free-and-per-app-rbac.md).
      *Done when:* a user added to a role's source group appears as an app-role assignment on the next
      run, idempotently. → `D1`, `D3`
- [ ] **P-06 · CI identity & OIDC federation.** *(Lemon dev delivered by P-02a; remaining: prod, Lime,
      and the reviewer gate on prod.)* GitHub↔Azure workload-identity federation, one apply
      identity per app-env, each federated credential scoped to a **GitHub Environment**. *Done when:*
      a workflow can `az login` with no stored secret. → `D2`, `D9`

---

## M1 — Lemon in dev (the walking skeleton)

One application, one environment, end-to-end. This is the milestone that proves the whole chain. ADRs:
`D4`, `D6`, `D7`, `D8`, plus `D1` (login).

- [ ] **L-01 · Lemon Next.js app (skeleton).** A minimal Next.js app in `apps/lemon/`: a home page, a
      health endpoint, and a Dockerfile that produces a standalone image. No data yet. *Done when:* the
      image builds and runs locally. → `D4`
- [ ] **L-02 · Lemon dev infrastructure.** OpenTofu in `apps/lemon/infra/`: Container App
      (Consumption, `minReplicas: 0`), Key Vault (RBAC), and the app's managed identity — all in
      `sub-lemon-dev`. Image referenced **by digest**. *Done when:* `tofu apply` yields a reachable
      `lemon.dev.example.com`. → `D4`, `D2`, `D8`
- [ ] **L-03 · Entra login.** Wire Entra OIDC sign-in; authorize on the **`roles` claim**, absent role
      = Guest — the *runtime* half of per-app RBAC, per
      [`docs/entra-free-and-per-app-rbac.md`](docs/entra-free-and-per-app-rbac.md). Depends on P-05 for
      assignments. *Done when:* an assigned user signs in and sees their role; an unassigned user gets
      the Guest experience. → `D1`
- [ ] **L-04 · Data + the two tiers.** Azure SQL (serverless, auto-pause in dev). Model a **Standard**
      and a **Restricted** data path with separate schema, DB principal, and per-read audit hook — same
      shape it will have in prod. *Done when:* a Standard read and a Restricted read work and the
      Restricted read emits an audit event. → `D6`, `D7`
- [ ] **L-05 · Schema migration job.** Migrations run as a gated job to a terminal state *before*
      `tofu apply` swaps the image. *Done when:* a schema change deploys via migrate-then-apply, and a
      no-op deploy runs zero migrations. → `D7`

*Exit criteria for M1:* Lemon dev is reachable, authenticates real users, reads both data tiers, and
was deployed by digest — all by hand-run `tofu apply`. Delivery automation is M2.

---

## M2 — Delivery pipeline

Automate what M1 did by hand. One pipeline per app; branch→environment by GitFlow. ADR: `D9` (and `D7`
for the migration gate).

- [ ] **CD-01 · Lemon dev pipeline.** `.github/workflows/lemon.yml`, path-triggered: build → capture
      **digest** → migrate → `tofu apply` to dev, via the OIDC identity from P-06. *Done when:* a merge
      to `develop` deploys Lemon dev with no human step. → `D9`
- [ ] **CD-02 · Promotion by digest.** `main` promotes the **exact digest** already tested in dev —
      never a rebuild — behind a reviewer gate on the prod GitHub Environment. (Wires up in M3 when prod
      infra exists.) *Done when:* promotion re-applies a digest with no `docker build`. → `D9`

---

## M3 — Lemon in prod

Prove `dev ≠ prod` is real, not cosmetic. ADRs: `D1`/`P6` (separate access), `D4`/`D7` (prod sizing),
`D9` (gate).

- [ ] **L-06 · Lemon prod infrastructure.** Same OpenTofu, prod values: `sub-lemon-prod`, SQL sized for
      prod (no auto-pause), stricter access, its own Key Vault and identity — **nothing shared with
      dev**. *Done when:* `lemon.example.com` runs and no dev principal can touch it. → `P6`, `D1`, `D7`
- [ ] **L-07 · Gated promotion live.** Turn on CD-02 into prod: reviewer approval, same-digest apply.
      *Done when:* a dev-tested digest reaches prod only through the gate. → `D9`

---

## M4 — Lime (prove the pattern generalizes)

Lime is the reuse test. If M0–M3 were built right, Lime is mostly configuration. ADRs: same as Lemon.

- [ ] **LM-01 · Lime Next.js app.** A second trivial Next.js app — deliberately *different enough*
      (different data shape) to catch things Lemon hard-coded. → `D4`
- [ ] **LM-02 · Lime dev + prod infra.** Reuse Lemon's infra module with Lime values across
      `sub-lime-dev`/`sub-lime-prod`. *Done when:* both environments run with no Lemon-specific
      copy-paste. Any fork needed here is a bug in the shared boundary — fix the module. → `P5`, `D8`
- [ ] **LM-03 · Lime pipeline.** `.github/workflows/lime.yml`, path-triggered, mirroring Lemon.
      *Done when:* Lime deploys independently; a Lemon change never triggers Lime. → `D9`

---

## M5 — Operations

The three measurements, kept separate, plus the docs that gate prod. ADRs: `D10`–`D13`. Per `D13` and
the OpenSpec rule, changes here update the app's `docs/operations.md` in the same change.

- [ ] **OPS-01 · Telemetry.** App Insights / OTel per app-env — the *product/perf* signal. → `D10`
- [ ] **OPS-02 · Audit logging.** Immutable, per-read on Restricted data — the *who-saw-what* signal,
      distinct from telemetry. → `D11`
- [ ] **OPS-03 · Alerting.** Actionable alerts on the telemetry, routed to an owner. → `D12`
- [ ] **OPS-04 · Operations docs.** `apps/<app>/docs/operations.md` for Lemon and Lime — the required
      pre-prod artifact (access, data classes, alerts, dependencies, the quarterly access review). →
      `D13`

---

## M6 — Adoption

Deploy continuously, release deliberately. ADRs: `D14`, `D15` — the third measurement (product metrics),
kept distinct from telemetry and audit.

- [ ] **ADO-01 · Release communication.** Decouple deploy from release (flag/announce path). → `D14`
- [ ] **ADO-02 · Impact metrics.** Product-adoption metrics, separate from `D10` telemetry. → `D15`

---

## M7 — Beyond a single application

Only after two apps run cleanly in isolation. ADRs: `D16`, `D17`.

- [ ] **X-01 · Cross-application integration.** A sanctioned Lemon↔Lime interaction that does **not**
      breach isolation (no shared DB/identity) — integrate at the edge, per `D16`. → `D16`
- [ ] **X-02 · Sandboxes.** The throwaway-environment pattern for experiments. → `D17`

---

## Cross-cutting, every change

- **Cost ceiling.** One whole application, both environments, under **$30/month** (`P1`). Check the
  running estimate as infra lands; scale-to-zero and serverless auto-pause are load-bearing, not
  optional.
- **De-identification.** Grep the diff for real names before committing (`AGENTS.md`).
- **`docs/` wins.** If building something reveals the playbook is wrong or silent, fix `docs/` in the
  same change — don't let code and design authority drift.
- **Deployable `main`.** Every archived change leaves the repo in a plan-clean, deployable state.
