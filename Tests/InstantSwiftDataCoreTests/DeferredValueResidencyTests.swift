import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

@Suite(.serialized)
struct DeferredValueResidencyTests {
  @Test
  func rejectsDeferredAttributesThatCannotStayOutOfHotIndexes() async throws {
    let invalidAttributes = [
      InstantAttribute(
        id: "routeChunks/indexedPayload",
        namespace: "routeChunks",
        name: "indexedPayload",
        valueType: .json,
        isIndexed: true
      ),
      InstantAttribute(
        id: "routeChunks/manyPayloads",
        namespace: "routeChunks",
        name: "manyPayloads",
        valueType: .json,
        cardinality: .many
      ),
      InstantAttribute(
        id: "routeChunks/recording",
        namespace: "routeChunks",
        name: "recording",
        valueType: .ref,
        linkNamespace: "recordings"
      ),
    ]

    for attribute in invalidAttributes {
      let cacheURL = temporaryDeferredValueCacheURL(attribute.name)
      defer { try? FileManager.default.removeItem(at: cacheURL) }
      do {
        _ = try await InstantRuntime.bootstrap(
          configuration: InstantRuntimeConfiguration(
            appID: "deferred-validation-\(attribute.name)",
            persistenceURL: cacheURL,
            initialAttributes: invalidAttributes,
            deferredValueResidency: InstantDeferredValueResidencyPolicy(
              attributeIDs: [attribute.id]
            )
          )
        )
        Issue.record("Expected deferred-value residency validation to fail for \(attribute.id).")
      } catch let error as InstantError {
        expectNoDifference(error.code, .validationFailed)
        expectNoDifference(error.operation, "validate deferred value residency")
        expectNoDifference(error.path, attribute.name)
      }
    }
  }

  @Test
  func bootstrapAndRouteFreePageDecodeNoDeferredPayloadBytes() async throws {
    let cacheURL = temporaryDeferredValueCacheURL("route-free")
    defer { try? FileManager.default.removeItem(at: cacheURL) }
    let fixture = DeferredRouteFixture()
    try await seedDeferredRouteCache(
      cacheURL,
      fixture: fixture,
      rows: [
        (id: "chunk-a", title: "A", payload: fixture.payload("a")),
        (id: "chunk-b", title: "B", payload: fixture.payload("b")),
        (id: "chunk-c", title: "C", payload: fixture.payload("c")),
      ]
    )

    let runtime = try await deferredRouteRuntime(cacheURL, fixture: fixture)

    let bootstrapMetrics = await runtime.persistence.deferredValueDecodeMetricsForTesting()
    expectNoDifference(bootstrapMetrics, InstantDeferredValueDecodeMetrics())
    let bootstrapTriples = await runtime.store.snapshot().triples
    #expect(
      bootstrapTriples.allSatisfy { $0.attributeID != fixture.samplesAttribute.id }
    )

    let routeFree = try await runtime.query(
      fixture.pageQuery(id: "route-free", selectedFields: [fixture.titleAttribute.name])
    )
    expectNoDifference(routeFree.map(\.id), ["chunk-a"])
    expectNoDifference(routeFree.first?.values[fixture.titleAttribute.name], .one(.string("A")))
    #expect(routeFree.first?.values[fixture.samplesAttribute.name] == nil)
    let routeFreeMetrics = await runtime.persistence.deferredValueDecodeMetricsForTesting()
    expectNoDifference(routeFreeMetrics, InstantDeferredValueDecodeMetrics())

