import Foundation

public struct CursorsRecipeCursor: Hashable, Codable, Sendable, Identifiable {
  public var id: String { userID }
  public var userID: String
  public var x: Double
  public var y: Double
  public var xPercent: Double
  public var yPercent: Double
  public var color: String?
  public var name: String?
  public var isViewer: Bool
  public var updatedAt: InstantTimestamp

  public init(
    userID: String,
    x: Double,
    y: Double,
    xPercent: Double,
    yPercent: Double,
    color: String?,
    name: String?,
    isViewer: Bool,
    updatedAt: InstantTimestamp
  ) {
    self.userID = userID
    self.x = x
    self.y = y
    self.xPercent = xPercent
    self.yPercent = yPercent
    self.color = color
    self.name = name
    self.isViewer = isViewer
    self.updatedAt = updatedAt
  }
}

public struct CursorsRecipeSnapshot: Hashable, Codable, Sendable {
  public var viewerUserID: String?
  public var cursorCount: Int
  public var visibleCursors: [CursorsRecipeCursor]
  public var members: [CursorsRecipeCursor]

  public init(
    viewerUserID: String?,
    cursorCount: Int,
    visibleCursors: [CursorsRecipeCursor],
    members: [CursorsRecipeCursor]
  ) {
    self.viewerUserID = viewerUserID
    self.cursorCount = cursorCount
    self.visibleCursors = visibleCursors
    self.members = members
  }
}

public enum CursorsRecipeExample {
  public static let room = InstantRoomHandle(type: "cursors-example", id: "123")
  public static let customRoom = InstantRoomHandle(type: "cursors-example", id: "124")
  public static let defaultColor = "#000000"
  public static let nameKey = "name"

  public static var spaceID: String {
    spaceID(for: room)
  }

  public static func spaceID(for room: InstantRoomHandle) -> String {
    "cursors-space-default--\(room.type)-\(room.id)"
  }

  public static func cursorValues(
    room handle: InstantRoomHandle = room,
    x: Double,
    y: Double,
    width: Double,
    height: Double,
    color: String? = nil
  ) -> [String: JSONValue] {
    cursorValues(
      room: handle,
      x: x,
      y: y,
      xPercent: (x / width) * 100,
      yPercent: (y / height) * 100,
      color: color
    )
  }

  public static func cursorValues(
    room handle: InstantRoomHandle = room,
    x: Double,
    y: Double,
    xPercent: Double,
    yPercent: Double,
    color: String? = nil
  ) -> [String: JSONValue] {
    var cursor: [String: JSONValue] = [
      "x": .number(x),
      "xPercent": .number(xPercent),
      "y": .number(y),
      "yPercent": .number(yPercent),
    ]
    if let color {
      cursor["color"] = .string(color)
    }
    return [spaceID(for: handle): .object(cursor)]
  }

  public static func customCursorValues(
    x: Double,
    y: Double,
    xPercent: Double,
    yPercent: Double,
    color: String? = nil,
    name: String
  ) -> [String: JSONValue] {
    var values = cursorValues(
      room: customRoom,
      x: x,
      y: y,
      xPercent: xPercent,
      yPercent: yPercent,
      color: color
    )
    values[nameKey] = .string(name)
    return values
  }

  public static func cursor(
    from presence: InstantRoomPresenceMember,
    room handle: InstantRoomHandle = room,
    viewerUserID: String? = nil
  ) -> CursorsRecipeCursor? {
    guard presence.room == handle,
      case let .object(cursor)? = presence.values[spaceID(for: handle)],
      case let .number(x)? = cursor["x"],
      case let .number(y)? = cursor["y"],
      case let .number(xPercent)? = cursor["xPercent"],
      case let .number(yPercent)? = cursor["yPercent"]
    else {
      return nil
    }

    let color: String?
    if case let .string(value)? = cursor["color"] {
      color = value
    } else {
      color = nil
    }

    let name: String?
    if case let .string(value)? = presence.values[nameKey] {
      name = value
    } else {
      name = nil
    }

    return CursorsRecipeCursor(
      userID: presence.userID,
      x: x,
      y: y,
      xPercent: xPercent,
      yPercent: yPercent,
      color: color,
      name: name,
      isViewer: presence.userID == viewerUserID,
      updatedAt: presence.updatedAt
    )
  }

  public static func cursors(
    from presence: [InstantRoomPresenceMember],
    room handle: InstantRoomHandle = room,
    viewerUserID: String? = nil
  ) -> [CursorsRecipeCursor] {
    presence.compactMap { cursor(from: $0, room: handle, viewerUserID: viewerUserID) }
  }

  public static func snapshot(
    from presence: [InstantRoomPresenceMember],
    room handle: InstantRoomHandle = room,
    viewerUserID: String? = nil
  ) -> CursorsRecipeSnapshot {
    let members = cursors(from: presence, room: handle, viewerUserID: viewerUserID)
    let visibleCursors = members.filter { cursor in
      guard let viewerUserID else {
        return true
      }
      return cursor.userID != viewerUserID
    }
    return CursorsRecipeSnapshot(
      viewerUserID: viewerUserID,
      cursorCount: visibleCursors.count,
      visibleCursors: visibleCursors,
      members: members
    )
  }
}
