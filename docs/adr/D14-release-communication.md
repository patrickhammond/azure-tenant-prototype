# D14 · Release communication

**Status:** Accepted · **Group:** Adoption

## Decision

**Deploy continuously; release deliberately.** Feature flags separate the two. The internal audience
is technically literate, so we ship frequently with short asynchronous notice and reserve people's
time for changes that alter how they work.

| Class | Examples | Communication | Training |
| ----- | -------- | ------------- | -------- |
| **Silent** | Bug fixes, performance, refactors | Nothing. The GitHub release is the record | None |
| **Notice** | UI changes, new optional feature, new field | Post in the application's channel and in-app "what's new" on next sign-in, at release, not before | None |
| **Training-required** | Workflow changes, changed permissions, anything altering how someone works | The above, plus a named owner | Ships dark behind a feature flag. Enabled when the material exists, not on a calendar |
| **Launch** | A new application | Readiness checklist | Full |

**The gate is readiness, not lead time.** A training-required change is enabled once the
quick-reference exists on the SharePoint site and the champion has seen it — that can be the same
afternoon, and it must never become a deploy freeze.

## Required

- **Release notes are the post in the application's channel**, written in outcomes rather than
  commits. No separate changelog file; GitHub Releases keeps the history.
- One named **change owner** on our side, and one **champion** inside the user group.
- **One channel per application** (Slack or Teams, whichever that group reads) carrying every
  Notice-and-above change.
- **One SharePoint site per application** holding the user guide, quick-references, and recorded
  walkthroughs. Recordings are made in Teams or Clipchamp; no external tools (`P0`).

## Launch readiness

Items, not dates: quick-reference and recorded walkthrough published; champion has reviewed both;
in-app first-run guidance for the Guest and first-time-user states (`D1`); support path published and
staffed for the first week; announcement posted; impact dashboard live (`D15`); operations document
complete (`D13`). Check in after two weeks.
