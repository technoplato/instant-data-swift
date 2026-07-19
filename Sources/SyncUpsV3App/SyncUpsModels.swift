import Foundation
import InstantSwiftData
import InstantSwiftDataSchema

public enum SyncUpsV3Theme: String, CaseIterable, Codable, Hashable, InstantStringEnum,
  Sendable
{
  case appIndigo
  case appMagenta
  case appOrange
  case appPurple
  case appTeal
  case appYellow
  case bubblegum
  case buttercup
  case lavender
  case navy
  case oxblood
  case periwinkle
  case poppy
  case seafoam
  case sky
  case tan
}

public enum SyncUpsV3Schema {
  public static let document = InstantSchemaExamples.syncUpsV3Document
  public static let attributes = document.attributes
}

@InstantEntity("syncUps")
public struct SyncUpsV3SyncUp: Codable, Hashable, InstantEntityModel {
  public static let identifier = InstantAttributePath<Self, String>("id")
  public static let seconds = InstantAttributePath<Self, Int>("seconds")
  public static let theme = InstantAttributePath<Self, SyncUpsV3Theme>("theme")
  public static let title = InstantAttributePath<Self, String>("title")
  public static let attendees = InstantReverseRelation<Self, SyncUpsV3Attendee>(
    attribute: SyncUpsV3Attendee.syncUp
  )
  public static let meetings = InstantReverseRelation<Self, SyncUpsV3Meeting>(
    attribute: SyncUpsV3Meeting.syncUp
  )
  public static let instantAttributes = SyncUpsV3Schema.attributes.filter {
    $0.namespace == instantNamespace
  }

  public var id: InstantID<Self>
  public var seconds: Int
  @InstantWire(.string)
  public var theme: SyncUpsV3Theme
  public var title: String
  public var attendees: [SyncUpsV3Attendee]
  public var meetings: [SyncUpsV3Meeting]

  public init(
    id: InstantID<Self>,
    seconds: Int = 60 * 5,
    theme: SyncUpsV3Theme = .bubblegum,
    title: String = "",
    attendees: [SyncUpsV3Attendee] = [],
    meetings: [SyncUpsV3Meeting] = []
  ) {
    self.id = id
    self.seconds = seconds
    self.theme = theme
    self.title = title
    self.attendees = attendees
    self.meetings = meetings
  }

  public init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    seconds = try snapshot.syncUpsV3Integer("seconds", operation: "decode SyncUps sync-up")
    let rawTheme = try snapshot.syncUpsV3String("theme", operation: "decode SyncUps sync-up")
    guard let theme = SyncUpsV3Theme(rawValue: rawTheme) else {
      throw snapshot.syncUpsV3DecodeError(
        path: "theme",
        operation: "decode SyncUps sync-up",
        expected: "a known SyncUps theme"
      )
    }
    self.theme = theme
    title = try snapshot.syncUpsV3String("title", operation: "decode SyncUps sync-up")
    attendees = try snapshot.syncUpsV3Linked("attendees").map {
      try SyncUpsV3Attendee(snapshot: InstantEntitySnapshot($0))
    }
    meetings = try snapshot.syncUpsV3Linked("meetings").map {
      try SyncUpsV3Meeting(snapshot: InstantEntitySnapshot($0))
    }
  }

  public static var list: InstantQuery<Self> {
    query
      .include(attendees, SyncUpsV3Attendee.query.order(SyncUpsV3Attendee.name))
      .order(title)
  }

  public static func detail(_ id: InstantID<Self>) -> InstantQuery<Self> {
    query
      .where(identifier == id.rawValue)
      .include(attendees, SyncUpsV3Attendee.query.order(SyncUpsV3Attendee.name))
      .include(meetings, SyncUpsV3Meeting.query.order(SyncUpsV3Meeting.date, .descending))
  }
}

@InstantEntity("attendees")
public struct SyncUpsV3Attendee: Codable, Hashable, InstantEntityModel {
  public static let name = InstantAttributePath<Self, String>("name")
  public static let syncUp = InstantAttributePath<Self, InstantID<SyncUpsV3SyncUp>>("syncUp")
  public static let instantAttributes = SyncUpsV3Schema.attributes.filter {
    $0.namespace == instantNamespace
  }

