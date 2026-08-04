import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

private let reactorInitOKAttributeSource =
  "upstream/instant/client/packages/core/src/Reactor.js _onMessage case 'init-ok' -> "
  + "this._setAttrs(msg.attrs) (line 640), and _setAttrs (line 1046) "
  + "[adapted: upstream replaces its whole in-memory attr store on every init-ok and keeps "
  + "locally minted attrs separately in optimisticAttrs(); Swift persists one durable "
  + "attribute set, so the same convergence is expressed as the merge already used by "
  + "refresh-ok, which keeps a local attribute id whenever the namespace/name pair exists]"

/// A device that has already synced once holds attributes for the namespaces that existed
/// then. Instant models attributes as data, so a namespace added to the schema afterwards is
/// unknown to that device until the server sends its attributes again. The server does send
/// them — in every `init-ok` — and until this suite existed the Swift client kept them in
/// memory only, which left the namespace permanently unqueryable: query observation refuses to
/// subscribe to a namespace it has no attributes for, so the subscription that would have
/// delivered the attributes was never opened.
@Suite("Instant applies the init-ok attribute set")
struct InstantInitialAttributeSyncTests {
  private static let knownNamespace = TodoExample.namespace
  private static let laterNamespace = "screenStreamSessions"

  private static let laterNamespaceQuery = InstantQueryPlan(
    id: "tests.screen-stream-sessions.list",
    namespace: laterNamespace
  )

  /// The server attribute payload a device receives in `init-ok`: everything it already knows
  /// plus a namespace added to the schema after that device last synced.
  private static var initOKAttributes: [InstantLiveJSONValue] {
    [
      .initialSyncServerAttr(id: "server-todos-id", namespace: knownNamespace, name: "id"),
      .initialSyncServerAttr(id: "server-todos-text", namespace: knownNamespace, name: "text"),
      .initialSyncServerAttr(
        id: "server-screen-stream-id",
        namespace: laterNamespace,
        name: "id"
      ),
      .initialSyncServerAttr(
        id: "server-screen-stream-status",
        namespace: laterNamespace,
        name: "status"
      ),
    ]
  }

  /// Store-level statement of the defect, with no socket involved: a store that has never seen
  /// a namespace must be able to materialize a row of it once the `init-ok` attribute set is
  /// applied.
  @Test("Applying init-ok attributes makes a never-seen namespace materializable")
  func initOKAttributesMakeALaterNamespaceMaterializable() async throws {
    let existingAttributes = TodoExample.attributes
    let store = InstantStore(
      snapshot: InstantStoreSnapshot(attributes: existingAttributes, triples: [])
    )

    let plan = Self.laterNamespaceQuery
    #expect(
      TripleIndexes.validate(plan, attributes: AttributeStore(attributes: existingAttributes))
        != nil,
      """
      Precondition: a store with no attributes for '\(Self.laterNamespace)' cannot serve the \
      query, which is why the attributes have to arrive before the subscription.
      """
    )

    let merged = try InstantLiveRefreshTranslator.attributesToMerge(
      serverAttributes: Self.initOKAttributes,
      existingAttributes: existingAttributes
    )
    expectNoDifference(
      merged.map(\.id).sorted(),
      ["server-screen-stream-status"],
      """
      Only the unknown namespace is merged. 'todos' already has local attributes, and \
      replacing those with the server's would orphan every local triple and every pending \
      mutation that references the local attribute ids. The server's 'id' attribute is left \
      out because the store derives a namespace's primary key itself.
      """
    )

