import Foundation

public enum SyncUpTheme: String, CaseIterable, Codable, Sendable {
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

public struct SyncUpRecord: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var title: String
  public var seconds: Int
  public var theme: SyncUpTheme

  public init(id: String, title: String, seconds: Int, theme: SyncUpTheme) {
    self.id = id
    self.title = title
    self.seconds = seconds
    self.theme = theme
  }
}

public struct SyncUpAttendeeRecord: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var name: String
  public var syncUpID: String

  public init(id: String, name: String, syncUpID: String) {
    self.id = id
    self.name = name
    self.syncUpID = syncUpID
  }
}

public struct SyncUpMeetingRecord: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var date: InstantTimestamp
  public var syncUpID: String
  public var transcript: String

  public init(id: String, date: InstantTimestamp, syncUpID: String, transcript: String) {
    self.id = id
    self.date = date
    self.syncUpID = syncUpID
    self.transcript = transcript
  }
}

public struct SyncUpSummary: Hashable, Codable, Sendable, Identifiable {
  public var id: String { syncUp.id }
  public var syncUp: SyncUpRecord
  public var attendeeCount: Int
  public var meetingCount: Int

  public init(syncUp: SyncUpRecord, attendeeCount: Int, meetingCount: Int) {
    self.syncUp = syncUp
    self.attendeeCount = attendeeCount
    self.meetingCount = meetingCount
  }
}

public struct SyncUpSeedRecord: Hashable, Codable, Sendable {
  public var localIDName: String
  public var title: String
  public var seconds: Int
  public var theme: SyncUpTheme

  public init(localIDName: String, title: String, seconds: Int, theme: SyncUpTheme) {
    self.localIDName = localIDName
    self.title = title
    self.seconds = seconds
    self.theme = theme
  }
}

public struct SyncUpDraft: Hashable, Codable, Sendable {
  public var id: String?
  public var title: String
  public var seconds: Int
  public var theme: SyncUpTheme

  public init(
    id: String? = nil,
    title: String = "",
    seconds: Int = 60 * 5,
    theme: SyncUpTheme = .bubblegum
  ) {
    self.id = id
    self.title = title
    self.seconds = seconds
    self.theme = theme
  }

  public init(_ syncUp: SyncUpRecord) {
    self.init(
      id: syncUp.id,
      title: syncUp.title,
      seconds: syncUp.seconds,
      theme: syncUp.theme
    )
  }
}

public struct SyncUpAttendeeSeedRecord: Hashable, Codable, Sendable {
  public var localIDName: String
  public var syncUpLocalIDName: String
  public var name: String

  public init(localIDName: String, syncUpLocalIDName: String, name: String) {
    self.localIDName = localIDName
    self.syncUpLocalIDName = syncUpLocalIDName
    self.name = name
  }
}

public struct SyncUpAttendeeDraft: Hashable, Codable, Sendable {
  public var id: String
  public var name: String

  public init(id: String, name: String) {
    self.id = id
    self.name = name
  }
}

public struct SyncUpFormSave: Hashable, Sendable {
  public var syncUpID: String
  public var operations: [InstantTripleOperation]
  public var attendees: [SyncUpAttendeeDraft]

  public init(
    syncUpID: String,
    operations: [InstantTripleOperation],
    attendees: [SyncUpAttendeeDraft]
  ) {
    self.syncUpID = syncUpID
    self.operations = operations
    self.attendees = attendees
  }
}

public struct SyncUpFormModel: Hashable, Sendable {
  public enum Field: Hashable, Sendable {
    case attendee(String)
    case title
  }

  public var attendees: [SyncUpAttendeeDraft]
  public private(set) var existingAttendeeIDs: [String]
  public var focus: Field?
  public var isDismissed: Bool
  public var syncUp: SyncUpDraft

  public init(
    syncUp: SyncUpDraft,
    attendees: [SyncUpAttendeeDraft] = [],
    existingAttendeeIDs: [String] = [],
    blankAttendeeID: String,
    focus: Field? = .title
  ) {
    let existingAttendeeIDs = Self.unique(existingAttendeeIDs)
    let attendees = attendees.isEmpty
      ? [SyncUpAttendeeDraft(id: blankAttendeeID, name: "")]
      : attendees
    self.syncUp = syncUp
    self.attendees = Self.sanitizedAttendees(
      attendees,
      existingAttendeeIDs: existingAttendeeIDs
    )
    self.existingAttendeeIDs = existingAttendeeIDs
    self.focus = Self.sanitizedFocus(focus, attendees: self.attendees)
    self.isDismissed = false
  }

