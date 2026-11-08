import CustomDump
import Dependencies
import Foundation
import InstantSwiftData
import Testing

/// ADR 0015 L3: aggregates derived when a query is read, the Instant counterparts of SQLiteData's grouped-join counts
/// (`$1.id.count(filter:)`) and sectioned results (`fetchAll(_:sectionBy:)`). Nothing stores a count or a section, so
/// nothing keeps one in sync: each follows the rows it is derived from.
@Suite(.serialized)
struct InstantAggregateFetchTests {
  struct UserRow: Equatable, Sendable {
    var name: String
    var postCount: Int
  }

  @Test
  func countsAReverseRelationsChildrenOnEachRow() async throws {
    try await withAggregateClient { db in
      try await seedPosts(db, author: "user-ada", name: "Ada", sortIndexes: [0, 1, 2])
      try await seedPosts(db, author: "user-grace", name: "Grace", sortIndexes: [])

      let rows = try await InstantFetchRequest(
        AggregateUser.query.order(AggregateUser.name),
        counting: AggregateUser.posts.count()
      ) { user, postCount in
        UserRow(name: user.name, postCount: postCount)
      }
      .load(using: db)

      expectNoDifference(
        rows,
        [
          UserRow(name: "Ada", postCount: 3),
          UserRow(name: "Grace", postCount: 0),
        ]
      )
    }
  }

  @Test
  func countsOnlyTheChildrenItsPredicateAdmits() async throws {
    struct Counts: Equatable, Sendable {
      var posts: Int
      var laterPosts: Int
      var images: Int
    }
    try await withAggregateClient { db in
      try await seedPosts(db, author: "user-ada", name: "Ada", sortIndexes: [0, 1, 2])
      try await db.transact {
        AggregateAttachment.create(
          id: InstantID(rawValue: "attachment-1"),
          AggregateAttachment.kind.set("image"),
          AggregateAttachment.owner.set(InstantID(rawValue: "user-ada"))
        )
        AggregateAttachment.create(
          id: InstantID(rawValue: "attachment-2"),
          AggregateAttachment.kind.set("image"),
          AggregateAttachment.owner.set(InstantID(rawValue: "user-ada"))
        )
        AggregateAttachment.create(
          id: InstantID(rawValue: "attachment-3"),
          AggregateAttachment.kind.set("audio"),
          AggregateAttachment.owner.set(InstantID(rawValue: "user-ada"))
        )
      }

      let rows = try await InstantFetchRequest(
        AggregateUser.query,
        counting: AggregateUser.posts.count(),
        AggregateUser.posts.count(where: AggregatePost.sortIndex >= 1),
        AggregateUser.attachments.count(where: AggregateAttachment.kind == "image")
      ) { _, posts, laterPosts, images in
        Counts(posts: posts, laterPosts: laterPosts, images: images)
      }
      .load(using: db)

      expectNoDifference(rows, [Counts(posts: 3, laterPosts: 2, images: 2)])
    }
  }

  @Test
  func countsTheEntitiesAForwardManyLinkHolds() async throws {
    struct AlbumRow: Equatable, Sendable {
      var title: String
      var photos: Int
      var images: Int
    }
    try await withAggregateClient { db in
      let albumID = InstantID<AggregateAlbum>(rawValue: "album-1")
      try await db.transact {
        AggregateAlbum.create(id: albumID, AggregateAlbum.title.set("Trip"))
        AggregateAlbum.create(id: InstantID(rawValue: "album-2"), AggregateAlbum.title.set("Empty"))
      }
      for (index, kind) in ["image", "image", "video"].enumerated() {
        let photoID = InstantID<AggregatePhoto>(rawValue: "photo-\(index)")
        try await db.transact {
          AggregatePhoto.create(id: photoID, AggregatePhoto.kind.set(kind))
          AggregateAlbum.photos.link(from: albumID, to: photoID)
        }
      }

      let rows = try await InstantFetchRequest(
        AggregateAlbum.query.order(AggregateAlbum.title, .descending),
        counting: AggregateAlbum.photos.count(),
        AggregateAlbum.photos.count(where: AggregatePhoto.kind == "image")
      ) { album, photos, images in
        AlbumRow(title: album.title, photos: photos, images: images)
      }
      .load(using: db)

      expectNoDifference(
        rows,
        [
          AlbumRow(title: "Trip", photos: 3, images: 2),
          AlbumRow(title: "Empty", photos: 0, images: 0),
        ]
      )
    }
  }

