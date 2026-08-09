# Follow-on: same-entity outbox supersession (high-churn segments)

**Status:** Deferred until open-segment recipe + Codable JSON land and façade peel
clears the speech path. **Not** required to delete `ScribeInstantStore`, but
required for clean speech performance under multi-× human write rates.

## Problem

Live open-segment speech issues many updates to the **same** segment entity ID
(wordsJSON / text / updatedAtMs). Without supersession, the durable outbox can
queue many pending mutations for one entity, increasing HOL risk and thrash.

## Desired library behavior

When a new outbox mutation **fully replaces** the prior pending mutation for the
same entity primary key (same namespace + id) and operation kind (upsert), drop or
coalesce the superseded pending entry so only the latest local intent remains.

Cite Instant TypeScript `Reactor.js` pending-tx / push behavior before inventing
a novel policy. Document deliberate divergences (Swift SQLite durability).

## Non-goals (for this follow-on)

- Deleting failed terminal mutations without user/agent visibility
- Silencing permission-denied poison
- App-side rate limiting as a substitute for library supersession

## Entry criteria

1. Open-segment write recipe documented and used on Scribe speech path
2. `InstantCodableJSON` / `JSONRepresentation` used for wordsJSON (no silent try?)
3. Completeness lanes (local Instant + network) green under moderate soak

## Related

- ADR 0015 overview 10, plan S2/S5
- Instant issue #155, performance soaks
