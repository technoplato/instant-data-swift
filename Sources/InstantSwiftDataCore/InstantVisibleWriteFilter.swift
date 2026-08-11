import Foundation
import IssueReporting

package struct InstantVisibleWriteKey: Hashable, Sendable {
  var entityID: String
  var attributeID: String
}

package struct InstantAuthoritativeWriteCoverage: Sendable {
  private var replacementKeys: Set<InstantVisibleWriteKey> = []
  private var exactValues: Set<InstantAuthoritativeWriteValue> = []
  private var exactMergeValues: Set<InstantAuthoritativeWriteValue> = []
  private var fullyCoveredEntityIDs: Set<String> = []
  private var coveredNamespaces: Set<InstantAuthoritativeEntityNamespace> = []
  private var attributes: AttributeStore

  init(
    operations: [InstantTripleOperation],
    attributes: AttributeStore,
    previousChangedEntityTriples: [String: [InstantTriple]],
    changedEntityTriples: [String: [InstantTriple]]
  ) {
    self.attributes = attributes
    let previousValues = Set(
      previousChangedEntityTriples.values.lazy.flatMap { triples in
        triples.lazy.map {
          let key = InstantVisibleWriteKey(entityID: $0.entityID, attributeID: $0.attributeID)
          return InstantAuthoritativeWriteValue(key: key, value: $0.value)
        }
      }
    )
    let changedKeys = Set(
      changedEntityTriples.values.lazy.flatMap { triples in
        triples.lazy.map {
          InstantVisibleWriteKey(entityID: $0.entityID, attributeID: $0.attributeID)
        }
      }
    )
    for operation in operations {
      switch operation {
      case let .insert(triple):
        let key = InstantVisibleWriteKey(
          entityID: triple.entityID,
          attributeID: triple.attributeID
        )
        replacementKeys.insert(key)
        exactValues.insert(InstantAuthoritativeWriteValue(key: key, value: triple.value))
      case let .retract(triple):
        let key = InstantVisibleWriteKey(
          entityID: triple.entityID,
          attributeID: triple.attributeID
        )
        // Upstream retracts an exact EAV value, even for cardinality-one attributes. Treat
        // it as whole-slot replacement evidence only when this authoritative transition
        // actually removed that exact value and left the entity/attribute key absent.
        let value = InstantAuthoritativeWriteValue(key: key, value: triple.value)
        if attributes[triple.attributeID]?.cardinality == .one,
          previousValues.contains(value),
          !changedKeys.contains(key)
        {
          replacementKeys.insert(key)
        }
        exactValues.insert(value)
      case let .merge(triple):
        let key = InstantVisibleWriteKey(
          entityID: triple.entityID,
          attributeID: triple.attributeID
        )
        exactMergeValues.insert(InstantAuthoritativeWriteValue(key: key, value: triple.value))
      case let .deleteEntity(entityID):
        fullyCoveredEntityIDs.insert(entityID)
      case let .deleteEntityInNamespace(entityID, namespace):
        coveredNamespaces.insert(
          InstantAuthoritativeEntityNamespace(entityID: entityID, namespace: namespace)
        )
      case .requireEntityMissing, .requireEntityMissingByLookup,
        .requireEntityExists, .requireEntityExistsByLookup,
        .requireTripleExists,
        .insertByLookup, .mergeByLookup, .retractByLookup,
        .deleteEntityByLookup,
        .ruleParams, .ruleParamsByLookup:
        break
      }
    }
  }

  func covers(_ operations: [InstantTripleOperation]) -> Bool {
    var hasMaterializedWrite = false
    for operation in operations {
      switch operation {
      case let .insert(triple), let .retract(triple):
        hasMaterializedWrite = true
        let key = InstantVisibleWriteKey(
          entityID: triple.entityID,
          attributeID: triple.attributeID
        )
        let namespaceIsCovered = attributes[triple.attributeID].map {
          coveredNamespaces.contains(
            InstantAuthoritativeEntityNamespace(
              entityID: triple.entityID,
              namespace: $0.namespace
            )
          )
        } ?? false
        let isCovered: Bool
        if fullyCoveredEntityIDs.contains(triple.entityID) || namespaceIsCovered {
          isCovered = true
        } else if attributes[triple.attributeID]?.cardinality == .one {
          isCovered = replacementKeys.contains(key)
            || exactValues.contains(
              InstantAuthoritativeWriteValue(key: key, value: triple.value)
            )
        } else {
          isCovered = exactValues.contains(
            InstantAuthoritativeWriteValue(key: key, value: triple.value)
          )
        }
        guard isCovered else {
          return false
        }
      case let .merge(triple):
        hasMaterializedWrite = true
        let key = InstantVisibleWriteKey(
          entityID: triple.entityID,
          attributeID: triple.attributeID
        )
        let namespaceIsCovered = attributes[triple.attributeID].map {
          coveredNamespaces.contains(
            InstantAuthoritativeEntityNamespace(
              entityID: triple.entityID,
              namespace: $0.namespace
            )
          )
        } ?? false
        let exactMerge = InstantAuthoritativeWriteValue(key: key, value: triple.value)
        guard fullyCoveredEntityIDs.contains(triple.entityID)
          || namespaceIsCovered
          || (attributes[triple.attributeID]?.cardinality == .one
            && replacementKeys.contains(key))
          || exactMergeValues.contains(exactMerge)
        else { return false }
      case let .deleteEntity(entityID):
        hasMaterializedWrite = true
        guard fullyCoveredEntityIDs.contains(entityID) else { return false }
      case let .deleteEntityInNamespace(entityID, namespace):
        hasMaterializedWrite = true
        guard fullyCoveredEntityIDs.contains(entityID)
          || coveredNamespaces.contains(
            InstantAuthoritativeEntityNamespace(entityID: entityID, namespace: namespace)
          )
        else { return false }
      case .insertByLookup, .mergeByLookup, .retractByLookup, .deleteEntityByLookup:
        // The authoritative payload is lowered to concrete entity ids. Without resolving the
        // lookup against that exact payload, coverage cannot be proven, so retain the receipt.
        return false
      case .requireEntityMissing, .requireEntityMissingByLookup,
        .requireEntityExists, .requireEntityExistsByLookup,
        .requireTripleExists,
        .ruleParams, .ruleParamsByLookup:
        break
      }
    }
    return hasMaterializedWrite
  }
}

