import CustomDump
import Dependencies
import Foundation
import InstantSwiftData
import Testing

/// ADR 0015 L2 — InstantFetchRequest map root + included children into flat rows.
@Suite
struct InstantIncludedMapFetchTests {
  @Test
  func fetchRequestMapsRootWithTwoIncludedBags() async throws {
    let persistenceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-multi-bag-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: persistenceURL) }

    struct ListRow: Equatable, Sendable {
      var userName: String
      var postTitles: [String]
      var attachmentKinds: [InstantMediaKind]
    }

    try await withDependencies {
      try await $0.bootstrapInstantSwiftData(
        appID: "multi-bag-\(UUID().uuidString)",
        persistenceURL: persistenceURL,
        context: .test,
        initialAttributes:
          MapFetchUser.instantAttributes
          + MapFetchPost.instantAttributes
          + MapFetchAttachment.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db
      let userID = InstantID<MapFetchUser>(rawValue: "user-1")
      try await db.transact {
        MapFetchUser.create(id: userID, MapFetchUser.name.set("Ada"))
      }
      for (index, title) in ["alpha", "bravo", "charlie"].enumerated() {
        try await db.transact {
          MapFetchPost.create(
            id: InstantID(rawValue: "post-\(index)"),
            MapFetchPost.title.set(title),
            MapFetchPost.sortIndex.set(Double(index)),
            MapFetchPost.author.set(userID)
          )
        }
      }
      try await db.transact {
        MapFetchAttachment.create(
          id: InstantID(rawValue: "att-1"),
          MapFetchAttachment.kind.set(InstantMediaKind.image.rawValue),
          MapFetchAttachment.owner.set(userID)
        )
        MapFetchAttachment.create(
          id: InstantID(rawValue: "att-2"),
          MapFetchAttachment.kind.set(InstantMediaKind.audio.rawValue),
          MapFetchAttachment.owner.set(userID)
        )
      }

      let request = InstantFetchRequest(
        MapFetchUser.query
          .include(
            MapFetchUser.posts,
            MapFetchPost.query.order(MapFetchPost.sortIndex, .descending).limit(2)
          )
          .include(MapFetchUser.attachments, MapFetchAttachment.query.limit(24)),
        children: MapFetchUser.posts, MapFetchUser.attachments,
        map: { user, posts, attachments in
          ListRow(
            userName: user.name,
            postTitles: posts.map(\.title),
            attachmentKinds: attachments.compactMap { InstantMediaKind(rawValue: $0.kind) }
          )
        }
      )

      let rows = try await request.load(using: db)
      expectNoDifference(rows.count, 1)
      expectNoDifference(rows.first?.userName, "Ada")
      expectNoDifference(rows.first?.postTitles, ["charlie", "bravo"])
      expectNoDifference(
        Set(rows.first?.attachmentKinds ?? []),
        Set([InstantMediaKind.image, InstantMediaKind.audio])
      )
    }
  }

  @Test
  func fetchRequestMapsRootAndLimitedIncludedChildren() async throws {
    let persistenceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-included-map-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: persistenceURL) }

    struct ListRow: Equatable, Sendable {
      var userName: String
      var postTitles: [String]
    }

    try await withDependencies {
      try await $0.bootstrapInstantSwiftData(
        appID: "included-map-\(UUID().uuidString)",
        persistenceURL: persistenceURL,
        context: .test,
        initialAttributes:
          MapFetchUser.instantAttributes + MapFetchPost.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db
      let userID = InstantID<MapFetchUser>(rawValue: "user-1")
      try await db.transact {
        MapFetchUser.create(
          id: userID,
          MapFetchUser.name.set("Ada")
        )
      }
      for (index, title) in ["alpha", "bravo", "charlie"].enumerated() {
        try await db.transact {
          MapFetchPost.create(
            id: InstantID(rawValue: "post-\(index)"),
            MapFetchPost.title.set(title),
            MapFetchPost.sortIndex.set(Double(index)),
            MapFetchPost.author.set(userID)
          )
        }
      }

      let request = InstantFetchRequest(
        MapFetchUser.query.include(
          MapFetchUser.posts,
          MapFetchPost.query
            .order(MapFetchPost.sortIndex, .descending)
            .limit(2)
        ),
        children: MapFetchUser.posts,
        map: { user, posts in
          ListRow(
            userName: user.name,
            postTitles: posts.map(\.title)
          )
        }
      )

      let rows = try await request.load(using: db)
      expectNoDifference(rows.count, 1)
      expectNoDifference(rows.first?.userName, "Ada")
      // limit 2 after descending sortIndex → charlie, bravo
      expectNoDifference(rows.first?.postTitles, ["charlie", "bravo"])
    }
  }
}

@InstantEntity("map_fetch_users")
private struct MapFetchUser: Hashable, Codable, InstantEntityModel {
  var id: InstantID<MapFetchUser>
  var name: String

  static let name = InstantAttributePath<MapFetchUser, String>("name")
  /// Reverse of `MapFetchPost.author` (`@InstantRelation(reverse: "posts")`).
  static let posts = InstantReverseRelation<MapFetchUser, MapFetchPost>("posts")
  /// Reverse of `MapFetchAttachment.owner`.
  static let attachments = InstantReverseRelation<MapFetchUser, MapFetchAttachment>("attachments")

  init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    if case let .string(name) = snapshot.values["name"]?.first {
      self.name = name
    } else {
      name = ""
    }
  }
}

@InstantEntity("map_fetch_posts")
private struct MapFetchPost: Hashable, Codable, InstantEntityModel {
  var id: InstantID<MapFetchPost>
  var title: String
  var sortIndex: Double

  @InstantRelation(reverse: "posts")
  var author: InstantID<MapFetchUser>

  static let title = InstantAttributePath<MapFetchPost, String>("title")
  static let sortIndex = InstantAttributePath<MapFetchPost, Double>("sortIndex")
  static let author = InstantAttributePath<MapFetchPost, InstantID<MapFetchUser>>("author")

  init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    if case let .string(title) = snapshot.values["title"]?.first {
      self.title = title
    } else {
      title = ""
    }
    if case let .number(sortIndex) = snapshot.values["sortIndex"]?.first {
      self.sortIndex = sortIndex
    } else {
      sortIndex = 0
    }
    if case let .ref(authorID) = snapshot.values["author"]?.first {
      author = InstantID(rawValue: authorID)
    } else {
      author = InstantID(rawValue: "")
    }
  }
}

@InstantEntity("map_fetch_attachments")
private struct MapFetchAttachment: Hashable, Codable, InstantEntityModel {
  var id: InstantID<MapFetchAttachment>
  var kind: String

  @InstantRelation(reverse: "attachments")
  var owner: InstantID<MapFetchUser>

  static let kind = InstantAttributePath<MapFetchAttachment, String>("kind")
  static let owner = InstantAttributePath<MapFetchAttachment, InstantID<MapFetchUser>>("owner")

  init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    if case let .string(kind) = snapshot.values["kind"]?.first {
      self.kind = kind
    } else {
      kind = InstantMediaKind.file.rawValue
    }
    if case let .ref(ownerID) = snapshot.values["owner"]?.first {
      owner = InstantID(rawValue: ownerID)
    } else {
      owner = InstantID(rawValue: "")
    }
  }
}