  public var id: InstantID<Self>
  public var name: String
  public var syncUp: InstantID<SyncUpsV3SyncUp>

  public init(id: InstantID<Self>, name: String = "", syncUp: InstantID<SyncUpsV3SyncUp>) {
    self.id = id
    self.name = name
    self.syncUp = syncUp
  }

  public init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    name = try snapshot.syncUpsV3String("name", operation: "decode SyncUps attendee")
    syncUp = try snapshot.syncUpsV3Ref("syncUp", operation: "decode SyncUps attendee")
  }

  public static func forSyncUp(_ id: InstantID<SyncUpsV3SyncUp>) -> InstantQuery<Self> {
    query.where(syncUp == id).order(name)
  }
}

@InstantEntity("meetings")
public struct SyncUpsV3Meeting: Codable, Hashable, InstantEntityModel {
  public static let date = InstantAttributePath<Self, Date>("date")
  public static let syncUp = InstantAttributePath<Self, InstantID<SyncUpsV3SyncUp>>("syncUp")
  public static let transcript = InstantAttributePath<Self, String>("transcript")
  public static let instantAttributes = SyncUpsV3Schema.attributes.filter {
    $0.namespace == instantNamespace
  }

  public var id: InstantID<Self>
  public var date: Date
  public var syncUp: InstantID<SyncUpsV3SyncUp>
  public var transcript: String

  public init(
    id: InstantID<Self>,
    date: Date,
    syncUp: InstantID<SyncUpsV3SyncUp>,
    transcript: String
  ) {
    self.id = id
    self.date = date
    self.syncUp = syncUp
    self.transcript = transcript
  }

  public init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    date = try snapshot.syncUpsV3Date("date", operation: "decode SyncUps meeting")
    syncUp = try snapshot.syncUpsV3Ref("syncUp", operation: "decode SyncUps meeting")
    transcript = try snapshot.syncUpsV3String(
      "transcript",
      operation: "decode SyncUps meeting"
    )
  }

  public static func forSyncUp(_ id: InstantID<SyncUpsV3SyncUp>) -> InstantQuery<Self> {
    query.where(syncUp == id).order(date, .descending)
  }
}

extension InstantEntitySnapshot {
  fileprivate init(_ linked: InstantLinkedEntitySnapshot) {
    self.init(
      id: linked.id,
      namespace: linked.namespace,
      values: linked.values,
      links: linked.links
    )
  }

  fileprivate func syncUpsV3Linked(_ path: String) -> [InstantLinkedEntitySnapshot] {
    links?[path] ?? []
  }

  fileprivate func syncUpsV3String(_ path: String, operation: String) throws -> String {
    guard case let .string(value) = values[path]?.first else {
      throw syncUpsV3DecodeError(path: path, operation: operation, expected: "a string")
    }
    return value
  }

  fileprivate func syncUpsV3Integer(_ path: String, operation: String) throws -> Int {
    guard case let .number(value) = values[path]?.first, value.rounded() == value else {
      throw syncUpsV3DecodeError(path: path, operation: operation, expected: "an integer")
    }
    return Int(value)
  }

  fileprivate func syncUpsV3Date(_ path: String, operation: String) throws -> Date {
    guard case let .date(value) = values[path]?.first else {
      throw syncUpsV3DecodeError(path: path, operation: operation, expected: "a date")
    }
    return value
  }

  fileprivate func syncUpsV3Ref<Entity>(
    _ path: String,
    operation: String
  ) throws -> InstantID<Entity> {
    guard case let .ref(value) = values[path]?.first else {
      throw syncUpsV3DecodeError(
        path: path,
        operation: operation,
        expected: "an entity reference"
      )
    }
    return InstantID(rawValue: value)
  }

  fileprivate func syncUpsV3DecodeError(
    path: String,
    operation: String,
    expected: String
  ) -> InstantError {
    InstantError(
      code: .decodeFailed,
      operation: operation,
      namespace: namespace,
      path: path,
      localID: id,
      message: "Expected \(expected), received \(String(describing: values[path]?.first)).",
      recovery: "Keep the SyncUps V3 app model aligned with its generated schema."
    )
  }
}
