# Deferred hydration must not strand an observation (#259 #274, Scribe)

- `planId`: `2026-09-27-deferred-hydration-progress`
- `agentId`: `claude-opus-5.5-triage-b`
- `role`: grower (P0 user reports from Scribe 0.1 (61))
- `outcome`: `hydrateDeferredValuesIfCurrent` and `hydrateDeferredInfiniteQuerySnapshot` drop an
  emission when the global store sequence moved. The store only re-emits a query whose own rows
  changed, so an unrelated write between emission and hydration strands the observation forever
  (Scribe: "Loading saved transcript…" forever; words missing on a just-finished recording).
  Fix: the store records the sequence of each query's last refresh; a stale emission is dropped
  only when its query was refreshed after it (a newer emission is queued); otherwise it is still
  the query's current result and is hydrated. Metadata/payload revisions still never mix.
- `tests`: deterministic unrelated write between emission and hydration, for a plain observation
  and a local infinite query (red before, green after); existing no-mixing test stays green.
- `touching`: `_touching` entries with `plan=2026-09-27-deferred-hydration-progress`.
