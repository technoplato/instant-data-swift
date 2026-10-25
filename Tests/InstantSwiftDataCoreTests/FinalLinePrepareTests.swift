import Foundation
import Testing

@testable import InstantSwiftDataCore

// #1153 (2026-10-24): a write that deletes something ran a whole throwaway prepare first, only to list the entities the
// delete changes so their deferred values (Scribe's segment text and words) could be loaded before the real prepare.
// Scribe's finished line deletes its `liveLines` row, which links to nothing, so the preview found nothing to load and
// copied everything the real prepare copies: 2.0 store prepares per finished line at the phone's size (the memory
// audit's E04, M14).
//
// History:
// - 2026-10-24: #1153: the tests.

@Suite
struct FinalLinePrepareTests {
  /// A finished line, as Scribe's typed API writes it (the line, then a delete of its `liveLines` row in its namespace),
  /// is prepared once.
  @Test func aFinishedLineIsPreparedOnce() async throws {
    var fixture = try await FastDrainFixture.make(
      suffix: "final-line-prepare", serverSegmentCount: 2, pendingSegmentCount: 0,
      scribeLinks: true, defersSegmentText: true, liveLines: true
    )
    let runtime = fixture.runtime
    let writes = fixture.script.nextSegmentWrites()
    // Three interims on the live row, then the final, which deletes it.
    for write in writes.prefix(3) {
      _ = try await runtime.transact(write, createdAt: InstantTimestamp(milliseconds: fixture.script.deviceMilliseconds))
    }
    var final = writes[3]
    final.operations = final.operations.map { operation in
      guard case let .deleteEntity(entityID) = operation else { return operation }
      return .deleteEntityInNamespace(entityID: entityID, namespace: "liveLines")
    }
    let before = await runtime.store.preparationCountForTesting
    _ = try await runtime.transact(final, createdAt: InstantTimestamp(milliseconds: fixture.script.deviceMilliseconds))
    let prepared = await runtime.store.preparationCountForTesting - before

    #expect(prepared == 1, "The finished line was prepared \(prepared) times.")
    let liveRows = try await runtime.queryLocally(InstantQueryPlan(id: "live", namespace: "liveLines"))
    #expect(liveRows.values.isEmpty, "The final deleted its live row.")
    _ = try? await runtime.closeConnection()
  }

  /// Wherever a delete can reach a deferred value, the entities it reaches are still found: a recording's delete
  /// cascades to its lines, whose text stays on disk.
  @Test func aDeleteReachesWhatItsCascadesAndLinksReach() {
    let attributes = AttributeStore(
      attributes: FastDrainSchema.scribeLinkAttributes + FastDrainSchema.liveLineAttributes + [
        InstantAttribute(
          id: "notes/about", namespace: "notes", name: "about", valueType: .ref, isRequired: false,
          forwardIdentity: "notes/about", reverseIdentity: "transcriptionSegments/notes", linkNamespace: "transcriptionSegments"
        ),
        InstantAttribute(id: "tags/anything", namespace: "tags", name: "anything", valueType: .ref, isRequired: false),
      ]
    )
    let deferred: Set<String> = ["transcriptionSegments"]
    // A live line links to nothing.
    #expect(!attributes.deleteCanReach(deferred, from: "liveLines"))
    // A recording's delete cascades to its lines.
    #expect(attributes.deleteCanReach(deferred, from: "recordings"))
    // A line's own delete reaches no other line.
    #expect(!attributes.deleteCanReach(deferred, from: "transcriptionSegments"))
    // A line's delete changes the notes that link to it: they lose the link.
    #expect(attributes.deleteCanReach(["notes"], from: "transcriptionSegments"))
    // A link with no target namespace may point anywhere.
    #expect(attributes.deleteCanReach(["tags"], from: "liveLines"))
  }
}
