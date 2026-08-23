import Foundation
@testable import InstantSwiftDataCore

/// Deterministically packs benchmark seed work into durable transactions that
/// fit the same transport-step ceiling enforced for product writes.
///
/// Callers choose the atomic operation groups. A plain insert-only seed can use
/// one operation per group, while an entity-creation seed keeps its missing
/// precondition and every field write for that entity in one group.
enum BoundedBenchmarkSeed {
  static func transactions(
    baseID: String,
    atomicOperationGroups: [[InstantTripleOperation]]
  ) -> [InstantStoreTransaction] {
    var batches: [[InstantTripleOperation]] = []
    var currentBatch: [InstantTripleOperation] = []
    var currentStepCount = 0

    for group in atomicOperationGroups {
      let groupStepCount = group.reduce(into: 0) { count, operation in
        count += transportStepCount(of: operation)
      }
      precondition(
        groupStepCount <= InstantAutomaticOutboxClaimLimits.maximumStepCount,
        "A benchmark seed's atomic operation group must fit one durable transaction."
      )

      if !currentBatch.isEmpty,
        currentStepCount + groupStepCount > InstantAutomaticOutboxClaimLimits.maximumStepCount
      {
        batches.append(currentBatch)
        currentBatch.removeAll(keepingCapacity: true)
        currentStepCount = 0
      }

      currentBatch.append(contentsOf: group)
      currentStepCount += groupStepCount
    }

    if !currentBatch.isEmpty {
      batches.append(currentBatch)
    }

    return batches.enumerated().map { batchIndex, operations in
      InstantStoreTransaction(
        id: "\(baseID)-\(String(format: "%04d", batchIndex))",
        operations: operations
      )
    }
  }

  static func entityCreationGroups(
    from operations: [InstantTripleOperation]
  ) -> [[InstantTripleOperation]] {
    var groups: [[InstantTripleOperation]] = []
    for operation in operations {
      switch operation {
      case .requireEntityMissing, .requireEntityMissingByLookup:
        groups.append([operation])

      default:
        precondition(
          !groups.isEmpty,
          "An entity-creation benchmark seed must begin each entity with a missing precondition."
        )
        groups[groups.index(before: groups.endIndex)].append(operation)
      }
    }
    return groups
  }

  private static func transportStepCount(of operation: InstantTripleOperation) -> Int {
    switch operation {
    case .requireEntityMissing, .requireEntityMissingByLookup,
      .requireEntityExists, .requireEntityExistsByLookup, .requireTripleExists:
      0

    case .merge, .mergeByLookup, .insert, .insertByLookup, .retract, .retractByLookup,
      .deleteEntity, .deleteEntityInNamespace, .deleteEntityByLookup,
      .ruleParams, .ruleParamsByLookup:
      1
    }
  }
}