  /// A row shows its first two posts and how many there are: the count covers the include's children before its limit.
  @Test
  func countCoversAnIncludesChildrenBeforeItsLimit() async throws {
    struct PreviewRow: Equatable, Sendable {
      var name: String
      var previewTitles: [String]
      var postCount: Int
    }
    try await withAggregateClient { db in
      try await seedPosts(db, author: "user-ada", name: "Ada", sortIndexes: [0, 1, 2])
      let postCount = AggregateUser.posts.count()

      let rows = try await InstantFetchRequest(
        snapshotsOf: AggregateUser.query
          .counting(postCount)
          .include(
            AggregateUser.posts,
            AggregatePost.query.order(AggregatePost.sortIndex, .descending).limit(2)
          )
      ) { snapshots in
        try snapshots.map { snapshot in
          PreviewRow(
            name: try AggregateUser(snapshot: snapshot).name,
            previewTitles: try snapshot.includedEntitySnapshots(named: AggregateUser.posts.name)
              .map { try AggregatePost(snapshot: $0).title },
            postCount: snapshot.count(postCount)
          )
        }
      }
      .load(using: db)

      expectNoDifference(
        rows,
        [PreviewRow(name: "Ada", previewTitles: ["post-2", "post-1"], postCount: 3)]
      )
    }
  }

  /// A count is derived each time the rows change: a child written, one whose counted field changes, and one deleted.
  @Test
  func countsFollowWritesAsTheyHappen() async throws {
    struct Counts: Equatable, Sendable {
      var posts: Int
      var laterPosts: Int
    }
    try await withAggregateClient { db in
      try await seedPosts(db, author: "user-ada", name: "Ada", sortIndexes: [])
      let request = InstantFetchRequest(
        AggregateUser.query,
        counting: AggregateUser.posts.count(),
        AggregateUser.posts.count(where: AggregatePost.sortIndex >= 1)
      ) { _, posts, laterPosts in
        Counts(posts: posts, laterPosts: laterPosts)
      }
      let subscription = try await request.subscribe(using: db)
      defer { subscription.cancel() }
      var iterator = subscription.makeAsyncIterator()
      try await expectNext(&iterator, [Counts(posts: 0, laterPosts: 0)])

      let postID = InstantID<AggregatePost>(rawValue: "post-live")
      try await db.transact {
        AggregatePost.create(
          id: postID,
          AggregatePost.title.set("live"),
          AggregatePost.sortIndex.set(5),
          AggregatePost.author.set(InstantID(rawValue: "user-ada"))
        )
      }
      try await expectNext(&iterator, [Counts(posts: 1, laterPosts: 1)])

      try await db.transact { AggregatePost.update(id: postID, AggregatePost.sortIndex.set(0)) }
      try await expectNext(&iterator, [Counts(posts: 1, laterPosts: 0)])

      try await db.transact { AggregatePost.delete(id: postID) }
      try await expectNext(&iterator, [Counts(posts: 0, laterPosts: 0)])
    }
  }

  @Test
  func sectionsGroupRowsInTheOrderTheirFirstRowsAppear() async throws {
    try await withAggregateClient { db in
      try await seedPosts(
        db,
        author: "user-ada",
        name: "Ada",
        sortIndexes: [0, 1, 2, 3, 4],
        categories: ["news", "notes", "news", "drafts", "notes"]
      )

      let sections = try await InstantFetchRequest(AggregatePost.query.order(AggregatePost.sortIndex))
        .sectioned(by: \.category)
        .load(using: db)

      expectNoDifference(sections.sectionNames, ["news", "notes", "drafts"])
      expectNoDifference(sections.map { $0.map(\.title) }, [["post-0", "post-2"], ["post-1", "post-4"], ["post-3"]])
      expectNoDifference(sections.map(\.count), [2, 2, 1])
      expectNoDifference(sections[sectionName: "notes"]?.map(\.title), ["post-1", "post-4"])
      expectNoDifference(sections[sectionName: "missing"]?.count, nil)
      #expect(sections.contains(sectionName: "drafts"))
      expectNoDifference(sections.index(ofSectionNamed: "drafts"), 2)
      expectNoDifference(sections.first?.id, "news")
    }
  }

