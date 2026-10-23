import CustomDump
import Darwin
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// #1007: before refreshing a verified page, a publication asks of each changed entity whether it is in the page's result
/// set and where (#654, and the skip for pages with includes). The answer read the entity's whole snapshot, and a
/// recording's whole snapshot materializes every link set it holds, thousands of refs sorted on every read. A heartbeat
/// of a long recording asked it twice, before and after, for every list page that does not show the recording, and
/// cost more than refreshing those pages had. The answer needs only the fields the plan's filters and order name.
@Suite
struct InstantResultSetMembershipCostTests {
  /// Placing a recording that holds 4,000 linked lines in a list costs about what placing one without links costs.
  @Test
  func placingALinkHubCostsAboutWhatPlacingARowWithoutLinksCosts() {
    let (indexes, attributes) = Self.store(hubLinkCount: 4_000)
    let plan = InstantQueryPlan(
      id: "membership.list",
      namespace: Self.namespace,
      filters: [.equals(field: "ownerUserID", value: .string("owner"))],
      order: InstantQueryOrder("startedAtMs", .descending),
      limit: 12
    )
    expectNoDifference(
      indexes.resultSetMembership("hub", plan: plan, attributes: attributes),
      .member(orderValue: .number(2))
    )
    expectNoDifference(
      indexes.resultSetMembership("plain", plan: plan, attributes: attributes),
      .member(orderValue: .number(1))
    )
    let hub = Self.threadCPUNanoseconds {
      for _ in 0..<200 { _ = indexes.resultSetMembership("hub", plan: plan, attributes: attributes) }
    }
    let plain = Self.threadCPUNanoseconds {
      for _ in 0..<200 { _ = indexes.resultSetMembership("plain", plan: plan, attributes: attributes) }
    }
    let ratio = Double(hub) / Double(max(plain, 1))
    #expect(ratio < 10, "placing the hub cost \(ratio) times placing a row without links")
  }

  /// Wherever a plan's filters and order place an entity, the answer is the one the entity's whole snapshot gives: for
  /// every filter kind, missing and many-cardinality fields, ids, links, and writes after the store was built.
  @Test(arguments: [UInt64(41_007), 41_008, 41_009, 41_010])
  func placingAgreesWithTheWholeSnapshot(seed: UInt64) {
    var random = InfiniteWindowRandom(seed: seed)
    let attributes = Self.attributes
    var triples: [InstantTriple] = []
    var time: Int64 = 1
    func fact(_ entityID: String, _ name: String, _ value: InstantValue) -> InstantTriple {
      defer { time += 1 }
      return InstantTriple(
        entityID: entityID,
        attributeID: "\(Self.namespace)/\(name)",
        value: value,
        txID: "tx-\(time)",
        txTime: InstantTimestamp(milliseconds: time)
      )
    }
    func randomFacts(_ entityID: String) -> [InstantTriple] {
      var facts: [InstantTriple] = []
      if random.chance(80) { facts.append(fact(entityID, "id", .string(entityID))) }
      if random.chance(70) { facts.append(fact(entityID, "ownerUserID", .string(Self.owners[random.int(0...2)]))) }
      if random.chance(70) { facts.append(fact(entityID, "title", .string(Self.titles[random.int(0...3)]))) }
      if random.chance(70) { facts.append(fact(entityID, "startedAtMs", .number(Double(random.int(0...9))))) }
      if random.chance(30) { facts.append(fact(entityID, "deletedAtMs", .number(Double(random.int(0...9))))) }
      for _ in 0..<random.int(0...3) {
        facts.append(fact(entityID, "tags", .string(Self.tags[random.int(0...3)])))
      }
      for _ in 0..<random.int(0...12) {
        facts.append(fact(entityID, "segments", .ref("segment-\(random.int(0...40))")))
      }
      return facts
    }
    let entityIDs = (0..<30).map { "entity-\($0)" } + ["segment-1", "nobody"]
    for entityID in entityIDs.prefix(30) {
      triples += randomFacts(entityID)
    }
    var indexes = TripleIndexes(triples: triples, attributes: attributes)
    // Later writes take the store's write path, interning what they write.
    for _ in 0..<40 {
      let entityID = entityIDs[random.int(0...29)]
      for triple in randomFacts(entityID).prefix(2) {
        _ = indexes.apply(.insert(triple), attributes: attributes)
      }
      indexes.finishInternCachesAfterWrite(attributes: attributes)
    }

    var actual: [String] = []
    var expected: [String] = []
    for planIndex in 0..<120 {
      let plan = InstantQueryPlan(
        id: "membership.random.\(planIndex)",
        namespace: Self.namespace,
        filters: (0..<random.int(0...3)).map { _ in Self.randomFilter(&random, depth: 0) },
        order: Self.randomOrder(&random)
      )
      for entityID in entityIDs {
        let label = "plan \(planIndex) \(plan.filters) \(String(describing: plan.order)) entity \(entityID)"
        let placed = indexes.resultSetMembership(entityID, plan: plan, attributes: attributes)
        let whole = Self.wholeSnapshotMembership(entityID, plan: plan, indexes: indexes)
        actual.append("\(label): \(Self.describe(placed, plan: plan))")
        expected.append("\(label): \(Self.describe(whole, plan: plan))")
      }
    }
    expectNoDifference(actual, expected)
  }

  // MARK: - Helpers

  static let namespace = "membershipRecordings"
  static let owners = ["owner", "other", "third"]
  static let titles = ["alpha", "beta", "gamma", "Alphabet"]
  static let tags = ["red", "green", "blue", "Red"]

