import Foundation
import os

// History:
// - 2026-10-25: added (#1145): a long session's memory is what a relaunch's would be.

/// The entities a residency sweep may release from memory, and when one is due (#1145).
///
/// After a relaunch the store holds only the facts a stored result owns, and a local read finds the rest on disk
/// (#1006). A running session kept every row it wrote once the server acknowledged it and no result owned it: in the
/// memory audit's two-hour replay the resident facts grew from 56,109 to 71,211 and the heap by 12.1 MB an hour. A sweep
/// releases from memory, never from disk, the entities no stored result owns, no outbox row touches and no open observer
/// shows.
///
/// Its candidates cost what changed, not the store: the entities each committed local write changed, and the entities a
/// result's save removed ownership rows of. A candidate kept because a write to it is pending, or an observer shows it,
/// stays one; one a stored result owns leaves until a save removes its rows again. A sweep runs on the write count only,
/// never on a timer, so a phone in a pocket with nothing written does nothing.
final class InstantResidencySweepState: Sendable {
  private struct State {
    var candidates: Set<String> = []
    var writesSinceSweep = 0
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

  /// Records a committed local write's changed entities, and whether `interval` writes have now accumulated since the
  /// last sweep took its candidates. An interval of `Int.max` turns the sweep off and records nothing.
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
  /// Candidates kept for a later sweep: a write to them is pending, or an open observer shows them.
  var keptEntityCount = 0
  /// Holds of the operation gate it took.
  var batchCount = 0
  /// Whether it stopped early because a prune's release was pending; its candidates wait for the next sweep.
  var deferredForPruneRelease = false
}

/// What persistence decided for a batch of a sweep's candidates (#1145).
struct InstantResidencySweepDecision: Equatable, Sendable {
  /// No stored result owns them and no outbox row touches them.
  var releasable: Set<String>
  /// An outbox row touches them: kept for a later sweep.
  var pending: Set<String>
}
