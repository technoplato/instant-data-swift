import Foundation

struct InstantOptimisticEffectFootprint: Equatable, Sendable {
  static let currentVersion = 2

  var entityIDs: Set<String>
  var isGlobal: Bool

  static func normalized(for mutation: PendingMutation) -> Self? {
    guard let overlayState = mutation.optimisticOverlayState else { return nil }
    guard overlayState != .removed else {
      return Self(entityIDs: [], isGlobal: false)
    }
    guard mutation.provesReplayableOptimisticEffectReceipt else { return nil }

    var footprint = Self(entityIDs: [], isGlobal: false)
    footprint.formUnion(mutation.transaction.operations)
    if let rollbackTransaction = mutation.rollbackTransaction {
      footprint.formUnion(rollbackTransaction.operations)
    }
    return footprint
  }

  private mutating func formUnion(_ operations: [InstantTripleOperation]) {
    for operation in operations {
      switch operation {
      case let .merge(triple), let .insert(triple), let .retract(triple):
        entityIDs.insert(triple.entityID)
        switch triple.value {
        case let .ref(entityID):
          entityIDs.insert(entityID)
        case .lookupRef:
          isGlobal = true
        case .null, .string, .number, .bool, .date, .json:
          break
        }

      case let .deleteEntity(entityID), let .deleteEntityInNamespace(entityID, _):
        entityIDs.insert(entityID)

      case .mergeByLookup, .insertByLookup, .retractByLookup, .deleteEntityByLookup:
        isGlobal = true

      case let .requireEntityMissing(entityID, _),
        let .requireEntityExists(entityID, _):
        entityIDs.insert(entityID)

      case let .requireTripleExists(entityID, _, value):
        entityIDs.insert(entityID)
        switch value {
        case let .ref(targetEntityID):
          entityIDs.insert(targetEntityID)
        case .lookupRef:
          isGlobal = true
        case .null, .string, .number, .bool, .date, .json:
          break
        }

      case .requireEntityMissingByLookup,
        .requireEntityExistsByLookup,
        .ruleParams,
        .ruleParamsByLookup:
        isGlobal = true
      }
    }
  }
}

struct InstantTerminalFailureComponent: Sendable {
  var target: PendingMutation
  var successors: [PendingMutation]
  var targetPosition: InstantOutboxDeliveryPosition
  var expectedStoreRevision: Int64
  var rowRevisions: [String: Int64]
  var decodedBodyCount: Int
  var decodedBodyByteCount: Int

  var ids: Set<String> {
    Set([target.id] + successors.map(\.id))
  }
}

enum InstantTerminalFailureComponentLoad: Sendable {
  case ready(InstantTerminalFailureComponent)
  case staleClaim
  case alreadyTerminal
  case normalizationRequired(firstMutationID: String)
  case componentLimitExceeded(
    mutationCountAtLeast: Int,
    encodedBodyByteCountAtLeast: Int
  )
}

struct InstantOptimisticEffectNormalizationResult: Sendable {
  var normalizedMutationIDs: [String]
  var blockedMutationID: String?
  var decodedBodyCount: Int
  var decodedBodyByteCount: Int
}

struct InstantTerminalFailureCommit: Sendable {
  var failedMutation: PendingMutation?
  var rebasedSuccessors: [PendingMutation]
  var pendingMutationCount: Int
  var didChange: Bool
}
