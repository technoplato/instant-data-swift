import Foundation

public struct CounterRecord: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var count: Int
  public var createdAt: InstantTimestamp

  public init(id: String, count: Int, createdAt: InstantTimestamp) {
    self.id = id
    self.count = count
    self.createdAt = createdAt
  }
}

public struct SharedCounterRecord: Hashable, Codable, Sendable, Identifiable {
  public var id: String { counter.id }
  public var counter: CounterRecord
  public var isShared: Bool
  public var shareID: String?
  public var shareRole: InstantShareRole?
  public var shareMemberCount: Int

  public init(
    counter: CounterRecord,
    isShared: Bool,
    shareID: String?,
    shareRole: InstantShareRole?,
    shareMemberCount: Int
  ) {
    self.counter = counter
    self.isShared = isShared
    self.shareID = shareID
    self.shareRole = shareRole
    self.shareMemberCount = shareMemberCount
  }
}

public enum CounterExample {
  public static let namespace = "counters"
  public static let firstSeedIDName = "examples.counters.seed.first"
  public static let secondSeedIDName = "examples.counters.seed.second"

  public static let attributes: [InstantAttribute] = [
    .primaryKey(namespace: namespace),
    InstantAttribute(
      id: "counters/count",
      namespace: namespace,
      name: "count",
      valueType: .number,
      isIndexed: true
    ),
    InstantAttribute(
      id: "counters/createdAt",
      namespace: namespace,
      name: "createdAt",
      valueType: .date,
      isIndexed: true
    ),
  ]

  public static let query = InstantQueryPlan(
    id: "examples.counters.list",
    namespace: namespace,
    order: InstantQueryOrder("createdAt", .ascending)
  )

  public static func createOperations(
    id: String,
    count: Int = 0,
    createdAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      .requireEntityMissing(entityID: id, namespace: namespace),
    ] + upsertOperations(
      id: id,
      count: count,
      createdAt: createdAt,
      transactionID: transactionID
    )
  }

  public static func upsertOperations(
    id: String,
    count: Int,
    createdAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      identityOperation(id: id, updatedAt: createdAt, transactionID: transactionID),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "counters/count",
          value: .number(Double(count)),
          txID: transactionID,
          txTime: createdAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "counters/createdAt",
          value: .date(Date(timeIntervalSince1970: Double(createdAt.milliseconds) / 1000)),
          txID: transactionID,
          txTime: createdAt
        )
      ),
    ]
  }

  public static func updateCountOperations(
    id: String,
    count: Int,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: id, namespace: namespace),
      identityOperation(id: id, updatedAt: updatedAt, transactionID: transactionID),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "counters/count",
          value: .number(Double(count)),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
    ]
  }

  public static func deleteOperations(id: String) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: id, namespace: namespace),
      .deleteEntityInNamespace(entityID: id, namespace: namespace),
    ]
  }

  public static func sharedRows(
    counters: [CounterRecord],
    shares: [InstantShareSnapshot],
    userID: String? = nil
  ) -> [SharedCounterRecord] {
    counters.map { counter in
      let snapshot = shares.first {
        !$0.share.isRevoked
          && $0.share.rootNamespace == namespace
          && $0.share.rootID == counter.id
      }
      let activeMemberships = snapshot?.memberships.filter { !$0.isRevoked } ?? []
      let currentUserRole =
        userID.flatMap { userID in
          activeMemberships.first { $0.userID == userID }?.role
        } ?? activeMemberships.first?.role
      return SharedCounterRecord(
        counter: counter,
        isShared: snapshot != nil,
        shareID: snapshot?.share.id,
        shareRole: currentUserRole,
        shareMemberCount: activeMemberships.count
      )
    }
  }

  public static func decode(_ snapshots: [InstantEntitySnapshot]) throws -> [CounterRecord] {
    try snapshots.map { snapshot in
      guard case let .number(count) = snapshot.values["count"]?.first
      else {
        throw decodeError(snapshot: snapshot, field: "count", expected: "number")
      }
      guard count.rounded() == count else {
        throw decodeError(snapshot: snapshot, field: "count", expected: "integer number")
      }
      guard case let .date(createdAt) = snapshot.values["createdAt"]?.first
      else {
        throw decodeError(snapshot: snapshot, field: "createdAt", expected: "date")
      }
      return CounterRecord(
        id: snapshot.id,
        count: Int(count),
        createdAt: InstantTimestamp(
          milliseconds: Int64((createdAt.timeIntervalSince1970 * 1000).rounded())
        )
      )
    }
  }

  private static func identityOperation(
    id: String,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> InstantTripleOperation {
    .insert(
      InstantTriple(
        entityID: id,
        attributeID: InstantAttribute.primaryKeyID(namespace: namespace),
        value: .string(id),
        txID: transactionID,
        txTime: updatedAt
      )
    )
  }

  private static func decodeError(
    snapshot: InstantEntitySnapshot,
    field: String,
    expected: String
  ) -> InstantError {
    InstantError(
      code: .decodeFailed,
      operation: "decode counter example",
      namespace: namespace,
      path: field,
      localID: snapshot.id,
      message: "Expected \(expected) for counter field '\(field)'.",
      recovery: "Inspect the local CloudKitDemo counter triples and attributes."
    )
  }
}
