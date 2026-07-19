import Foundation
import InstantSwiftData

public struct SyncUpsV3AttendeeDraft: Equatable, Hashable, Identifiable, Sendable {
  public var id: InstantID<SyncUpsV3Attendee>
  public var name: String

  public init(id: InstantID<SyncUpsV3Attendee>, name: String = "") {
    self.id = id
    self.name = name
  }
}

public struct SyncUpsV3FormState: Equatable, Identifiable, Sendable {
  public enum Field: Equatable, Hashable, Sendable {
    case attendee(InstantID<SyncUpsV3Attendee>)
    case title
  }

  public var syncUpID: InstantID<SyncUpsV3SyncUp>?
  public var title: String
  public var seconds: Int
  public var theme: SyncUpsV3Theme
  public var attendees: [SyncUpsV3AttendeeDraft]
  public internal(set) var existingAttendeeIDs: [InstantID<SyncUpsV3Attendee>]
  public var focus: Field?
  public var isDismissed: Bool

  public var id: String { syncUpID?.rawValue ?? "new-sync-up" }

  public var durationMinutes: Double {
    get { Double(seconds) / 60 }
    set { seconds = Int(newValue * 60) }
  }

  public init(
    syncUp: SyncUpsV3SyncUp? = nil,
    attendeeDraftIDs: [InstantID<SyncUpsV3Attendee>] = [],
    blankAttendeeID: InstantID<SyncUpsV3Attendee>,
    focus: Field? = .title
  ) {
    syncUpID = syncUp?.id
    title = syncUp?.title ?? ""
    seconds = syncUp?.seconds ?? 60 * 5
    theme = syncUp?.theme ?? .bubblegum
    existingAttendeeIDs = syncUp?.attendees.map(\.id) ?? []
    attendees = syncUp?.attendees.enumerated().map { offset, attendee in
      SyncUpsV3AttendeeDraft(
        id: attendeeDraftIDs.indices.contains(offset)
          ? attendeeDraftIDs[offset]
          : InstantID(rawValue: "draft-\(attendee.id.rawValue)"),
        name: attendee.name
      )
    } ?? []
    if attendees.isEmpty {
      attendees = [SyncUpsV3AttendeeDraft(id: blankAttendeeID)]
    }
    self.focus = focus
    isDismissed = false
  }

  public mutating func addAttendeeButtonTapped(id: InstantID<SyncUpsV3Attendee>) {
    let id = distinctAttendeeID(id)
    attendees.append(SyncUpsV3AttendeeDraft(id: id))
    focus = .attendee(id)
  }

  public mutating func deleteAttendees(
    atOffsets indices: IndexSet,
    blankAttendeeID: InstantID<SyncUpsV3Attendee>
  ) {
    for index in indices.sorted(by: >) where attendees.indices.contains(index) {
      attendees.remove(at: index)
    }
    if attendees.isEmpty {
      attendees.append(SyncUpsV3AttendeeDraft(id: distinctAttendeeID(blankAttendeeID)))
    }
    guard let firstIndex = indices.first else { return }
    focus = .attendee(attendees[min(firstIndex, attendees.count - 1)].id)
  }

  public mutating func cancelButtonTapped() {
    isDismissed = true
  }

  public mutating func saveButtonTapped(
    newSyncUpID: InstantID<SyncUpsV3SyncUp>,
    blankAttendeeID: InstantID<SyncUpsV3Attendee>
  ) -> SaveSyncUpsV3Form {
    normalizeAttendees(blankAttendeeID: blankAttendeeID)
    return SaveSyncUpsV3Form(
      syncUpID: syncUpID ?? newSyncUpID,
      isNew: syncUpID == nil,
      title: title,
      seconds: seconds,
      theme: theme,
      existingAttendeeIDs: existingAttendeeIDs,
      attendees: attendees.map { SyncUpsV3AttendeeInput(id: $0.id, name: $0.name) }
    )
  }

  public mutating func commit(_ saved: SyncUpsV3FormSaved) {
    syncUpID = saved.syncUpID
    existingAttendeeIDs = saved.attendeeIDs
    isDismissed = true
  }

  private mutating func normalizeAttendees(
    blankAttendeeID: InstantID<SyncUpsV3Attendee>
  ) {
    attendees.removeAll { attendee in
      attendee.name.allSatisfy(\.isWhitespace)
    }
    if attendees.isEmpty {
      attendees = [SyncUpsV3AttendeeDraft(id: distinctAttendeeID(blankAttendeeID))]
    }
    var seen: Set<String> = []
    attendees = attendees.map { attendee in
      var attendee = attendee
      while !seen.insert(attendee.id.rawValue).inserted
        || existingAttendeeIDs.contains(attendee.id)
      {
        attendee.id = InstantID(rawValue: "draft-\(attendee.id.rawValue)")
      }
      return attendee
    }
    if case let .attendee(id) = focus,
      !attendees.contains(where: { $0.id == id })
    {
      focus = attendees.first.map { .attendee($0.id) }
    }
  }

  private func distinctAttendeeID(
    _ proposed: InstantID<SyncUpsV3Attendee>
  ) -> InstantID<SyncUpsV3Attendee> {
    var id = proposed
    let used = Set(attendees.map(\.id) + existingAttendeeIDs)
    while used.contains(id) {
      id = InstantID(rawValue: "draft-\(id.rawValue)")
    }
    return id
  }
}