    let selectedPage = try await runtime.query(
      fixture.pageQuery(id: "selected-page", selectedFields: [fixture.samplesAttribute.name])
    )
    expectNoDifference(selectedPage.map(\.id), ["chunk-a"])
    expectNoDifference(
      selectedPage.first?.values[fixture.samplesAttribute.name],
      .one(.json(fixture.payload("a")))
    )
    let metrics = await runtime.persistence.deferredValueDecodeMetricsForTesting()
    expectNoDifference(metrics.valueCount, 1)
    #expect(metrics.encodedByteCount >= fixture.payloadByteCount)
    #expect(metrics.encodedByteCount < fixture.payloadByteCount * 2)
    let selectedPageHotTriples = await runtime.store.snapshot().triples
    #expect(
      selectedPageHotTriples.allSatisfy { $0.attributeID != fixture.samplesAttribute.id }
    )
  }

  @Test
  func localInfiniteQueryHydratesOnlyNewlyVisiblePages() async throws {
    let cacheURL = temporaryDeferredValueCacheURL("local-infinite-pages")
    defer { try? FileManager.default.removeItem(at: cacheURL) }
    let fixture = DeferredRouteFixture()
    try await seedDeferredRouteCache(
      cacheURL,
      fixture: fixture,
      rows: [
        (id: "chunk-a", title: "A", payload: fixture.payload("a")),
        (id: "chunk-b", title: "B", payload: fixture.payload("b")),
        (id: "chunk-c", title: "C", payload: fixture.payload("c")),
        (id: "chunk-d", title: "D", payload: fixture.payload("d")),
        (id: "chunk-e", title: "E", payload: fixture.payload("e")),
        (id: "chunk-f", title: "F", payload: fixture.payload("f")),
      ]
    )
    let runtime = try await deferredRouteRuntime(cacheURL, fixture: fixture)
    let subscription = await runtime.subscribeInfiniteQuery(
      fixture.infinitePageQuery(
        id: "local-infinite-selected-pages",
        limit: 2,
        selectedFields: [fixture.samplesAttribute.name]
      )
    )
    defer { subscription.unsubscribe() }
    var iterator = subscription.snapshots.makeAsyncIterator()

    let firstPage = try #require(await iterator.next())
    expectNoDifference(firstPage.values.map(\.id), ["chunk-a", "chunk-b"])
    expectNoDifference(
      firstPage.values.map { $0.values[fixture.samplesAttribute.name] },
      [
        .one(.json(fixture.payload("a"))),
        .one(.json(fixture.payload("b"))),
      ]
    )
    let firstPageMetrics = await runtime.persistence.deferredValueDecodeMetricsForTesting()
    expectNoDifference(firstPageMetrics.valueCount, 2)
    #expect(firstPageMetrics.encodedByteCount >= fixture.payloadByteCount * 2)
    #expect(firstPageMetrics.encodedByteCount < fixture.payloadByteCount * 3)

    subscription.loadNextPage()
    let secondPage = try #require(await iterator.next())
    expectNoDifference(
      secondPage.values.map(\.id),
      ["chunk-a", "chunk-b", "chunk-c", "chunk-d"]
    )
    expectNoDifference(
      secondPage.values.map { $0.values[fixture.samplesAttribute.name] },
      [
        .one(.json(fixture.payload("a"))),
        .one(.json(fixture.payload("b"))),
        .one(.json(fixture.payload("c"))),
        .one(.json(fixture.payload("d"))),
      ]
    )
    let secondPageMetrics = await runtime.persistence.deferredValueDecodeMetricsForTesting()
    expectNoDifference(secondPageMetrics.valueCount, 4)
    #expect(secondPageMetrics.encodedByteCount >= fixture.payloadByteCount * 4)
    #expect(secondPageMetrics.encodedByteCount < fixture.payloadByteCount * 5)
    let hotTriples = await runtime.store.snapshot().triples
    #expect(hotTriples.allSatisfy { $0.attributeID != fixture.samplesAttribute.id })
  }

  @Test
  func localInfiniteQueryWindowPrunesEvictedDeferredSnapshotsAndHydratedCache() async throws {
    let cacheURL = temporaryDeferredValueCacheURL("local-infinite-window")
    defer { try? FileManager.default.removeItem(at: cacheURL) }
    let fixture = DeferredRouteFixture()
    try await seedDeferredRouteCache(
      cacheURL,
      fixture: fixture,
      rows: [
        (id: "chunk-a", title: "A", payload: fixture.payload("a")),
        (id: "chunk-b", title: "B", payload: fixture.payload("b")),
        (id: "chunk-c", title: "C", payload: fixture.payload("c")),
        (id: "chunk-d", title: "D", payload: fixture.payload("d")),
        (id: "chunk-e", title: "E", payload: fixture.payload("e")),
        (id: "chunk-f", title: "F", payload: fixture.payload("f")),
        (id: "chunk-g", title: "G", payload: fixture.payload("g")),
        (id: "chunk-h", title: "H", payload: fixture.payload("h")),
      ]
    )
    let runtime = try await deferredRouteRuntime(cacheURL, fixture: fixture)
    let subscription = await runtime.subscribeInfiniteQuery(
      fixture.infinitePageQuery(
        id: "local-infinite-window",
        limit: 2,
        selectedFields: [fixture.samplesAttribute.name]
      ),
      retentionPolicy: .window(maximumPageCount: 2)
    )
    defer { subscription.unsubscribe() }
    var iterator = subscription.snapshots.makeAsyncIterator()

    let first = try #require(await iterator.next())
    expectNoDifference(first.values.map(\.id), ["chunk-a", "chunk-b"])
    let firstMetrics = await runtime.persistence.deferredValueDecodeMetricsForTesting()
    expectNoDifference(firstMetrics.valueCount, 2)

    subscription.loadNextPage()
    let second = try #require(await iterator.next())
    expectNoDifference(
      second.values.map(\.id),
      ["chunk-a", "chunk-b", "chunk-c", "chunk-d"]
    )
    expectNoDifference(second.values.count, 4)
    let secondMetrics = await runtime.persistence.deferredValueDecodeMetricsForTesting()
    expectNoDifference(secondMetrics.valueCount, 4)

    subscription.loadNextPage()
    let third = try #require(await iterator.next())
    expectNoDifference(
      third.values.map(\.id),
      ["chunk-c", "chunk-d", "chunk-e", "chunk-f"]
    )
    expectNoDifference(third.values.count, 4)
    expectNoDifference(third.canLoadPreviousPage, true)
    expectNoDifference(third.canLoadNextPage, true)
    let thirdMetrics = await runtime.persistence.deferredValueDecodeMetricsForTesting()
    expectNoDifference(thirdMetrics.valueCount, 6)

    subscription.loadPreviousPage()
    let previous = try #require(await iterator.next())
    expectNoDifference(
      previous.values.map(\.id),
      ["chunk-a", "chunk-b", "chunk-c", "chunk-d"]
    )
    expectNoDifference(previous.values.count, 4)
    expectNoDifference(
      previous.values.map { $0.values[fixture.samplesAttribute.name] },
      [
        .one(.json(fixture.payload("a"))),
        .one(.json(fixture.payload("b"))),
        .one(.json(fixture.payload("c"))),
        .one(.json(fixture.payload("d"))),
      ]
    )
    // Returning to an evicted page decodes its two values again. This proves the
    // hydrated cache retains only the current two-page window.
    let previousMetrics = await runtime.persistence.deferredValueDecodeMetricsForTesting()
    expectNoDifference(previousMetrics.valueCount, 8)
    let hotTriples = await runtime.store.snapshot().triples
    #expect(hotTriples.allSatisfy { $0.attributeID != fixture.samplesAttribute.id })
  }

  @Test
  func stalledLiveInfiniteQueryHydratesOnlyNewlyVisiblePages() async throws {
    let cacheURL = temporaryDeferredValueCacheURL("stalled-live-infinite-pages")
    defer { try? FileManager.default.removeItem(at: cacheURL) }
    let fixture = DeferredRouteFixture()
    try await seedDeferredRouteCache(
      cacheURL,
      fixture: fixture,
      rows: [
        (id: "chunk-a", title: "A", payload: fixture.payload("a")),
        (id: "chunk-b", title: "B", payload: fixture.payload("b")),
        (id: "chunk-c", title: "C", payload: fixture.payload("c")),
        (id: "chunk-d", title: "D", payload: fixture.payload("d")),
        (id: "chunk-e", title: "E", payload: fixture.payload("e")),
        (id: "chunk-f", title: "F", payload: fixture.payload("f")),
      ]
    )
    let session = LiveReactorParitySession(messages: [])
    var configuration = InstantRuntimeConfiguration(
      appID: "deferred-stalled-live-infinite",
      persistenceURL: cacheURL,
      initialAttributes: fixture.attributes,
      deferredValueResidency: InstantDeferredValueResidencyPolicy(
        attributeIDs: [fixture.samplesAttribute.id]
      ),
      liveTransport: session.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let subscription = await runtime.subscribeInfiniteQuery(
      fixture.infinitePageQuery(
        id: "stalled-live-infinite-selected-pages",
        limit: 2,
        selectedFields: [fixture.samplesAttribute.name]
      )
    )
    defer { subscription.unsubscribe() }
    var iterator = subscription.snapshots.makeAsyncIterator()

    let firstPage = try #require(await iterator.next())
    expectNoDifference(firstPage.values.map(\.id), ["chunk-a", "chunk-b"])
    let firstPageMetrics = await runtime.persistence.deferredValueDecodeMetricsForTesting()
    expectNoDifference(firstPageMetrics.valueCount, 2)

    subscription.loadNextPage()
    let secondPage = try #require(await iterator.next())
    expectNoDifference(
      secondPage.values.map(\.id),
      ["chunk-a", "chunk-b", "chunk-c", "chunk-d"]
    )
    let secondPageMetrics = await runtime.persistence.deferredValueDecodeMetricsForTesting()
    expectNoDifference(secondPageMetrics.valueCount, 4)

    subscription.loadNextPage()
    let thirdPage = try #require(await iterator.next())
    expectNoDifference(
      thirdPage.values.map(\.id),
      ["chunk-a", "chunk-b", "chunk-c", "chunk-d", "chunk-e", "chunk-f"]
    )
    expectNoDifference(
      thirdPage.values.map { $0.values[fixture.samplesAttribute.name] },
      [
        .one(.json(fixture.payload("a"))),
        .one(.json(fixture.payload("b"))),
        .one(.json(fixture.payload("c"))),
        .one(.json(fixture.payload("d"))),
        .one(.json(fixture.payload("e"))),
        .one(.json(fixture.payload("f"))),
      ]
    )
    let metrics = await runtime.persistence.deferredValueDecodeMetricsForTesting()
    expectNoDifference(metrics.valueCount, 6)
    #expect(metrics.encodedByteCount >= fixture.payloadByteCount * 6)
    #expect(metrics.encodedByteCount < fixture.payloadByteCount * 7)
    let sentMessages = await session.sentMessages()
    expectNoDifference(sentMessages, [])
  }

  @Test
  func routeFreeLocalInfiniteQueryDecodesNoDeferredPayloadBytes() async throws {
    let cacheURL = temporaryDeferredValueCacheURL("route-free-local-infinite")
    defer { try? FileManager.default.removeItem(at: cacheURL) }
    let fixture = DeferredRouteFixture()
    try await seedDeferredRouteCache(
      cacheURL,
      fixture: fixture,
      rows: [
        (id: "chunk-a", title: "A", payload: fixture.payload("a")),
        (id: "chunk-b", title: "B", payload: fixture.payload("b")),
        (id: "chunk-c", title: "C", payload: fixture.payload("c")),
        (id: "chunk-d", title: "D", payload: fixture.payload("d")),
      ]
    )
    let runtime = try await deferredRouteRuntime(cacheURL, fixture: fixture)
    let subscription = await runtime.subscribeInfiniteQuery(
      fixture.infinitePageQuery(
        id: "route-free-local-infinite",
        limit: 2,
        selectedFields: [fixture.titleAttribute.name]
      )
    )
    defer { subscription.unsubscribe() }
    var iterator = subscription.snapshots.makeAsyncIterator()

    let firstPage = try #require(await iterator.next())
    expectNoDifference(firstPage.values.map(\.id), ["chunk-a", "chunk-b"])
    subscription.loadNextPage()
    let secondPage = try #require(await iterator.next())
    expectNoDifference(
      secondPage.values.map(\.id),
      ["chunk-a", "chunk-b", "chunk-c", "chunk-d"]
    )
    let metrics = await runtime.persistence.deferredValueDecodeMetricsForTesting()
    expectNoDifference(metrics, InstantDeferredValueDecodeMetrics())
  }

  @Test
  func localInfiniteQueryRehydratesVisibleWindowAfterOutOfWindowReorder() async throws {
    let cacheURL = temporaryDeferredValueCacheURL("local-infinite-reorder")
    defer { try? FileManager.default.removeItem(at: cacheURL) }
    let fixture = DeferredRouteFixture()
    try await seedDeferredRouteCache(
      cacheURL,
      fixture: fixture,
      rows: [
        (id: "chunk-a", title: "A", payload: fixture.payload("a")),
        (id: "chunk-b", title: "B", payload: fixture.payload("b")),
        (id: "chunk-c", title: "C", payload: fixture.payload("c")),
        (id: "chunk-d", title: "D", payload: fixture.payload("d")),
      ]
    )
    let runtime = try await deferredRouteRuntime(cacheURL, fixture: fixture)
    let subscription = await runtime.subscribeInfiniteQuery(
      fixture.infinitePageQuery(
        id: "local-infinite-reorder",
        limit: 2,
        selectedFields: [fixture.samplesAttribute.name]
      )
    )
    defer { subscription.unsubscribe() }
    var iterator = subscription.snapshots.makeAsyncIterator()

    let initial = try #require(await iterator.next())
    expectNoDifference(initial.values.map(\.id), ["chunk-a", "chunk-b"])
    let prepared = try await runtime.store.prepareCurrent(
      InstantStoreTransaction(
        id: "reorder-out-of-window-deferred-row",
        operations: [
          .insert(
            InstantTriple(
              entityID: "chunk-d",
              attributeID: fixture.titleAttribute.id,
              value: .string("AA"),
              txID: "reorder-out-of-window-deferred-row",
              txTime: InstantTimestamp(milliseconds: 100)
            )
          )
        ]
      )
    )
    _ = await runtime.store.commitAndPublish(prepared)

    let reordered = try #require(await iterator.next())
    expectNoDifference(reordered.values.map(\.id), ["chunk-a", "chunk-d"])
    expectNoDifference(
      reordered.values.map { $0.values[fixture.samplesAttribute.name] },
      [
        .one(.json(fixture.payload("a"))),
        .one(.json(fixture.payload("d"))),
      ]
    )
    let metrics = await runtime.persistence.deferredValueDecodeMetricsForTesting()
    expectNoDifference(metrics.valueCount, 4)
  }

  @Test
  func localInfiniteQueryNeverMixesMetadataAndDeferredPayloadRevisions() async throws {
    let cacheURL = temporaryDeferredValueCacheURL("local-infinite-revision-race")
    defer { try? FileManager.default.removeItem(at: cacheURL) }
    let fixture = DeferredRouteFixture()
    try await seedDeferredRouteCache(
      cacheURL,
      fixture: fixture,
      rows: [
        (id: "chunk-a", title: "A", payload: fixture.payload("a")),
        (id: "chunk-b", title: "B old", payload: fixture.payload("b-old")),
      ]
    )
    let publicationBarrier = DeferredStorePublicationBarrier()
    let actorHopRecorder = InstantActorHopRecorder()
    var configuration = InstantRuntimeConfiguration(
      appID: "deferred-local-infinite-revision-race",
      persistenceURL: cacheURL,
      initialAttributes: fixture.attributes,
      deferredValueResidency: InstantDeferredValueResidencyPolicy(
        attributeIDs: [fixture.samplesAttribute.id]
      )
    )
    configuration.actorHopRecorder = actorHopRecorder
    configuration.onLocalMutationPersistedBeforeStorePublicationForTesting = { transactionID in
      await publicationBarrier.pause(transactionID: transactionID)
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let subscription = await runtime.subscribeInfiniteQuery(
      fixture.infinitePageQuery(
        id: "local-infinite-revision-race",
        limit: 1,
        selectedFields: [fixture.titleAttribute.name, fixture.samplesAttribute.name]
      )
    )
    let snapshots = DeferredInfiniteSnapshotRecorder()
    let collection = Task {
      for await snapshot in subscription.snapshots {
        await snapshots.append(snapshot)
      }
    }
    defer {
      subscription.unsubscribe()
      collection.cancel()
      Task { await publicationBarrier.release() }
    }
    await snapshots.waitForCount(1)

    let updateTransaction = InstantStoreTransaction(
      id: "deferred-revision-race-update",
      operations: [
        .requireEntityExists(entityID: "chunk-b", namespace: fixture.namespace),
        .insert(
          InstantTriple(
            entityID: "chunk-b",
            attributeID: fixture.titleAttribute.id,
            value: .string("B new"),
            txID: "deferred-revision-race-update",
            txTime: InstantTimestamp(milliseconds: 100)
          )
        ),
        .insert(
          InstantTriple(
            entityID: "chunk-b",
            attributeID: fixture.samplesAttribute.id,
            value: .json(fixture.payload("b-new")),
            txID: "deferred-revision-race-update",
            txTime: InstantTimestamp(milliseconds: 100)
          )
        ),
      ]
    )
    let update = Task {
      try await runtime.transact(
        updateTransaction,
        createdAt: InstantTimestamp(milliseconds: 100)
      )
    }
    await publicationBarrier.waitUntilPaused()
    let hydrationGateBaseline = actorHopRecorder.baseline()

    subscription.loadNextPage()
    let hydrationQueuedBehindPublication = await waitForDeferredOperationGateHop(
      recorder: actorHopRecorder,
      since: hydrationGateBaseline
    )
    await publicationBarrier.release()
    _ = try await update.value

    #expect(
      hydrationQueuedBehindPublication,
      "Deferred hydration must queue behind the mutation's persistence-to-publication interval."
    )
    await snapshots.waitForCount(2)
    let observed = await snapshots.values()
    let loadedSecondRows = observed.dropFirst().compactMap { snapshot in
      snapshot.values.first(where: { $0.id == "chunk-b" })
    }
    #expect(!loadedSecondRows.isEmpty)
    for row in loadedSecondRows {
      expectNoDifference(row.values[fixture.titleAttribute.name], .one(.string("B new")))
      expectNoDifference(
        row.values[fixture.samplesAttribute.name],
        .one(.json(fixture.payload("b-new")))
      )
    }
  }

  @Test
  func localInfiniteQueryHydrationFailureEmitsOneTypedFailureThenTerminates() async throws {
    let cacheURL = temporaryDeferredValueCacheURL("local-infinite-failure")
    defer { try? FileManager.default.removeItem(at: cacheURL) }
    let fixture = DeferredRouteFixture()
    try await seedDeferredRouteCache(
      cacheURL,
      fixture: fixture,
      rows: [(id: "chunk-a", title: "A", payload: fixture.payload("a"))]
    )
    let runtime = try await deferredRouteRuntime(cacheURL, fixture: fixture)
    try corruptDeferredValueJSON(
      at: cacheURL,
      entityID: "chunk-a",
      attributeID: fixture.samplesAttribute.id
    )
    try await withKnownIssue {
      let subscription = await runtime.subscribeInfiniteQuery(
        fixture.infinitePageQuery(
          id: "local-infinite-hydration-failure",
          limit: 1,
          selectedFields: [fixture.samplesAttribute.name]
        )
      )
      defer { subscription.unsubscribe() }
      var iterator = subscription.snapshots.makeAsyncIterator()

      let failure = try #require(await iterator.next())
      expectNoDifference(failure.values, [])
      expectNoDifference(failure.canLoadNextPage, false)
      expectNoDifference(failure.error?.code, .persistenceFailed)
      expectNoDifference(failure.error?.operation, "hydrate deferred infinite query values")
      #expect(await iterator.next() == nil)
    } matching: { issue in
      // InstantError.description prefixes "[persistenceFailed] " before operation: message.
      issue.description.contains(
        """
        Instant could not hydrate selected deferred values for query \
        'local-infinite-hydration-failure':
        """
      )
        && issue.description.contains("hydrate deferred infinite query values:")
    }
  }

  @Test
  func commitStripsOnlyTheAffectedDeferredKeyFromTenThousandRows() async throws {
    let fixture = DeferredRouteFixture()
    let rowCount = 10_000
    var triples: [InstantTriple] = []
    triples.reserveCapacity(rowCount * 2)
    for index in 0..<rowCount {
      let entityID = "chunk-\(index)"
      triples.append(
        InstantTriple(
          entityID: entityID,
          attributeID: fixture.titleAttribute.id,
          value: .string("Title \(index)"),
          txID: "seed-\(index)",
          txTime: InstantTimestamp(milliseconds: Int64(index + 1))
        )
      )
      triples.append(
        InstantTriple(
          entityID: entityID,
          attributeID: fixture.samplesAttribute.id,
          value: .json(.string("Payload \(index)")),
          txID: "seed-\(index)",
          txTime: InstantTimestamp(milliseconds: Int64(index + 1))
        )
      )
    }

    let targetEntityID = "chunk-9999"
    let originalDeferredTriple = try #require(
      triples.first {
        $0.entityID == targetEntityID
          && $0.attributeID == fixture.samplesAttribute.id
      }
    )
    let store = InstantStore(
      snapshot: InstantStoreSnapshot(attributes: fixture.attributes, triples: triples),
      deferredValueResidency: InstantDeferredValueResidencyPolicy(
        attributeIDs: [fixture.samplesAttribute.id]
      )
    )
    let updatedDeferredTriple = InstantTriple(
      entityID: targetEntityID,
      attributeID: fixture.samplesAttribute.id,
      value: .json(.string("Updated payload")),
      txID: "update-one-deferred-key",
      txTime: InstantTimestamp(milliseconds: 20_000)
    )
    let prepared = try await store.prepareCurrent(
      InstantStoreTransaction(
        id: "update-one-deferred-key",
        operations: [.insert(updatedDeferredTriple)]
      ),
      hydratingDeferredValues: [originalDeferredTriple]
    )

    expectNoDifference(prepared.indexes.pendingDeferredValueRemovalCount, 1)
    expectNoDifference(prepared.result.changedEntityIDs, [targetEntityID])
    let committed = await store.commitAndPublish(prepared)

    expectNoDifference(
      committed.deferredValueRemovalMetrics,
      TripleIndexes.DeferredValueRemovalMetrics(
        examinedKeyCount: 1,
        residentKeyCount: 1,
        removedValueCount: 1
      )
    )
    expectNoDifference(committed.indexes.pendingDeferredValueRemovalCount, 0)
    expectNoDifference(committed.indexes.tripleCount, rowCount)
    let hotTriples = await store.snapshot().triples
    expectNoDifference(hotTriples.count, rowCount)
    #expect(
      hotTriples.allSatisfy { $0.attributeID != fixture.samplesAttribute.id }
    )
  }

  @Test
  func optimisticUpdateRestartAndRejectionKeepExactDeferredValue() async throws {
    let cacheURL = temporaryDeferredValueCacheURL("optimistic")
    defer { try? FileManager.default.removeItem(at: cacheURL) }
    let fixture = DeferredRouteFixture()
    let originalPayload = fixture.payload("original")
    let optimisticPayload = fixture.payload("optimistic")
    try await seedDeferredRouteCache(
      cacheURL,
      fixture: fixture,
      rows: [(id: "chunk-a", title: "A", payload: originalPayload)]
    )
    let runtime = try await deferredRouteRuntime(cacheURL, fixture: fixture)
    let query = fixture.pageQuery(
      id: "optimistic-selected-page",
      selectedFields: [fixture.samplesAttribute.name]
    )

    let originalValue = try await runtime.query(query).first?.values[fixture.samplesAttribute.name]
    expectNoDifference(originalValue, .one(.json(originalPayload)))

    let transactionID = "deferred-optimistic-update"
    _ = try await runtime.transact(
      InstantStoreTransaction(
        id: transactionID,
        operations: [
          .requireEntityExists(entityID: "chunk-a", namespace: fixture.namespace),
          .insert(
            InstantTriple(
              entityID: "chunk-a",
              attributeID: fixture.samplesAttribute.id,
              value: .json(optimisticPayload),
              txID: transactionID,
              txTime: InstantTimestamp(milliseconds: 20)
            )
          ),
        ]
      ),
      createdAt: InstantTimestamp(milliseconds: 20)
    )

    let optimisticValue = try await runtime.query(query).first?.values[
      fixture.samplesAttribute.name
    ]
    expectNoDifference(optimisticValue, .one(.json(optimisticPayload)))
    let optimisticHotTriples = await runtime.store.snapshot().triples
    #expect(
      optimisticHotTriples.allSatisfy { $0.attributeID != fixture.samplesAttribute.id }
    )

    let restartedWithOptimisticValue = try await deferredRouteRuntime(cacheURL, fixture: fixture)
    let restartedOptimisticValue =
      try await restartedWithOptimisticValue.query(query).first?.values[
        fixture.samplesAttribute.name
      ]
    expectNoDifference(restartedOptimisticValue, .one(.json(optimisticPayload)))

    _ = try await restartedWithOptimisticValue.failMutation(
      id: transactionID,
      message: "permission denied deferred optimistic update"
    )
    let rejectedValue = try await restartedWithOptimisticValue.query(query).first?.values[
      fixture.samplesAttribute.name
    ]
    expectNoDifference(rejectedValue, .one(.json(originalPayload)))

    let restartedAfterRejection = try await deferredRouteRuntime(cacheURL, fixture: fixture)
    let restartedRejectedValue = try await restartedAfterRejection.query(query).first?.values[
      fixture.samplesAttribute.name
    ]
    expectNoDifference(restartedRejectedValue, .one(.json(originalPayload)))
    let rejectedHotTriples = await restartedAfterRejection.store.snapshot().triples
    #expect(
      rejectedHotTriples.allSatisfy { $0.attributeID != fixture.samplesAttribute.id }
    )
  }

  @Test
  func rejectionOfFirstDeferredValueDeletesItAcrossRestart() async throws {
    let cacheURL = temporaryDeferredValueCacheURL("optimistic-create")
    defer { try? FileManager.default.removeItem(at: cacheURL) }
    let fixture = DeferredRouteFixture()
    let optimisticPayload = fixture.payload("optimistic-create")
    try await seedDeferredRouteCache(
      cacheURL,
      fixture: fixture,
      rows: [(id: "chunk-a", title: "A", payload: nil)]
    )
    let runtime = try await deferredRouteRuntime(cacheURL, fixture: fixture)
    let query = fixture.pageQuery(
      id: "optimistic-created-selected-page",
      selectedFields: [fixture.samplesAttribute.name]
    )

    let originalValue = try await runtime.query(query).first?.values[
      fixture.samplesAttribute.name
    ]
    #expect(originalValue == nil)

    let transactionID = "deferred-optimistic-create"
    _ = try await runtime.transact(
      InstantStoreTransaction(
        id: transactionID,
        operations: [
          .requireEntityExists(entityID: "chunk-a", namespace: fixture.namespace),
          .insert(
            InstantTriple(
              entityID: "chunk-a",
              attributeID: fixture.samplesAttribute.id,
              value: .json(optimisticPayload),
              txID: transactionID,
              txTime: InstantTimestamp(milliseconds: 30)
            )
          ),
        ]
      ),
      createdAt: InstantTimestamp(milliseconds: 30)
    )

    let restartedWithOptimisticValue = try await deferredRouteRuntime(cacheURL, fixture: fixture)
    let optimisticValue = try await restartedWithOptimisticValue.query(query).first?.values[
      fixture.samplesAttribute.name
    ]
    expectNoDifference(optimisticValue, .one(.json(optimisticPayload)))

    _ = try await restartedWithOptimisticValue.failMutation(
      id: transactionID,
      message: "permission denied first deferred value"
    )
    let rejectedValue = try await restartedWithOptimisticValue.query(query).first?.values[
      fixture.samplesAttribute.name
    ]
    #expect(rejectedValue == nil)

    let restartedAfterRejection = try await deferredRouteRuntime(cacheURL, fixture: fixture)
    let restartedRejectedValue = try await restartedAfterRejection.query(query).first?.values[
      fixture.samplesAttribute.name
    ]
    #expect(restartedRejectedValue == nil)
  }
}

