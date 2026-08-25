# Upstream references

`upstream/instant` is a Git submodule pinned to the exact TypeScript Instant revision used by the cross-SDK compatibility and performance contract:

```bash
git submodule update --init --recursive upstream/instant
git -C upstream/instant rev-parse HEAD
# e71017612aed4031710a35e2fcace30d38d557ac
```

The pin is deliberate. Release comparisons must not silently move when upstream `main` changes. A reference refresh is a reviewed compatibility change that updates the gitlink, TypeScript package contract, fixtures, release evidence, and measured baselines together.

The current upstream repository has continued beyond this compatibility pin. Audit newer Reactor, persistence, React Native storage, query, and self-hosting changes separately; do not mix a moving TypeScript target into a Swift optimization run.

SQLiteData and historical Swift experiments remain optional source references rather than package dependencies:

```bash
git clone https://github.com/pointfreeco/sqlite-data.git upstream/sqlite-data
git -C upstream/sqlite-data checkout 0c79d7a5748fc6d9ce7a1ba2b50f31b175305049
```

| Directory | Repository | Reference commit | Purpose |
| --- | --- | --- | --- |
| `instant` | `https://github.com/instantdb/instant.git` | `e71017612aed4031710a35e2fcace30d38d557ac` | Reproducible TypeScript client, Reactor, query/store, persistence, tests, and benchmark reference. |
| `sqlite-data` | `https://github.com/pointfreeco/sqlite-data.git` | `0c79d7a5748fc6d9ce7a1ba2b50f31b175305049` | Point-Free API, observation, testing, and application-architecture reference. |
| `sharing-instant` | `https://github.com/technoplato/sharing-instant.git` | `d78601a` | Historical Swift Sharing + Instant experiment. |
| `instant-ios-sdk` | `https://github.com/technoplato/instant-ios-sdk.git` | `304677c` | Historical Swift Instant SDK experiment. |

Normal SwiftPM consumers do not compile the submodule. Repository CI and contributors clone it only for compatibility, correctness, and performance work.
