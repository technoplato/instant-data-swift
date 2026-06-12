# Upstream References

These checkouts are local source material for building Instant Swift Data.
They are intentionally kept under `upstream/` so implementation work can compare
against the TypeScript client, SQLiteData examples, and prior Swift Instant
experiments.

| Directory | Repository | Ref checked out | Why it is here |
| --- | --- | --- | --- |
| `instant` | `https://github.com/instantdb/instant.git` | `e7101761` on `main` | InstantDB TypeScript client, website examples, recipes, tests, schema, presence, storage, streams, and triple-store behavior. |
| `sqlite-data` | `https://github.com/pointfreeco/sqlite-data.git` | `0c79d7a` on `main` | SQLiteData API and example apps to port, including Reminders, SyncUps, CloudKitDemo, and CaseStudies. |
| `sharing-instant` | `git@github.com:technoplato/sharing-instant.git` | `d78601a` on `master` | Prior Swift Sharing + Instant integration work referenced in the planning chat. |
| `instant-ios-sdk` | `git@github.com:technoplato/instant-ios-sdk.git` | `304677c` on `main` | Prior Swift Instant SDK work to fold into this single-package design. |

The transferred plan also references a local-only path named
`swift-sharing-instant-ship`; that checkout was not present on this machine and
no `technoplato/swift-sharing-instant-ship` GitHub repository was found.