  public init(
    syncUp: SyncUpRecord,
    existingAttendees: [SyncUpAttendeeRecord],
    draftAttendeeIDs: [String],
    blankAttendeeID: String,
    focus: Field? = .title
  ) {
    let existingAttendeeIDs = existingAttendees.map(\.id)
    var usedDraftAttendeeIDs: [String] = []
    let draftAttendees = existingAttendees.enumerated().map { offset, attendee in
      let proposedID = draftAttendeeIDs.indices.contains(offset)
        ? draftAttendeeIDs[offset]
        : "draft-\(attendee.id)"
      let id = Self.distinctDraftAttendeeID(
        proposedID,
        existingAttendeeIDs: existingAttendeeIDs,
        usedDraftAttendeeIDs: usedDraftAttendeeIDs
      )
      usedDraftAttendeeIDs.append(id)
      return SyncUpAttendeeDraft(id: id, name: attendee.name)
    }
    self.init(
      syncUp: SyncUpDraft(syncUp),
      attendees: draftAttendees,
      existingAttendeeIDs: existingAttendeeIDs,
      blankAttendeeID: blankAttendeeID,
      focus: focus
    )
  }

  public mutating func deleteAttendees(
    atOffsets indices: IndexSet,
    blankAttendeeID: String
  ) {
    for index in indices.sorted(by: >) where attendees.indices.contains(index) {
      attendees.remove(at: index)
    }
    if attendees.isEmpty {
      attendees.append(SyncUpAttendeeDraft(id: blankAttendeeID, name: ""))
    }
    guard let firstIndex = indices.first else { return }
    let index = min(firstIndex, attendees.count - 1)
    focus = .attendee(attendees[index].id)
  }

  public mutating func addAttendeeButtonTapped(id: String) {
    let attendee = SyncUpAttendeeDraft(
      id: Self.distinctDraftAttendeeID(
        id,
        existingAttendeeIDs: existingAttendeeIDs,
        usedDraftAttendeeIDs: attendees.map(\.id)
      ),
      name: ""
    )
    attendees.append(attendee)
    focus = .attendee(attendee.id)
  }

  public mutating func cancelButtonTapped() {
    isDismissed = true
  }

