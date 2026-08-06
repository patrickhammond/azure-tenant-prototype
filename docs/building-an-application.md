# Building an application

The checklist for standing up a new application (or a new environment for one), and the go-live gates
that must be answered before it reaches production. (Playbook Section 5.)

## New application / domain checklist

- Create `sub-<app>-dev` and `sub-<app>-prod` under `corp`. Policy, budget, and diagnostics apply on
  arrival.
- Create the Entra security groups: per application, per environment, none shared, none spanning
  environments (`D1`, `P6`).
- Register the application, define **three to seven app roles**, design the **Guest** state, and add
  the group-to-role mappings to the access-reconciliation configuration (`D1`, `D3`).
- Classify the data model (`D6`). **Decide what is Restricted before any table exists.**
- Provision from the `app-standard` module: Container Apps environment (BYO VNet, `/27` subnet,
  immutable after creation), Key Vault, SQL database, Log Analytics, Application Insights.
- Create the container-registry repository namespace and the ABAC-conditioned pull identity (`D4`).
- Create the DNS records, production and non-production, with managed certificates (`D5`).
- Wire GitHub: branches, `dev` and `prod` environments with branch policies, plan and apply
  identities, federated credentials scoped to the environments, reviewer on `prod` only (`D9`).
- Configure alerts from the standard set and the routing (`D12`).
- Stand up the audit log (`D11`).
- Name the change owner and the champion; create the channel and SharePoint site (`D14`).
- Create `docs/operations.md` and `docs/decisions/` for the app (`D13`), including the go-live
  answers below.
- Agree the impact metrics with the champion and stand up the dashboard (`D15`).
- Run the launch-readiness checklist (`D14`).

## Go-live gates

Several ADRs defer to "the domain" or "the application." Those answers are **gates, not
documentation chores** — each must be answered (in the app's `operations.md`) before launch.

| Question | `operations.md` heading | Why it cannot wait |
| -------- | ----------------------- | ------------------ |
| What data do we hold, and what tier is each sensitive field? (`D6`) | Data | Determines whether a restricted schema and projection boundary are needed. Retrofitting means re-architecting. |
| What is our retention obligation, and who says so? | Data | Drives long-term retention and the audit log's retention floor (`D11`). |
| Who approves each app role, and how is access revoked? (`D1`) | Access | Without it the Guest state has nowhere to send a request. |
| What is our RTO, if not the one-week default? (`D7`) | Data | A tighter target changes the recovery design. |
| What are our impact metrics, and what is the baseline? (`D15`) | Impact metrics | A baseline measured after launch is a story. |
| What runbook covers each alert we configured? (`D12`) | Runbooks | An alert without a runbook should not exist. |

## Launch readiness (`D14`)

Readiness is **items, not dates**: quick-reference and recorded walkthrough published; champion has
reviewed both; in-app first-run guidance for the Guest and first-time-user states (`D1`); support
path published and staffed for the first week; announcement posted; impact dashboard live (`D15`);
operations document complete (`D13`). Check in after two weeks.
