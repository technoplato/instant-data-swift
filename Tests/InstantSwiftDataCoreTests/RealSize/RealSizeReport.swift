import Foundation
import Testing

@testable import InstantSwiftDataCore

// #1072 (2026-10-24): the whole-store cost audit's report run. Every hot-path operation, metered on the generated
// store at a quarter of the phone's size and at its full size (and on a copy of a phone's own store when
// `INSTANT_REAL_SIZE_STORE` names one): the same change at both sizes should cost the same, so a row whose cost grows
// four-fold with the store is the audit's defect. One `REALSIZE` line per operation and size; the audit table in
// docs/audits/2026-10-24-whole-store-cost-audit.md is read from these lines.
//
// `INSTANT_REAL_SIZE_REPORT=1` runs it (minutes, release); `INSTANT_REAL_SIZE_REPORT_SCALES=0.25,1` picks the sizes,
// `INSTANT_REAL_SIZE_REPORT_ONLY=transact,prune` some operations. The smoke test below runs always: a tiny shape, so
// the fixture and the meter cannot rot.
//
// History:
// - 2026-10-24: #1072: the report and the smoke test.

@Suite(.serialized)
struct RealSizeFixtureSmokeTests {
  @Test func aTinyFixtureGeneratesOpensAndMeters() async throws {
    let shape = RealSizeShape.phone.scaled(0.01)
    let session = try await RealSizeFixture.open(shape, label: "smoke")
    try await session.closing {
      let counts = try RealSizeStoreCounts(session.configuration.persistenceURL)
      #expect(counts.facts > 0)
      #expect(counts.attributes >= RealSizeAccount.scribeAttributeCount)
      #expect(counts.fileRecords == shape.deviceFileRecords)
      #expect((counts.outbox["failed"] ?? 0) == shape.refusedWrites)
      #expect(counts.unloadedResults > 0)
      print("REALSIZE-FIXTURE smoke counts: \(counts)")

      let recordingID = RealSizeID.make(.recording, 0)
      let write = try await RealSizeMeter.measure("transact", label: "smoke", iterations: 3, gate: session.gate) { index in
        try await session.runtime.transact(
          session.segmentWrite(recordingID: recordingID, line: 10_000 + index, revision: 0, id: RealSizeID.make(.write, index))
        )
      }
      #expect(write.allocations > 0)
      #expect(write.medianWall > .zero)
      #expect((write.gate?.acquisitions ?? 0) > 0)
      print(write.line)
    }
  }
}

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["INSTANT_REAL_SIZE_REPORT"] != nil))
struct RealSizeReport {
  @Test func everyOperationAtTwoSizes() async throws {
    let environment = ProcessInfo.processInfo.environment
    let scales = (environment["INSTANT_REAL_SIZE_REPORT_SCALES"] ?? "0.25,1").split(separator: ",").compactMap { Double($0) }
    let only = environment["INSTANT_REAL_SIZE_REPORT_ONLY"].map { Set($0.split(separator: ",").map(String.init)) }
    for scale in scales {
      let shape = scale == 1 ? RealSizeShape.phone : RealSizeShape.phone.scaled(scale)
      let label = environment["INSTANT_REAL_SIZE_STORE"] != nil && scale == 1 ? "phone-copy" : "x\(scale)"
      try await RealSizeOperations.report(shape, label: label, only: only)
    }
  }
}