  public mutating func saveButtonTapped(
    newSyncUpID: String,
    blankAttendeeID: String,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> SyncUpFormSave {
    normalizeAttendees(blankAttendeeID: blankAttendeeID)

    let isNew = syncUp.id == nil
    let syncUpID = syncUp.id ?? newSyncUpID

    let syncUpOperations =
      isNew
      ? SyncUpsExample.createSyncUpOperations(
        id: syncUpID,
        title: syncUp.title,
        seconds: syncUp.seconds,
        theme: syncUp.theme,
        updatedAt: updatedAt,
        transactionID: transactionID
      )
      : SyncUpsExample.updateSyncUpOperations(
        id: syncUpID,
        title: syncUp.title,
        seconds: syncUp.seconds,
        theme: syncUp.theme,
        updatedAt: updatedAt,
        transactionID: transactionID
      )

    let operations =
      syncUpOperations
      + SyncUpsExample.replaceAttendeesOperations(
        syncUpID: syncUpID,
        existingAttendeeIDs: existingAttendeeIDs,
        newAttendees: attendees,
        updatedAt: updatedAt,
        transactionID: transactionID
      )
    return SyncUpFormSave(syncUpID: syncUpID, operations: operations, attendees: attendees)
  }

  public mutating func commit(_ save: SyncUpFormSave) {
    syncUp.id = save.syncUpID
    attendees = save.attendees
    existingAttendeeIDs = save.attendees.map(\.id)
    isDismissed = true
  }

  private mutating func normalizeAttendees(blankAttendeeID: String) {
    let focus = focus
    attendees.removeAll { attendee in
      attendee.name.allSatisfy(\.isWhitespace)
    }
    if attendees.isEmpty {
      attendees.append(SyncUpAttendeeDraft(id: blankAttendeeID, name: ""))
    }
    attendees = Self.sanitizedAttendees(
      attendees,
      existingAttendeeIDs: existingAttendeeIDs
    )
    self.focus = Self.sanitizedFocus(focus, attendees: attendees)
  }

  private static func sanitizedAttendees(
    _ attendees: [SyncUpAttendeeDraft],
    existingAttendeeIDs: [String]
  ) -> [SyncUpAttendeeDraft] {
    var usedDraftAttendeeIDs: [String] = []
    return attendees.map { attendee in
      let id = distinctDraftAttendeeID(
        attendee.id,
        existingAttendeeIDs: existingAttendeeIDs,
        usedDraftAttendeeIDs: usedDraftAttendeeIDs
      )
      usedDraftAttendeeIDs.append(id)
      var attendee = attendee
      attendee.id = id
      return attendee
    }
  }

  private static func sanitizedFocus(
    _ focus: Field?,
    attendees: [SyncUpAttendeeDraft]
  ) -> Field? {
    switch focus {
    case let .attendee(id) where attendees.contains(where: { $0.id == id }):
      return focus
    case .attendee:
      return attendees.first.map { .attendee($0.id) }
    case .title, nil:
      return focus
    }
  }

  private static func unique(_ ids: [String]) -> [String] {
    var seen: Set<String> = []
    return ids.filter { seen.insert($0).inserted }
  }

  private static func distinctDraftAttendeeID(
    _ id: String,
    existingAttendeeIDs: [String],
    usedDraftAttendeeIDs: [String]
  ) -> String {
    guard existingAttendeeIDs.contains(id) || usedDraftAttendeeIDs.contains(id)
    else { return id }
    var candidate = "draft-\(id)"
    while existingAttendeeIDs.contains(candidate) || usedDraftAttendeeIDs.contains(candidate) {
      candidate = "draft-\(candidate)"
    }
    return candidate
  }
}

public struct SyncUpMeetingSeedRecord: Hashable, Codable, Sendable {
  public var localIDName: String
  public var syncUpLocalIDName: String
  public var transcript: String
  public var dateOffsetMilliseconds: Int64

  public init(
    localIDName: String,
    syncUpLocalIDName: String,
    transcript: String,
    dateOffsetMilliseconds: Int64
  ) {
    self.localIDName = localIDName
    self.syncUpLocalIDName = syncUpLocalIDName
    self.transcript = transcript
    self.dateOffsetMilliseconds = dateOffsetMilliseconds
  }
}

public enum SyncUpsExample {
  public static let syncUpsNamespace = "syncUps"
  public static let attendeesNamespace = "attendees"
  public static let meetingsNamespace = "meetings"

  public static let seedSyncUps: [SyncUpSeedRecord] = [
    SyncUpSeedRecord(
      localIDName: "examples.sync-ups.seed.design",
      title: "Design",
      seconds: 60,
      theme: .appOrange
    ),
    SyncUpSeedRecord(
      localIDName: "examples.sync-ups.seed.engineering",
      title: "Engineering",
      seconds: 60 * 10,
      theme: .periwinkle
    ),
    SyncUpSeedRecord(
      localIDName: "examples.sync-ups.seed.product",
      title: "Product",
      seconds: 60 * 30,
      theme: .poppy
    ),
  ]

