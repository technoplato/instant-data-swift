import CustomDump
import Dependencies
import Foundation
import InstantSwiftData
import Testing

#if canImport(SwiftUI)
  import SwiftUI

  @Suite
  struct V3RecordingsListFixtureTests {
    private let sourceReferences = [
      "upstream/instant/client/packages/vue/src/tests/InstantVueDatabase.test.ts:76-204",
      "upstream/sqlite-data/Sources/SQLiteData/Documentation.docc/Articles/DynamicQueries.md:46-91",
      "upstream/sqlite-data/Examples/CaseStudies/DynamicQuery.swift:17,82-99",
      "upstream/sqlite-data/Tests/SQLiteDataTests/CloudKitTests/SharingPermissionsTests.swift",
      "validation/ts-runner/src/sharing-sdk-contract.test.ts:12-108",
    ]

    @Test @MainActor
    func recordingsListModifierSyntaxCompilesWithDynamicQueryIdentity() {
      let screen = V3RecordingsListFixture()
      let view: any View = screen
      _ = view

      let viewerID = InstantID<V3RecordingListUser>(rawValue: "user-viewer")
      let mine = v3RecordingsQuery(
        scope: .mine,
        searchText: "walk",
        viewerID: viewerID
      )
      let shared = v3RecordingsQuery(
        scope: .shared,
        searchText: "walk",
        viewerID: viewerID
      )
      let searched = v3RecordingsQuery(
        scope: .mine,
        searchText: "meeting",
        viewerID: viewerID
      )

      #expect(mine.plan.id != shared.plan.id)
      #expect(mine.plan.id != searched.plan.id)
      expectNoDifference(
        mine.plan.filters,
        [
          .equals(field: "owner.id", value: .string("user-viewer")),
          .iLike(field: "title", pattern: "%walk%"),
        ]
      )
      expectNoDifference(
        shared.plan.filters,
        [
          .or([
            .equals(field: "readers.id", value: .string("user-viewer")),
            .equals(field: "writers.id", value: .string("user-viewer")),
          ]),
          .iLike(field: "title", pattern: "%walk%"),
        ]
      )
      expectNoDifference(
        shared.plan.includes?.map(\.name),
        ["owner", "readers", "writers", "share"]
      )
      expectNoDifference(
        shared.plan.includes?.last?.query?.includes?.last?.query?.filters,
        [.equals(field: "user.id", value: .string("user-viewer"))]
      )
      expectNoDifference(
        sourceReferences,
        [
          "upstream/instant/client/packages/vue/src/tests/InstantVueDatabase.test.ts:76-204",
          "upstream/sqlite-data/Sources/SQLiteData/Documentation.docc/Articles/DynamicQueries.md:46-91",
          "upstream/sqlite-data/Examples/CaseStudies/DynamicQuery.swift:17,82-99",
          "upstream/sqlite-data/Tests/SQLiteDataTests/CloudKitTests/SharingPermissionsTests.swift",
          "validation/ts-runner/src/sharing-sdk-contract.test.ts:12-108",
        ]
      )
    }

    @Test
    func recordingsListDynamicFetchPreservesCacheAndReplacesStaleObservation() async throws {
      let recorder = V3RecordingsObservationRecorder()
      let client = v3RecordingsObservationClient(recorder)
      let cached = try V3RecordingListRow(
        snapshot: v3RecordingSnapshot(
          id: "recording-cached",
          title: "Cached walk",
          ownerID: "user-viewer"
        )
      )
      let fetch = FetchAll<V3RecordingListRow>(wrappedValue: [cached])
      let viewerID = InstantID<V3RecordingListUser>(rawValue: "user-viewer")
      let mineQuery = v3RecordingsQuery(
        scope: .mine,
        searchText: "",
        viewerID: viewerID
      )
      let sharedQuery = v3RecordingsQuery(
        scope: .shared,
        searchText: "",
        viewerID: viewerID
      )

      let mineTask = Task {
        let fetch = fetch
        try await fetch.task(mineQuery, using: client)
      }
      try await waitForV3RecordingsCondition(
        operation: "wait for mine recordings observation"
      ) {
        await recorder.counts().observationCount == 1
      }
      expectNoDifference(fetch.wrappedValue.map(\.title), ["Cached walk"])
      expectNoDifference(fetch.loadError, nil)
      expectNoDifference(fetch.isLoading, true)

      await recorder.yield(
        .mine,
        values: [
          v3RecordingSnapshot(
            id: "recording-live-mine",
            title: "Live walk",
            ownerID: "user-viewer"
          )
        ]
      )
      try await waitForV3RecordingsCondition(
        operation: "wait for mine recordings value"
      ) {
        fetch.wrappedValue.map(\.title) == ["Live walk"]
      }
      expectNoDifference(fetch.wrappedValue.first?.viewerMembership?.role, .owner)
      expectNoDifference(fetch.isLoading, false)

      let sharedTask = Task {
        let fetch = fetch
        try await fetch.task(sharedQuery, using: client)
      }
      try await waitForV3RecordingsCondition(
        operation: "wait for replacement recordings observation"
      ) {
        await recorder.counts().observationCount == 2
      }
      try await waitForV3RecordingsCondition(
        operation: "wait for stale recordings observation cancellation"
      ) {
        await recorder.counts().terminationCount == 1
      }
      expectNoDifference(fetch.wrappedValue.map(\.title), ["Live walk"])
      expectNoDifference(fetch.loadError, nil)
      expectNoDifference(fetch.isLoading, true)

      do {
        try await mineTask.value
        Issue.record("Expected the replaced recordings query task to cancel.")
      } catch is CancellationError {
      } catch {
        Issue.record("Expected CancellationError, got \(error).")
      }

      await recorder.yield(
        .mine,
        values: [
          v3RecordingSnapshot(
            id: "recording-stale-mine",
            title: "Stale walk",
            ownerID: "user-viewer"
          )
        ],
        sequence: 1
      )
      try await Task.sleep(nanoseconds: 10_000_000)
      expectNoDifference(fetch.wrappedValue.map(\.title), ["Live walk"])
      expectNoDifference(fetch.isLoading, true)

      await recorder.yield(
        .shared,
        values: [
          v3RecordingSnapshot(
            id: "recording-live-shared",
            title: "Shared meeting",
            ownerID: "user-owner"
          )
        ]
      )
      try await waitForV3RecordingsCondition(
        operation: "wait for replacement recordings value"
      ) {
        fetch.wrappedValue.map(\.title) == ["Shared meeting"]
      }
      expectNoDifference(fetch.wrappedValue.first?.viewerMembership?.role, .reader)
      expectNoDifference(fetch.loadError, nil)
      expectNoDifference(fetch.isLoading, false)

      await recorder.yield(
        .shared,
        values: [
          v3RecordingSnapshot(
            id: "recording-live-shared",
            title: "Shared meeting",
            ownerID: "user-owner",
            role: .writer
          )
        ],
        sequence: 1
      )
      try await waitForV3RecordingsCondition(
        operation: "wait for recording membership role replacement"
      ) {
        fetch.wrappedValue.first?.viewerMembership?.role == .writer
      }

      await recorder.yield(.shared, values: [], sequence: 2)
      try await waitForV3RecordingsCondition(
        operation: "wait for recording share revocation"
      ) {
        fetch.wrappedValue.isEmpty
      }

      sharedTask.cancel()
      do {
        try await sharedTask.value
        Issue.record("Expected the active recordings query task to cancel.")
      } catch is CancellationError {
      } catch {
        Issue.record("Expected CancellationError, got \(error).")
      }
      try await waitForV3RecordingsCondition(
        operation: "wait for replacement recordings observation cleanup"
      ) {
        await recorder.counts().terminationCount == 2
      }

      let plans = await recorder.queryPlans()
      expectNoDifference(
        plans.map(\.filters),
        [
          [.equals(field: "owner.id", value: .string("user-viewer"))],
          [
            .or([
              .equals(field: "readers.id", value: .string("user-viewer")),
              .equals(field: "writers.id", value: .string("user-viewer")),
            ])
          ],
        ]
      )
    }

    @Test @MainActor
    func renameMessageFiresOptimisticAndAcceptedCallbacksOnce() async throws {
      let (client, runtime) = try await v3RecordingsMessageRuntime("accepted")
      let recorder = V3RenameCallbackRecorder()
      let task = client.send(
        RenameRecording(
          id: InstantID(rawValue: "recording-message-accepted"),
          title: "Edited walk title"
        ),
        onOptimisticCommit: { (change: borrowing RecordingRenamedChange) in
          recorder.optimistic.append(change.summary())
        },
        onServerAccepted: { (change: borrowing RecordingRenamedChange) in
          recorder.accepted.append(change.summary())
        },
        onFailure: { error in
          recorder.failures.append(error)
        }
      )

      let mutationID = try await waitForV3PendingMutation(runtime)
      let optimisticRows = try await client.query(V3RecordingListRow.query)
      expectNoDifference(optimisticRows.map(\.title), ["Edited walk title"])
      expectNoDifference(recorder.optimistic.map(\.newTitle), ["Edited walk title"])
      expectNoDifference(recorder.accepted, [])
      expectNoDifference(recorder.failures, [])

      _ = try await runtime.applyServerTransaction(
        InstantStoreTransaction(id: "passive-refresh", operations: []),
        processedTransactionID: "passive-refresh"
      )
      try await Task.sleep(nanoseconds: 10_000_000)
      expectNoDifference(recorder.accepted, [])

      _ = try await runtime.flushPendingMutations()
      await task.value
      expectNoDifference(recorder.optimistic.count, 1)
      expectNoDifference(recorder.accepted.map(\.newTitle), ["Edited walk title"])
      expectNoDifference(recorder.failures, [])

      _ = try await runtime.applyServerTransaction(
        InstantStoreTransaction(id: "later-passive-refresh", operations: []),
        processedTransactionID: "later-passive-refresh"
      )
      try await Task.sleep(nanoseconds: 10_000_000)
      expectNoDifference(recorder.optimistic.count, 1)
      expectNoDifference(recorder.accepted.count, 1)
    }

    @Test @MainActor
    func renameMessageFailureDoesNotReplayCallbacksAfterRetry() async throws {
      let (client, runtime) = try await v3RecordingsMessageRuntime("failed")
      let recorder = V3RenameCallbackRecorder()
      let task = client.send(
        RenameRecording(
          id: InstantID(rawValue: "recording-message-failed"),
          title: "Rejected title"
        ),
        onOptimisticCommit: { change in
          recorder.optimistic.append(change.summary())
        },
        onServerAccepted: { change in
          recorder.accepted.append(change.summary())
        },
        onFailure: { error in
          recorder.failures.append(error)
        }
      )

      let mutationID = try await waitForV3PendingMutation(runtime)
      _ = try await runtime.failMutation(id: mutationID, message: "title update denied")
      await task.value

      expectNoDifference(recorder.optimistic.count, 1)
      expectNoDifference(recorder.accepted, [])
      expectNoDifference(recorder.failures.map(\.message), ["title update denied"])
      expectNoDifference(
        recorder.failures.map(\.recoveryMessage),
        ["Inspect the deployed schema and permissions, then retry the action."]
      )

      _ = try await runtime.retryMutation(id: mutationID)
      _ = try await runtime.flushPendingMutations()
      try await Task.sleep(nanoseconds: 10_000_000)
      expectNoDifference(recorder.optimistic.count, 1)
      expectNoDifference(recorder.accepted, [])
      expectNoDifference(recorder.failures.count, 1)
    }
  }

  @MainActor
  private struct V3RecordingsListFixture: View {
    @InstantAuth(V3RecordingListUser.self, providers: V3RecordingListAuthProviders.self)
    private var auth

    @FetchAll
    private var rows: [V3RecordingListRow]

    @State
    private var scope: V3RecordingListScope = .mine

    @State
    private var searchText = ""

    @Dependency(\.defaultInstantSwiftData)
    private var db

    var body: some View {
      List(rows) { row in
        Button(row.title) {
          renameButtonTapped(row)
        }
      }
      .searchable(text: $searchText)
      .instantFetch(
        $rows,
        rowsQuery
      )
    }

    private var rowsQuery: InstantQuery<V3RecordingListRow> {
      v3RecordingsQuery(
        scope: scope,
        searchText: searchText,
        viewerID: auth.user?.id
      )
    }

    private func renameButtonTapped(_ row: V3RecordingListRow) {
      db.send(
        RenameRecording(id: row.id, title: "Edited walk title"),
        onOptimisticCommit: { (change: borrowing RecordingRenamedChange) in
          _ = change.summary()
        },
        onServerAccepted: { _ in },
        onFailure: { error in
          _ = error.recoveryMessage
        }
      )
    }
  }

  private enum V3RecordingListScope: String, Hashable, Sendable {
    case mine
    case shared
  }

  private func v3RecordingsQuery(
    scope: V3RecordingListScope,
    searchText: String,
    viewerID: InstantID<V3RecordingListUser>?
  ) -> InstantQuery<V3RecordingListRow> {
    guard let viewerID else {
      return V3RecordingListRow.query.where(V3RecordingListRow.identifier.isIn([]))
    }
    let viewerMembership = V3RecordingShareMembership.query
      .where(V3RecordingShareMembership.user == viewerID)
      .include(V3RecordingShareMembership.user)
    let share = V3RecordingShare.query
      .include(V3RecordingShare.owner)
      .include(V3RecordingShare.memberships, viewerMembership)
    var query = V3RecordingListRow.query
      .include(V3RecordingListRow.owner)
      .include(V3RecordingListRow.readers)
      .include(V3RecordingListRow.writers)
      .include(V3RecordingListRow.share, share)
      .order(V3RecordingListRow.title)
    switch scope {
    case .mine:
      query = query.where(V3RecordingListRow.owner == viewerID)
    case .shared:
      query = query.where(
        .any(
          V3RecordingListRow.readers == viewerID,
          V3RecordingListRow.writers == viewerID
        )
      )
    }
    guard !searchText.isEmpty else { return query }
    return query.where(V3RecordingListRow.title.iLike("%\(searchText)%"))
  }

  private struct V3RecordingListRow: Hashable, Codable, InstantEntityModel {
    var id: InstantID<V3RecordingListRow>
    var title: String
    var ownerID: InstantID<V3RecordingListUser>
    var deviceID: String
    var state: String
    var durationMilliseconds: Int
    var viewerMembership: V3RecordingViewerMembership?

    static let instantNamespace = "v3_capture_recordings"
    static let identifier = InstantAttributePath<V3RecordingListRow, String>("id")
    static let title = InstantAttributePath<V3RecordingListRow, String>("title")
    static let owner = InstantAttributePath<V3RecordingListRow, InstantID<V3RecordingListUser>>(
      "owner"
    )
    static let readers = InstantAttributePath<
      V3RecordingListRow,
      InstantID<V3RecordingListUser>
    >("readers")
    static let writers = InstantAttributePath<
      V3RecordingListRow,
      InstantID<V3RecordingListUser>
    >("writers")
    static let share = InstantReverseRelation<V3RecordingListRow, V3RecordingShare>(
      attribute: V3RecordingShare.root
    )
    static let deviceID = InstantAttributePath<V3RecordingListRow, String>("deviceID")
    static let state = InstantAttributePath<V3RecordingListRow, String>("state")
    static let durationMilliseconds = InstantAttributePath<V3RecordingListRow, Int>(
      "durationMilliseconds"
    )
    static let instantAttributes = [
      InstantAttribute.primaryKey(namespace: instantNamespace),
      InstantAttribute(
        id: "v3_capture_recordings/title",
        namespace: instantNamespace,
        name: "title",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "v3_capture_recordings/owner",
        namespace: instantNamespace,
        name: "owner",
        valueType: .ref,
        isIndexed: true,
        forwardIdentity: "v3_capture_recordings/owner",
        reverseIdentity: "$users/recordings",
        linkNamespace: V3RecordingListUser.instantNamespace
      ),
      InstantAttribute(
        id: "v3_capture_recordings/readers",
        namespace: instantNamespace,
        name: "readers",
        valueType: .ref,
        cardinality: .many,
        forwardIdentity: "v3_capture_recordings/readers",
        reverseIdentity: "$users/readableRecordings",
        linkNamespace: V3RecordingListUser.instantNamespace
      ),
      InstantAttribute(
        id: "v3_capture_recordings/writers",
        namespace: instantNamespace,
        name: "writers",
        valueType: .ref,
        cardinality: .many,
        forwardIdentity: "v3_capture_recordings/writers",
        reverseIdentity: "$users/writableRecordings",
        linkNamespace: V3RecordingListUser.instantNamespace
      ),
      InstantAttribute(
        id: "v3_capture_recordings/deviceID",
        namespace: instantNamespace,
        name: "deviceID",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "v3_capture_recordings/state",
        namespace: instantNamespace,
        name: "state",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "v3_capture_recordings/durationMilliseconds",
        namespace: instantNamespace,
        name: "durationMilliseconds",
        valueType: .number,
        isIndexed: true
      ),
    ]

    init(
      id: InstantID<Self>,
      title: String,
      ownerID: InstantID<V3RecordingListUser>,
      deviceID: String,
      state: String,
      durationMilliseconds: Int,
      viewerMembership: V3RecordingViewerMembership? = nil
    ) {
      self.id = id
      self.title = title
      self.ownerID = ownerID
      self.deviceID = deviceID
      self.state = state
      self.durationMilliseconds = durationMilliseconds
      self.viewerMembership = viewerMembership
    }

    init(snapshot: InstantEntitySnapshot) throws {
      guard case let .string(title) = snapshot.values["title"]?.first,
        case let .ref(ownerID) = snapshot.values["owner"]?.first,
        case let .string(deviceID) = snapshot.values["deviceID"]?.first,
        case let .string(state) = snapshot.values["state"]?.first,
        case let .number(durationMilliseconds) =
          snapshot.values["durationMilliseconds"]?.first,
        let exactDuration = Int(exactly: durationMilliseconds)
      else {
        throw InstantError(
          code: .decodeFailed,
          operation: "decode V3 recording list row fixture",
          namespace: Self.instantNamespace,
          localID: snapshot.id,
          message: "Expected canonical title, owner, device, state, and duration values.",
          recovery: "Keep the compile fixture aligned with its declared attributes."
        )
      }
      self.id = InstantID(rawValue: snapshot.id)
      self.title = title
      self.ownerID = InstantID(rawValue: ownerID)
      self.deviceID = deviceID
      self.state = state
      self.durationMilliseconds = exactDuration
      self.viewerMembership = try snapshot.links?["share"]?.first
        .flatMap { $0.links?["memberships"]?.first }
        .map(V3RecordingViewerMembership.init)
    }
  }

  private enum V3RecordingListAuthProviders: InstantAuthProviderCatalog {
    static let magicCode = AuthProvider.magicCode(
      email: .instant,
      extraFields: V3RecordingListUser.Signup.self
    )
    static let all = [magicCode]
  }

  private struct V3RecordingListUser: Hashable, Codable, InstantEntityModel {
    struct Signup: Sendable {}

    var id: InstantID<Self>
    var email: String

    static let instantNamespace = "$users"
    static let instantAttributes = [
      InstantAttribute(
        id: "$users/email",
        namespace: instantNamespace,
        name: "email",
        valueType: .string,
        isIndexed: true,
        isUnique: true
      )
    ]

    init(snapshot: InstantEntitySnapshot) throws {
      guard case let .string(email) = snapshot.values["email"]?.first else {
        throw InstantError(
          code: .decodeFailed,
          operation: "decode V3 recordings-list user",
          namespace: Self.instantNamespace,
          localID: snapshot.id,
          message: "Expected the canonical user email.",
          recovery: "Keep the recordings-list auth model aligned with $users."
        )
      }
      id = InstantID(rawValue: snapshot.id)
      self.email = email
    }
  }

  private struct V3RecordingShare: Hashable, Codable, InstantEntityModel {
    var id: InstantID<Self>

    static let instantNamespace = "v3_shares"
    static let owner =
      InstantAttributePath<V3RecordingShare, InstantID<V3RecordingListUser>>("owner")
    static let root =
      InstantAttributePath<V3RecordingShare, InstantID<V3RecordingListRow>>("root")
    static let memberships = InstantReverseRelation<
      V3RecordingShare,
      V3RecordingShareMembership
    >(attribute: V3RecordingShareMembership.share)
    static let instantAttributes = [
      InstantAttribute(
        id: "v3_shares/token",
        namespace: instantNamespace,
        name: "token",
        valueType: .string,
        isIndexed: true,
        isUnique: true
      ),
      InstantAttribute(
        id: "v3_shares/rootNamespace",
        namespace: instantNamespace,
        name: "rootNamespace",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "v3_shares/rootID",
        namespace: instantNamespace,
        name: "rootID",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "v3_shares/createdAt",
        namespace: instantNamespace,
        name: "createdAt",
        valueType: .date,
        isIndexed: true
      ),
      InstantAttribute(
        id: "v3_shares/updatedAt",
        namespace: instantNamespace,
        name: "updatedAt",
        valueType: .date,
        isIndexed: true
      ),
      InstantAttribute(
        id: "v3_shares/revokedAt",
        namespace: instantNamespace,
        name: "revokedAt",
        valueType: .date,
        isRequired: false,
        isIndexed: true
      ),
      InstantAttribute(
        id: "v3_shares/owner",
        namespace: instantNamespace,
        name: "owner",
        valueType: .ref,
        forwardIdentity: "v3_shares/owner",
        reverseIdentity: "$users/ownedShares",
        linkNamespace: V3RecordingListUser.instantNamespace
      ),
      InstantAttribute(
        id: "v3_shares/root",
        namespace: instantNamespace,
        name: "root",
        valueType: .ref,
        isUnique: true,
        forwardIdentity: "v3_shares/root",
        reverseIdentity: "v3_capture_recordings/share",
        linkNamespace: V3RecordingListRow.instantNamespace
      ),
    ]

    init(snapshot: InstantEntitySnapshot) throws {
      id = InstantID(rawValue: snapshot.id)
    }
  }

  private struct V3RecordingShareMembership: Hashable, Codable, InstantEntityModel {
    var id: InstantID<Self>

    static let instantNamespace = "v3_share_memberships"
    static let role = InstantAttributePath<V3RecordingShareMembership, String>("role")
    static let acceptedAt = InstantAttributePath<V3RecordingShareMembership, Date>("acceptedAt")
    static let share =
      InstantAttributePath<V3RecordingShareMembership, InstantID<V3RecordingShare>>("share")
    static let user = InstantAttributePath<
      V3RecordingShareMembership,
      InstantID<V3RecordingListUser>
    >("user")
    static let instantAttributes = [
      InstantAttribute(
        id: "v3_share_memberships/role",
        namespace: instantNamespace,
        name: "role",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "v3_share_memberships/acceptedAt",
        namespace: instantNamespace,
        name: "acceptedAt",
        valueType: .date,
        isIndexed: true
      ),
      InstantAttribute(
        id: "v3_share_memberships/revokedAt",
        namespace: instantNamespace,
        name: "revokedAt",
        valueType: .date,
        isRequired: false,
        isIndexed: true
      ),
      InstantAttribute(
        id: "v3_share_memberships/share",
        namespace: instantNamespace,
        name: "share",
        valueType: .ref,
        forwardIdentity: "v3_share_memberships/share",
        reverseIdentity: "v3_shares/memberships",
        linkNamespace: V3RecordingShare.instantNamespace,
        onDelete: .cascade
      ),
      InstantAttribute(
        id: "v3_share_memberships/user",
        namespace: instantNamespace,
        name: "user",
        valueType: .ref,
        forwardIdentity: "v3_share_memberships/user",
        reverseIdentity: "$users/shareMemberships",
        linkNamespace: V3RecordingListUser.instantNamespace
      ),
    ]

    init(snapshot: InstantEntitySnapshot) throws {
      id = InstantID(rawValue: snapshot.id)
    }
  }

  private struct V3RecordingViewerMembership: Hashable, Codable, Sendable {
    var id: String
    var userID: InstantID<V3RecordingListUser>
    var role: InstantShareRole
    var acceptedAt: Date

    init(_ snapshot: InstantLinkedEntitySnapshot) throws {
      guard case let .string(rawRole) = snapshot.values["role"]?.first,
        let role = InstantShareRole(rawValue: rawRole),
        case let .date(acceptedAt) = snapshot.values["acceptedAt"]?.first,
        let userID = snapshot.links?["user"]?.first?.id
      else {
        throw InstantError(
          code: .decodeFailed,
          operation: "decode V3 recording viewer membership",
          namespace: V3RecordingShareMembership.instantNamespace,
          localID: snapshot.id,
          message: "Expected role, acceptedAt, and one user link.",
          recovery: "Keep the recording row projection aligned with the share graph."
        )
      }
      id = snapshot.id
      self.userID = InstantID(rawValue: userID)
      self.role = role
      self.acceptedAt = acceptedAt
    }
  }

  private struct RenameRecording: InstantMessage {
    var id: InstantID<V3RecordingListRow>
    var title: String

    func prepare(using client: InstantSwiftDataClient) async throws
      -> InstantPreparedMessage<RecordingRenamedChange>
    {
      guard let recording = try await client.query(V3RecordingListRow.query)
        .first(where: { $0.id == id })
      else {
        throw InstantError(
          code: .validationFailed,
          operation: "prepare recording rename",
          localID: id.rawValue,
          message: "The recording does not exist in the local snapshot.",
          recovery: "Reload the recordings query before retrying the rename."
        )
      }
      let change = RecordingRenamedChange(
        id: id,
        oldTitle: recording.title,
        newTitle: title
      )
      return InstantPreparedMessage(change: change) {
        V3RecordingListRow.update(id: id, V3RecordingListRow.title.set(title))
      }
    }
  }

  private struct RecordingRenamedChange: Sendable {
    var id: InstantID<V3RecordingListRow>
    var oldTitle: String
    var newTitle: String

    borrowing func summary() -> RecordingRenameSummary {
      RecordingRenameSummary(
        id: id,
        oldTitle: oldTitle,
        newTitle: newTitle
      )
    }
  }

  private struct RecordingRenameSummary: Equatable, Sendable {
    var id: InstantID<V3RecordingListRow>
    var oldTitle: String
    var newTitle: String
  }

  @MainActor
  private final class V3RenameCallbackRecorder {
    var optimistic: [RecordingRenameSummary] = []
    var accepted: [RecordingRenameSummary] = []
    var failures: [InstantError] = []
  }

  private actor V3RecordingsObservationRecorder {
    enum Request: Hashable, Sendable {
      case mine
      case shared
    }

    private var continuations: [Request: AsyncStream<InstantQueryEmission>.Continuation] = [:]
    private var observationCount = 0
    private var plans: [InstantQueryPlan] = []
    private var queryIDs: [Request: String] = [:]
    private var terminationCount = 0

    func observe(plan: InstantQueryPlan) -> AsyncStream<InstantQueryEmission> {
      observationCount += 1
      plans.append(plan)
      let request = Self.request(for: plan)
      queryIDs[request] = plan.id

      let stream = AsyncStream<InstantQueryEmission>.makeStream(
        bufferingPolicy: .bufferingNewest(1)
      )
      continuations[request] = stream.continuation
      stream.continuation.onTermination = { @Sendable _ in
        Task {
          await self.recordTermination()
        }
      }
      return stream.stream
    }

    func yield(
      _ request: Request,
      values: [InstantEntitySnapshot],
      sequence: Int64 = 0
    ) {
      guard
        let continuation = continuations[request],
        let queryID = queryIDs[request]
      else { return }

      continuation.yield(
        InstantQueryEmission(queryID: queryID, sequence: sequence, values: values)
      )
    }

    func counts() -> (observationCount: Int, terminationCount: Int) {
      (observationCount, terminationCount)
    }

    func queryPlans() -> [InstantQueryPlan] {
      plans
    }

    private func recordTermination() {
      terminationCount += 1
    }

    private static func request(for plan: InstantQueryPlan) -> Request {
      plan.filters.contains {
        if case let .or(filters) = $0 {
          return filters.contains(.equals(field: "readers.id", value: .string("user-viewer")))
            || filters.contains(.equals(field: "writers.id", value: .string("user-viewer")))
        }
        return false
      }
        ? .shared
        : .mine
    }
  }

  private func v3RecordingsObservationClient(
    _ recorder: V3RecordingsObservationRecorder
  ) -> InstantSwiftDataClient {
    InstantSwiftDataClient(
      transact: { transaction in
        InstantStoreMutationResult(
          transactionID: transaction.id,
          changedEntityIDs: [],
          tripleCount: transaction.operations.count,
          emissions: []
        )
      },
      query: { _ in [] },
      observe: { plan in
        await recorder.observe(plan: plan)
      },
      pendingMutations: { [] },
      localID: { name in "v3-recordings-\(name)" }
    )
  }

  private func v3RecordingsMessageRuntime(
    _ suffix: String
  ) async throws -> (InstantSwiftDataClient, InstantRuntime) {
    let cacheURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("v3-recordings-message-\(suffix)-\(UUID().uuidString).sqlite")
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "v3-recordings-message-\(suffix)",
        persistenceURL: cacheURL,
        initialAttributes: V3RecordingListRow.instantAttributes,
        mutationTransport: InstantMutationTransportClient { request in
          InstantMutationTransportResponse(
            results: request.mutations.map {
              InstantMutationTransportResult(
                mutationID: $0.mutationID,
                outcome: .confirmed,
                acceptance: .serverAccepted
              )
            }
          )
        }
      )
    )
    let client = InstantSwiftDataClient(runtime: runtime)
    try await client.transact(id: "seed-\(suffix)") {
      V3RecordingListRow.create(
        id: InstantID(rawValue: "recording-message-\(suffix)"),
        V3RecordingListRow.title.set("Morning walk"),
        V3RecordingListRow.owner.set(InstantID(rawValue: "user-message-owner")),
        V3RecordingListRow.deviceID.set("device-message"),
        V3RecordingListRow.state.set("ready"),
        V3RecordingListRow.durationMilliseconds.set(0)
      )
    }
    _ = try await runtime.flushPendingMutations()
    return (client, runtime)
  }

  private func waitForV3PendingMutation(_ runtime: InstantRuntime) async throws -> String {
    for _ in 0..<100 {
      if let id = await runtime.pendingMutations().first?.id {
        return id
      }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    throw InstantError(
      code: .validationFailed,
      operation: "wait for V3 rename mutation",
      message: "Timed out waiting for the optimistic rename mutation.",
      recovery: "Inspect InstantMessage preparation and the durable outbox."
    )
  }

  private func waitForV3RecordingsCondition(
    operation: String,
    until condition: @escaping @Sendable () async -> Bool
  ) async throws {
    for _ in 0..<100 {
      if await condition() {
        return
      }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    throw InstantError(
      code: .validationFailed,
      operation: operation,
      message: "Timed out waiting for the V3 recordings-list fixture condition.",
      recovery: "Inspect the controlled query client and FetchAll replacement lifecycle."
    )
  }

  private func v3RecordingSnapshot(
    id: String,
    title: String,
    ownerID: String,
    viewerID: String = "user-viewer",
    role explicitRole: InstantShareRole? = nil
  ) -> InstantEntitySnapshot {
    let role = explicitRole ?? (ownerID == viewerID ? .owner : .reader)
    let acceptedAt = Date(timeIntervalSince1970: 1)
    let owner = InstantLinkedEntitySnapshot(
      id: ownerID,
      namespace: V3RecordingListUser.instantNamespace,
      values: [:]
    )
    let viewer = InstantLinkedEntitySnapshot(
      id: viewerID,
      namespace: V3RecordingListUser.instantNamespace,
      values: [:]
    )
    let membership = InstantLinkedEntitySnapshot(
      id: "membership-\(id)-\(viewerID)",
      namespace: V3RecordingShareMembership.instantNamespace,
      values: [
        "role": .one(.string(role.rawValue)),
        "acceptedAt": .one(.date(acceptedAt)),
      ],
      links: ["user": [viewer]]
    )
    let share = InstantLinkedEntitySnapshot(
      id: "share-\(id)",
      namespace: V3RecordingShare.instantNamespace,
      values: [
        "token": .one(.string("token-\(id)")),
        "rootNamespace": .one(.string(V3RecordingListRow.instantNamespace)),
        "rootID": .one(.string(id)),
        "createdAt": .one(.date(acceptedAt)),
        "updatedAt": .one(.date(acceptedAt)),
      ],
      links: [
        "owner": [owner],
        "memberships": [membership],
      ]
    )
    let readers = role == .reader ? [viewer] : []
    let writers = role == .writer ? [viewer] : []
    return InstantEntitySnapshot(
      id: id,
      namespace: V3RecordingListRow.instantNamespace,
      values: [
        "title": .one(.string(title)),
        "owner": .one(.ref(ownerID)),
        "deviceID": .one(.string("device-fixture")),
        "state": .one(.string("ready")),
        "durationMilliseconds": .one(.number(0)),
        "readers": .many(readers.map { .ref($0.id) }),
        "writers": .many(writers.map { .ref($0.id) }),
      ],
      links: [
        "owner": [owner],
        "readers": readers,
        "writers": writers,
        "share": [share],
      ]
    )
  }
#endif