  @Test
  func sectionsOrderedByNameSortByTheirNames() async throws {
    try await withAggregateClient { db in
      try await seedPosts(
        db,
        author: "user-ada",
        name: "Ada",
        sortIndexes: [0, 1, 2, 3],
        categories: ["b", "c", "a", "b"]
      )
      let request = InstantFetchRequest(AggregatePost.query.order(AggregatePost.sortIndex))

      let ascending = try await request.sectioned(by: \.category, order: .ascending).load(using: db)
      let descending = try await request.sectioned(by: \.category, order: .descending).load(using: db)

      expectNoDifference(ascending.sectionNames, ["a", "b", "c"])
      expectNoDifference(ascending[sectionName: "b"]?.map(\.title), ["post-0", "post-3"])
      expectNoDifference(descending.sectionNames, ["c", "b", "a"])
      expectNoDifference(descending.index(ofSectionNamed: "a"), 2)
    }
  }

  @Test
  func anEmptyResultHasNoSections() async throws {
    try await withAggregateClient { db in
      let sections = try await InstantFetchRequest(AggregatePost.query)
        .sectioned(by: \.category)
        .load(using: db)

      expectNoDifference(sections, InstantResultsSectionCollection())
      #expect(sections.isEmpty)
    }
  }

  /// Rows grouped by a plain string field, each group counted, and each group's newest matching row: what a list row
  /// reads of the threads that name its recording, where no link joins them (#2005).
  @Test
  func groupedCountsOfAFlatQueryFollowItsRows() async throws {
    struct GroupCounts: Equatable, Sendable {
      var threads: Int
      var working: Int
      var newestWorkingID: String?
    }
    try await withAggregateClient { db in
      let threads: [(id: String, recordingID: String, authorKind: String?, status: String, updatedAtMs: Double)] = [
        ("thread-1", "recording-a", "agent", "done", 10),
        ("thread-2", "recording-a", nil, "working", 20),
        ("thread-3", "recording-a", "agent", "queued", 30),
        ("thread-4", "recording-a", "person", "working", 40),
        ("thread-5", "recording-b", "agent", "done", 50),
        ("thread-6", "recording-c", "agent", "working", 60),
      ]
      for thread in threads {
        try await db.transact {
          AggregateThread.create(
            id: InstantID(rawValue: thread.id),
            AggregateThread.recordingID.set(thread.recordingID),
            AggregateThread.authorKind.set(thread.authorKind),
            AggregateThread.status.set(thread.status),
            AggregateThread.updatedAtMs.set(thread.updatedAtMs)
          )
        }
      }

      let request = InstantFetchRequest(
        AggregateThread.query
          .where(AggregateThread.recordingID.isIn(["recording-a", "recording-b"]))
          .where(.any(AggregateThread.authorKind != "person", AggregateThread.authorKind.isNull))
          .order(AggregateThread.updatedAtMs, .descending)
      )
      .sectioned(by: \.recordingID)
      .map { sections in
        Dictionary(
          uniqueKeysWithValues: sections.map { section in
            let working = section.filter { ["working", "queued"].contains($0.status) }
            return (
              section.name,
              GroupCounts(threads: section.count, working: working.count, newestWorkingID: working.first?.id.rawValue)
            )
          }
        )
      }

      let loaded = try await request.load(using: db)
      expectNoDifference(
        loaded,
        [
          "recording-a": GroupCounts(threads: 3, working: 2, newestWorkingID: "thread-3"),
          "recording-b": GroupCounts(threads: 1, working: 0, newestWorkingID: nil),
        ]
      )

      let subscription = try await request.subscribe(using: db)
      defer { subscription.cancel() }
      var iterator = subscription.makeAsyncIterator()
      _ = try await iterator.next()
      try await db.transact {
        AggregateThread.create(
          id: InstantID(rawValue: "thread-7"),
          AggregateThread.recordingID.set("recording-b"),
          AggregateThread.authorKind.set("agent"),
          AggregateThread.status.set("working"),
          AggregateThread.updatedAtMs.set(70)
        )
      }
      try await expectNext(
        &iterator,
        [
          "recording-a": GroupCounts(threads: 3, working: 2, newestWorkingID: "thread-3"),
          "recording-b": GroupCounts(threads: 2, working: 1, newestWorkingID: "thread-7"),
        ]
      )
    }
  }
}