  public static let seedAttendees: [SyncUpAttendeeSeedRecord] = [
    SyncUpAttendeeSeedRecord(
      localIDName: "examples.sync-ups.seed.design.blob",
      syncUpLocalIDName: "examples.sync-ups.seed.design",
      name: "Blob"
    ),
    SyncUpAttendeeSeedRecord(
      localIDName: "examples.sync-ups.seed.design.blob-jr",
      syncUpLocalIDName: "examples.sync-ups.seed.design",
      name: "Blob Jr"
    ),
    SyncUpAttendeeSeedRecord(
      localIDName: "examples.sync-ups.seed.design.blob-sr",
      syncUpLocalIDName: "examples.sync-ups.seed.design",
      name: "Blob Sr"
    ),
    SyncUpAttendeeSeedRecord(
      localIDName: "examples.sync-ups.seed.design.blob-esq",
      syncUpLocalIDName: "examples.sync-ups.seed.design",
      name: "Blob Esq"
    ),
    SyncUpAttendeeSeedRecord(
      localIDName: "examples.sync-ups.seed.design.blob-iii",
      syncUpLocalIDName: "examples.sync-ups.seed.design",
      name: "Blob III"
    ),
    SyncUpAttendeeSeedRecord(
      localIDName: "examples.sync-ups.seed.design.blob-i",
      syncUpLocalIDName: "examples.sync-ups.seed.design",
      name: "Blob I"
    ),
    SyncUpAttendeeSeedRecord(
      localIDName: "examples.sync-ups.seed.engineering.blob",
      syncUpLocalIDName: "examples.sync-ups.seed.engineering",
      name: "Blob"
    ),
    SyncUpAttendeeSeedRecord(
      localIDName: "examples.sync-ups.seed.engineering.blob-jr",
      syncUpLocalIDName: "examples.sync-ups.seed.engineering",
      name: "Blob Jr"
    ),
    SyncUpAttendeeSeedRecord(
      localIDName: "examples.sync-ups.seed.product.blob-sr",
      syncUpLocalIDName: "examples.sync-ups.seed.product",
      name: "Blob Sr"
    ),
    SyncUpAttendeeSeedRecord(
      localIDName: "examples.sync-ups.seed.product.blob-jr",
      syncUpLocalIDName: "examples.sync-ups.seed.product",
      name: "Blob Jr"
    ),
  ]

  public static let seedMeetings: [SyncUpMeetingSeedRecord] = [
    SyncUpMeetingSeedRecord(
      localIDName: "examples.sync-ups.seed.design.meeting",
      syncUpLocalIDName: "examples.sync-ups.seed.design",
      transcript:
        """
        Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor \
        incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud \
        exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute \
        irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla \
        pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia \
        deserunt mollit anim id est laborum.
        """,
      dateOffsetMilliseconds: -7 * 24 * 60 * 60 * 1000
    )
  ]

  public static let attributes: [InstantAttribute] = [
    .primaryKey(namespace: syncUpsNamespace),
    InstantAttribute(
      id: "syncUps/title",
      namespace: syncUpsNamespace,
      name: "title",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "syncUps/seconds",
      namespace: syncUpsNamespace,
      name: "seconds",
      valueType: .number,
      isIndexed: true
    ),
    InstantAttribute(
      id: "syncUps/theme",
      namespace: syncUpsNamespace,
      name: "theme",
      valueType: .string,
      isIndexed: true
    ),
    .primaryKey(namespace: attendeesNamespace),
    InstantAttribute(
      id: "attendees/name",
      namespace: attendeesNamespace,
      name: "name",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "attendees/syncUp",
      namespace: attendeesNamespace,
      name: "syncUp",
      valueType: .ref,
      isIndexed: true,
      forwardIdentity: "attendees/syncUp",
      reverseIdentity: "syncUps/attendees",
      linkNamespace: syncUpsNamespace,
      onDelete: .cascade
    ),
    .primaryKey(namespace: meetingsNamespace),
    InstantAttribute(
      id: "meetings/date",
      namespace: meetingsNamespace,
      name: "date",
      valueType: .date,
      isIndexed: true
    ),
    InstantAttribute(
      id: "meetings/transcript",
      namespace: meetingsNamespace,
      name: "transcript",
      valueType: .string
    ),
    InstantAttribute(
      id: "meetings/syncUp",
      namespace: meetingsNamespace,
      name: "syncUp",
      valueType: .ref,
      isIndexed: true,
      forwardIdentity: "meetings/syncUp",
      reverseIdentity: "syncUps/meetings",
      linkNamespace: syncUpsNamespace,
      onDelete: .cascade
    ),
  ]

  public static let syncUpsQuery = InstantQueryPlan(
    id: "examples.sync-ups.list",
    namespace: syncUpsNamespace,
    order: InstantQueryOrder("title", .ascending)
  )

  public static let attendeesQuery = InstantQueryPlan(
    id: "examples.sync-ups.attendees",
    namespace: attendeesNamespace,
    order: InstantQueryOrder("name", .ascending)
  )

  public static let meetingsQuery = InstantQueryPlan(
    id: "examples.sync-ups.meetings",
    namespace: meetingsNamespace,
    order: InstantQueryOrder("date", .descending)
  )