  static let attributes = AttributeStore(attributes: [
    .primaryKey(namespace: namespace),
    InstantAttribute(
      id: "\(namespace)/ownerUserID",
      namespace: namespace,
      name: "ownerUserID",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(id: "\(namespace)/title", namespace: namespace, name: "title", valueType: .string),
    InstantAttribute(
      id: "\(namespace)/startedAtMs",
      namespace: namespace,
      name: "startedAtMs",
      valueType: .number,
      isIndexed: true
    ),
    InstantAttribute(
      id: "\(namespace)/deletedAtMs",
      namespace: namespace,
      name: "deletedAtMs",
      valueType: .number,
      isRequired: false
    ),
    InstantAttribute(
      id: "\(namespace)/tags",
      namespace: namespace,
      name: "tags",
      valueType: .string,
      isRequired: false,
      cardinality: .many
    ),
    InstantAttribute(
      id: "\(namespace)/segments",
      namespace: namespace,
      name: "segments",
      valueType: .ref,
      isRequired: false,
      cardinality: .many,
      isIndexed: true,
      forwardIdentity: "\(namespace)/segments",
      reverseIdentity: "membershipSegments/recording",
      linkNamespace: "membershipSegments"
    ),
  ])

  /// What placing `entityID` answered before #1007: the entity's whole snapshot, filtered, and its order value.
  static func wholeSnapshotMembership(
    _ entityID: String,
    plan: InstantQueryPlan,
    indexes: TripleIndexes
  ) -> InstantResultSetMembership {
    guard let snapshot = indexes.entitySnapshot(entityID, plan: plan, attributes: attributes) else { return .absent }
    let order = plan.order ?? .serverCreatedAt
    return .member(orderValue: order.isServerCreatedAt ? nil : snapshot.values[order.field]?.first)
  }

  /// A plan ordered by server creation time places by the id fact's stamp, read the same way either side: compare
  /// membership only.
  static func describe(_ membership: InstantResultSetMembership, plan: InstantQueryPlan) -> String {
    if (plan.order ?? .serverCreatedAt).isServerCreatedAt, case .member = membership { return "member" }
    return "\(membership)"
  }

  static func randomFilter(_ random: inout InfiniteWindowRandom, depth: Int) -> InstantQueryFilter {
    let owner = InstantValue.string(owners[random.int(0...2)])
    let title = InstantValue.string(titles[random.int(0...3)])
    let number = InstantValue.number(Double(random.int(0...9)))
    switch random.int(0...(depth < 2 ? 15 : 13)) {
    case 0: return .equals(field: "ownerUserID", value: owner)
    case 1: return .notEquals(field: "title", value: title)
    case 2: return .greaterThan(field: "startedAtMs", value: number)
    case 3: return .greaterThanOrEqual(field: "startedAtMs", value: number)
    case 4: return .lessThan(field: "deletedAtMs", value: number)
    case 5: return .lessThanOrEqual(field: "startedAtMs", value: number)
    case 6: return .in(field: "ownerUserID", values: [owner, .string(owners[random.int(0...2)])])
    case 7: return .like(field: "title", pattern: "%lph%")
    case 8: return .iLike(field: "title", pattern: "alpha%")
    case 9: return .isNull(field: "deletedAtMs")
    case 10: return .isNotNull(field: "startedAtMs")
    case 11: return .equals(field: "id", value: .string("entity-\(random.int(0...29))"))
    case 12: return .equals(field: "tags", value: .string(tags[random.int(0...3)]))
    case 13: return .equals(field: "segments", value: .ref("segment-\(random.int(0...40))"))
    case 14:
      return .and((0..<random.int(1...3)).map { _ in randomFilter(&random, depth: depth + 1) })
    default:
      return .or((0..<random.int(1...3)).map { _ in randomFilter(&random, depth: depth + 1) })
    }
  }

  static func randomOrder(_ random: inout InfiniteWindowRandom) -> InstantQueryOrder? {
    switch random.int(0...5) {
    case 0: return nil
    case 1: return InstantQueryOrder("startedAtMs", .descending)
    case 2: return InstantQueryOrder("startedAtMs", .ascending)
    case 3: return InstantQueryOrder("title", .descending)
    case 4: return InstantQueryOrder("deletedAtMs", .ascending)
    default: return .serverCreatedAt
    }
  }

  /// A hub recording holding `hubLinkCount` linked lines, and a plain one holding none, both the owner's.
  static func store(hubLinkCount: Int) -> (TripleIndexes, AttributeStore) {
    var triples: [InstantTriple] = []
    var time: Int64 = 1
    func insert(_ entityID: String, _ name: String, _ value: InstantValue) {
      triples.append(
        InstantTriple(
          entityID: entityID,
          attributeID: "\(namespace)/\(name)",
          value: value,
          txID: "tx-\(time)",
          txTime: InstantTimestamp(milliseconds: time)
        )
      )
      time += 1
    }
    for (entityID, startedAtMs) in [("hub", 2.0), ("plain", 1.0)] {
      insert(entityID, "id", .string(entityID))
      insert(entityID, "ownerUserID", .string("owner"))
      insert(entityID, "title", .string(entityID))
      insert(entityID, "startedAtMs", .number(startedAtMs))
    }
    for index in 0..<hubLinkCount {
      insert("hub", "segments", .ref(InstantManyCardinalitySortCostTests.uuidString(seed: 7, index: index)))
    }
    return (TripleIndexes(triples: triples, attributes: attributes), attributes)
  }

  static func threadCPUNanoseconds(_ work: () -> Void) -> UInt64 {
    let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
    work()
    return clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start
  }
}
