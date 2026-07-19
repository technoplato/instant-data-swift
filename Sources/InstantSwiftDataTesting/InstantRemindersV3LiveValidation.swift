import Foundation

public struct InstantRemindersV3LiveReminderEvidence:
  Codable, Equatable, Sendable
{
  public var id: String
  public var title: String
  public var notes: String
  public var isCompleted: Bool
  public var isFlagged: Bool
  public var dueDateMilliseconds: Int64?
  public var priority: Int?
  public var position: Int
  public var tagIDs: [String]

  public init(
    id: String,
    title: String,
    notes: String,
    isCompleted: Bool,
    isFlagged: Bool,
    dueDateMilliseconds: Int64?,
    priority: Int?,
    position: Int,
    tagIDs: [String]
  ) {
    self.id = id
    self.title = title
    self.notes = notes
    self.isCompleted = isCompleted
    self.isFlagged = isFlagged
    self.dueDateMilliseconds = dueDateMilliseconds
    self.priority = priority
    self.position = position
    self.tagIDs = tagIDs
  }
}

public struct InstantRemindersV3LiveListEvidence:
  Codable, Equatable, Sendable
{
  public var id: String
  public var title: String
  public var color: String
  public var position: Int
  public var ownerID: String
  public var readerIDs: [String]
  public var writerIDs: [String]
  public var shareID: String?
  public var membershipRoles: [String]

  public init(
    id: String,
    title: String,
    color: String,
    position: Int,
    ownerID: String,
    readerIDs: [String],
    writerIDs: [String],
    shareID: String?,
    membershipRoles: [String]
  ) {
    self.id = id
    self.title = title
    self.color = color
    self.position = position
    self.ownerID = ownerID
    self.readerIDs = readerIDs
    self.writerIDs = writerIDs
    self.shareID = shareID
    self.membershipRoles = membershipRoles
  }
}

public struct InstantRemindersV3LiveValidationDetails:
  Codable, Equatable, Sendable
{
  public var list: InstantRemindersV3LiveListEvidence
  public var swiftReminder: InstantRemindersV3LiveReminderEvidence
  public var typeScriptReminderObservedBySwift: InstantRemindersV3LiveReminderEvidence
  public var connectionState: String
  public var pendingMutationCount: Int

  public init(
    list: InstantRemindersV3LiveListEvidence,
    swiftReminder: InstantRemindersV3LiveReminderEvidence,
    typeScriptReminderObservedBySwift: InstantRemindersV3LiveReminderEvidence,
    connectionState: String,
    pendingMutationCount: Int
  ) {
    self.list = list
    self.swiftReminder = swiftReminder
    self.typeScriptReminderObservedBySwift = typeScriptReminderObservedBySwift
    self.connectionState = connectionState
    self.pendingMutationCount = pendingMutationCount
  }
}

public enum InstantRemindersV3LiveValidation {
  public static let listID = "00000000-0000-4000-8000-000000000401"
  public static let swiftReminderID = "00000000-0000-4000-8000-000000000402"
  public static let shareID = "00000000-0000-4000-8000-000000000403"
  public static let ownerMembershipID = "00000000-0000-4000-8000-000000000404"
  public static let readerMembershipID = "00000000-0000-4000-8000-000000000405"
  public static let typeScriptReminderID = "00000000-0000-4000-8000-000000000406"
  public static let swiftTagID = "swift"
  public static let typeScriptTagID = "typescript"
}