// MARK: - Helpers

private func withAggregateClient(
  _ body: (InstantSwiftDataClient) async throws -> Void
) async throws {
  let persistenceURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("instant-aggregate-\(UUID().uuidString).sqlite")
  defer { try? FileManager.default.removeItem(at: persistenceURL) }
  try await withDependencies {
    try await $0.bootstrapInstantSwiftData(
      appID: "aggregate-\(UUID().uuidString)",
      persistenceURL: persistenceURL,
      context: .test,
      initialAttributes:
        AggregateUser.instantAttributes
        + AggregatePost.instantAttributes
        + AggregateAttachment.instantAttributes
        + AggregateAlbum.instantAttributes
        + AggregatePhoto.instantAttributes
        + AggregateThread.instantAttributes
    )
  } operation: {
    @Dependency(\.defaultInstantSwiftData) var db
    try await body(db)
  }
}

private func seedPosts(
  _ db: InstantSwiftDataClient,
  author: String,
  name: String,
  sortIndexes: [Int],
  categories: [String]? = nil
) async throws {
  let authorID = InstantID<AggregateUser>(rawValue: author)
  try await db.transact {
    AggregateUser.create(id: authorID, AggregateUser.name.set(name))
  }
  for (offset, sortIndex) in sortIndexes.enumerated() {
    try await db.transact {
      AggregatePost.create(
        id: InstantID(rawValue: "\(author)-post-\(sortIndex)"),
        AggregatePost.title.set("post-\(sortIndex)"),
        AggregatePost.sortIndex.set(Double(sortIndex)),
        AggregatePost.category.set(categories?[offset] ?? "general"),
        AggregatePost.author.set(authorID)
      )
    }
  }
}

/// The next value the subscription emits that equals `expected`, waiting through the values in between (a write can
/// publish more than once as it lands), for at most five seconds.
private func expectNext<Value: Equatable & Sendable>(
  _ iterator: inout FetchSubscription<Value>.AsyncIterator,
  _ expected: Value,
  sourceLocation: SourceLocation = #_sourceLocation
) async throws {
  let deadline = ContinuousClock.now + .seconds(5)
  var last: Value?
  while ContinuousClock.now < deadline {
    guard let value = try await iterator.next() else { break }
    if value == expected { return }
    last = value
  }
  Issue.record(
    "Expected \(String(customDumping: expected)), last saw \(last.map { String(customDumping: $0) } ?? "nothing")",
    sourceLocation: sourceLocation
  )
}

// MARK: - Fixture schema

@InstantEntity("aggregate_users")
private struct AggregateUser: Hashable, Codable, InstantEntityModel {
  var id: InstantID<AggregateUser>
  var name: String

  static let name = InstantAttributePath<AggregateUser, String>("name")
  /// Reverse of `AggregatePost.author`.
  static let posts = InstantReverseRelation<AggregateUser, AggregatePost>("posts")
  /// Reverse of `AggregateAttachment.owner`.
  static let attachments = InstantReverseRelation<AggregateUser, AggregateAttachment>("attachments")

  init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    guard case let .string(name) = snapshot.values["name"]?.first else {
      throw InstantError(code: .decodeFailed, operation: "decode aggregate user", message: "Missing name.", recovery: "Write every field the fixture declares.")
    }
    self.name = name
  }
}

@InstantEntity("aggregate_posts")
private struct AggregatePost: Hashable, Codable, InstantEntityModel {
  var id: InstantID<AggregatePost>
  var title: String
  var sortIndex: Double
  var category: String

  @InstantRelation(reverse: "posts")
  var author: InstantID<AggregateUser>

  static let title = InstantAttributePath<AggregatePost, String>("title")
  static let sortIndex = InstantAttributePath<AggregatePost, Double>("sortIndex")
  static let category = InstantAttributePath<AggregatePost, String>("category")
  static let author = InstantAttributePath<AggregatePost, InstantID<AggregateUser>>("author")

  init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    guard
      case let .string(title) = snapshot.values["title"]?.first,
      case let .number(sortIndex) = snapshot.values["sortIndex"]?.first,
      case let .string(category) = snapshot.values["category"]?.first,
      case let .ref(authorID) = snapshot.values["author"]?.first
    else {
      throw InstantError(code: .decodeFailed, operation: "decode aggregate post", message: "Missing a field.", recovery: "Write every field the fixture declares.")
    }
    self.title = title
    self.sortIndex = sortIndex
    self.category = category
    self.author = InstantID(rawValue: authorID)
  }
}