/// The metered operations: each opens what it needs on one session and prints one line.
enum RealSizeOperations {
  static func report(_ shape: RealSizeShape, label: String, only: Set<String>?) async throws {
    func wanted(_ name: String) -> Bool { only?.contains(name) ?? true }
    func emit(_ measurement: RealSizeMeasurement) { print(measurement.line) }

    // Launch: a fresh copy of the store for every boot, copied before the clock starts.
    if wanted("launch") {
      let source = try await RealSizeFixture.store(shape)
      let account = RealSizeAccount(shape)
      var copies: [URL] = []
      for _ in 0..<4 {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("real-size-launch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try RealSizeFixture.copyStore(from: source, to: directory.appendingPathComponent("cache.sqlite"))
        copies.append(directory)
      }
      defer { for directory in copies { try? FileManager.default.removeItem(at: directory) } }
      emit(
        try await RealSizeMeter.measure("launch", label: label, iterations: 1, warmup: 0) { index in
          let directory = copies[index]
          let session = try await RealSizeFixture.boot(
            shape: shape, account: account, storeURL: directory.appendingPathComponent("cache.sqlite"),
            directory: directory, removesDirectory: false, onFrame: nil, configure: { _ in }
          )
          await session.close()
        }
      )
    }

    let session = try await RealSizeFixture.open(shape, label: "report-\(label)")
    try await session.closing { try await operations(on: session, label: label, wanted: wanted, emit: emit) }
  }

  private static func operations(
    on session: RealSizeSession,
    label: String,
    wanted: (String) -> Bool,
    emit: (RealSizeMeasurement) -> Void
  ) async throws {
    let runtime = session.runtime
    let server = session.server
    // Every measurement reads the operation gate's timeline: the longest hold, its holder, the longest wait.
    func measure(
      _ operation: String, iterations: Int, warmup: Int, _ body: (Int) async throws -> Void
    ) async throws -> RealSizeMeasurement {
      try await RealSizeMeter.measure(operation, label: label, iterations: iterations, warmup: warmup, gate: session.gate, body)
    }

    // The recording: a new recording's live transcript page, as Scribe holds it open while recording.
    let recording = session.newRecording(90_000)
    try await runtime.transact(recording.write)
    let page = session.transcriptPage(recordingID: recording.id)
    let added = await server.addQueries
    let pageLease = await runtime.observeQueryLease(page)
    let pageQuery = try await server.nextAddQuery(after: added)
    var lines: [RealSizeEntity] = []
    func writeLine(_ index: Int, revision: Int) -> InstantStoreTransaction {
      let id = RealSizeID.make(.write, 100_000 + index / 5)
      return session.segmentWrite(recordingID: recording.id, line: index / 5, revision: revision, id: id)
    }

    if wanted("transact") {
      emit(
        try await measure("transact", iterations: 25, warmup: 5) { index in
          try await runtime.transact(writeLine(index, revision: index % 5))
        }
      )
    }
    try await RealSizeGenerator.waitForSettledOutbox(runtime)

    // The server's echo: the page's refresh with every line the recording has, the newest changed.
    if wanted("server-apply") {
      for index in 0..<128 {
        lines.append(
          RealSizeAccount.segment(recordingID: recording.id, line: index, revision: 4, serial: 0, id: RealSizeID.make(.write, 200_000 + index))
        )
      }
      emit(
        try await measure("server-apply.refresh-128", iterations: 10, warmup: 2) { index in
          lines[index % lines.count] = RealSizeAccount.segment(
            recordingID: recording.id, line: index % lines.count, revision: index % 5, serial: 0,
            id: lines[index % lines.count].id
          )
          let tx = await server.refresh(pageQuery, rows: lines.map { $0.joinRow() })
          _ = try await session.applies.wait(for: tx)
        }
      )
    }

    if wanted("prune") {
      emit(
        try await measure("prune", iterations: 5, warmup: 1) { _ in
          _ = try await runtime.pruneLiveQueryResults(
            policy: session.configuration.liveQueryResultPruningPolicy, now: session.clock.now()
          )
        }
      )
    }

    if wanted("query") {
      let other = session.transcriptPage(recordingID: RealSizeID.make(.recording, 1))
      emit(
        try await measure("queryOnce.transcript-page", iterations: 10, warmup: 2) { _ in
          _ = try await runtime.queryOnce(other)
        }
      )
    }

    if wanted("observe") {
      let other = session.transcriptPage(recordingID: RealSizeID.make(.recording, 2))
      emit(
        try await measure("observe.first-emission", iterations: 10, warmup: 2) { _ in
          let lease = await runtime.observeQueryLease(other)
          for await _ in lease.stream { break }
          await lease.cancel()
        }
      )
      // A new line each time, so the page's emission that holds it is the one this write caused (the stream keeps only
      // its newest emission).
      emit(
        try await measure("observe.emission-after-write", iterations: 10, warmup: 2) { index in
          let write = writeLine(1_000 + index * 5, revision: 1)
          let lineID = RealSizeID.make(.write, 100_000 + (1_000 + index * 5) / 5)
          try await runtime.transact(write)
          for await emission in pageLease.stream where emission.values.contains(where: { $0.id == lineID }) { break }
        }
      )
    }

    if wanted("files") {
      let local = (try await runtime.persistence.loadStoredFiles(appID: RealSizeAccount.appID)).first
      let scratch = session.directory.appendingPathComponent("upload.wav")
      try Data(repeating: 1, count: 16_384).write(to: scratch)
      emit(
        try await measure("uploadFile", iterations: 10, warmup: 2) { index in
          _ = try await runtime.uploadFile(from: scratch, name: "scribe/new/chunk-\(index).wav", contentType: "audio/wav")
        }
      )
      emit(
        try await measure("storedFiles", iterations: 3, warmup: 1) { _ in
          _ = try await runtime.storedFiles()
        }
      )
      emit(
        try await measure("observeStoredFiles.first-emission", iterations: 3, warmup: 1) { _ in
          let stream = try await runtime.observeStoredFiles()
          for await _ in stream { break }
        }
      )
      emit(
        try await measure("storageSnapshot", iterations: 5, warmup: 1) { _ in
          _ = try await runtime.storageSnapshot()
        }
      )
      if let local {
        emit(
          try await measure("downloadStoredFile.by-id-with-record", iterations: 5, warmup: 1) { index in
            _ = try await runtime.downloadStoredFile(
              id: local.id, to: session.directory.appendingPathComponent("download-\(index)")
            )
          }
        )
      }
      let remote = (session.account.entities["$files"] ?? []).last
      if let remote {
        emit(
          try await measure("downloadStoredFile.by-id-without-record", iterations: 5, warmup: 1) { index in
            _ = try? await runtime.downloadStoredFile(
              id: remote.id, to: session.directory.appendingPathComponent("remote-\(index)")
            )
          }
        )
      }
      emit(
        try await measure("deleteStoredFile.uploaded", iterations: 5, warmup: 1) { index in
          let file = try await runtime.uploadFile(from: scratch, name: "scribe/delete/\(index).wav", contentType: "audio/wav")
          _ = try await runtime.deleteStoredFile(id: file.id)
        }
      )
      emit(
        try await measure("evictStoredFiles.one", iterations: 5, warmup: 1) { _ in
          if let local { _ = try? await runtime.evictStoredFiles(ids: [local.id]) }
        }
      )
    }

    if wanted("outbox") {
      emit(try await measure("pendingMutationCount", iterations: 20, warmup: 2) { _ in
        _ = await runtime.pendingMutationCount()
      })
      emit(try await measure("pendingMutations(limit:50)", iterations: 10, warmup: 2) { _ in
        _ = await runtime.pendingMutations(limit: 50)
      })
      emit(try await measure("pendingMutations", iterations: 3, warmup: 1) { _ in
        _ = await runtime.pendingMutations()
      })
      emit(try await measure("failedMutations(limit:50)", iterations: 10, warmup: 2) { _ in
        _ = await runtime.failedMutations(limit: 50)
      })
      emit(try await measure("failedMutations", iterations: 3, warmup: 1) { _ in
        _ = await runtime.failedMutations()
      })
      emit(try await measure("quarantinedMutationCount", iterations: 10, warmup: 2) { _ in
        _ = try await runtime.quarantinedMutationCount()
      })
    }

    if wanted("status") {
      emit(try await measure("connectionStatus", iterations: 20, warmup: 2) { _ in
        _ = try await runtime.connectionStatus()
      })
      emit(try await measure("syncState", iterations: 10, warmup: 2) { _ in
        _ = try await runtime.syncState()
      })
      emit(try await measure("cachedQueries", iterations: 5, warmup: 1) { _ in
        _ = try await runtime.cachedQueries()
      })
    }

    if wanted("refused-write") {
      await server.setWriteAnswer(.refuse)
      emit(
        try await measure("refused-write", iterations: 5, warmup: 1) { index in
          let before = await runtime.failedMutations(limit: 1_000).count
          try await runtime.transact(writeLine(5_000 + index * 5, revision: 2))
          let deadline = ContinuousClock.now + .seconds(60)
          while await runtime.failedMutations(limit: 1_000).count == before, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
          }
        }
      )
      await server.setWriteAnswer(.accept)
    }

    if wanted("compact") {
      emit(try await measure("compactLocalCache", iterations: 1, warmup: 0) { _ in
        _ = try await runtime.compactLocalCache()
      })
    }
    await pageLease.cancel()
  }
}
