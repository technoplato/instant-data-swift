import CustomDump
import Darwin
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// #1007: a page that selects a few fields materialized every field of each row, then dropped the rest. A recording holds
/// thousands of refs in its link sets (its lines, attachments, events, chunks), and the app's queries over recordings
/// select a few scalars, so every re-read of the recording being written built and sorted all of them for nothing. The
/// recordings list filters on a field no index covers (`deletedAtMs` is null), so it built every candidate recording
/// whole, not only the twelve it shows.
@Suite
struct InstantSelectedFieldsMaterializationTests {
  /// A list page selecting two fields costs about the same whether one of its recordings holds 20,000 linked lines or
  /// none.
  @Test
  func aPageThatSelectsFewFieldsCostsTheSameWhateverLinksItsRowsHold() {
    let plan = InstantQueryPlan(
      id: "selected.list",
      namespace: Self.recordings,
      filters: [
        .equals(field: "ownerUserID", value: .string("owner")),
        .isNull(field: "deletedAtMs"),
      ],
      order: InstantQueryOrder("startedAtMs", .descending),
      limit: 12,
      selectedFields: ["title", "startedAtMs"]
    )
    let withLinks = Self.listStore(hubLinkCount: 20_000)
    let withoutLinks = Self.listStore(hubLinkCount: 0)
    let shown = withLinks.materializePageWithMetrics(plan, attributes: Self.attributes, remotePageInfo: nil).page
    expectNoDifference(shown.values.count, 12)
    expectNoDifference(shown.values.first?.values, ["title": .one(.string("hub")), "startedAtMs": .one(.number(99))])
    expectNoDifference(
      shown.values.map(\.values),
      withoutLinks.materializePageWithMetrics(plan, attributes: Self.attributes, remotePageInfo: nil).page.values
        .map(\.values)
    )
    let hub = Self.threadCPUNanoseconds {
      for _ in 0..<50 {
        _ = withLinks.materializePageWithMetrics(plan, attributes: Self.attributes, remotePageInfo: nil)
      }
    }
    let plain = Self.threadCPUNanoseconds {
      for _ in 0..<50 {
        _ = withoutLinks.materializePageWithMetrics(plan, attributes: Self.attributes, remotePageInfo: nil)
      }
    }
    let ratio = Double(hub) / Double(max(plain, 1))
    #expect(ratio < 3, "the page with a 20,000-link recording cost \(ratio) times the page without")
  }

  /// A page that selects fields holds exactly what the same page selecting every field holds, cut to its selection: for
  /// filters, orders, windows and includes (forward and reverse, with their own selections), and after later writes.
  @Test(arguments: [UInt64(51_007), 51_008, 51_009, 51_010, 51_011])
  func aPageThatSelectsFieldsHoldsWhatTheWholePageHoldsCutToItsSelection(seed: UInt64) {
    var random = InfiniteWindowRandom(seed: seed)
    var indexes = TripleIndexes(triples: Self.randomTriples(&random, count: 40), attributes: Self.attributes)
    for round in 0..<6 {
      if round > 0 {
        // Later writes take the store's write path, interning what they write.
        for triple in Self.randomTriples(&random, count: 4) {
          _ = indexes.apply(.insert(triple), attributes: Self.attributes)
        }
        indexes.finishInternCachesAfterWrite(attributes: Self.attributes)
      }
      for planIndex in 0..<30 {
        let plan = Self.randomPlan(&random, id: "selected.random.\(round).\(planIndex)")
        let selected = indexes.materializePageWithMetrics(plan, attributes: Self.attributes, remotePageInfo: nil).page
        let whole = indexes.materializePageWithMetrics(
          Self.selectingEveryField(plan),
          attributes: Self.attributes,
          remotePageInfo: nil
        ).page
        expectNoDifference(
          selected.values,
          Self.cut(whole.values, to: plan),
          "seed \(seed) round \(round) plan \(plan)"
        )
        expectNoDifference(selected.pageInfo, whole.pageInfo, "seed \(seed) round \(round) plan \(plan)")
      }
    }
  }

