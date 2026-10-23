# Plan: an upload keeps no copy of its file, and copies already kept can go once the server holds them (#959)

- **planId:** `2026-10-23-storage-959`
- **agentId:** `claude-code/storage-959@ld`
- **Role:** mower, ordered for #959 (part of #1005): the file store stops growing with every upload.
- **Branch:** `agent/claude/storage-959`, from `main` (`6e4ecd74`); each green step lands on `main`, then a patch tag.
- **Outcome:** `uploadFile` with a storage transport records the stored file (id, name, size) and keeps no copy of
  its bytes, as upstream `StorageAPI.uploadFile` keeps none. Before: every upload was copied into
  `apps/files/<app>/<file>/` and kept for good; on one device that was 3,754 files and 25.9 GB of logical size, of
  which 10.8 GB were real blocks (an app wrote each file, the store cloned it, the app deleted its own) and the rest
  APFS clones of files the app still holds. Copies kept before this change go through a new
  `evictStoredFiles(ids:)`, only once storage's own `$files` record of each holds the same size.

## Steps (no code here)

1. Red: an upload through a storage transport leaves no file in the store and a record that is not downloaded;
   `storedFileContents` and `downloadStoredFile` of that record download it by its stored name; `storageSnapshot`
   counts held copies only; a local-only client still keeps its copy (the only one).
2. Green: `SQLitePersistenceStore.saveUploadedFileRecord` beside `saveStoredFile`; readers check `isDownloaded`.
3. Red, then green: `evictStoredFiles(ids:)` removes a held copy whose `$files` record (by id, through the live
   socket) has the same size, keeps the record, reports the bytes the volume got back (APFS private size); keeps a
   copy whose record is missing or differs, every copy of a local-only client, and throws when the socket is closed.
4. Focused storage suites through heavy.sh; CHANGELOG; PROGRESS; a patch tag.

## Touching

- `Sources/InstantSwiftDataCore/InstantRuntime.swift` (the stored-file functions only)
- `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` (the stored-file functions only)
- `Sources/InstantSwiftDataCore/InstantFileModels.swift`
- `Sources/InstantSwiftData/InstantSwiftData.swift` (one operation)
- `Tests/InstantSwiftDataCoreTests/InstantStorageRuntimeTests.swift`, `InstantStoredFileDownloadTests.swift`,
  `InstantStorageSnapshotTests.swift`, `InstantStoredFileEvictionTests.swift` (new)

## Conflict check

- #1007 edits `InstantStore` publication and the server apply; #1006 the prune and gate entries; #1011 meter lines
  in `SQLitePersistenceStore`: none of them touch the stored-file functions. Tag order with #1007 is in the app
  repository's channel `2026-10-23-instant-pin-959-1007`.
