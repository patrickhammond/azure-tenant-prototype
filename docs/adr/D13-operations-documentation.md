# D13 · Operations documentation

**Status:** Accepted · **Group:** Operations

## Decision

Every application's operational documentation lives in the repository, as markdown, at
`docs/operations.md`, with per-application decision records in `docs/decisions/`. **An application
without one is not in production.**

## Required

- The operations document is **updated in the same pull request** as the change that affects it. A
  change to access, data classification, alerting, or dependencies that does not touch
  `docs/operations.md` is sent back.
- **Two homes, two audiences.** GitHub for people who run it; SharePoint, per application (`D14`), for
  people who use it. User documentation must be findable by someone who has never seen a repository.

## Desired headings

- **What it does, and who uses it.**
- **Owner and support path.**
- **Access.** The app roles, who approves each, how a grant is made and revoked, the review cadence,
  and any relationship-based access. Where access spans two systems — an app role in Entra plus an
  assignment table in the application — both halves belong here with an owner named against each.
- **Data.** What is stored, the classification tier of every sensitive field (`D6`), the retention
  obligation and who set it, the RTO if it differs from one week, and the restore procedure with the
  last drill date.
- **Runbooks.** One per alert defined in `D12`.
- **Dependencies and integrations.**
- **Impact metrics and dashboard link (`D15`).**
