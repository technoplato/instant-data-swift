import Foundation
import Testing

@testable import InstantSwiftDataCore

// #1147 (2026-10-24): where the memory exercises' allocations are made. Each runs the same operation as its exercise in
// `MemoryExercises` (same session, store and frames) and prints the call sites that made its allocations, per operation,
// largest count first:
//
//     MEMORY-SITE <exercise> rank=… allocations=… bytes=… site=<library function> allocator=… caller=…
//
// Run alone and in release, as the exercises are: `INSTANT_MEMORY_SITES=1`, filter `MemorySiteExercises`.
//
// History:
// - 2026-10-24: #1147: the refresh of an open page (E03) and a finished line (E04).
// - 2026-10-25: #1150: a page of a long recording's history read locally (E14).

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["INSTANT_MEMORY_SITES"] != nil))
struct MemorySiteExercises {
  /// E03's refresh of a 64-line page with one line changed, four times.
  @Test func s03PageRefreshSites() async throws {
    try await MemoryExerciseSession.open(MemoryExercises.shape, label: "s03").closing { context in
      let recordingID = RealSizeID.make(.write, 700_000)
      let rows = 64
      let page = try await MemoryOpenPage.open(
        context, recordingID: recordingID, rows: rows, firstLine: rows * 1_000, idBase: 2_000_000 + rows * 1_000,
        id: "s03-page-\(rows)"
      )
      let iterations = 4
      let frames = await page.frames(count: 2 + iterations)
      for index in 0..<2 {
        await context.server.push(encoded: frames[index].frame)
        try await context.waitApplies.wait(for: frames[index].tx)
      }
      let recording = try await MemoryAllocationSites.record {
        for index in 2..<(2 + iterations) {
          await context.server.push(encoded: frames[index].frame)
          try await context.waitApplies.wait(for: frames[index].tx)
        }
      }
      MemoryAllocationSites.print("S03.page-refresh-\(rows)", recording, top: 60, iterations: iterations)
      await page.close()
    }
  }

  /// E04's finished line on the account's longest recording, eight times.
  @Test func s04FinalLineSites() async throws {
    try await MemoryExerciseSession.open(MemoryExercises.shape, label: "s04").closing { context in
      let runtime = context.runtime
      let clock = context.session.clock
      let (longestID, _) = MemoryExercises.longestRecording
      let longest = try #require(context.session.account.entities["recordings"]?.first { $0.id == longestID })
      _ = try await MemoryScribeWrites.seedLinks(context, recordingID: longestID)
      let iterations = 8
      let lives = (0..<(2 + iterations)).map {
        MemoryScribeWrites.liveLine(recordingID: longestID, line: 100_000 + $0, words: 9, at: clock.now())
      }
      try await runtime.transact(MemoryScribeWrites.transaction { txID in
        lives.flatMap { MemoryScribeWrites.update($0, at: clock.advance(), txID: txID) }
      })
      try await MemoryExerciseSession.settle(runtime)
      // Each line is built before the recording, as E04 builds them: generating a line's words is the harness's work.
      // The write itself is assembled in the recording, at its time.
      let lines = (0..<(2 + iterations)).map { index in
        RealSizeAccount.segment(
          recordingID: longestID, line: 100_000 + index, revision: 4, serial: 0,
          id: RealSizeID.make(.write, 910_000 + index)
        )
      }
      func write(_ index: Int) async throws {
        try await runtime.transact(
          MemoryScribeWrites.finalLine(lines[index], recording: longest, liveLine: (lives[index].id, lives[index].namespace), at: clock.advance())
        )
        try await MemoryExerciseSession.waitUntilAcknowledged(runtime)
      }
      for index in 0..<2 { try await write(index) }
      let recording = try await MemoryAllocationSites.record {
        for index in 2..<(2 + iterations) { try await write(index) }
      }
      MemoryAllocationSites.print("S04.final-line-long-recording", recording, top: 60, iterations: iterations)
    }
  }

  /// E14's local read of the longest recording's history, one 256-line page, four times.
  @Test func s14LocalHistoryPageSites() async throws {
    try await MemoryExerciseSession.open(MemoryExercises.shape, label: "s14").closing { context in
      let (recordingID, lines) = MemoryExercises.longestRecording
      let pages = max(1, (lines + 255) / 256)
      func plan(_ page: Int) -> InstantQueryPlan {
        InstantQueryPlan(
          id: "s14-history", namespace: "transcriptionSegments",
          filters: [.equals(field: "recordingID", value: .string(recordingID))],
          order: InstantQueryOrder("segmentIndex", .descending), offset: (page % pages) * 256, limit: 256,
          selectedFields: RealSizeAccount.segmentFields.filter { $0 != "id" }
        )
      }
      for page in 0..<2 { _ = try await context.runtime.queryLocally(plan(page)) }
      let iterations = 4
      let recording = try await MemoryAllocationSites.record {
        for page in 2..<(2 + iterations) { _ = try await context.runtime.queryLocally(plan(page)) }
      }
      MemoryAllocationSites.print("S14.local-history-page", recording, top: 60, iterations: iterations)
    }
  }
}
