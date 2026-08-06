# D16 · Cross-application integration

**Status:** Accepted · **Group:** Beyond a single application

## Decision

When one application needs a fact that lives in another, the default is an **app-to-app API call**.
The producer publishes an endpoint; the consumer's workload identity holds an app role on it and
calls with an **app-only token**. No shared database, no shared credential, no copy.

| Option | Verdict |
| ------ | ------- |
| Shared database access | **Never.** Breaks `P5`, and no variant of it does not |
| App-to-app API call | **Default** |
| Published copy | By exception, only when latency or availability requires it |

When a copy is justified, three rules apply **without exception**: it inherits the source's
classification (`D6`); it is recorded in **both** operations documents (`D13`); and the **producing
application owns the shape**, so a consumer cannot reach for a field the producer did not publish.

## Why the API is the default

Cross-application integration is where isolation dies, and never by decision — it is a shortcut under
deadline. A written default means the shortcut argues against a standard rather than filling a vacuum,
and the API leaves the authorization decision with the producer.

**Revisit** when cross-application calls become a mesh. The answer then is a published event stream
with a schema registry, not a weaker isolation rule.