  public static func attendeesForSyncUpQuery(_ syncUpID: String) -> InstantQueryPlan {
    InstantQueryPlan(
      id: "examples.sync-ups.attendees.\(syncUpID)",
      namespace: attendeesNamespace,
      filters: [.equals(field: "syncUp", value: .ref(syncUpID))],
      order: InstantQueryOrder("name", .ascending)
    )
  }

  public static func meetingsForSyncUpQuery(_ syncUpID: String) -> InstantQueryPlan {
    InstantQueryPlan(
      id: "examples.sync-ups.meetings.\(syncUpID)",
      namespace: meetingsNamespace,
      filters: [.equals(field: "syncUp", value: .ref(syncUpID))],
      order: InstantQueryOrder("date", .descending)
    )
  }

  public static func createSyncUpOperations(
    id: String,
    title: String,
    seconds: Int = 60 * 5,
    theme: SyncUpTheme = .bubblegum,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      .requireEntityMissing(entityID: id, namespace: syncUpsNamespace),
    ] + upsertSyncUpOperations(
      id: id,
      title: title,
      seconds: seconds,
      theme: theme,
      updatedAt: updatedAt,
      transactionID: transactionID
    )
  }

  public static func updateSyncUpOperations(
    id: String,
    title: String,
    seconds: Int,
    theme: SyncUpTheme,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: id, namespace: syncUpsNamespace),
    ] + upsertSyncUpOperations(
      id: id,
      title: title,
      seconds: seconds,
      theme: theme,
      updatedAt: updatedAt,
      transactionID: transactionID
    )
  }

  public static func replaceAttendeesOperations(
    syncUpID: String,
    existingAttendeeIDs: [String],
    newAttendees: [SyncUpAttendeeDraft],
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    guard !newAttendees.isEmpty else {
      return [
        .requireEntityExists(entityID: syncUpID, namespace: syncUpsNamespace),
        .requireEntityMissing(entityID: syncUpID, namespace: syncUpsNamespace),
      ]
    }
    return [
      .requireEntityExists(entityID: syncUpID, namespace: syncUpsNamespace)
    ] + newAttendees.map { attendee in
      .requireEntityMissing(entityID: attendee.id, namespace: attendeesNamespace)
    } + existingAttendeeIDs.flatMap { id in
      deleteAttendeeEntityPreconditions(id: id, syncUpID: syncUpID)
    } + existingAttendeeIDs.map { id in
      .deleteEntity(id)
    } + newAttendees.flatMap { attendee in
      [
        .requireEntityMissing(entityID: attendee.id, namespace: attendeesNamespace)
      ] + upsertAttendeeOperations(
        id: attendee.id,
        syncUpID: syncUpID,
        name: attendee.name,
        updatedAt: updatedAt,
        transactionID: transactionID
      )
    }
  }

  public static func createAttendeeOperations(
    id: String,
    syncUpID: String,
    name: String,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: syncUpID, namespace: syncUpsNamespace),
      .requireEntityMissing(entityID: id, namespace: attendeesNamespace),
    ] + upsertAttendeeOperations(
      id: id,
      syncUpID: syncUpID,
      name: name,
      updatedAt: updatedAt,
      transactionID: transactionID
    )
  }

  public static func recordMeetingOperations(
    id: String,
    syncUpID: String,
    transcript: String,
    date: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: syncUpID, namespace: syncUpsNamespace),
      .requireEntityMissing(entityID: id, namespace: meetingsNamespace),
    ] + upsertMeetingOperations(
      id: id,
      syncUpID: syncUpID,
      transcript: transcript,
      date: date,
      transactionID: transactionID
    )
  }

  public static func deleteSyncUpOperations(id: String) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: id, namespace: syncUpsNamespace),
      .deleteEntity(id),
    ]
  }

  public static func deleteAttendeeOperations(
    id: String,
    syncUpID: String,
    remainingAttendeeIDs: [String],
    replacementAttendeeID: String? = nil,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    let verifiedRemainingAttendeeIDs = remainingAttendeeIDs.filter { $0 != id }
    let keepsAtLeastOneAttendee = !verifiedRemainingAttendeeIDs.isEmpty || replacementAttendeeID != nil
    var operations: [InstantTripleOperation] = [
      .requireEntityExists(entityID: syncUpID, namespace: syncUpsNamespace),
      .requireEntityExists(entityID: id, namespace: attendeesNamespace),
      .requireTripleExists(entityID: id, attributeID: "attendees/syncUp", value: .ref(syncUpID)),
    ] + (
      keepsAtLeastOneAttendee
        ? []
        : [.requireEntityMissing(entityID: syncUpID, namespace: syncUpsNamespace)]
    ) + verifiedRemainingAttendeeIDs.flatMap { remainingAttendeeID in
      [
        .requireEntityExists(entityID: remainingAttendeeID, namespace: attendeesNamespace),
        .requireTripleExists(
          entityID: remainingAttendeeID,
          attributeID: "attendees/syncUp",
          value: .ref(syncUpID)
        ),
      ]
    } + [
      .deleteEntity(id),
    ]
    if let replacementAttendeeID {
      operations += createAttendeeOperations(
        id: replacementAttendeeID,
        syncUpID: syncUpID,
        name: "",
        updatedAt: updatedAt,
        transactionID: transactionID
      )
    }
    return operations
  }

  public static func deleteMeetingOperations(id: String) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: id, namespace: meetingsNamespace),
      .deleteEntity(id),
    ]
  }

  public static func seedOperations(
    syncUps: [(id: String, seed: SyncUpSeedRecord)],
    attendees: [(id: String, syncUpID: String, seed: SyncUpAttendeeSeedRecord)],
    meetings: [(id: String, syncUpID: String, seed: SyncUpMeetingSeedRecord)],
    baseCreatedAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    syncUps.flatMap { id, seed in
      upsertSyncUpOperations(
        id: id,
        title: seed.title,
        seconds: seed.seconds,
        theme: seed.theme,
        updatedAt: baseCreatedAt,
        transactionID: transactionID
      )
    } + attendees.flatMap { id, syncUpID, seed in
      upsertAttendeeOperations(
        id: id,
        syncUpID: syncUpID,
        name: seed.name,
        updatedAt: baseCreatedAt,
        transactionID: transactionID
      )
    } + meetings.flatMap { id, syncUpID, seed in
      let date = InstantTimestamp(
        milliseconds: baseCreatedAt.milliseconds + seed.dateOffsetMilliseconds
      )
      return upsertMeetingOperations(
        id: id,
        syncUpID: syncUpID,
        transcript: seed.transcript,
        date: date,
        transactionID: transactionID
      )
    }
  }

  public static func decodeSyncUps(
    _ snapshots: [InstantEntitySnapshot]
  ) throws -> [SyncUpRecord] {
    try snapshots.map { snapshot in
      let title = try stringField("title", from: snapshot, namespace: syncUpsNamespace)
      let seconds = try intField("seconds", from: snapshot, namespace: syncUpsNamespace)
      let themeRawValue = try stringField("theme", from: snapshot, namespace: syncUpsNamespace)
      guard let theme = SyncUpTheme(rawValue: themeRawValue) else {
        throw decodeError(
          namespace: syncUpsNamespace,
          id: snapshot.id,
          field: "theme",
          expected: "known sync-up theme"
        )
      }
      return SyncUpRecord(id: snapshot.id, title: title, seconds: seconds, theme: theme)
    }
  }

  public static func decodeAttendees(
    _ snapshots: [InstantEntitySnapshot]
  ) throws -> [SyncUpAttendeeRecord] {
    try snapshots.map { snapshot in
      SyncUpAttendeeRecord(
        id: snapshot.id,
        name: try stringField("name", from: snapshot, namespace: attendeesNamespace),
        syncUpID: try refField("syncUp", from: snapshot, namespace: attendeesNamespace)
      )
    }
  }

  public static func decodeMeetings(
    _ snapshots: [InstantEntitySnapshot]
  ) throws -> [SyncUpMeetingRecord] {
    try snapshots.map { snapshot in
      SyncUpMeetingRecord(
        id: snapshot.id,
        date: try timestampField("date", from: snapshot, namespace: meetingsNamespace),
        syncUpID: try refField("syncUp", from: snapshot, namespace: meetingsNamespace),
        transcript: try stringField("transcript", from: snapshot, namespace: meetingsNamespace)
      )
    }
  }

  private static func upsertSyncUpOperations(
    id: String,
    title: String,
    seconds: Int,
    theme: SyncUpTheme,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      syncUpIdentityOperation(id: id, updatedAt: updatedAt, transactionID: transactionID),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "syncUps/title",
          value: .string(title),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "syncUps/seconds",
          value: .number(Double(seconds)),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "syncUps/theme",
          value: .string(theme.rawValue),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
    ]
  }

  private static func upsertAttendeeOperations(
    id: String,
    syncUpID: String,
    name: String,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      attendeeIdentityOperation(id: id, updatedAt: updatedAt, transactionID: transactionID),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "attendees/name",
          value: .string(name),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "attendees/syncUp",
          value: .ref(syncUpID),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
    ]
  }

  private static func deleteAttendeeEntityPreconditions(
    id: String,
    syncUpID: String? = nil
  ) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: id, namespace: attendeesNamespace),
    ] + (
      syncUpID.map { syncUpID in
        [
          InstantTripleOperation.requireTripleExists(
            entityID: id,
            attributeID: "attendees/syncUp",
            value: .ref(syncUpID)
          )
        ]
      } ?? []
    )
  }

  private static func upsertMeetingOperations(
    id: String,
    syncUpID: String,
    transcript: String,
    date: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      meetingIdentityOperation(id: id, updatedAt: date, transactionID: transactionID),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "meetings/date",
          value: .date(Date(timeIntervalSince1970: Double(date.milliseconds) / 1000)),
          txID: transactionID,
          txTime: date
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "meetings/transcript",
          value: .string(transcript),
          txID: transactionID,
          txTime: date
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "meetings/syncUp",
          value: .ref(syncUpID),
          txID: transactionID,
          txTime: date
        )
      ),
    ]
  }

  private static func syncUpIdentityOperation(
    id: String,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> InstantTripleOperation {
    identityOperation(
      id: id,
      namespace: syncUpsNamespace,
      updatedAt: updatedAt,
      transactionID: transactionID
    )
  }

  private static func attendeeIdentityOperation(
    id: String,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> InstantTripleOperation {
    identityOperation(
      id: id,
      namespace: attendeesNamespace,
      updatedAt: updatedAt,
      transactionID: transactionID
    )
  }

  private static func meetingIdentityOperation(
    id: String,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> InstantTripleOperation {
    identityOperation(
      id: id,
      namespace: meetingsNamespace,
      updatedAt: updatedAt,
      transactionID: transactionID
    )
  }

  private static func identityOperation(
    id: String,
    namespace: String,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> InstantTripleOperation {
    .insert(
      InstantTriple(
        entityID: id,
        attributeID: InstantAttribute.primaryKeyID(namespace: namespace),
        value: .string(id),
        txID: transactionID,
        txTime: updatedAt
      )
    )
  }

  private static func stringField(
    _ field: String,
    from snapshot: InstantEntitySnapshot,
    namespace: String
  ) throws -> String {
    guard case let .string(value) = snapshot.values[field]?.first else {
      throw decodeError(namespace: namespace, id: snapshot.id, field: field, expected: "string")
    }
    return value
  }

  private static func intField(
    _ field: String,
    from snapshot: InstantEntitySnapshot,
    namespace: String
  ) throws -> Int {
    guard case let .number(value) = snapshot.values[field]?.first else {
      throw decodeError(namespace: namespace, id: snapshot.id, field: field, expected: "number")
    }
    return Int(value)
  }

  private static func refField(
    _ field: String,
    from snapshot: InstantEntitySnapshot,
    namespace: String
  ) throws -> String {
    guard case let .ref(value) = snapshot.values[field]?.first else {
      throw decodeError(namespace: namespace, id: snapshot.id, field: field, expected: "ref")
    }
    return value
  }

  private static func timestampField(
    _ field: String,
    from snapshot: InstantEntitySnapshot,
    namespace: String
  ) throws -> InstantTimestamp {
    guard case let .date(value) = snapshot.values[field]?.first else {
      throw decodeError(namespace: namespace, id: snapshot.id, field: field, expected: "date")
    }
    return InstantTimestamp(milliseconds: Int64(value.timeIntervalSince1970 * 1000))
  }

  private static func decodeError(
    namespace: String,
    id: String,
    field: String,
    expected: String
  ) -> InstantError {
    InstantError(
      code: .decodeFailed,
      operation: "decode sync-ups example",
      namespace: namespace,
      path: field,
      localID: id,
      message: "Expected \(expected) for '\(namespace).\(field)'.",
      recovery: "Inspect the local SyncUps example triples and attributes."
    )
  }
}
