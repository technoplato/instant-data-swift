import Foundation
import os

// History:
// - 2026-11-04: added (#1145): a long session's memory is what a relaunch's is. Designed 2026-10-25 and parked until a
//   write could prepare against an entity kept on disk only (#1165).

/// The entities a residency sweep may release from memory, and when one is due (#1145).
///
/// After a relaunch the store holds the facts the stored results own and the outbox's effects; a local read finds the
/// rest on disk (#1006), and a write reads an entity memory lacks before it prepares (#1165). A running session kept
/// every row it wrote: on a phone recording, the store's resident facts grew about 13,000 an hour and the heap in use
/// about 30 MB an hour (2026-11-04), and the next relaunch dropped them. A sweep releases from memory, never from disk,
/// the entities no stored result owns, no outbox row touches and no open observer shows.
///
/// Its candidates cost what changed, not the store: the entities each committed local write changed, and the entities
/// a result's save stopped owning. A candidate a pending write or an observer keeps stays one; one a stored result owns
/// leaves until a save stops owning it. A sweep is due after a number of local writes, never on a timer, so a phone in a
/// pocket that writes nothing does nothing.
final class InstantResidencySweepState: Sendable {
  private struct State {
    var candidates: Set<String> = []
    var writesSinceSweep = 0
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

  /// Records a committed local write's changed entities, and whether `interval` writes have accumulated since the last
  /// sweep took its candidates. An interval of `Int.max` turns the sweep off and records nothing.
  func recordWrite(changing entityIDs: Set<String>, interval: Int) -> Bool {
    guard interval < .max else { return false }
    return state.withLock { state in
      state.candidates.formUnion(entityIDs)
      state.writesSinceSweep += 1
      return state.writesSinceSweep >= interval
    }
  }

  /// Every candidate, for a sweep to decide; the write count starts again.
  func takeCandidates() -> Set<String> {
    state.withLock { state in
      let candidates = state.candidates
      state.candidates = []
      state.writesSinceSweep = 0
      return candidates
    }
  }

  /// Candidates a sweep kept for a later one.
  func keep(_ entityIDs: Set<String>) {
    guard !entityIDs.isEmpty else { return }
    state.withLock { $0.candidates.formUnion(entityIDs) }
  }
}

/// What one sweep did (#1145).
struct InstantResidencySweepResult: Equatable, Sendable {
  /// Entities whose facts left memory.
  var releasedEntityCount = 0
  /// Facts that left memory.
  var releasedFactCount = 0
  /// Candidates kept for a later sweep: a write to them is pending, or an open observer shows them.
  var keptEntityCount = 0
  /// Holds of the operation gate it took.
  var batchCount = 0
  /// Whether it stopped before a batch because a prune was releasing results; its candidates wait for the next sweep.
  var deferredForPrune = false
}

/// What persistence decided for a sweep's candidates (#1145).
struct InstantResidencySweepDecision: Equatable, Sendable {
  /// No stored result owns them and no outbox row touches them.
  var releasable: Set<String>
  /// No stored result owns them, and an outbox row touches them: kept for a later sweep.
  var pending: Set<String>
}
