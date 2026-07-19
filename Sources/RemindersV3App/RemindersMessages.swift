import Foundation
import InstantSwiftData

public struct RemindersV3ListChanged: Hashable, Sendable {
  public var listID: InstantID<RemindersV3List>

  public init(listID: InstantID<RemindersV3List>) {
    self.listID = listID
  }
}

public struct CreateRemindersV3List: InstantMessage {
  public var listID: InstantID<RemindersV3List>
  public var ownerID: InstantID<RemindersV3User>
  public var title: String
  public var color: String
  public var position: Int
  public var createdAt: Date

  public init(
    listID: InstantID<RemindersV3List>,
    ownerID: InstantID<RemindersV3User>,
    title: String,
    color: String = "#4a99ef",
    position: Int,
    createdAt: Date
  ) {
    self.listID = listID
    self.ownerID = ownerID
    self.title = title
    self.color = color
    self.position = position
    self.createdAt = createdAt
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<RemindersV3ListChanged>
  {
    _ = client
    return InstantPreparedMessage(change: .init(listID: listID)) {
      RemindersV3List.create(
        id: listID,
        RemindersV3List.title.set(title),
        RemindersV3List.color.set(color),
        RemindersV3List.position.set(position),
        RemindersV3List.createdAt.set(createdAt),
        RemindersV3List.owner.set(ownerID)
      )
    }
  }
}

public struct RenameRemindersV3List: InstantMessage {
  public var listID: InstantID<RemindersV3List>
  public var title: String

  public init(listID: InstantID<RemindersV3List>, title: String) {
    self.listID = listID
    self.title = title
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<RemindersV3ListChanged>
  {
    _ = client
    return InstantPreparedMessage(change: .init(listID: listID)) {
      RemindersV3List.updateExisting(id: listID, RemindersV3List.title.set(title))
    }
  }
}

public struct MoveRemindersV3List: InstantMessage {
  public var listID: InstantID<RemindersV3List>
  public var position: Int

  public init(listID: InstantID<RemindersV3List>, position: Int) {
    self.listID = listID
    self.position = position
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<RemindersV3ListChanged>
  {
    _ = client
    return InstantPreparedMessage(change: .init(listID: listID)) {
      RemindersV3List.updateExisting(
        id: listID,
        RemindersV3List.position.set(position)
      )
    }
  }
}

public struct DeleteRemindersV3List: InstantMessage {
  public var listID: InstantID<RemindersV3List>

  public init(listID: InstantID<RemindersV3List>) {
    self.listID = listID
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<RemindersV3ListChanged>
  {
    _ = client
    return InstantPreparedMessage(change: .init(listID: listID)) {
      RemindersV3List.delete(id: listID)
    }
  }
}

public struct RemindersV3ReminderChanged: Hashable, Sendable {
  public var reminderID: InstantID<RemindersV3Reminder>
  public var listID: InstantID<RemindersV3List>

  public init(
    reminderID: InstantID<RemindersV3Reminder>,
    listID: InstantID<RemindersV3List>
  ) {
    self.reminderID = reminderID
    self.listID = listID
  }
}

public struct CreateRemindersV3Reminder: InstantMessage {
  public var reminderID: InstantID<RemindersV3Reminder>
  public var listID: InstantID<RemindersV3List>
  public var title: String
  public var notes: String
  public var isFlagged: Bool
  public var dueDate: Date?
  public var priority: RemindersV3Priority?
  public var position: Int
  public var createdAt: Date
  public var tagIDs: [InstantID<RemindersV3Tag>]
  public var tagTitles: [InstantID<RemindersV3Tag>: String]

  public init(
    reminderID: InstantID<RemindersV3Reminder>,
    listID: InstantID<RemindersV3List>,
    title: String,
    notes: String = "",
    isFlagged: Bool = false,
    dueDate: Date? = nil,
    priority: RemindersV3Priority? = nil,
    position: Int,
    createdAt: Date,
    tagIDs: [InstantID<RemindersV3Tag>] = [],
    tagTitles: [InstantID<RemindersV3Tag>: String] = [:]
  ) {
    self.reminderID = reminderID
    self.listID = listID
    self.title = title
    self.notes = notes
    self.isFlagged = isFlagged
    self.dueDate = dueDate
    self.priority = priority
    self.position = position
    self.createdAt = createdAt
    self.tagIDs = Self.unique(tagIDs)
    self.tagTitles = tagTitles
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<RemindersV3ReminderChanged>
  {
    _ = client
    return InstantPreparedMessage(
      change: .init(reminderID: reminderID, listID: listID)
    ) {
      RemindersV3Reminder.create(
        id: reminderID,
        RemindersV3Reminder.title.set(title),
        RemindersV3Reminder.notes.set(notes),
        RemindersV3Reminder.isCompleted.set(false),
        RemindersV3Reminder.isFlagged.set(isFlagged),
        RemindersV3Reminder.dueDate.set(dueDate),
        RemindersV3Reminder.priority.set(priority),
        RemindersV3Reminder.position.set(position),
        RemindersV3Reminder.createdAt.set(createdAt),
        RemindersV3Reminder.list.set(listID)
      )
      for tagID in tagIDs {
        RemindersV3Tag.create(
          id: tagID,
          RemindersV3Tag.title.set(tagTitles[tagID] ?? tagID.rawValue)
        )
        RemindersV3Reminder.tags.link(from: reminderID, to: tagID)
      }
    }
  }

  private static func unique(
    _ ids: [InstantID<RemindersV3Tag>]
  ) -> [InstantID<RemindersV3Tag>] {
    var seen: Set<String> = []
    return ids.filter { seen.insert($0.rawValue).inserted }
  }
}

public struct UpdateRemindersV3Reminder: InstantMessage {
  public var reminderID: InstantID<RemindersV3Reminder>
  public var listID: InstantID<RemindersV3List>
  public var title: String
  public var notes: String
  public var isFlagged: Bool
  public var dueDate: Date?
  public var priority: RemindersV3Priority?
  public var existingTagIDs: [InstantID<RemindersV3Tag>]
  public var tagIDs: [InstantID<RemindersV3Tag>]
  public var tagTitles: [InstantID<RemindersV3Tag>: String]

