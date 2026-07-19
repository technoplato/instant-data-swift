import Foundation
import PresenceRecipesV3App

public struct InstantReactionsV3LiveValidationDetails: Codable, Equatable, Sendable {
  public var roomType: String
  public var roomID: String
  public var topic: String
  public var publishedPayload: ReactionsV3Payload
  public var observedPayload: ReactionsV3Payload
  public var ignoredInvalidName: String
  public var connectionState: String

  public init(
    roomType: String,
    roomID: String,
    topic: String,
    publishedPayload: ReactionsV3Payload,
    observedPayload: ReactionsV3Payload,
    ignoredInvalidName: String,
    connectionState: String
  ) {
    self.roomType = roomType
    self.roomID = roomID
    self.topic = topic
    self.publishedPayload = publishedPayload
    self.observedPayload = observedPayload
    self.ignoredInvalidName = ignoredInvalidName
    self.connectionState = connectionState
  }
}

public enum InstantReactionsV3LiveValidation {
  public static let swiftPayload = ReactionsV3Payload(
    name: ReactionsV3Name.heart.rawValue,
    directionAngle: 45,
    rotationAngle: 270
  )

  public static let typeScriptPayload = ReactionsV3Payload(
    name: ReactionsV3Name.wave.rawValue,
    directionAngle: 90,
    rotationAngle: 180
  )
}
