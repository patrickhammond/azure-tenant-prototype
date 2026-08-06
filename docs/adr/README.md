# Architecture decision records

The standard for building and running internal business applications on Azure. New work conforms to
it or argues with it. **Identifiers (`D1`–`D17`) are stable** — regrouping the records will not
renumber them.

These are the de-identified reference version of an internal platform playbook. See
`docs/principles.md` for the principles (`P0`–`P10`) the records defer to, `docs/azure-organization.md`
for the subscription/topology layout, and `docs/building-an-application.md` for the onboarding
checklist and go-live gates.

> **Naming.** This is a public repository. Examples use the two reference applications **Lemon** and
> **Lime**, environments **dev** / **prod**, and the placeholder DNS zone `example.com`. Never
> reintroduce a real client, tenant, person, or subscription ID.

| Group | Records |
| ----- | ------- |
| **Foundations** | [D1 Identity and access](D1-identity-and-access.md) · [D2 Secrets and configuration](D2-secrets-and-configuration.md) · [D3 Shared platform components](D3-shared-platform-components.md) |
| **The application** | [D4 Compute and images](D4-compute-and-images.md) · [D5 DNS](D5-dns.md) · [D6 Data classification](D6-data-classification.md) · [D7 Data, backup, and recovery](D7-data-backup-and-recovery.md) |
| **Delivery** | [D8 Infrastructure as code](D8-infrastructure-as-code.md) · [D9 CI/CD](D9-cicd.md) |
| **Operations** | [D10 Observability](D10-observability.md) · [D11 Audit logging](D11-audit-logging.md) · [D12 Alerting](D12-alerting.md) · [D13 Operations documentation](D13-operations-documentation.md) |
| **Adoption** | [D14 Release communication](D14-release-communication.md) · [D15 Measuring impact](D15-measuring-impact.md) |
| **Beyond a single application** | [D16 Cross-domain integration](D16-cross-domain-integration.md) · [D17 Sandboxes](D17-sandboxes.md) |

## Operating constraint that shapes the foundations: Entra ID Free

The reference tenant runs on **Entra ID Free**, deliberately. Several records (`D1` especially) bend
around what that tier cannot do. The workarounds are the design, not a temporary state:

| Capability | Requires | What we do instead |
| ---------- | -------- | ------------------ |
| Assigning a **group** to an **app role** | Entra ID P1 | Assign users individually, reconciled by a platform job (`D3`) |
| Conditional Access | Entra ID P1 | Security Defaults, tenant-wide (`D1`) |
| Dynamic group membership | Entra ID P1 | Groups maintained explicitly |
| Privileged Identity Management | Entra ID P2 | Structural least privilege, an accepted risk (`D1`) |
| Access reviews | Entra ID P2 | A quarterly manual review recorded in `operations.md` (`D13`) |
| Sign-in log retention beyond 7 days | Entra ID P1 (gives 30) | Application-level telemetry (`D10`, `D15`) |

Assigning an Entra security group to an **Azure RBAC** role is **free**. The P1 requirement applies
to enterprise applications and Entra directory roles, not Azure resource RBAC — so control-plane
access (`D1`) is unaffected; only application authorization has to bend.

How the bend still yields per-application RBAC — without paying for P1 — is walked through end to end
in [`../entra-free-and-per-app-rbac.md`](../entra-free-and-per-app-rbac.md).
