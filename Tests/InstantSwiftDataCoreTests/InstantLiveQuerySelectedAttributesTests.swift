import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// The attributes a live query selects, read from its registration key (#431): a refreshed result that leaves one of
/// them empty on an entity it holds says the server cleared it, and one it does not select says nothing.
@Suite
struct InstantLiveQuerySelectedAttributesTests {
  @Test
  func fieldsSelectTheirSingleValueAttributes() {
    expectNoDifference(
      Self.selected(#"{"recordings":{"$":{"fields":["activityKind","title","previewSegmentB"]}}}"#),
      ["recordings": ["recordings/activityKind", "recordings/title"]]
    )
  }

  @Test
  func aLevelWithoutFieldsSelectsEverySingleValueAttributeOfItsNamespace() {
    let recordings = Set(
      FastDrainSchema.attributes
        .filter { $0.namespace == "recordings" && $0.cardinality == .one && $0.valueType != .ref }
        .map(\.id)
    )
    #expect(recordings.contains("recordings/activityKind"))
    #expect(!recordings.contains("recordings/previewSegmentB"))
    expectNoDifference(Self.selected(#"{"recordings":{"$":{"order":{"updatedAtMs":"desc"}}}}"#), ["recordings": recordings])
    expectNoDifference(Self.selected(#"{"recordings":{}}"#), ["recordings": recordings])
  }

  @Test
  func anIncludeSelectsForTheNamespaceItsLinkLeadsTo() {
    expectNoDifference(
      Self.selected(
        #"{"recordings":{"$":{"fields":["title"]},"transcriptionSegments":{"$":{"fields":["text","isFinal"]}}}}"#
      ),
      [
        "recordings": ["recordings/title"],
        "transcriptionSegments": ["transcriptionSegments/text", "transcriptionSegments/isFinal"],
      ]
    )
  }

  /// A namespace at two levels keeps only what both select, so neither level's missing attribute reads as cleared.
  @Test
  func aNamespaceAtTwoLevelsKeepsWhatBothSelect() {
    expectNoDifference(
      Self.selected(
        #"{"transcriptionSegments":{"$":{"fields":["text","isFinal"]}},"recordings":{"$":{"fields":["title"]},"#
          + #""transcriptionSegments":{"$":{"fields":["text"]}}}}"#
      ),
      ["recordings": ["recordings/title"], "transcriptionSegments": ["transcriptionSegments/text"]]
    )
  }

  /// A key that is not an InstaQL query, or names a namespace or link this store does not know, selects nothing it can
  /// vouch for.
  @Test
  func anUnknownShapeSelectsNothing() {
    #expect(Self.selected("fast-drain-query-list") == nil)
    #expect(Self.selected("[]") == nil)
    #expect(Self.selected("{}") == nil)
    #expect(Self.selected(#"{"unknownNamespace":{"$":{}}}"#) == nil)
    #expect(Self.selected(#"{"recordings":{"$":{},"unknownLink":{"$":{}}}}"#) == nil)
  }

  private static func selected(_ key: String) -> [String: Set<String>]? {
    SQLitePersistenceStore.liveQuerySelectedValueAttributeIDs(queryKey: key, attributes: FastDrainSchema.attributes)
  }
}
