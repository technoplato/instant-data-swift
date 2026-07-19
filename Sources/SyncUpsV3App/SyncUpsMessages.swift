import Foundation
import InstantSwiftData

public struct SyncUpsV3AttendeeInput: Equatable, Hashable, Sendable {
  public var id: InstantID<SyncUpsV3Attendee>
  public var name: String

  public init(id: InstantID<SyncUpsV3Attendee>, name: String) {
    self.id = id
    self.name = name
  }
}

public struct SyncUpsV3FormSaved: Equatable, Hashable, Sendable {
  public var syncUpID: InstantID<SyncUpsV3SyncUp>
  public var attendeeIDs: [InstantID<SyncUpsV3Attendee>]

  public init(
    syncUpID: InstantID<SyncUpsV3SyncUp>,
    attendeeIDs: [InstantID<SyncUpsV3Attendee>]
  ) {
    self.syncUpID = syncUpID
    self.attendeeIDs = attendeeIDs
  }
}

public struct SaveSyncUpsV3Form: InstantMessage {
  public var syncUpID: InstantID<SyncUpsV3SyncUp>
  public var isNew: Bool
  public var title: String
  public var seconds: Int
  public var theme: SyncUpsV3Theme
  public var existingAttendeeIDs: [InstantID<SyncUpsV3Attendee>]
  public var attendees: [SyncUpsV3AttendeeInput]

  public init(
    syncUpID: InstantID<SyncUpsV3SyncUp>,
    isNew: Bool,
    title: String,
    seconds: Int,
    theme: SyncUpsV3Theme,
    existingAttendeeIDs: [InstantID<SyncUpsV3Attendee>] = [],
    attendees: [SyncUpsV3AttendeeInput]
  ) {
    self.syncUpID = syncUpID
    self.isNew = isNew
    self.title = title
    self.seconds = seconds
    self.theme = theme
    self.existingAttendeeIDs = Self.unique(existingAttendeeIDs)
    self.attendees = Self.unique(attendees)
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<SyncUpsV3FormSaved>
  {
    _ = client
    guard !attendees.isEmpty else { throw SyncUpsV3MessageError.attendeeRequired }
    guard seconds > 0 else { throw SyncUpsV3MessageError.invalidDuration(seconds) }

    return InstantPreparedMessage(
      change: SyncUpsV3FormSaved(
        syncUpID: syncUpID,
        attendeeIDs: attendees.map(\.id)
      )
    ) {
      if isNew {
        SyncUpsV3SyncUp.create(
          id: syncUpID,
          SyncUpsV3SyncUp.seconds.set(seconds),
          SyncUpsV3SyncUp.theme.set(theme),
          SyncUpsV3SyncUp.title.set(title)
        )
      } else {
        SyncUpsV3SyncUp.updateExisting(
          id: syncUpID,
          SyncUpsV3SyncUp.seconds.set(seconds),
          SyncUpsV3SyncUp.theme.set(theme),
          SyncUpsV3SyncUp.title.set(title)
        )
      }
      for attendeeID in existingAttendeeIDs {
        SyncUpsV3Attendee.delete(id: attendeeID)
      }
      for attendee in attendees {
        SyncUpsV3Attendee.create(
          id: attendee.id,
          SyncUpsV3Attendee.name.set(attendee.name),
          SyncUpsV3Attendee.syncUp.set(syncUpID)
        )
      }
    }
  }

  private static func unique(
    _ ids: [InstantID<SyncUpsV3Attendee>]
  ) -> [InstantID<SyncUpsV3Attendee>] {
    var seen: Set<String> = []
    return ids.filter { seen.insert($0.rawValue).inserted }
  }

  private static func unique(
    _ attendees: [SyncUpsV3AttendeeInput]
  ) -> [SyncUpsV3AttendeeInput] {
    var seen: Set<String> = []
    return attendees.filter { seen.insert($0.id.rawValue).inserted }
  }
}

public enum SyncUpsV3MessageError: Error, Equatable, Sendable {
  case attendeeRequired
  case invalidDuration(Int)
}