    let snapshot = await store.mergeAttributes(merged)
    expectNoDifference(
      snapshot.attributes.map(\.id).sorted(),
      (existingAttributes.map(\.id)
        + merged.map(\.id)
        + [InstantAttribute.primaryKeyID(namespace: Self.laterNamespace)])
        .sorted(),
      """
      Merging adds to the local attribute set and never replaces it. Learning one attribute of \
      a namespace is enough for the store to know the namespace, so it derives that \
      namespace's primary key as well.
      """
    )
    #expect(
      TripleIndexes.validate(plan, attributes: AttributeStore(attributes: snapshot.attributes))
        == nil
    )

    _ = try await store.prepare(
      InstantStoreTransaction(
        id: "server-tx-screen-stream",
        operations: [
          .insert(
            InstantTriple(
              entityID: "session-1",
              attributeID: "server-screen-stream-id",
              value: .string("session-1"),
              txID: "server-tx-screen-stream",
              txTime: InstantTimestamp(milliseconds: 1_700_000_000_000)
            )
          ),
          .insert(
            InstantTriple(
              entityID: "session-1",
              attributeID: "server-screen-stream-status",
              value: .string("requested"),
              txID: "server-tx-screen-stream",
              txTime: InstantTimestamp(milliseconds: 1_700_000_000_000)
            )
          ),
        ]
      )
    )

    let stream = await store.observe(plan)
    var iterator = stream.makeAsyncIterator()
    let emission = try #require(await iterator.next())
    expectNoDifference(
      emission.values,
      [
        InstantEntitySnapshot(
          id: "session-1",
          namespace: Self.laterNamespace,
          values: [
            "id": .one(.string("session-1")),
            "status": .one(.string("requested")),
          ]
        )
      ]
    )
  }

  /// Runtime-level statement of the same defect over a scripted socket: opening a connection
  /// must durably converge the local attribute set with the server's, so a namespace added
  /// after this device's last sync becomes observable without reinstalling the app.
  ///
  /// Upstream parity: \(reactorInitOKAttributeSource)
  @Test("Opening a connection persists the server attribute set")
  func openingAConnectionPersistsTheServerAttributeSet() async throws {
    let session = LiveReactorParitySession(messages: [
      InstantLiveMessage.initialSyncInitOK(
        clientEventID: "event-init",
        attrs: Self.initOKAttributes
      )
    ])
    let cacheURL = try Self.temporaryCacheURL()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "instant-initial-attribute-sync",
        websocketURI: try #require(URL(string: "wss://ws.example.test/initial-attribute-sync")),
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        liveTransport: session.transport
      )
    )

    let connected = try await runtime.connect()
    expectNoDifference(connected.state, .opened)

    let attributes = try await runtime.persistedStoreAttributes()
    expectNoDifference(
      attributes.filter { $0.namespace == Self.laterNamespace }.map(\.name).sorted(),
      ["id", "status"],
      """
      init-ok carried the attributes for '\(Self.laterNamespace)'. Keeping them in memory only \
      leaves this device unable to query the namespace for the lifetime of the install.
      """
    )
    expectNoDifference(
      attributes.filter { $0.namespace == Self.knownNamespace }.map(\.id).sorted(),
      TodoExample.attributes.map(\.id).sorted(),
      "The already-synced namespace keeps its local attribute ids."
    )

    _ = try await runtime.closeConnection()
  }

  /// The user-visible consequence: with the attributes persisted, observing the new namespace
  /// actually subscribes. Before the fix, observation failed schema validation and returned an
  /// empty stream without sending `add-query`, so the Mac's screen-stream subscription sat open
  /// and silent forever.
  @Test("A namespace learned from init-ok can be subscribed to")
  func aNamespaceLearnedFromInitOKCanBeSubscribedTo() async throws {
    let session = LiveReactorParitySession(messages: [
      InstantLiveMessage.initialSyncInitOK(
        clientEventID: "event-init",
        attrs: Self.initOKAttributes
      )
    ])
    let cacheURL = try Self.temporaryCacheURL()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "instant-initial-attribute-subscription",
        websocketURI: try #require(
          URL(string: "wss://ws.example.test/initial-attribute-subscription")
        ),
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        liveTransport: session.transport
      )
    )

    _ = try await runtime.connect()

    let stream = await runtime.observe(Self.laterNamespaceQuery)
    var iterator = stream.makeAsyncIterator()
    let initial = try #require(await iterator.next())
    expectNoDifference(initial.values, [])

    let sent = await Self.sentMessages(from: session, atLeast: 2)
    expectNoDifference(
      sent.map(\.op),
      ["init", "add-query"],
      """
      Observation must reach the server. An empty observation that never sends add-query is \
      indistinguishable from a namespace with no rows.
      """
    )
    expectNoDifference(
      sent.last?.fields["q"]?.objectValue?.keys.sorted(),
      [Self.laterNamespace]
    )

    _ = try await runtime.closeConnection()
  }

  /// Bounded on purpose. A regression here means the message is never sent, and this suite has
  /// to report that as a failed expectation rather than block the run waiting for it.
  private static func sentMessages(
    from session: LiveReactorParitySession,
    atLeast count: Int
  ) async -> [InstantLiveMessage] {
    for _ in 0..<200 {
      let sent = await session.sentMessages()
      if sent.count >= count { return sent }
      await Task.yield()
    }
    return await session.sentMessages()
  }

  private static func temporaryCacheURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantInitialAttributeSyncTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("state.sqlite")
  }
}

private extension InstantLiveJSONValue {
  static func initialSyncServerAttr(
    id: String,
    namespace: String,
    name: String
  ) -> Self {
    .object([
      "forward-identity": .array([
        .string("identity-\(id)"),
        .string(namespace),
        .string(name),
      ]),
      "id": .string(id),
    ])
  }
}

private extension InstantLiveMessage {
  static func initialSyncInitOK(
    clientEventID: String,
    attrs: [InstantLiveJSONValue]
  ) -> Self {
    Self(
      op: "init-ok",
      clientEventID: clientEventID,
      fields: [
        "attrs": .array(attrs),
        "auth": .null,
        "session-id": .string("initial-attribute-sync-session"),
      ]
    )
  }
}
