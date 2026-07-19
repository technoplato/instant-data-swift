import Foundation
import InstantSwiftData

public struct AppBuilderV3BuildChange: Equatable, Hashable, Sendable {
  public var buildID: InstantID<AppBuilderV3Build>
  public var codeLength: Int
  public var reasoningLength: Int
  public var isPreviewable: Bool
  public var fileID: InstantID<AppBuilderV3File>?

  public init(
    buildID: InstantID<AppBuilderV3Build>,
    codeLength: Int,
    reasoningLength: Int,
    isPreviewable: Bool,
    fileID: InstantID<AppBuilderV3File>? = nil
  ) {
    self.buildID = buildID
    self.codeLength = codeLength
    self.reasoningLength = reasoningLength
    self.isPreviewable = isPreviewable
    self.fileID = fileID
  }
}

public struct CreateAppBuilderV3Build: InstantMessage {
  public var buildID: InstantID<AppBuilderV3Build>
  public var ownerID: InstantID<AppBuilderV3User>
  public var instantAppID: String
  public var title: String

  public init(
    buildID: InstantID<AppBuilderV3Build>,
    ownerID: InstantID<AppBuilderV3User>,
    instantAppID: String,
    title: String
  ) {
    self.buildID = buildID
    self.ownerID = ownerID
    self.instantAppID = instantAppID
    self.title = title
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<AppBuilderV3BuildChange>
  {
    _ = client
    return InstantPreparedMessage(
      change: AppBuilderV3BuildChange(
        buildID: buildID,
        codeLength: 0,
        reasoningLength: 0,
        isPreviewable: false
      )
    ) {
      AppBuilderV3Build.create(
        id: buildID,
        AppBuilderV3Build.instantAppID.set(instantAppID),
        AppBuilderV3Build.code.set(""),
        AppBuilderV3Build.isPreviewable.set(false),
        AppBuilderV3Build.title.set(title),
        AppBuilderV3Build.owner.set(ownerID)
      )
    }
  }
}

public struct UpdateAppBuilderV3Build: InstantMessage {
  public var buildID: InstantID<AppBuilderV3Build>
  public var code: String
  public var reasoning: String
  public var isPreviewable: Bool
  public var fileID: InstantID<AppBuilderV3File>?

  public init(
    buildID: InstantID<AppBuilderV3Build>,
    code: String,
    reasoning: String,
    isPreviewable: Bool,
    fileID: InstantID<AppBuilderV3File>? = nil
  ) {
    self.buildID = buildID
    self.code = code
    self.reasoning = reasoning
    self.isPreviewable = isPreviewable
    self.fileID = fileID
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<AppBuilderV3BuildChange>
  {
    _ = client
    return InstantPreparedMessage(
      change: AppBuilderV3BuildChange(
        buildID: buildID,
        codeLength: code.count,
        reasoningLength: reasoning.count,
        isPreviewable: isPreviewable,
        fileID: fileID
      )
    ) {
      AppBuilderV3Build.updateExisting(
        id: buildID,
        AppBuilderV3Build.code.set(code),
        AppBuilderV3Build.reasoning.set(reasoning),
        AppBuilderV3Build.isPreviewable.set(isPreviewable)
      )
      if let fileID {
        AppBuilderV3Build.updateExisting(
          id: buildID,
          AppBuilderV3Build.file.set(fileID)
        )
      }
    }
  }
}

public struct DeleteAppBuilderV3Build: InstantMessage {
  public var buildID: InstantID<AppBuilderV3Build>

  public init(buildID: InstantID<AppBuilderV3Build>) {
    self.buildID = buildID
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<InstantID<AppBuilderV3Build>>
  {
    _ = client
    return InstantPreparedMessage(change: buildID) {
      AppBuilderV3Build.delete(id: buildID)
    }
  }
}