  public init(
    reminderID: InstantID<RemindersV3Reminder>,
    listID: InstantID<RemindersV3List>,
    title: String,
    notes: String,
    isFlagged: Bool,
    dueDate: Date?,
    priority: RemindersV3Priority?,
    existingTagIDs: [InstantID<RemindersV3Tag>],
    tagIDs: [InstantID<RemindersV3Tag>],
    tagTitles: [InstantID<RemindersV3Tag>: String] = [:]
  ) {
    self.reminderID = reminderID
    self.listID = listID
    self.title = title
    self.notes = notes
    self.isFlagged = isFlagged
    self.dueDate = dueDate
    self.priority = priority
    self.existingTagIDs = Self.unique(existingTagIDs)
    self.tagIDs = Self.unique(tagIDs)
    self.tagTitles = tagTitles
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<RemindersV3ReminderChanged>
  {
    _ = client
    let removed = existingTagIDs.filter { !tagIDs.contains($0) }
    let added = tagIDs.filter { !existingTagIDs.contains($0) }
    return InstantPreparedMessage(
      change: .init(reminderID: reminderID, listID: listID)
    ) {
      RemindersV3Reminder.updateExisting(
        id: reminderID,
        RemindersV3Reminder.title.set(title),
        RemindersV3Reminder.notes.set(notes),
        RemindersV3Reminder.isFlagged.set(isFlagged),
        RemindersV3Reminder.dueDate.set(dueDate),
        RemindersV3Reminder.priority.set(priority),
        RemindersV3Reminder.list.set(listID)
      )
      for tagID in removed {
        RemindersV3Reminder.tags.unlink(from: reminderID, to: tagID)
      }
      for tagID in added {
        RemindersV3Tag.create(
          id: tagID,
          RemindersV3Tag.title.set(tagTitles[tagID] ?? tagID.rawValue)
        )
        RemindersV3Reminder.tags.link(from: reminderID, to: tagID)
      }
    }
  }

  private static func unique(
    _ ids: [InstantID<RemindersV3Tag>]
  ) -> [InstantID<RemindersV3Tag>] {
    var seen: Set<String> = []
    return ids.filter { seen.insert($0.rawValue).inserted }
  }
}

public struct SetRemindersV3Completion: InstantMessage {
  public var reminderID: InstantID<RemindersV3Reminder>
  public var listID: InstantID<RemindersV3List>
  public var isCompleted: Bool

  public init(
    reminderID: InstantID<RemindersV3Reminder>,
    listID: InstantID<RemindersV3List>,
    isCompleted: Bool
  ) {
    self.reminderID = reminderID
    self.listID = listID
    self.isCompleted = isCompleted
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<RemindersV3ReminderChanged>
  {
    _ = client
    return InstantPreparedMessage(
      change: .init(reminderID: reminderID, listID: listID)
    ) {
      RemindersV3Reminder.updateExisting(
        id: reminderID,
        RemindersV3Reminder.isCompleted.set(isCompleted),
        RemindersV3Reminder.list.set(listID)
      )
    }
  }
}

public struct DeleteRemindersV3Reminder: InstantMessage {
  public var reminderID: InstantID<RemindersV3Reminder>
  public var listID: InstantID<RemindersV3List>

  public init(
    reminderID: InstantID<RemindersV3Reminder>,
    listID: InstantID<RemindersV3List>
  ) {
    self.reminderID = reminderID
    self.listID = listID
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<RemindersV3ReminderChanged>
  {
    _ = client
    return InstantPreparedMessage(
      change: .init(reminderID: reminderID, listID: listID)
    ) {
      RemindersV3Reminder.list.link(from: reminderID, to: listID)
      RemindersV3Reminder.delete(id: reminderID)
    }
  }
}