  // MARK: - Helpers

  static let recordings = "selRecordings"
  static let segments = "selSegments"
  static let attachments = "selAttachments"

  static let attributes = AttributeStore(attributes: [
    .primaryKey(namespace: recordings),
    InstantAttribute(
      id: "\(recordings)/ownerUserID",
      namespace: recordings,
      name: "ownerUserID",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(id: "\(recordings)/title", namespace: recordings, name: "title", valueType: .string),
    InstantAttribute(
      id: "\(recordings)/startedAtMs",
      namespace: recordings,
      name: "startedAtMs",
      valueType: .number,
      isIndexed: true
    ),
    InstantAttribute(
      id: "\(recordings)/deletedAtMs",
      namespace: recordings,
      name: "deletedAtMs",
      valueType: .number,
      isRequired: false
    ),
    InstantAttribute(
      id: "\(recordings)/tags",
      namespace: recordings,
      name: "tags",
      valueType: .string,
      isRequired: false,
      cardinality: .many
    ),
    InstantAttribute(
      id: "\(recordings)/segments",
      namespace: recordings,
      name: "segments",
      valueType: .ref,
      isRequired: false,
      cardinality: .many,
      isIndexed: true,
      forwardIdentity: "\(recordings)/segments",
      reverseIdentity: "\(segments)/recording",
      linkNamespace: segments
    ),
    InstantAttribute(
      id: "\(recordings)/cover",
      namespace: recordings,
      name: "cover",
      valueType: .ref,
      isRequired: false,
      forwardIdentity: "\(recordings)/cover",
      reverseIdentity: "\(attachments)/coverOf",
      linkNamespace: attachments
    ),
    .primaryKey(namespace: segments),
    InstantAttribute(id: "\(segments)/index", namespace: segments, name: "index", valueType: .number, isIndexed: true),
    InstantAttribute(id: "\(segments)/text", namespace: segments, name: "text", valueType: .string),
    InstantAttribute(id: "\(segments)/final", namespace: segments, name: "final", valueType: .boolean),
    .primaryKey(namespace: attachments),
    InstantAttribute(id: "\(attachments)/kind", namespace: attachments, name: "kind", valueType: .string),
    InstantAttribute(
      id: "\(attachments)/updatedAtMs",
      namespace: attachments,
      name: "updatedAtMs",
      valueType: .number,
      isIndexed: true
    ),
    // A link stored on the attachment: the recording's `attachments` include is a reverse one.
    InstantAttribute(
      id: "\(attachments)/recording",
      namespace: attachments,
      name: "recording",
      valueType: .ref,
      isRequired: false,
      isIndexed: true,
      forwardIdentity: "\(attachments)/recording",
      reverseIdentity: "\(recordings)/attachments",
      linkNamespace: recordings
    ),
  ])

  static let recordingFields = ["id", "ownerUserID", "title", "startedAtMs", "deletedAtMs", "tags", "segments", "cover"]
  static let segmentFields = ["id", "index", "text", "final"]
  static let attachmentFields = ["id", "kind", "updatedAtMs", "recording"]

  /// Twelve of the owner's recordings, newest first the hub, which holds `hubLinkCount` linked lines.
  static func listStore(hubLinkCount: Int) -> TripleIndexes {
    var triples: [InstantTriple] = []
    var time: Int64 = 1
    func insert(_ entityID: String, _ attributeID: String, _ value: InstantValue) {
      triples.append(
        InstantTriple(
          entityID: entityID,
          attributeID: attributeID,
          value: value,
          txID: "tx-\(time)",
          txTime: InstantTimestamp(milliseconds: time)
        )
      )
      time += 1
    }
    let rows = [("hub", 99.0)] + (0..<11).map { ("plain-\($0)", Double($0)) }
    for (entityID, startedAtMs) in rows {
      insert(entityID, "\(recordings)/id", .string(entityID))
      insert(entityID, "\(recordings)/ownerUserID", .string("owner"))
      insert(entityID, "\(recordings)/title", .string(entityID))
      insert(entityID, "\(recordings)/startedAtMs", .number(startedAtMs))
    }
    for index in 0..<hubLinkCount {
      insert("hub", "\(recordings)/segments", .ref(InstantManyCardinalitySortCostTests.uuidString(seed: 9, index: index)))
    }
    return TripleIndexes(triples: triples, attributes: attributes)
  }

  static func randomTriples(_ random: inout InfiniteWindowRandom, count: Int) -> [InstantTriple] {
    var triples: [InstantTriple] = []
    func fact(_ entityID: String, _ attributeID: String, _ value: InstantValue) {
      triples.append(
        InstantTriple(
          entityID: entityID,
          attributeID: attributeID,
          value: value,
          txID: "tx-\(random.int(0...1_000_000))",
          txTime: InstantTimestamp(milliseconds: Int64(random.int(1...1_000_000)))
        )
      )
    }
    for _ in 0..<count {
      switch random.int(0...2) {
      case 0:
        let id = "recording-\(random.int(0...11))"
        if random.chance(70) { fact(id, "\(recordings)/id", .string(id)) }
        if random.chance(70) { fact(id, "\(recordings)/ownerUserID", .string(["owner", "other"][random.int(0...1)])) }
        if random.chance(70) { fact(id, "\(recordings)/title", .string(["alpha", "beta", "gamma"][random.int(0...2)])) }
        if random.chance(70) { fact(id, "\(recordings)/startedAtMs", .number(Double(random.int(0...20)))) }
        if random.chance(25) { fact(id, "\(recordings)/deletedAtMs", .number(Double(random.int(0...20)))) }
        if random.chance(40) { fact(id, "\(recordings)/tags", .string(["red", "green", "blue"][random.int(0...2)])) }
        for _ in 0..<random.int(0...4) {
          fact(id, "\(recordings)/segments", .ref("segment-\(random.int(0...29))"))
        }
        if random.chance(30) { fact(id, "\(recordings)/cover", .ref("attachment-\(random.int(0...14))")) }
      case 1:
        let id = "segment-\(random.int(0...29))"
        fact(id, "\(segments)/id", .string(id))
        if random.chance(80) { fact(id, "\(segments)/index", .number(Double(random.int(0...9)))) }
        if random.chance(80) { fact(id, "\(segments)/text", .string("line \(random.int(0...9))")) }
        if random.chance(50) { fact(id, "\(segments)/final", .bool(random.chance(50))) }
      default:
        let id = "attachment-\(random.int(0...14))"
        fact(id, "\(attachments)/id", .string(id))
        if random.chance(80) { fact(id, "\(attachments)/kind", .string(["photo", "screen"][random.int(0...1)])) }
        if random.chance(80) { fact(id, "\(attachments)/updatedAtMs", .number(Double(random.int(0...30)))) }
        if random.chance(70) { fact(id, "\(attachments)/recording", .ref("recording-\(random.int(0...11))")) }
      }
    }
    return triples
  }

  static func randomSelection(_ random: inout InfiniteWindowRandom, from fields: [String]) -> [String]? {
    guard random.chance(85) else { return nil }
    let chosen = fields.filter { _ in random.chance(40) }
    return chosen.isEmpty ? [fields[random.int(0...(fields.count - 1))]] : chosen
  }

  static func randomPlan(_ random: inout InfiniteWindowRandom, id: String) -> InstantQueryPlan {
    var filters: [InstantQueryFilter] = []
    if random.chance(60) { filters.append(.equals(field: "ownerUserID", value: .string("owner"))) }
    if random.chance(40) { filters.append(.isNull(field: "deletedAtMs")) }
    if random.chance(25) { filters.append(.greaterThan(field: "startedAtMs", value: .number(Double(random.int(0...10))))) }
    if random.chance(15) { filters.append(.like(field: "title", pattern: "%a%")) }
    if random.chance(15) { filters.append(.equals(field: "tags", value: .string("red"))) }
    if random.chance(10) { filters.append(.equals(field: "segments", value: .ref("segment-\(random.int(0...29))"))) }
    if random.chance(10) { filters.append(.or([.isNotNull(field: "cover"), .equals(field: "title", value: .string("beta"))])) }
    let order: InstantQueryOrder? = switch random.int(0...4) {
    case 0: nil
    case 1: InstantQueryOrder("startedAtMs", .descending)
    case 2: InstantQueryOrder("startedAtMs", .ascending)
    case 3: InstantQueryOrder("title", .descending)
    default: InstantQueryOrder("deletedAtMs", .ascending)
    }
    var includes: [InstantQueryInclude] = []
    if random.chance(50) {
      includes.append(
        InstantQueryInclude(
          "segments",
          direction: .forward,
          query: InstantQueryIncludePlan(
            id: "\(id).segments",
            namespace: segments,
            filters: random.chance(30) ? [.equals(field: "final", value: .bool(true))] : [],
            order: random.chance(70) ? InstantQueryOrder("index", .descending) : nil,
            limit: random.chance(70) ? random.int(1...3) : nil,
            selectedFields: randomSelection(&random, from: segmentFields)
          )
        )
      )
    }
    if random.chance(30) {
      includes.append(
        InstantQueryInclude(
          "cover",
          direction: .forward,
          query: InstantQueryIncludePlan(
            id: "\(id).cover",
            namespace: attachments,
            selectedFields: randomSelection(&random, from: attachmentFields)
          )
        )
      )
    }
    if random.chance(40) {
      includes.append(
        InstantQueryInclude(
          "attachments",
          direction: .reverse,
          query: InstantQueryIncludePlan(
            id: "\(id).attachments",
            namespace: attachments,
            order: InstantQueryOrder("updatedAtMs", .descending),
            limit: random.chance(70) ? random.int(1...3) : nil,
            selectedFields: randomSelection(&random, from: attachmentFields)
          )
        )
      )
    }
    return InstantQueryPlan(
      id: id,
      namespace: recordings,
      filters: filters,
      order: order,
      offset: random.chance(20) ? random.int(1...3) : nil,
      limit: random.chance(75) ? random.int(1...6) : nil,
      selectedFields: randomSelection(&random, from: recordingFields),
      includes: includes
    )
  }

  /// `plan` selecting every field of its namespace, and each include every field of its own.
  static func selectingEveryField(_ plan: InstantQueryPlan) -> InstantQueryPlan {
    var plan = plan
    plan.selectedFields = recordingFields
    plan.includes = plan.includes?.map { include in
      var include = include
      let namespace = include.query?.namespace
      include.query?.selectedFields = namespace == segments ? segmentFields : attachmentFields
      return include
    }
    return plan
  }

  /// `values` cut to `plan`'s selection, and each included child to its include's.
  static func cut(_ values: [InstantEntitySnapshot], to plan: InstantQueryPlan) -> [InstantEntitySnapshot] {
    values.map { snapshot in
      var links = snapshot.links
      for include in plan.includes ?? [] {
        guard let children = links?[include.name] else { continue }
        links?[include.name] = children.map { child in
          guard let selected = include.query?.selectedFields.map(Set.init) else { return child }
          return InstantLinkedEntitySnapshot(
            id: child.id,
            namespace: child.namespace,
            values: child.values.filter { selected.contains($0.key) },
            links: child.links
          )
        }
      }
      guard let selected = plan.selectedFields.map(Set.init) else {
        return InstantEntitySnapshot(id: snapshot.id, namespace: snapshot.namespace, values: snapshot.values, links: links)
      }
      return InstantEntitySnapshot(
        id: snapshot.id,
        namespace: snapshot.namespace,
        values: snapshot.values.filter { selected.contains($0.key) },
        links: links
      )
    }
  }

  static func threadCPUNanoseconds(_ work: () -> Void) -> UInt64 {
    let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
    work()
    return clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start
  }
}
