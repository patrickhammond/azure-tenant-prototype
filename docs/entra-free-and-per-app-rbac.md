# Appendix · Per-application RBAC on Entra ID Free

**How the reference tenant gives each application its own role-based access control without holding
Entra ID P1.** This is the connective narrative between [`adr/D1`](adr/D1-identity-and-access.md)
(the rules) and [`adr/D3`](adr/D3-shared-platform-components.md) (the job). The ADRs are normative;
this appendix explains how the pieces fit and why the free tier does not cost us per-app authorization.

## The confusion this resolves: "RBAC" is two different systems

The word "RBAC" gets used for two things that live in different planes, are assigned to different
principals, and have different licensing costs. Conflating them is what makes the free tier look like a
blocker when it is not.

| | **Azure resource RBAC** (control plane) | **Application authorization** (data plane) |
| --- | --- | --- |
| Governs | Who can manage Azure resources — deploy, read secrets, restart | What a signed-in user may do *inside* an application |
| Roles are | Azure built-in/custom roles (Reader, Contributor, …) | **App roles** — 3–7 coarse strings you define per app |
| Assigned to | **Entra security groups** | Individual **users** (via the job) |
| Defined on | Subscriptions / resource groups | Each application's **own app registration** |
| Group assignment costs | **Free** — group → Azure role needs no paid tier | Group → app role needs **Entra ID P1** (we don't have it) |
| Isolation | Per app-env subscription + one group each (`P6`) | Per app registration — a role in Lemon says nothing about Lime |

The P1 requirement applies **only** to the right-hand column, and **only** to assigning *groups* to app
roles. Everything on the left is free and unaffected — so control-plane access in `D1` uses groups
directly, exactly as it would with a paid tier.

## Per-app RBAC is isolated by construction

Each application has its **own app registration**, and its coarse roles (`Viewer`, `Editor`,
`Approver`, …) are declared in **that registration's** `appRoles`. Because Entra emits the `roles`
claim from the app-role assignments on the application a token is issued *for*, the claim a user carries
in Lemon is derived from Lemon's assignments alone.

- A user who is `Editor` in Lemon and unassigned in Lime gets `roles: [Editor]` in a Lemon token and a
  **Guest** experience in Lime — no configuration links the two.
- There is no shared "roles" directory to leak across apps: the assignment *is* the per-app boundary.

This is `P5` (isolation by construction) reaching into authorization: separation comes from the topology
of app registrations, not from filtering a shared claim in code.

## The free-tier gap, and the bridge across it

On Entra ID Free you **cannot** assign a *group* to an app role, but you **can** assign a *user* to one,
and you can require an assignment before a token is issued. That is the whole opening the design uses:

1. **`appRoleAssignmentRequired = true`** on every enterprise application. A user with no assignment
   cannot obtain a token for that app at all. (This gate is free — it is not the thing P1 unlocks.)
2. The **access-reconciliation job** (`D3`) is the bridge from the group-based world we *want* to
   express to the individual-user assignments the free tier *permits*. Its configuration maps, per
   application-environment, **source group → app role**. Hourly it reads each group's membership and the
   assignments currently on the app's service principal, computes the difference, and adds/removes
   individual user→app-role assignments to converge. It is idempotent, skips a group it cannot read
   (never interpreting "unreadable" as "empty"), and can grant nothing but app roles.

So group membership stays the single source of truth an operator edits — the job just materializes it as
the per-user assignments the tier requires.

## End-to-end: how a request is authorized

```
define app roles on the app registration            (D1, per-app → isolation)
        │
map source group → app role in job config           (per app-env; P6)
        │
reconciliation job assigns matching users hourly     (D3; group-of-truth → user assignments)
        │
user signs in via Entra OIDC                         (appRoleAssignmentRequired gates token issuance)
        │
token carries the `roles` claim for THIS app only
        │
app authorizes on `roles`  ── absent role ⇒ Guest    (D1; never an error, never an implicit grant)
        │
anything finer than a role resolved from app data    (D1; never from the token)
```

Two rules keep this honest, both from `D1`:

- **Authorize on `roles`, never on `groups`.** Group membership is an input to *provisioning* (the job),
  not to *authorization*. Reading `groups` also fails outright for the most senior people, who exceed
  the token's group limit — and never in testing, only in production.
- **Absent role is a designed Guest**, routed to the request-access path in the app's `operations.md`.

## What it costs us, and when it goes away

- **Latency, not correctness.** A new joiner waits up to the reconciliation interval (hourly) for
  access; removal is bounded the same way, with the audit trail (`D11`) catching the interim after the
  fact. Applications have **no runtime dependency** on the job — if it stops, existing access is
  unaffected.
- **One powerful job instead of many.** The job holds `AppRoleAssignment.ReadWrite.All` (Graph has no
  scoped form), making its identity a **tier-0 asset** — see the accepted risk in `D3`.
- **Reversible by construction.** The day the tenant buys Entra ID P1, the job is **deleted** and the
  same source groups are assigned **directly** to the same app roles. Nothing else in the design —
  per-app registrations, the `roles` claim, `appRoleAssignmentRequired`, Guest — changes. The workaround
  is isolated to the bridge, so removing it is a subtraction, not a migration.

## See also

- [`adr/D1`](adr/D1-identity-and-access.md) — the normative identity/access rules (control vs data
  plane, `roles` claim, Guest).
- [`adr/D3`](adr/D3-shared-platform-components.md) — the reconciliation job and its safety property.
- [`adr/README.md`](adr/README.md) — the Entra ID Free capability table this appendix expands on.