private struct DeferredRouteFixture {
  let namespace = "routeChunks"
  let idAttribute = InstantAttribute.primaryKey(namespace: "routeChunks")
  let titleAttribute = InstantAttribute(
    id: "routeChunks/title",
    namespace: "routeChunks",
    name: "title",
    valueType: .string,
    isIndexed: true
  )
  let samplesAttribute = InstantAttribute(
    id: "routeChunks/samplesJSON",
    namespace: "routeChunks",
    name: "samplesJSON",
    valueType: .json
  )

  var attributes: [InstantAttribute] {
    [idAttribute, titleAttribute, samplesAttribute]
  }

  var payloadByteCount: Int {
    ("bytes" + String(repeating: "-route-sample", count: 512)).utf8.count
  }

  func payload(_ marker: String) -> JSONValue {
    .string(marker + String(repeating: "-route-sample", count: 512))
  }

  func pageQuery(id: String, selectedFields: [String]) -> InstantQueryPlan {
    InstantQueryPlan(
      id: id,
      namespace: namespace,
      order: InstantQueryOrder(titleAttribute.name),
      limit: 1,
      selectedFields: selectedFields
    )
  }

  func infinitePageQuery(
    id: String,
    limit: Int,
    selectedFields: [String]
  ) -> InstantQueryPlan {
    InstantQueryPlan(
      id: id,
      namespace: namespace,
      order: InstantQueryOrder(titleAttribute.name),
      limit: limit,
      selectedFields: selectedFields
    )
  }
}

