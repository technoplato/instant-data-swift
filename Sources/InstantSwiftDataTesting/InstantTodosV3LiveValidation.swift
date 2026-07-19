import Foundation

public struct InstantTodosV3LiveValidationDetails: Codable, Equatable, Sendable {
  public var direction: String
  public var id: String
  public var text: String
  public var isCompleted: Bool
  public var createdAtMilliseconds: Int64
  public var connectionState: String
  public var pendingMutationCount: Int

  public init(
    direction: String,
    id: String,
    text: String,
    isCompleted: Bool,
    createdAtMilliseconds: Int64,
    connectionState: String,
    pendingMutationCount: Int
  ) {
    self.direction = direction
    self.id = id
    self.text = text
    self.isCompleted = isCompleted
    self.createdAtMilliseconds = createdAtMilliseconds
    self.connectionState = connectionState
    self.pendingMutationCount = pendingMutationCount
  }
}