package struct InstantAuthoritativeWriteValue: Hashable, Sendable {
  var key: InstantVisibleWriteKey
  var value: InstantValue
}

package struct InstantAuthoritativeEntityNamespace: Hashable, Sendable {
  var entityID: String
  var namespace: String
}

package struct InstantVisibleWriteFilter: Sendable {
  private var attributesByID: [String: InstantAttribute]
  private var newestVisibleWrite: [InstantVisibleWriteKey: InstantTimestamp]

  init(
    attributesByID: [String: InstantAttribute],
    newestVisibleWrite: [InstantVisibleWriteKey: InstantTimestamp]
  ) {
    self.attributesByID = attributesByID
    self.newestVisibleWrite = newestVisibleWrite
  }

  static func writeKeys(in mutations: [PendingMutation]) -> Set<InstantVisibleWriteKey> {
    writeKeys(in: mutations.flatMap(\.transaction.operations))
  }

  static func writeKeys(
    in operations: [InstantTripleOperation]
  ) -> Set<InstantVisibleWriteKey> {
    Set(
      operations.compactMap { operation in
        switch operation {
        case let .insert(triple), let .merge(triple):
          return InstantVisibleWriteKey(
            entityID: triple.entityID,
            attributeID: triple.attributeID
          )
        case .requireEntityMissing, .requireEntityMissingByLookup,
          .requireEntityExists, .requireEntityExistsByLookup,
          .requireTripleExists,
          .insertByLookup, .mergeByLookup,
          .retract, .retractByLookup,
          .deleteEntity, .deleteEntityInNamespace, .deleteEntityByLookup,
          .ruleParams, .ruleParamsByLookup:
          return nil
        }
      }
    )
  }

  func discardingWritesOlderThanVisibleState(
    _ operations: [InstantTripleOperation],
    preserving queuedSuccessorWriteKeys: Set<InstantVisibleWriteKey> = []
  ) -> [InstantTripleOperation] {
    return operations.filter { operation in
      let triple: InstantTriple
      switch operation {
      case .insert(let value), .merge(let value):
        triple = value

      case .requireEntityMissing, .requireEntityMissingByLookup,
        .requireEntityExists, .requireEntityExistsByLookup,
        .requireTripleExists,
        .insertByLookup, .mergeByLookup,
        .retract, .retractByLookup,
        .deleteEntity, .deleteEntityInNamespace, .deleteEntityByLookup,
        .ruleParams, .ruleParamsByLookup:
        return true
      }

      guard let attribute = attributesByID[triple.attributeID],
        attribute.cardinality == .one,
        !attribute.primaryKey
      else { return true }
      let key = InstantVisibleWriteKey(
        entityID: triple.entityID,
        attributeID: triple.attributeID
      )
      if queuedSuccessorWriteKeys.contains(key) { return true }
      guard let visibleWrite = newestVisibleWrite[key] else { return true }
      return visibleWrite <= triple.txTime
    }
  }
}