private func deferredRouteRuntime(
  _ cacheURL: URL,
  fixture: DeferredRouteFixture
) async throws -> InstantRuntime {
  try await InstantRuntime.bootstrap(
    configuration: InstantRuntimeConfiguration(
      appID: "deferred-route-values",
      persistenceURL: cacheURL,
      initialAttributes: fixture.attributes,
      deferredValueResidency: InstantDeferredValueResidencyPolicy(
        attributeIDs: [fixture.samplesAttribute.id]
      )
    )
  )
}

private func seedDeferredRouteCache(
  _ cacheURL: URL,
  fixture: DeferredRouteFixture,
  rows: [(id: String, title: String, payload: JSONValue?)]
) async throws {
  let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
  try await persistence.bootstrap()
  var triples: [InstantTriple] = []
  for (offset, row) in rows.enumerated() {
    let timestamp = InstantTimestamp(milliseconds: Int64(offset + 1))
    triples.append(
      InstantTriple(
        entityID: row.id,
        attributeID: fixture.idAttribute.id,
        value: .string(row.id),
        txID: "seed-\(row.id)",
        txTime: timestamp
      )
    )
    triples.append(
      InstantTriple(
        entityID: row.id,
        attributeID: fixture.titleAttribute.id,
        value: .string(row.title),
        txID: "seed-\(row.id)",
        txTime: timestamp
      )
    )
    if let payload = row.payload {
      triples.append(
        InstantTriple(
          entityID: row.id,
          attributeID: fixture.samplesAttribute.id,
          value: .json(payload),
          txID: "seed-\(row.id)",
          txTime: timestamp
        )
      )
    }
  }
  try await persistence.saveStoreSnapshot(
    InstantStoreSnapshot(attributes: fixture.attributes, triples: triples)
  )
}

