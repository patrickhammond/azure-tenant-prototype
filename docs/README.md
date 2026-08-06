# docs/

The de-identified platform playbook — the **design authority** for this repository. Adapt the
placeholders (`org`, `example.com`, zero-GUIDs) to your own; never reintroduce a real client, tenant,
person, or subscription ID.

- [`adr/`](adr/README.md) — the 17 architecture decision records (`D1`–`D17`); start at the index.
- [`principles.md`](principles.md) — principles `P0`–`P10`, the tie-breakers every record defers to.
- [`azure-organization.md`](azure-organization.md) — subscriptions, management-group hierarchy,
  resource-group layout, naming, and the platform bootstrap / ownership split.
- [`building-an-application.md`](building-an-application.md) — the new-application checklist and
  go-live gates.

Appendices and the source playbook's client-specific migration state are intentionally omitted;
implementation notes are written as the implementations land.
