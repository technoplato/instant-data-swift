import CustomDump
import Foundation
import SQLite3
import Testing
@testable import InstantSwiftDataCore

@Suite(.serialized)
struct AttributeStoreIdentityUpgradeTests {
  @Test
  func mergingDeclaredRelationPreservesDurablePhysicalIdentityAndAliasesLogicalWrites()
    async throws
  {
    let physicalRelationID = "server-7e4f80fb-5647-4c48-9e33-bde10cf49e63"
    let declaredRelation = InstantAttribute(
      id: "parents/children",
      namespace: "parents",
      name: "children",
      valueType: .ref,
      isRequired: false,
      cardinality: .many,
      isIndexed: true,
      isUnique: true,
      forwardIdentity: "parents/children",
      reverseIdentity: "children/parent",
      linkNamespace: "children",
      onDeleteReverse: .cascade
    )
    let durableRelation = InstantAttribute(
      id: physicalRelationID,
      namespace: declaredRelation.namespace,
      name: declaredRelation.name,
      valueType: .ref,
      isRequired: true,
      cardinality: .many,
      isIndexed: false,
      isUnique: true,
      forwardIdentity: declaredRelation.forwardIdentity,
      reverseIdentity: declaredRelation.reverseIdentity,
      linkNamespace: declaredRelation.linkNamespace,
      onDelete: .none,
      onDeleteReverse: .none
    )
    var previouslyPersistedLogicalRelation = declaredRelation
    previouslyPersistedLogicalRelation.isIndexed = false
    previouslyPersistedLogicalRelation.onDeleteReverse = .none
    let reciprocalChildRelation = InstantAttribute(
      id: "children/parent",
      namespace: "children",
      name: "parent",
      valueType: .ref,
      isRequired: false,
      cardinality: .one,
      isIndexed: true,
      isUnique: true,
      forwardIdentity: "children/parent",
      reverseIdentity: "parents/children",
      linkNamespace: "parents",
      onDelete: .cascade
    )
    let attributes = [
      .primaryKey(namespace: "parents"),
      .primaryKey(namespace: "children"),
      InstantAttribute(
        id: "children/name",
        namespace: "children",
        name: "name",
        valueType: .string
      ),
      durableRelation,
      previouslyPersistedLogicalRelation,
      reciprocalChildRelation,
    ]
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let legacyTimestamp = InstantTimestamp(milliseconds: 1_700_000_001_000)
    let store = InstantStore(
      snapshot: InstantStoreSnapshot(
        attributes: attributes,
        triples: [
          triple("parent-1", "parents/id", .string("parent-1"), timestamp: timestamp),
          triple("child-1", "children/id", .string("child-1"), timestamp: timestamp),
          triple("child-1", "children/name", .string("First"), timestamp: timestamp),
          triple("parent-1", physicalRelationID, .ref("child-1"), timestamp: timestamp),
          triple(
            "child-1",
            reciprocalChildRelation.id,
            .ref("parent-1"),
            timestamp: legacyTimestamp,
            txID: "legacy-child-link-wins-dedup"
          ),
          triple(
            "child-legacy",
            "children/id",
            .string("child-legacy"),
            timestamp: legacyTimestamp
          ),
          triple(
            "child-legacy",
            "children/name",
            .string("Legacy only"),
            timestamp: legacyTimestamp
          ),
          triple(
            "child-legacy",
            reciprocalChildRelation.id,
            .ref("parent-1"),
            timestamp: legacyTimestamp,
            txID: "legacy-child-link-only"
          ),
        ]
      )
    )

    _ = await store.mergeAttributes([declaredRelation])

    let upgraded = await store.snapshot()
    let upgradedRelations = upgraded.attributes.filter {
      $0.namespace == declaredRelation.namespace && $0.name == declaredRelation.name
    }
    let expectedRelation = durableRelation
    expectNoDifference(upgradedRelations, [expectedRelation])
    expectNoDifference(
      upgraded.attributes.filter {
        $0.namespace == reciprocalChildRelation.namespace
          && $0.name == reciprocalChildRelation.name
      },
      []
    )

    var restoredAttributes = AttributeStore(attributes: upgraded.attributes)
    restoredAttributes.merge([declaredRelation])
    expectNoDifference(restoredAttributes[declaredRelation.id], expectedRelation)
    expectNoDifference(
      restoredAttributes.lookupAttribute(id: declaredRelation.id)?.attribute.id,
      physicalRelationID
    )
    expectNoDifference(
      restoredAttributes.lookupAttribute(id: reciprocalChildRelation.id),
      InstantResolvedLookupAttribute(
        attribute: expectedRelation,
        direction: .reverse,
        namespace: "children",
        name: "parent"
      )
    )

    let reconciledRelationTriples = upgraded.triples.filter {
      $0.attributeID == physicalRelationID
    }
    expectNoDifference(
      Set(reconciledRelationTriples.map(\.entityID)),
      Set(["parent-1"])
    )
    expectNoDifference(
      Set(reconciledRelationTriples.map(\.value)),
      Set([InstantValue.ref("child-1"), .ref("child-legacy")])
    )
    let deduplicatedChildLink = try #require(
      reconciledRelationTriples.first { $0.value == .ref("child-1") }
    )
    expectNoDifference(deduplicatedChildLink.txID, "legacy-child-link-wins-dedup")
    expectNoDifference(deduplicatedChildLink.txTime, legacyTimestamp)
    #expect(
      upgraded.triples.allSatisfy { $0.attributeID != reciprocalChildRelation.id }
    )

    // A compact bootstrap need not hydrate every durable row. Simulate a cold legacy child link
    // loaded later, after reciprocal attribute metadata has already been removed.
    let laterLoadedTimestamp = InstantTimestamp(milliseconds: 1_700_000_002_000)
    let laterLoadedAttributes = AttributeStore(attributes: upgraded.attributes)
    let laterLoadedIndexes = TripleIndexes(
      triples: [
        triple("parent-cold", "parents/id", .string("parent-cold"), timestamp: timestamp),
        triple("child-cold", "children/id", .string("child-cold"), timestamp: timestamp),
        triple("child-cold", "children/name", .string("Cold"), timestamp: timestamp),
        triple(
          "child-cold",
          reciprocalChildRelation.id,
          .ref("parent-cold"),
          timestamp: laterLoadedTimestamp,
          txID: "later-loaded-legacy-child-link"
        ),
      ],
      attributes: laterLoadedAttributes
    )
    let laterLoadedPhysicalLink = try #require(
      laterLoadedIndexes.triples.first { $0.attributeID == physicalRelationID }
    )
    expectNoDifference(laterLoadedPhysicalLink.entityID, "parent-cold")
    expectNoDifference(laterLoadedPhysicalLink.value, .ref("child-cold"))
    expectNoDifference(laterLoadedPhysicalLink.txID, "later-loaded-legacy-child-link")
    expectNoDifference(laterLoadedPhysicalLink.txTime, laterLoadedTimestamp)
    let laterLoadedParents = laterLoadedIndexes.materialize(
      InstantQueryPlan(
        id: "parents-with-children.later-loaded-cold-link",
        namespace: "parents",
        includes: [InstantQueryInclude("children")]
      ),
      attributes: laterLoadedAttributes
    )
    expectNoDifference(
      laterLoadedParents.first?.links?["children"]?.map(\.id),
      ["child-cold"]
    )

    let initialParents = await store.materialize(
      InstantQueryPlan(
        id: "parents-with-children.before-logical-write",
        namespace: "parents",
        includes: [InstantQueryInclude("children")]
      )
    )
    expectNoDifference(
      initialParents.first?.links?["children"]?.map(\.id),
      ["child-1", "child-legacy"]
    )

    let logicalReverseTransaction = InstantStoreTransaction(
      id: "logical-relation-write",
      operations: [
        .insert(triple("child-2", "children/id", .string("child-2"), timestamp: timestamp)),
        .insert(triple("child-2", "children/name", .string("Second"), timestamp: timestamp)),
        .insert(
          triple(
            "child-2",
            reciprocalChildRelation.id,
            .ref("parent-1"),
            timestamp: timestamp
          )
        ),
      ]
    )
    _ = try await store.prepare(logicalReverseTransaction)

    let pending = PendingMutation(
      id: logicalReverseTransaction.id,
      createdAt: timestamp,
      transaction: logicalReverseTransaction
    )
    expectNoDifference(pending.transaction, logicalReverseTransaction)
    #expect(
      InstantTransportMutation(pending).txSteps.contains { step in
        guard
          case let .addTriple(entity, attributeID, value, _) = step,
          entity == .id("child-2"),
          attributeID == reciprocalChildRelation.id,
          value == .string("parent-1")
        else { return false }
        return true
      }
    )

    let afterLogicalWrite = await store.snapshot()
    let relationTriples = afterLogicalWrite.triples.filter {
      $0.entityID == "parent-1"
        && [physicalRelationID, declaredRelation.id].contains($0.attributeID)
    }
    expectNoDifference(Set(relationTriples.map(\.attributeID)), Set([physicalRelationID]))
    expectNoDifference(
      Set(relationTriples.map(\.value)),
      Set([.ref("child-1"), .ref("child-2"), .ref("child-legacy")])
    )

    _ = try await store.prepare(
      InstantStoreTransaction(
        id: "reverse-relation-precondition",
        operations: [
          .requireTripleExists(
            entityID: "child-2",
            attributeID: reciprocalChildRelation.id,
            value: .ref("parent-1")
          )
        ]
      )
    )

    let parentLookup = InstantLookupRef(
      attributeID: "parents/id",
      value: .string("parent-1")
    )
    let childLookup = InstantLookupRef(
      attributeID: "children/id",
      value: .string("child-3")
    )
    _ = try await store.prepare(
      InstantStoreTransaction(
        id: "reverse-relation-lookup-write",
        operations: [
          .insert(triple("child-3", "children/id", .string("child-3"), timestamp: timestamp)),
          .insert(triple("child-3", "children/name", .string("Third"), timestamp: timestamp)),
          .insertByLookup(
            entity: childLookup,
            attributeID: reciprocalChildRelation.id,
            value: .lookupRef(parentLookup),
            txID: "reverse-relation-lookup-write",
            txTime: timestamp
          ),
        ]
      )
    )
    let parents = await store.materialize(
      InstantQueryPlan(
        id: "parents-with-children.after-logical-write",
        namespace: "parents",
        includes: [InstantQueryInclude("children")]
      )
    )
    expectNoDifference(
      parents.first?.links?["children"]?.map(\.id).sorted(),
      ["child-1", "child-2", "child-3", "child-legacy"]
    )

    _ = try await store.prepare(
      InstantStoreTransaction(
        id: "reverse-relation-retracts",
        operations: [
          .retract(
            triple(
              "child-2",
              reciprocalChildRelation.id,
              .ref("parent-1"),
              timestamp: timestamp
            )
          ),
          .retractByLookup(
            entity: childLookup,
            attributeID: reciprocalChildRelation.id,
            value: .lookupRef(parentLookup),
            txID: "reverse-relation-retracts",
            txTime: timestamp
          ),
        ]
      )
    )
    let afterRetracts = await store.materialize(
      InstantQueryPlan(
        id: "parents-with-children.after-reverse-retracts",
        namespace: "parents",
        includes: [InstantQueryInclude("children")]
      )
    )
    expectNoDifference(
      afterRetracts.first?.links?["children"]?.map(\.id),
      ["child-1", "child-legacy"]
    )
  }

  @Test
  func reciprocalDeclarationPreservesReversePhysicalServerIdentityForLaterServerWrites()
    async throws
  {
    let physicalParentRelation = InstantAttribute(
      id: "server-af14162d-recordings-route-chunks",
      namespace: "recordings",
      name: "routeChunks",
      valueType: .ref,
      cardinality: .many,
      isIndexed: true,
      isUnique: true,
      forwardIdentity: "recordings/routeChunks",
      reverseIdentity: "recordingRouteChunks/recording",
      linkNamespace: "recordingRouteChunks",
      onDeleteReverse: .cascade
    )
    let declaredChildRelation = InstantAttribute(
      id: "recordingRouteChunks/recording",
      namespace: "recordingRouteChunks",
      name: "recording",
      valueType: .ref,
      cardinality: .one,
      isIndexed: true,
      isUnique: true,
      forwardIdentity: "recordingRouteChunks/recording",
      reverseIdentity: "recordings/routeChunks",
      linkNamespace: "recordings",
      onDelete: .cascade
    )
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_010_000)
    let store = InstantStore(
      snapshot: InstantStoreSnapshot(
        attributes: [
          .primaryKey(namespace: "recordings"),
          .primaryKey(namespace: "recordingRouteChunks"),
          physicalParentRelation,
          declaredChildRelation,
        ],
        triples: [
          triple("recording-1", "recordings/id", .string("recording-1"), timestamp: timestamp),
          triple(
            "chunk-physical",
            "recordingRouteChunks/id",
            .string("chunk-physical"),
            timestamp: timestamp
          ),
          triple(
            "recording-1",
            physicalParentRelation.id,
            .ref("chunk-physical"),
            timestamp: timestamp
          ),
          triple(
            "chunk-logical",
            "recordingRouteChunks/id",
            .string("chunk-logical"),
            timestamp: timestamp
          ),
          triple(
            "chunk-logical",
            declaredChildRelation.id,
            .ref("recording-1"),
            timestamp: timestamp
          ),
        ]
      )
    )

    _ = await store.mergeAttributes([declaredChildRelation])

    let upgraded = await store.snapshot()
    expectNoDifference(
      upgraded.attributes.filter {
        $0.forwardIdentity == physicalParentRelation.forwardIdentity
          || $0.reverseIdentity == physicalParentRelation.forwardIdentity
      },
      [physicalParentRelation]
    )
    #expect(upgraded.triples.allSatisfy { $0.attributeID != declaredChildRelation.id })
    expectNoDifference(
      Set(
        upgraded.triples.filter { $0.attributeID == physicalParentRelation.id }.map(\.value)
      ),
      Set([.ref("chunk-physical"), .ref("chunk-logical")])
    )

    let laterServerTransaction = InstantStoreTransaction(
      id: "later-server-physical-relation",
      operations: [
        .insert(
          triple(
            "chunk-server-later",
            "recordingRouteChunks/id",
            .string("chunk-server-later"),
            timestamp: timestamp,
            txID: "later-server-physical-relation"
          )
        ),
        .insert(
          triple(
            "recording-1",
            physicalParentRelation.id,
            .ref("chunk-server-later"),
            timestamp: timestamp,
            txID: "later-server-physical-relation"
          )
        ),
      ]
    )
    let prepared = try await store.prepare(
      peelingOverlays: [],
      thenApplying: laterServerTransaction
    )
    _ = await store.commitAndPublish(prepared)

    let recordings = await store.materialize(
      InstantQueryPlan(
        id: "recordings-with-route-chunks.after-later-server-write",
        namespace: "recordings",
        includes: [InstantQueryInclude("routeChunks")]
      )
    )
    expectNoDifference(
      recordings.first?.links?["routeChunks"]?.map(\.id).sorted(),
      ["chunk-logical", "chunk-physical", "chunk-server-later"]
    )
    let reverseChunks = await store.materialize(
      InstantQueryPlan(
        id: "route-chunks-with-recording.after-later-server-write",
        namespace: "recordingRouteChunks",
        includes: [InstantQueryInclude("recording", direction: .reverse)]
      )
    )
    expectNoDifference(
      reverseChunks.first { $0.id == "chunk-server-later" }?.links?["recording"]?.map(\.id),
      ["recording-1"]
    )

    // The opposite arrival order is equally important: a local child declaration can be durable
    // before the server publishes its UUID parent attribute. The incoming non-logical ID must win.
    let reverseArrivalStore = InstantStore(
      snapshot: InstantStoreSnapshot(
        attributes: [
          .primaryKey(namespace: "recordings"),
          .primaryKey(namespace: "recordingRouteChunks"),
          declaredChildRelation,
        ],
        triples: [
          triple("recording-2", "recordings/id", .string("recording-2"), timestamp: timestamp),
          triple(
            "chunk-before-server-schema",
            "recordingRouteChunks/id",
            .string("chunk-before-server-schema"),
            timestamp: timestamp
          ),
          triple(
            "chunk-before-server-schema",
            declaredChildRelation.id,
            .ref("recording-2"),
            timestamp: timestamp
          ),
        ]
      )
    )
    _ = await reverseArrivalStore.mergeAttributes([physicalParentRelation])
    let reverseArrivalUpgraded = await reverseArrivalStore.snapshot()
    expectNoDifference(
      reverseArrivalUpgraded.attributes.filter {
        $0.forwardIdentity == physicalParentRelation.forwardIdentity
          || $0.reverseIdentity == physicalParentRelation.forwardIdentity
      },
      [physicalParentRelation]
    )
    #expect(reverseArrivalUpgraded.triples.contains {
      $0.entityID == "recording-2"
        && $0.attributeID == physicalParentRelation.id
        && $0.value == .ref("chunk-before-server-schema")
    })

    let reverseArrivalServerTransaction = InstantStoreTransaction(
      id: "later-server-after-reverse-arrival",
      operations: [
        .insert(
          triple(
            "chunk-after-server-schema",
            "recordingRouteChunks/id",
            .string("chunk-after-server-schema"),
            timestamp: timestamp,
            txID: "later-server-after-reverse-arrival"
          )
        ),
        .insert(
          triple(
            "recording-2",
            physicalParentRelation.id,
            .ref("chunk-after-server-schema"),
            timestamp: timestamp,
            txID: "later-server-after-reverse-arrival"
          )
        ),
      ]
    )
    let reverseArrivalPrepared = try await reverseArrivalStore.prepare(
      peelingOverlays: [],
      thenApplying: reverseArrivalServerTransaction
    )
    _ = await reverseArrivalStore.commitAndPublish(reverseArrivalPrepared)
    let reverseArrivalRecordings = await reverseArrivalStore.materialize(
      InstantQueryPlan(
        id: "recordings-with-route-chunks.after-reverse-arrival",
        namespace: "recordings",
        includes: [InstantQueryInclude("routeChunks")]
      )
    )
    expectNoDifference(
      reverseArrivalRecordings.first?.links?["routeChunks"]?.map(\.id).sorted(),
      ["chunk-after-server-schema", "chunk-before-server-schema"]
    )
  }

  @Test
  func runtimeBootstrapDurablyReconcilesNonresidentReciprocalRelationTriples() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "AttributeStoreIdentityUpgradeTests-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let databaseURL = directory.appending(path: "instant.sqlite")
    let physicalRelationID = "server-physical-parents-children"
    let declaredRelation = InstantAttribute(
      id: "parents/children",
      namespace: "parents",
      name: "children",
      valueType: .ref,
      isRequired: false,
      cardinality: .many,
      isIndexed: true,
      isUnique: true,
      forwardIdentity: "parents/children",
      reverseIdentity: "children/parent",
      linkNamespace: "children",
      onDeleteReverse: .cascade
    )
    let durableRelation = InstantAttribute(
      id: physicalRelationID,
      namespace: declaredRelation.namespace,
      name: declaredRelation.name,
      valueType: .ref,
      isRequired: true,
      cardinality: .many,
      isIndexed: false,
      isUnique: true,
      forwardIdentity: declaredRelation.forwardIdentity,
      reverseIdentity: declaredRelation.reverseIdentity,
      linkNamespace: declaredRelation.linkNamespace,
      onDelete: .none,
      onDeleteReverse: .none
    )
    var previouslyPersistedLogicalRelation = declaredRelation
    previouslyPersistedLogicalRelation.isIndexed = false
    previouslyPersistedLogicalRelation.onDeleteReverse = .none
    let reciprocalChildRelation = InstantAttribute(
      id: "children/parent",
      namespace: "children",
      name: "parent",
      valueType: .ref,
      isRequired: false,
      cardinality: .one,
      isIndexed: true,
      isUnique: true,
      forwardIdentity: "children/parent",
      reverseIdentity: "parents/children",
      linkNamespace: "parents",
      onDelete: .cascade
    )
    let nameAttribute = InstantAttribute(
      id: "children/name",
      namespace: "children",
      name: "name",
      valueType: .string
    )
    let durableAttributes = [
      .primaryKey(namespace: "parents"),
      .primaryKey(namespace: "children"),
      nameAttribute,
      durableRelation,
      previouslyPersistedLogicalRelation,
      reciprocalChildRelation,
    ]
    let canonicalAttributes = [
      .primaryKey(namespace: "parents"),
      .primaryKey(namespace: "children"),
      nameAttribute,
      declaredRelation,
    ]
    let older = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let newer = InstantTimestamp(milliseconds: 1_700_000_001_000)
    let hotTriples = [
      triple("parent-hot", "parents/id", .string("parent-hot"), timestamp: older),
      triple("child-hot", "children/id", .string("child-hot"), timestamp: older),
      triple("child-hot", "children/name", .string("Hot"), timestamp: older),
      triple(
        "parent-hot",
        physicalRelationID,
        .ref("child-hot"),
        timestamp: older,
        txID: "older-hot-parent-link"
      ),
      triple(
        "child-hot",
        reciprocalChildRelation.id,
        .ref("parent-hot"),
        timestamp: newer,
        txID: "newer-hot-child-link"
      ),
    ]
    let coldTriples = [
      triple("parent-cold", "parents/id", .string("parent-cold"), timestamp: older),
      triple("child-cold", "children/id", .string("child-cold"), timestamp: older),
      triple("child-cold", "children/name", .string("Cold"), timestamp: older),
      triple(
        "parent-cold",
        physicalRelationID,
        .ref("child-cold"),
        timestamp: older,
        txID: "older-cold-parent-link"
      ),
      triple(
        "child-cold",
        reciprocalChildRelation.id,
        .ref("parent-cold"),
        timestamp: newer,
        txID: "newer-cold-child-link"
      ),
    ]

    let seedPersistence = try SQLitePersistenceStore(fileURL: databaseURL)
    try await seedPersistence.bootstrap()
    try await seedPersistence.saveSnapshot(
      InstantPersistenceSnapshot(
        store: InstantStoreSnapshot(
          attributes: durableAttributes,
          triples: hotTriples + coldTriples
        )
      )
    )
    let seeded = try await seedPersistence.loadState()
    let hotResult = InstantPersistedLiveQueryResult(
      replacement: InstantLiveQueryResultReplacement(
        key: "parents-with-children.hot",
        triples: hotTriples,
        pageInfo: nil
      ),
      updatedAt: newer
    )
    let ownershipOnlyResult = InstantPersistedLiveQueryResult(
      replacement: InstantLiveQueryResultReplacement(
        key: "parents-with-children.ownership-only-drift",
        triples: [hotTriples[1], hotTriples[0], hotTriples[3]],
        pageInfo: nil
      ),
      updatedAt: newer
    )
    let didSaveLiveOwnership = try await seedPersistence.saveLiveRefresh(
      seeded.snapshot,
      queryResults: [hotResult, ownershipOnlyResult],
      storeChanged: false,
      outboxChanged: false,
      metadataKey: "test.attribute-relation-upgrade",
      metadataValue: "seeded",
      metadataUpdatedAt: newer,
      expectedStoreRevision: seeded.storeRevision,
      expectedOutboxRevision: seeded.outboxRevision,
      expectedAttributeRevision: seeded.attributeRevision
    )
    expectNoDifference(didSaveLiveOwnership, true)
    try rewriteLiveQueryOwnership(
      at: databaseURL,
      queryKey: ownershipOnlyResult.key,
      from: hotTriples[3],
      to: hotTriples[4]
    )

    // Create a real SQLite-owned optimistic receipt. Its network body deliberately remains in
    // the old logical child direction while durable materialization is reconciled around it.
    let pendingRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "relation-upgrade-pending-fixture",
        persistenceURL: databaseURL,
        now: { newer }
      )
    )
    let pendingTransaction = InstantStoreTransaction(
      id: "pending-logical-child-link",
      operations: [
        .insert(
          triple(
            "child-pending",
            "children/id",
            .string("child-pending"),
            timestamp: newer,
            txID: "pending-logical-child-link"
          )
        ),
        .insert(
          triple(
            "child-pending",
            reciprocalChildRelation.id,
            .ref("parent-hot"),
            timestamp: newer,
            txID: "pending-logical-child-link"
          )
        ),
      ]
    )
    _ = try await pendingRuntime.transact(
      pendingTransaction,
      createdAt: newer,
      source: "test.relation-upgrade"
    )

    let beforeUpgrade = try await pendingRuntime.persistence.loadState()
    let compactProbe = try SQLitePersistenceStore(fileURL: databaseURL)
    try await compactProbe.bootstrap()
    let compactBeforeUpgrade = try await compactProbe.loadCompactState()
    #expect(compactBeforeUpgrade.snapshot.store.triples.contains { $0.entityID == "parent-hot" })
    #expect(!compactBeforeUpgrade.snapshot.store.triples.contains { $0.entityID == "parent-cold" })
    #expect(!compactBeforeUpgrade.snapshot.store.triples.contains { $0.entityID == "child-cold" })
    let outboxRowBefore = try readOutboxStorageRow(
      at: databaseURL,
      mutationID: pendingTransaction.id
    )
    let receiptBefore = try await pendingRuntime.persistence
      .optimisticEffectReceiptFingerprintForTesting(id: pendingTransaction.id)
    #expect(receiptBefore != nil)
    let rawColdLinksBefore: [InstantTriple] = try readJSONRows(
      at: databaseURL,
      sql:
        "SELECT json FROM instant_triples WHERE entity_id IN ('parent-cold', 'child-cold') ORDER BY entity_id, attribute_id, value_json"
    )
    #expect(rawColdLinksBefore.contains { $0.attributeID == reciprocalChildRelation.id })

    let upgradedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "relation-upgrade",
        persistenceURL: databaseURL,
        initialAttributes: canonicalAttributes,
        now: { newer }
      )
    )
    let afterUpgrade = try await upgradedRuntime.persistence.loadState()
    let firstBootstrapLiveResultScanCount = await upgradedRuntime.persistence
      .declaredRelationReconciliationLiveResultScanCountForTesting()
    expectNoDifference(firstBootstrapLiveResultScanCount, 2)
    expectNoDifference(afterUpgrade.storeRevision, beforeUpgrade.storeRevision + 1)
    expectNoDifference(afterUpgrade.attributeRevision, beforeUpgrade.attributeRevision + 1)
    expectNoDifference(afterUpgrade.queryResultRevision, beforeUpgrade.queryResultRevision + 1)
    expectNoDifference(afterUpgrade.outboxRevision, beforeUpgrade.outboxRevision)
    expectNoDifference(afterUpgrade.snapshot.outbox, beforeUpgrade.snapshot.outbox)
    expectNoDifference(
      try readOutboxStorageRow(at: databaseURL, mutationID: pendingTransaction.id),
      outboxRowBefore
    )
    let receiptAfter = try await upgradedRuntime.persistence
      .optimisticEffectReceiptFingerprintForTesting(id: pendingTransaction.id)
    expectNoDifference(
      receiptAfter,
      receiptBefore
    )

    let expectedPhysicalRelation = durableRelation
    expectNoDifference(
      afterUpgrade.snapshot.store.attributes.filter {
        [$0.forwardIdentity, $0.reverseIdentity].contains(declaredRelation.forwardIdentity)
          || [$0.forwardIdentity, $0.reverseIdentity].contains(declaredRelation.reverseIdentity)
      },
      [expectedPhysicalRelation]
    )
    let residentLinks = afterUpgrade.snapshot.store.triples.filter {
      $0.attributeID == physicalRelationID
    }
    expectNoDifference(
      residentLinks.map { "\($0.entityID):\($0.value.comparableKey)" }.sorted(),
      [
        "parent-hot:\(InstantValue.ref("child-hot").comparableKey)",
        "parent-hot:\(InstantValue.ref("child-pending").comparableKey)",
      ]
    )
    #expect(afterUpgrade.snapshot.store.triples.allSatisfy {
      $0.attributeID != reciprocalChildRelation.id
        && $0.attributeID != declaredRelation.id
    })
    let rawDurableTriples: [InstantTriple] = try readJSONRows(
      at: databaseURL,
      sql: "SELECT json FROM instant_triples ORDER BY entity_id, attribute_id, value_json"
    )
    let durableLinks = rawDurableTriples.filter { $0.attributeID == physicalRelationID }
    expectNoDifference(
      durableLinks.map { "\($0.entityID):\($0.value.comparableKey)" }.sorted(),
      [
        "parent-cold:\(InstantValue.ref("child-cold").comparableKey)",
        "parent-hot:\(InstantValue.ref("child-hot").comparableKey)",
        "parent-hot:\(InstantValue.ref("child-pending").comparableKey)",
      ]
    )
    let coldLink = try #require(
      durableLinks.first { $0.entityID == "parent-cold" && $0.value == .ref("child-cold") }
    )
    expectNoDifference(coldLink.txID, "newer-cold-child-link")
    expectNoDifference(coldLink.txTime, newer)
    #expect(rawDurableTriples.allSatisfy {
      $0.attributeID != reciprocalChildRelation.id
        && $0.attributeID != declaredRelation.id
    })

    let persistedUpgradedLiveResult = try await upgradedRuntime.persistence.liveQueryResult(
      key: hotResult.key
    )
    let upgradedLiveResult = try #require(persistedUpgradedLiveResult)
    let hotLink = try #require(
      upgradedLiveResult.triples.first {
        $0.attributeID == physicalRelationID && $0.value == .ref("child-hot")
      }
    )
    expectNoDifference(hotLink.txID, "newer-hot-child-link")
    expectNoDifference(hotLink.txTime, newer)
    #expect(upgradedLiveResult.triples.allSatisfy {
      $0.attributeID != reciprocalChildRelation.id
        && $0.attributeID != declaredRelation.id
    })
    let rawOwnershipAttributeIDs = try readSQLiteStrings(
      at: databaseURL,
      sql:
        "SELECT attribute_id FROM instant_live_query_triples WHERE query_key = 'parents-with-children.hot' ORDER BY entity_id, attribute_id, value_json"
    )
    #expect(!rawOwnershipAttributeIDs.contains(reciprocalChildRelation.id))
    #expect(!rawOwnershipAttributeIDs.contains(declaredRelation.id))
    #expect(rawOwnershipAttributeIDs.contains(physicalRelationID))
    let persistedOwnershipOnlyResult = try await upgradedRuntime.persistence.liveQueryResult(
      key: ownershipOnlyResult.key
    )
    let upgradedOwnershipOnlyResult = try #require(persistedOwnershipOnlyResult)
    expectNoDifference(upgradedOwnershipOnlyResult, ownershipOnlyResult)
    let ownershipOnlyAttributeIDs = try readSQLiteStrings(
      at: databaseURL,
      sql:
        "SELECT attribute_id FROM instant_live_query_triples WHERE query_key = 'parents-with-children.ownership-only-drift' ORDER BY entity_id, attribute_id, value_json"
    )
    #expect(!ownershipOnlyAttributeIDs.contains(reciprocalChildRelation.id))
    #expect(ownershipOnlyAttributeIDs.contains(physicalRelationID))

    let fullyLoadedStore = InstantStore(
      snapshot: InstantStoreSnapshot(
        attributes: afterUpgrade.snapshot.store.attributes,
        triples: rawDurableTriples
      )
    )
    let parents = await fullyLoadedStore.materialize(
      InstantQueryPlan(
        id: "parents-with-children.after-durable-reconciliation",
        namespace: "parents",
        includes: [InstantQueryInclude("children")]
      )
    )
    expectNoDifference(
      parents.flatMap { parent in
        parent.links?["children", default: []].map { "\(parent.id):\($0.id)" } ?? []
      }.sorted(),
      [
        "parent-cold:child-cold",
        "parent-hot:child-hot",
        "parent-hot:child-pending",
      ]
    )

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "relation-upgrade-relaunch",
        persistenceURL: databaseURL,
        initialAttributes: canonicalAttributes,
        now: { newer }
      )
    )
    let afterRelaunch = try await relaunchedRuntime.persistence.loadState()
    let secondBootstrapLiveResultScanCount = await relaunchedRuntime.persistence
      .declaredRelationReconciliationLiveResultScanCountForTesting()
    expectNoDifference(secondBootstrapLiveResultScanCount, 0)
    expectNoDifference(afterRelaunch, afterUpgrade)
    expectNoDifference(
      try readOutboxStorageRow(at: databaseURL, mutationID: pendingTransaction.id),
      outboxRowBefore
    )

    // Ordinary canonical writes do not invalidate the completed relation marker.
    let canonicalWrite = InstantStoreTransaction(
      id: "ordinary-canonical-write-after-reconciliation",
      operations: [
        .insert(
          triple(
            "child-canonical-later",
            "children/id",
            .string("child-canonical-later"),
            timestamp: newer,
            txID: "ordinary-canonical-write-after-reconciliation"
          )
        )
      ]
    )
    _ = try await relaunchedRuntime.transact(
      canonicalWrite,
      createdAt: newer,
      source: "test.ordinary-canonical-write"
    )
    let afterCanonicalWrite = try await relaunchedRuntime.persistence.loadState()
    let canonicalWriteRelaunch = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "relation-upgrade-canonical-write-relaunch",
        persistenceURL: databaseURL,
        initialAttributes: canonicalAttributes,
        now: { newer }
      )
    )
    let canonicalWriteRelaunchScanCount = await canonicalWriteRelaunch.persistence
      .declaredRelationReconciliationLiveResultScanCountForTesting()
    expectNoDifference(canonicalWriteRelaunchScanCount, 0)
    let canonicalWriteRelaunchState = try await canonicalWriteRelaunch.persistence.loadState()
    expectNoDifference(canonicalWriteRelaunchState, afterCanonicalWrite)

    // A revision-checked restore can reintroduce a pre-fix reciprocal attribute and cold triple.
    // The writer sink must invalidate the marker so the next compact bootstrap audits all results.
    var restoredStore = afterCanonicalWrite.snapshot.store
    restoredStore.attributes.append(reciprocalChildRelation)
    restoredStore.triples.append(contentsOf: [
      triple("parent-restored", "parents/id", .string("parent-restored"), timestamp: newer),
      triple("child-restored", "children/id", .string("child-restored"), timestamp: newer),
      triple("child-restored", "children/name", .string("Restored"), timestamp: newer),
      triple(
        "child-restored",
        reciprocalChildRelation.id,
        .ref("parent-restored"),
        timestamp: newer,
        txID: "restored-obsolete-child-link"
      ),
    ])
    let didRestoreObsoleteRelation = try await canonicalWriteRelaunch.persistence
      .saveRuntimePreparedStoreSnapshot(
        restoredStore,
        replacing: afterCanonicalWrite.snapshot.store,
        expectedStoreRevision: afterCanonicalWrite.storeRevision,
        expectedOutboxRevision: afterCanonicalWrite.outboxRevision,
        expectedAttributeRevision: afterCanonicalWrite.attributeRevision
      )
    expectNoDifference(didRestoreObsoleteRelation, true)
    try rewriteLiveQueryOwnership(
      at: databaseURL,
      queryKey: ownershipOnlyResult.key,
      from: hotTriples[3],
      to: hotTriples[4]
    )

    let repairedRestoreRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "relation-upgrade-repaired-restore",
        persistenceURL: databaseURL,
        initialAttributes: canonicalAttributes,
        now: { newer }
      )
    )
    let repairedRestoreScanCount = await repairedRestoreRuntime.persistence
      .declaredRelationReconciliationLiveResultScanCountForTesting()
    expectNoDifference(repairedRestoreScanCount, 2)
    let repairedRawTriples: [InstantTriple] = try readJSONRows(
      at: databaseURL,
      sql: "SELECT json FROM instant_triples ORDER BY entity_id, attribute_id, value_json"
    )
    #expect(repairedRawTriples.contains {
      $0.entityID == "parent-restored"
        && $0.attributeID == physicalRelationID
        && $0.value == .ref("child-restored")
        && $0.txID == "restored-obsolete-child-link"
    })
    #expect(repairedRawTriples.allSatisfy {
      $0.attributeID != reciprocalChildRelation.id
    })
    let repairedRestoreRelaunch = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "relation-upgrade-repaired-restore-relaunch",
        persistenceURL: databaseURL,
        initialAttributes: canonicalAttributes,
        now: { newer }
      )
    )
    let repairedRestoreRelaunchScanCount = await repairedRestoreRelaunch.persistence
      .declaredRelationReconciliationLiveResultScanCountForTesting()
    expectNoDifference(repairedRestoreRelaunchScanCount, 0)

    // Unrelated scalar and relation declarations are not part of this reconciliation marker.
    // Adding either must preserve the zero-scan fast path on the next bootstrap.
    let unrelatedSchemaAttributes = canonicalAttributes + [
      InstantAttribute(
        id: "notes/title",
        namespace: "notes",
        name: "title",
        valueType: .string
      ),
      InstantAttribute(
        id: "notes/tags",
        namespace: "notes",
        name: "tags",
        valueType: .ref,
        cardinality: .many,
        forwardIdentity: "notes/tags",
        reverseIdentity: "tags/notes",
        linkNamespace: "tags"
      ),
    ]
    let unrelatedSchemaRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "relation-upgrade-unrelated-schema",
        persistenceURL: databaseURL,
        initialAttributes: unrelatedSchemaAttributes,
        now: { newer }
      )
    )
    let unrelatedSchemaScanCount = await unrelatedSchemaRuntime.persistence
      .declaredRelationReconciliationLiveResultScanCountForTesting()
    expectNoDifference(unrelatedSchemaScanCount, 0)

    // The marker fingerprints the logical declaration as well as the retained server attribute.
    // Reciprocal declaration metadata changes therefore force one audit even though physical
    // server metadata remains authoritative and unchanged.
    var changedDeclaredRelation = declaredRelation
    changedDeclaredRelation.isIndexed = false
    changedDeclaredRelation.onDeleteReverse = .none
    let changedCanonicalAttributes = canonicalAttributes.map { attribute in
      attribute.id == declaredRelation.id ? changedDeclaredRelation : attribute
    }
    let declarationChangeRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "relation-upgrade-declaration-change",
        persistenceURL: databaseURL,
        initialAttributes: changedCanonicalAttributes,
        now: { newer }
      )
    )
    let declarationChangeScanCount = await declarationChangeRuntime.persistence
      .declaredRelationReconciliationLiveResultScanCountForTesting()
    expectNoDifference(declarationChangeScanCount, 2)
    let declarationChangeRelaunch = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "relation-upgrade-declaration-change-relaunch",
        persistenceURL: databaseURL,
        initialAttributes: changedCanonicalAttributes,
        now: { newer }
      )
    )
    let declarationChangeRelaunchScanCount = await declarationChangeRelaunch.persistence
      .declaredRelationReconciliationLiveResultScanCountForTesting()
    expectNoDifference(declarationChangeRelaunchScanCount, 0)
  }

  @Test
  func freshDeclaredRelationKeepsItsLogicalIdentity() {
    let declaredRelation = InstantAttribute(
      id: "parents/children",
      namespace: "parents",
      name: "children",
      valueType: .ref,
      cardinality: .many,
      forwardIdentity: "parents/children",
      reverseIdentity: "children/parent",
      linkNamespace: "children"
    )
    var attributes = AttributeStore()

    attributes.merge([declaredRelation])

    expectNoDifference(attributes[declaredRelation.id], declaredRelation)
    expectNoDifference(
      attributes.attributes.filter {
        $0.namespace == declaredRelation.namespace && $0.name == declaredRelation.name
      },
      [declaredRelation]
    )
    expectNoDifference(
      attributes.lookupAttribute(id: "children/parent"),
      InstantResolvedLookupAttribute(
        attribute: declaredRelation,
        direction: .reverse,
        namespace: "children",
        name: "parent"
      )
    )
  }

  @Test
  func residentRelationReconciliationExaminesOnlyRemappedAttributeSlots() {
    let scalarAttribute = InstantAttribute(
      id: "unrelated/value",
      namespace: "unrelated",
      name: "value",
      valueType: .string
    )
    let addedScalarAttribute = InstantAttribute(
      id: "unrelated/added",
      namespace: "unrelated",
      name: "added",
      valueType: .string
    )
    let physicalRelation = InstantAttribute(
      id: "server-relation-physical-id",
      namespace: "parents",
      name: "children",
      valueType: .ref,
      isRequired: true,
      cardinality: .many,
      isIndexed: false,
      isUnique: true,
      forwardIdentity: "parents/children",
      reverseIdentity: "children/parent",
      linkNamespace: "children"
    )
    let reciprocalLegacyRelation = InstantAttribute(
      id: "children/parent",
      namespace: "children",
      name: "parent",
      valueType: .ref,
      cardinality: .one,
      isIndexed: true,
      isUnique: true,
      forwardIdentity: "children/parent",
      reverseIdentity: "parents/children",
      linkNamespace: "parents"
    )
    let declaredRelation = InstantAttribute(
      id: "parents/children",
      namespace: "parents",
      name: "children",
      valueType: .ref,
      cardinality: .many,
      isIndexed: true,
      isUnique: true,
      forwardIdentity: "parents/children",
      reverseIdentity: "children/parent",
      linkNamespace: "children"
    )
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let unrelatedTriples = (0..<1_000).map { offset in
      triple(
        "unrelated-\(offset)",
        scalarAttribute.id,
        .string("value-\(offset)"),
        timestamp: timestamp
      )
    }
    var scalarAttributes = AttributeStore(attributes: [scalarAttribute])
    var scalarIndexes = TripleIndexes(
      triples: unrelatedTriples,
      attributes: scalarAttributes
    )
    let previousScalarAttributes = scalarAttributes
    scalarAttributes.merge([addedScalarAttribute])

    let scalarResult = scalarIndexes.reconcileRelationStorage(
      previousAttributes: previousScalarAttributes,
      mergedAttributes: scalarAttributes
    )

    expectNoDifference(
      scalarResult.metrics,
      TripleIndexes.RelationStorageReconciliationMetrics()
    )

    var previousRelationAttributes = AttributeStore(
      attributes: [scalarAttribute, physicalRelation, reciprocalLegacyRelation]
    )
    var relationIndexes = TripleIndexes(
      triples: unrelatedTriples + [
        triple(
          "child-1",
          reciprocalLegacyRelation.id,
          .ref("parent-1"),
          timestamp: timestamp
        )
      ],
      attributes: previousRelationAttributes
    )
    let beforeRelationMerge = previousRelationAttributes
    previousRelationAttributes.merge([declaredRelation])

    let relationResult = relationIndexes.reconcileRelationStorage(
      previousAttributes: beforeRelationMerge,
      mergedAttributes: previousRelationAttributes
    )

    expectNoDifference(relationResult.metrics.examinedAttributeSlotCount, 1)
    expectNoDifference(relationResult.metrics.examinedTripleCount, 1)
    expectNoDifference(relationResult.metrics.movedTripleCount, 1)
    expectNoDifference(
      relationIndexes.triples.filter { $0.attributeID == physicalRelation.id },
      [
        triple(
          "parent-1",
          physicalRelation.id,
          .ref("child-1"),
          timestamp: timestamp
        )
      ]
    )
    expectNoDifference(
      relationIndexes.triples.filter { $0.attributeID == scalarAttribute.id }.count,
      1_000
    )
  }

  private func triple(
    _ entityID: String,
    _ attributeID: String,
    _ value: InstantValue,
    timestamp: InstantTimestamp,
    txID: String = "server-fixture"
  ) -> InstantTriple {
    InstantTriple(
      entityID: entityID,
      attributeID: attributeID,
      value: value,
      txID: txID,
      txTime: timestamp
    )
  }

  private func readOutboxStorageRow(
    at databaseURL: URL,
    mutationID: String
  ) throws -> [String: String] {
    var connection: OpaquePointer?
    guard sqlite3_open_v2(databaseURL.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
      let connection
    else {
      defer { sqlite3_close(connection) }
      throw InstantError(
        code: .persistenceFailed,
        operation: "open relation-upgrade fixture",
        message: "Could not open the SQLite fixture.",
        recovery: "Inspect the test database path."
      )
    }
    defer { sqlite3_close(connection) }
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    let sql = "SELECT * FROM instant_outbox WHERE mutation_id = ? LIMIT 1"
    guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK,
      sqlite3_bind_text(statement, 1, mutationID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        == SQLITE_OK,
      sqlite3_step(statement) == SQLITE_ROW
    else {
      throw InstantError(
        code: .persistenceFailed,
        operation: "read relation-upgrade outbox fixture",
        message: "Could not read the expected outbox row.",
        recovery: "Inspect the test fixture."
      )
    }
    var valuesByColumn: [String: String] = [:]
    for column in 0..<sqlite3_column_count(statement) {
      guard let nameBytes = sqlite3_column_name(statement, column) else { continue }
      let name = String(cString: nameBytes)
      switch sqlite3_column_type(statement, column) {
      case SQLITE_INTEGER:
        valuesByColumn[name] = "integer:\(sqlite3_column_int64(statement, column))"
      case SQLITE_FLOAT:
        valuesByColumn[name] = "float:\(sqlite3_column_double(statement, column))"
      case SQLITE_TEXT:
        valuesByColumn[name] = sqlite3_column_text(statement, column).map {
          "text:\(String(cString: $0))"
        }
      case SQLITE_BLOB:
        let byteCount = Int(sqlite3_column_bytes(statement, column))
        if let bytes = sqlite3_column_blob(statement, column) {
          valuesByColumn[name] = "blob:" + Data(bytes: bytes, count: byteCount)
            .map { String(format: "%02x", $0) }
            .joined()
        } else {
          valuesByColumn[name] = "blob:"
        }
      default:
        valuesByColumn[name] = "null"
      }
    }
    return valuesByColumn
  }

  private func rewriteLiveQueryOwnership(
    at databaseURL: URL,
    queryKey: String,
    from previous: InstantTriple,
    to replacement: InstantTriple
  ) throws {
    var connection: OpaquePointer?
    guard
      sqlite3_open_v2(databaseURL.path, &connection, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
      let connection
    else {
      defer { sqlite3_close(connection) }
      throw InstantError(
        code: .persistenceFailed,
        operation: "open relation-upgrade ownership fixture",
        message: "Could not open the SQLite fixture.",
        recovery: "Inspect the test database path."
      )
    }
    defer { sqlite3_close(connection) }
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    let sql =
      "UPDATE instant_live_query_triples SET entity_id = ?, attribute_id = ?, value_json = ? WHERE query_key = ? AND entity_id = ? AND attribute_id = ? AND value_json = ?"
    guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
      throw InstantError(
        code: .persistenceFailed,
        operation: "prepare relation-upgrade ownership fixture",
        message: "Could not prepare the ownership fixture update.",
        recovery: "Inspect the test query."
      )
    }
    let values = [
      replacement.entityID,
      replacement.attributeID,
      String(decoding: try JSONEncoder().encode(replacement.value), as: UTF8.self),
      queryKey,
      previous.entityID,
      previous.attributeID,
      String(decoding: try JSONEncoder().encode(previous.value), as: UTF8.self),
    ]
    let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    for (offset, value) in values.enumerated() {
      let result = value.withCString {
        sqlite3_bind_text(statement, Int32(offset + 1), $0, -1, sqliteTransient)
      }
      guard result == SQLITE_OK else {
        throw InstantError(
          code: .persistenceFailed,
          operation: "bind relation-upgrade ownership fixture",
          message: "Could not bind the ownership fixture update.",
          recovery: "Inspect the test query."
        )
      }
    }
    guard sqlite3_step(statement) == SQLITE_DONE, sqlite3_changes(connection) == 1 else {
      throw InstantError(
        code: .persistenceFailed,
        operation: "write relation-upgrade ownership fixture",
        message: "Could not rewrite exactly one ownership row.",
        recovery: "Inspect the test fixture."
      )
    }
  }

  private func readJSONRows<Value: Decodable>(
    at databaseURL: URL,
    sql: String
  ) throws -> [Value] {
    try readSQLiteStrings(at: databaseURL, sql: sql).map { string in
      try JSONDecoder().decode(Value.self, from: Data(string.utf8))
    }
  }

  private func readSQLiteStrings(at databaseURL: URL, sql: String) throws -> [String] {
    var connection: OpaquePointer?
    guard sqlite3_open_v2(databaseURL.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
      let connection
    else {
      defer { sqlite3_close(connection) }
      throw InstantError(
        code: .persistenceFailed,
        operation: "open relation-upgrade fixture",
        message: "Could not open the SQLite fixture.",
        recovery: "Inspect the test database path."
      )
    }
    defer { sqlite3_close(connection) }
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
      throw InstantError(
        code: .persistenceFailed,
        operation: "prepare relation-upgrade fixture query",
        message: "Could not prepare the SQLite fixture query.",
        recovery: "Inspect the test query."
      )
    }
    var values: [String] = []
    while true {
      let result = sqlite3_step(statement)
      if result == SQLITE_DONE { return values }
      guard result == SQLITE_ROW, let bytes = sqlite3_column_text(statement, 0) else {
        throw InstantError(
          code: .persistenceFailed,
          operation: "read relation-upgrade fixture query",
          message: "Could not read the SQLite fixture query.",
          recovery: "Inspect the test database."
        )
      }
      values.append(String(cString: bytes))
    }
  }
}