private func temporaryDeferredValueCacheURL(_ name: String) -> URL {
  FileManager.default.temporaryDirectory
    .appendingPathComponent("DeferredValueResidencyTests-\(name)-\(UUID().uuidString)")
    .appendingPathComponent("state.sqlite")
}

private let deferredValueSQLiteTransient = unsafeBitCast(
  -1,
  to: sqlite3_destructor_type.self
)

private func corruptDeferredValueJSON(
  at cacheURL: URL,
  entityID: String,
  attributeID: String
) throws {
  var database: OpaquePointer?
  guard
    sqlite3_open_v2(
      cacheURL.path,
      &database,
      SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
      nil
    ) == SQLITE_OK,
    let database
  else {
    defer { sqlite3_close(database) }
    throw deferredValueSQLiteError(database, operation: "open deferred-value fault database")
  }
  defer { sqlite3_close(database) }
  sqlite3_busy_timeout(database, 5_000)

  var statement: OpaquePointer?
  guard
    sqlite3_prepare_v2(
      database,
      """
      UPDATE instant_triples
      SET json = '{malformed-json'
      WHERE entity_id = ? AND attribute_id = ?
      """,
      -1,
      &statement,
      nil
    ) == SQLITE_OK
  else {
    throw deferredValueSQLiteError(database, operation: "prepare deferred-value corruption")
  }
  defer { sqlite3_finalize(statement) }

  let entityBind = entityID.withCString {
    sqlite3_bind_text(statement, 1, $0, -1, deferredValueSQLiteTransient)
  }
  let attributeBind = attributeID.withCString {
    sqlite3_bind_text(statement, 2, $0, -1, deferredValueSQLiteTransient)
  }
  guard
    entityBind == SQLITE_OK,
    attributeBind == SQLITE_OK,
    sqlite3_step(statement) == SQLITE_DONE,
    sqlite3_changes(database) == 1
  else {
    throw deferredValueSQLiteError(database, operation: "corrupt deferred-value JSON")
  }
}

