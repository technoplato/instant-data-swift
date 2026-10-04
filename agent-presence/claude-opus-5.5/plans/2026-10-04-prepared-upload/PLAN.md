# Plan 2026-10-04-prepared-upload (#491)

- **Agent:** claude-opus-5.5-library-79, on the coordinating session's order (after 1.9.8), with the API agreed with
  Scribe's background-uploads on 2026-10-04 (#491's work log).
- **Branch:** `agent/claude-opus-5.5/library-79-491`, from the 1.9.7 branch; it takes 1.9.8 before release.
- **Why:** Scribe #481 uploads a recording's audio in a background `URLSession`. On the 1.9.3 public API it does that by
  replacing `InstantStorageHTTPClient.uploadFile`, throwing `ContinuesInBackground` through `uploadFile`, and replaying
  the finished task's answer through a second `uploadFile`, which also copies the source into the library's file store
  (321 MB for Recording 187's audio).
- **Change (grower, additive public API):**
  - `InstantRuntime.prepareFileUpload(from:name:contentType:)` and the client's: the live transport's
    `PUT {api}/storage/upload` as an `InstantPreparedFileUpload` (`request`, `path`, `byteCount`, `contentType`,
    `sourceURL`; `Sendable`). It stats the file and nothing else, and sends nothing.
  - `InstantRuntime.completeFileUpload(path:statusCode:responseBody:sourceURL:contentType:)` and the client's:
    `uploadFile`'s status mapping (401 and 403 `permissionRejected`, other non-2xx `networkFailed`, a bad body
    `decodeFailed`); the `instant_files` record gets an empty `localPath`, since deleting a stored file deletes
    `localPath` and Scribe's compensation deletes it; works in a process that never prepared the upload; completing
    the same upload again changes nothing.
  - An empty `localPath`, or one whose file is gone, means the library has no copy: `downloadStoredFile` and
    `storedFileContents` then download from storage under the record's path, instead of copying from the working
    directory or throwing.
  - `InstantStorageUploadRequest.urlRequest`, the one place the upload request is built, with a size-scaled
    `timeoutInterval` (60 s plus 4 s per MiB) for the live upload and the prepared one.
- **Tests:** `Tests/InstantSwiftDataCoreTests/InstantPreparedFileUploadTests.swift` (new). Red on the released code: a
  record whose library copy is gone fails both reads today. Then the prepared request equals the live transport's
  captured request and nothing is sent, recorded or copied; completion records without a copy, works without a
  prepare, is idempotent, maps failures as `uploadFile` does, and both reads fetch from storage afterwards.
- **Evidence kinds:** deterministic local and mock-transport tests; the background session itself is Scribe's to prove.
- **Paths:**
  - `Sources/InstantSwiftDataCore/InstantStorageTransport.swift` (the request builder and the answer decoding)
  - `Sources/InstantSwiftDataCore/InstantFileModels.swift` (`InstantPreparedFileUpload`)
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` (`readStoredFileContents`, `recordUploadedFile`)
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` (prepare, complete, and the two reads' fall-through)
  - `Sources/InstantSwiftData/InstantSwiftData.swift` (the client's two operations)
  - `Tests/InstantSwiftDataCoreTests/InstantPreparedFileUploadTests.swift` (new)
