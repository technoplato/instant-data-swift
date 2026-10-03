# Plan 2026-10-03-file-download (#454)

- **Agent:** claude-opus-5.5-phone-perf (Scribe's phone-perf), on main's direction, 2026-10-03 (P0).
- **Branch:** `agent/claude-opus-5.5/file-download` from `fe3ad82a` (library-79's 1.9.4 head on
  `library-79-hops`). library-79 merges it after the 1.9.4 tag and releases it as 1.9.5.
- **Why:** Scribe #454. An iPad on Scribe 0.1 (83) played back a recording whose 1,964,275,244-byte audio it did not
  have. `storedFileContents(id:name:)` downloads a file as `Data` (`InstantStorageTransportClient.downloadFile`,
  `URLSession.data`), caches a copy (`SQLitePersistenceStore.saveDownloadedFile`) and returns the `Data`, which
  Scribe wrote again: a 4,384 MB footprint and 3.9 GB more on disk. An iPhone would be killed for memory.
- **Change (grower, one public API):**
  - `InstantStorageHTTPClient.downloadToFile` (live: a `URLSession` download task), `InstantStorageHTTPFileResponse`.
  - `InstantStorageTransportClient.downloadToFile` and `downloadFileToFile` (temporary files the caller owns); the
    existing initializers build them from their data downloads, so custom transports keep working.
  - `InstantRuntime.downloadStoredFile(id:name:to:)` and `InstantSwiftDataClient.downloadStoredFile(id:name:to:)`:
    stream to a temporary file and move it to the destination; no `Data`, no copy of the library's own; a file the
    library already holds is copied file to file.
  - `storedFileContents` is unchanged.
- **Tests:** `Tests/InstantSwiftDataCoreTests/InstantStoredFileDownloadTests.swift` (the old path holds every byte and
  caches a copy; the new path never calls a data download, keeps no copy, leaves no temporary file; a held file copies
  without a download; a failed download leaves the destination as it was; a data-only transport still works).
- **Evidence kinds:** deterministic local and mock-transport tests. The live `URLSession` download is exercised by Scribe's
  simulator check against the throwaway app (#454 criterion 3), not by this suite.
- **Paths:**
  - `Sources/InstantSwiftDataCore/InstantStorageTransport.swift`
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` (`downloadStoredFile` and its two file helpers only)
  - `Sources/InstantSwiftData/InstantSwiftData.swift` (the client's `downloadStoredFile` wiring only)
  - `Tests/InstantSwiftDataCoreTests/InstantStoredFileDownloadTests.swift` (new)