@InstantEntity("aggregate_attachments")
private struct AggregateAttachment: Hashable, Codable, InstantEntityModel {
  var id: InstantID<AggregateAttachment>
  var kind: String

  @InstantRelation(reverse: "attachments")
  var owner: InstantID<AggregateUser>

  static let kind = InstantAttributePath<AggregateAttachment, String>("kind")
  static let owner = InstantAttributePath<AggregateAttachment, InstantID<AggregateUser>>("owner")

  init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    guard
      case let .string(kind) = snapshot.values["kind"]?.first,
      case let .ref(ownerID) = snapshot.values["owner"]?.first
    else {
      throw InstantError(code: .decodeFailed, operation: "decode aggregate attachment", message: "Missing a field.", recovery: "Write every field the fixture declares.")
    }
    self.kind = kind
    self.owner = InstantID(rawValue: ownerID)
  }
}

/// A parent that holds its children in a many-link of its own, as a recording holds its attachments.
private struct AggregateAlbum: Hashable, Sendable, InstantEntityModel {
  var id: InstantID<AggregateAlbum>
  var title: String

  static let instantNamespace = "aggregate_albums"
  static let title = InstantAttributePath<AggregateAlbum, String>("title")
  static let photos = InstantAttributePath<AggregateAlbum, InstantID<AggregatePhoto>>("photos")
  static let instantAttributes = [
    InstantAttribute.primaryKey(namespace: instantNamespace),
    InstantAttribute(
      id: "aggregate_albums/title",
      namespace: instantNamespace,
      name: "title",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "aggregate_albums/photos",
      namespace: instantNamespace,
      name: "photos",
      valueType: .ref,
      isRequired: false,
      cardinality: .many,
      isIndexed: true,
      forwardIdentity: "aggregate_albums/photos",
      reverseIdentity: "aggregate_photos/albums",
      linkNamespace: AggregatePhoto.instantNamespace
    ),
  ]

  init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    guard case let .string(title) = snapshot.values["title"]?.first else {
      throw InstantError(code: .decodeFailed, operation: "decode aggregate album", message: "Missing title.", recovery: "Write every field the fixture declares.")
    }
    self.title = title
  }
}

@InstantEntity("aggregate_photos")
private struct AggregatePhoto: Hashable, Codable, InstantEntityModel {
  var id: InstantID<AggregatePhoto>
  var kind: String

  static let kind = InstantAttributePath<AggregatePhoto, String>("kind")

  init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    guard case let .string(kind) = snapshot.values["kind"]?.first else {
      throw InstantError(code: .decodeFailed, operation: "decode aggregate photo", message: "Missing kind.", recovery: "Write every field the fixture declares.")
    }
    self.kind = kind
  }
}

/// A row that names its parent in a plain string field, with no link: an agent thread naming its recording.
@InstantEntity("aggregate_threads")
private struct AggregateThread: Hashable, Codable, InstantEntityModel {
  var id: InstantID<AggregateThread>
  var recordingID: String
  var authorKind: String?
  var status: String
  var updatedAtMs: Double

  static let recordingID = InstantAttributePath<AggregateThread, String>("recordingID")
  static let authorKind = InstantAttributePath<AggregateThread, String?>("authorKind")
  static let status = InstantAttributePath<AggregateThread, String>("status")
  static let updatedAtMs = InstantAttributePath<AggregateThread, Double>("updatedAtMs")

  init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    guard
      case let .string(recordingID) = snapshot.values["recordingID"]?.first,
      case let .string(status) = snapshot.values["status"]?.first,
      case let .number(updatedAtMs) = snapshot.values["updatedAtMs"]?.first
    else {
      throw InstantError(code: .decodeFailed, operation: "decode aggregate thread", message: "Missing a field.", recovery: "Write every field the fixture declares.")
    }
    self.recordingID = recordingID
    if case let .string(authorKind) = snapshot.values["authorKind"]?.first {
      self.authorKind = authorKind
    } else {
      self.authorKind = nil
    }
    self.status = status
    self.updatedAtMs = updatedAtMs
  }
}
