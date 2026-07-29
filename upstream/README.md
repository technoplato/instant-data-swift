# Upstream References

These optional local checkouts are source material for developing Instant Swift
Data. They are not package dependencies and are deliberately not Git submodules:
SwiftPM recursively fetches a package's submodules, which would make every Scribe
build download large reference repositories and would make public installation
depend on access to historical experiments.

Clone only the reference you need:

```bash
git clone https://github.com/instantdb/instant.git upstream/instant
git -C upstream/instant checkout e71017612aed4031710a35e2fcace30d38d557ac

git clone https://github.com/pointfreeco/sqlite-data.git upstream/sqlite-data
git -C upstream/sqlite-data checkout 0c79d7a5748fc6d9ce7a1ba2b50f31b175305049
```

The historical Swift experiments are reference-only. Instant Swift Data does not
depend on them, and a normal local checkout should not clone them.

| Directory | Repository | Reference commit | Why it may be cloned locally |
| --- | --- | --- | --- |
| `instant` | `https://github.com/instantdb/instant.git` | `e7101761` on `main` | InstantDB TypeScript client, website examples, recipes, tests, schema, presence, storage, streams, and triple-store behavior. |
| `sqlite-data` | `https://github.com/pointfreeco/sqlite-data.git` | `0c79d7a` on `main` | SQLiteData API and example apps to port, including Reminders, SyncUps, CloudKitDemo, and CaseStudies. |
| `sharing-instant` | `https://github.com/technoplato/sharing-instant.git` | `d78601a` on `master` | Historical Swift Sharing + Instant integration work; reference only. |
| `instant-ios-sdk` | `https://github.com/technoplato/instant-ios-sdk.git` | `304677c` on `main` | Historical Swift Instant SDK work; reference only. |

The transferred plan also references a local-only path named
`swift-sharing-instant-ship`; that checkout was not present on this machine and
no `technoplato/swift-sharing-instant-ship` GitHub repository was found.
