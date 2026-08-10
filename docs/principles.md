# Principles (P0–P10)

The tie-breakers. Every architecture decision record (`docs/adr/`) defers to these when a specific
answer runs out. They are numbered and stable.

| #    | Principle | In practice |
| ---- | --------- | ----------- |
| **P0** | Everything fits inside the organization's approved tooling unless leadership approves a deviation | Microsoft 365, Teams, Slack, SharePoint, Entra, Azure, GitHub. Deviations are approved and recorded with the reason. |
| **P1** | Operational cost is a design constraint | An entire application — all environments and infrastructure — stays under **$30/month**. No line item is judged on its own. |
| **P2** | Access is decided by who you are, not where you connect from | There is no VPN. Network controls are a second layer, never a substitute for authorization. |
| **P3** | No standing credentials | Managed identities and federated identity. A password in a pipeline or on a laptop is a defect. |
| **P4** | Everything is reproducible from source | New work lands this way; existing resources follow as they are rebuilt. |
| **P5** | Isolation is enforced by construction, not convention | Separate applications and environments never share a database, database principal, managed identity, Key Vault, or security group. Sensitivity tiers inside one application share a database but never a database principal (`D6`). Scope isolation is resource-group RBAC, backed by policy that denies subscription-scoped grants — see the residual risk in `azure-organization.md`. |
| **P6** | Access to development does not imply access to production | Different resource groups, security groups, deploy identities, and approval. Development and production never share a Container Apps environment, SQL server, database, identity, or Key Vault. |
| **P7** | We measure for three distinct reasons and never conflate them | Telemetry answers "is it working" (`D10`), audit answers "who did what" (`D11`), product metrics answer "is this worth having" (`D15`). Each has a different owner, retention, and reader. All three are required; no application launches without the third. |
| **P8** | Adoption is part of delivery | Deploy continuously; release deliberately. |
| **P9** | Boring, managed, and default | Take the managed service and the documented default unless there is a specific reason not to. |
| **P10** | No preview features, and nothing with an announced retirement, outside a sandbox | Preview carries no SLA; a retirement is a deadline handed to whoever comes next. Outside a sandbox, either needs a named approver and a recorded fallback. |

## Scope and scale (what these decisions are sized for)

- **Scope.** Internal business applications: serverless containers, small relational databases,
  Entra-authenticated users.
- **Scale.** At most ~100 users at very light use, or ~5 at light use, per system. This drives most
  sizing decisions in the ADRs and is not repeated at each one.
