# Plan 2026-10-26-b301-disk-1227: a stored file's copy is found in the store's own files folder after the folder moves

- planId: 2026-10-26-b301-disk-1227
- agentId: claude-code/b301-disk@strangelearning
- role: mower (a fix at its cause; no new API, no stored format change)
- issue: #1227 (related #959, #1095, #1104, #1214)

## Why

A record of a stored file's copy keeps the absolute path the copy had when it was made. iOS moves an app's data
container, and this store's folder with it, when it installs an update. Measured on one device (#1227): 3,844 records
with a copy, 25.44 GB, all naming 14 earlier containers while every file sat at the same place under the current one, the
same size. So `evictStoredFiles(ids:)` answers `.kept(.notHeld)` for every copy, `readStoredFileContents` fails, and
`deleteStoredFile` removes the record and leaves the copy on disk forever; the consuming app's launch cleanup (#959)
removes nothing and logs every copy at every launch (#1095).

## Design

Every copy the store writes is `<files folder>/<app>/<file>/<name>` (`saveStoredFile(_:contentsOf:)`,
`saveDownloadedFile(_:data:)`). `loadStoredFiles(appID:)` and `loadStoredFile(appID:fileID:)`, which every read,
eviction, download and delete goes through, place a held copy whose path is not already in this store's files folder by
its path's last three components. A path already in the folder costs a prefix check. No migration; the stored JSON is
unchanged; a later container move is covered the same way.

## Steps

1. This plan and its claims (plan-only commit on main).
2. Red: `InstantStoredFileMovedStoreTests` (a store with two copies and a record without one, its folder moved, then
   list, read and delete). Measured red on the Mac mini (release, 1.9.42 source): the records name container-1 and the
   read throws.
3. Green: `SQLitePersistenceStore.locatedInFilesFolder(_:)`; the moved-store test and the stored-file, storage and
   store suites on the Mac mini.
4. Release 1.9.43 through the release gate (`scripts/known-failing-tests.sh run/compare` in debug, `InstantSwiftDataTests`
   in debug, `RealSizeBudgetTests` in release), docs/releases/v1.9.43.md, CHANGELOG.md, PROGRESS.md; the consuming app
   pins it.

## Touching

Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift (`loadStoredFiles`, `loadStoredFile`, and the new
`locatedInFilesFolder` only), Tests/InstantSwiftDataCoreTests/InstantStoredFileMovedStoreTests.swift (new),
docs/releases/v1.9.43.md (new), CHANGELOG.md, PROGRESS.md.

## Conflict check

The last claims on SQLitePersistenceStore.swift (fix-storage-1076, fix-memory-1075, 2026-10-25) are released in 1.9.42;
no source commit has landed on main since 1.9.42. Channel agent-presence/_channels/2026-10-26-b301-disk-1227.md.
