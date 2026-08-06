# D1 · Identity and access

**Status:** Accepted · **Group:** Foundations

## Decision

Control plane and data plane are separate systems; never conflate them. The tenant is on **Entra ID
Free**, deliberately (see the operating constraint in the ADR index). Assigning a security group to
an app role requires Entra ID P1, which we do not hold, so we assign users individually and reconcile
from groups by a platform job (`D3`). Assigning a group to an Azure RBAC role needs no paid tier, so
the control-plane rules below are unaffected. How these pieces combine into per-application RBAC
without P1 is walked through in
[`../entra-free-and-per-app-rbac.md`](../entra-free-and-per-app-rbac.md).

## Required — control plane

- All Azure RBAC is assigned to **Entra security groups, never to individuals**.
- **One group per application per environment.** No group spans environments.
  `lime-dev-contributors` and `lime-prod-contributors` have different membership and different
  approval. This is how `P6` is enforced.
- Built-in, job-function roles at the narrowest workable scope. **Owner** is limited to emergency
  access and platform, capped at three per subscription.
- **Two or more emergency-access accounts**, cloud-only on `*.onmicrosoft.com`, phishing-resistant
  passkeys (FIDO2), authenticators stored separately, tested on a schedule.
- **Security Defaults on**: MFA registration for everyone, MFA for the admin roles, legacy
  authentication and device-code flow blocked, MFA on the portal and CLI.

## Required — data plane

- Users authenticate via **Entra OIDC**.
- Authorization uses **app roles**: three to seven coarse, stable, string-named roles emitted in the
  `roles` claim.
- **`appRoleAssignmentRequired = true`** on every enterprise application, so a user with no
  assignment cannot obtain a token for it. Unlike group assignment, this needs no paid tier.
- Anything finer than a role — e.g. *which specific records* a user may act on — is resolved **inside
  the application from its own data**. Never in the token.
- **Never read the `groups` claim.** Authorize on roles. Group membership is an input to
  provisioning, not authorization. Reading groups also fails outright for the most senior people (who
  exceed the token's group limit), and never in testing.
- An **absent `roles` claim is a Guest**, never an error and never an implicit grant.

## The Guest state is designed

A user without a role gets a page naming the application, its owner, and a request-access action
pointing at the grant procedure in its operations document (`D13`). Where the application holds
**Restricted** data (`D6`), Guest sees the request path and nothing else.

## Accepted risk

Whoever can write to production can do so at any time — everyone in a production contributor group
holds that access continuously rather than requesting it per task with expiry. Making access
request-and-approve would need Privileged Identity Management (Entra ID P2). We compensate
structurally: administrator identities separate from everyday accounts, resource-group scope where it
works, a small production contributor group reviewed quarterly, and the audit trail (`D11`) catching
after the fact what we cannot gate before.

**Revisit** when an application takes on regulated data, or the team grows past the point where
everyone with production access is known to everyone else.