private func deferredValueSQLiteError(
  _ database: OpaquePointer?,
  operation: String
) -> InstantError {
  InstantError(
    code: .persistenceFailed,
    operation: operation,
    message: database.map { String(cString: sqlite3_errmsg($0)) }
      ?? "SQLite could not open the deferred-value test database.",
    recovery: "Check the temporary deferred-value test database."
  )
}

private actor DeferredStorePublicationBarrier {
  private var pausedTransactionID: String?
  private var pauseWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  func pause(transactionID: String) async {
    pausedTransactionID = transactionID
    let waiters = pauseWaiters
    pauseWaiters.removeAll(keepingCapacity: false)
    for waiter in waiters {
      waiter.resume()
    }
    await withCheckedContinuation { continuation in
      releaseContinuation = continuation
    }
  }

  func waitUntilPaused() async {
    guard pausedTransactionID == nil else { return }
    await withCheckedContinuation { continuation in
      pauseWaiters.append(continuation)
    }
  }

  func release() {
    releaseContinuation?.resume()
    releaseContinuation = nil
  }
}

private actor DeferredInfiniteSnapshotRecorder {
  private var snapshots: [InstantInfiniteQuerySnapshot] = []
  private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

  func append(_ snapshot: InstantInfiniteQuerySnapshot) {
    snapshots.append(snapshot)
    var remaining: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    for waiter in waiters {
      if snapshots.count >= waiter.count {
        waiter.continuation.resume()
      } else {
        remaining.append(waiter)
      }
    }
    waiters = remaining
  }

  func waitForCount(_ count: Int) async {
    guard snapshots.count < count else { return }
    await withCheckedContinuation { continuation in
      waiters.append((count, continuation))
    }
  }

  func values() -> [InstantInfiniteQuerySnapshot] {
    snapshots
  }
}

private func waitForDeferredOperationGateHop(
  recorder: InstantActorHopRecorder,
  since baseline: InstantActorHopBaseline
) async -> Bool {
  for _ in 0..<1_000 {
    if recorder.summary(since: baseline).breakdown["operation-gate", default: 0] >= 1 {
      return true
    }
    await Task.yield()
  }
  return recorder.summary(since: baseline).breakdown["operation-gate", default: 0] >= 1
}
