import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// #2554 (#2551): the live session applies every attr-less refresh with the attrs of its latest init-ok, or of the
/// latest refresh that carried attrs: after a reconnect, a new array equal to the one the cached attribute context was
/// built from. The cache returned the context but kept its old array, so `Array`'s buffer-identity check never passed
/// again and every later refresh compared every attr value by value: 2,283 of them on a phone, 636 samples (1.45% of the
/// app) in a 3.6-hour Power Profiler trace, before the frame's own translation began. These tests pin one value
/// comparison per new array, with the context still built once.
@Suite
struct InstantLiveRefreshAttributeContextReuseTests {
  /// The cache built from one array, then asked 100 times with an equal array in another buffer (a reconnect's).
  @Test
  func anEqualAttrsArrayInAnotherBufferIsComparedOnceThenReused() throws {
    let attributes = InstantLiveRefreshAttributeCostTests.scribeShapedAttributes()
    let built = InstantLiveRefreshAttributeCostTests.serverAttrs(for: attributes)
    let reconnected = InstantLiveRefreshAttributeCostTests.serverAttrs(for: attributes)
    try #require(built == reconnected)
    let sharesBuffer = built.withUnsafeBufferPointer { built in
      reconnected.withUnsafeBufferPointer { built.baseAddress == $0.baseAddress }
    }
    try #require(!sharesBuffer)
    let cache = InstantLiveRefreshAttributeContextCache()

    let first = try cache.context(serverAttributes: built, existingAttributes: attributes, localAttributeRevision: 1)
    var reused: [InstantLiveRefreshAttributeContext] = []
    for _ in 0..<100 {
      reused.append(
        try cache.context(serverAttributes: reconnected, existingAttributes: attributes, localAttributeRevision: 1)
      )
    }

    expectNoDifference(cache.buildCount, 1)
    expectNoDifference(cache.valueComparisonCount, 1)
    #expect(reused.allSatisfy { $0.attributesToMerge == first.attributesToMerge })
  }

  /// Attrs that differ, or a local schema that changed, still rebuild the context, as before.
  @Test
  func changedAttrsOrAChangedLocalSchemaStillRebuild() throws {
    let attributes = InstantLiveRefreshAttributeCostTests.scribeShapedAttributes()
    let attrs = InstantLiveRefreshAttributeCostTests.serverAttrs(for: attributes)
    let widened = attrs + [
      .object([
        "id": .string("server-recordings/added"),
        "forward-identity": .array([.string("identity-recordings/added"), .string("recordings"), .string("added")]),
        "value-type": .string("blob"),
        "cardinality": .string("one"),
        "unique?": .bool(false),
        "index?": .bool(false),
      ])
    ]
    let cache = InstantLiveRefreshAttributeContextCache()

    _ = try cache.context(serverAttributes: attrs, existingAttributes: attributes, localAttributeRevision: 1)
    let rebuilt = try cache.context(serverAttributes: widened, existingAttributes: attributes, localAttributeRevision: 1)
    _ = try cache.context(serverAttributes: widened, existingAttributes: attributes, localAttributeRevision: 2)

    expectNoDifference(cache.buildCount, 3)
    expectNoDifference(rebuilt.attributesToMerge.map(\.name), ["added"])
  }
}
