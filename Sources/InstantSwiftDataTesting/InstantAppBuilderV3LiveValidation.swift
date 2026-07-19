import AppBuilderV3App
import Dependencies
import Foundation
import InstantSwiftData

public struct InstantAppBuilderV3LiveFileDetails: Codable, Equatable, Sendable {
  public var id: String
  public var path: String
  public var url: String
  public var contents: String

  public init(id: String, path: String, url: String, contents: String) {
    self.id = id
    self.path = path
    self.url = url
    self.contents = contents
  }
}

public struct InstantAppBuilderV3LiveBuildDetails: Codable, Equatable, Sendable {
  public var id: String
  public var instantAppID: String
  public var code: String
  public var reasoning: String?
  public var isPreviewable: Bool?
  public var title: String?
  public var ownerID: String
  public var file: InstantAppBuilderV3LiveFileDetails?

  public init(
    id: String,
    instantAppID: String,
    code: String,
    reasoning: String?,
    isPreviewable: Bool?,
    title: String?,
    ownerID: String,
    file: InstantAppBuilderV3LiveFileDetails?
  ) {
    self.id = id
    self.instantAppID = instantAppID
    self.code = code
    self.reasoning = reasoning
    self.isPreviewable = isPreviewable
    self.title = title
    self.ownerID = ownerID
    self.file = file
  }
}

public struct InstantAppBuilderV3LiveValidationDetails: Codable, Equatable, Sendable {
  public var swiftBuild: InstantAppBuilderV3LiveBuildDetails
  public var typeScriptBuild: InstantAppBuilderV3LiveBuildDetails
  public var connectionState: String
  public var pendingMutationCount: Int

  public init(
    swiftBuild: InstantAppBuilderV3LiveBuildDetails,
    typeScriptBuild: InstantAppBuilderV3LiveBuildDetails,
    connectionState: String,
    pendingMutationCount: Int
  ) {
    self.swiftBuild = swiftBuild
    self.typeScriptBuild = typeScriptBuild
    self.connectionState = connectionState
    self.pendingMutationCount = pendingMutationCount
  }
}

public enum InstantAppBuilderV3LiveValidation {
  public static let swiftBuildID = "00000000-0000-4000-8000-000000000602"
  public static let typeScriptBuildID = "00000000-0000-4000-8000-000000000604"
  public static let swiftCode = "export default function SwiftGeneratedApp() {}"
  public static let swiftReasoning = "Plan the Swift-generated screen."
  public static let typeScriptCode = "export default function TypeScriptGeneratedApp() {}"

  @MainActor
  public static func run(
    appID: String,
    apiURI: URL,
    websocketURI: URL,
    refreshToken: String,
    expectedUserID: String,
    persistenceURL: URL? = nil,
    onSwiftBuildReady: @escaping @Sendable () -> Void = {},
    onTypeScriptBuildObserved: @escaping @Sendable () -> Void = {}
  ) async throws -> ValidationEvidenceRow<InstantAppBuilderV3LiveValidationDetails> {
    let client = try await liveClient(
      appID: appID,
      apiURI: apiURI,
      websocketURI: websocketURI,
      persistenceURL: persistenceURL
    )
    try await authenticate(
      client,
      refreshToken: refreshToken,
      expectedUserID: expectedUserID
    )

    let ownerID = InstantID<AppBuilderV3User>(rawValue: expectedUserID)
    let builds = FetchAll<AppBuilderV3Build>()
    let files = FetchAll<AppBuilderV3File>()
    let buildsTask = Task {
      try await builds.task(AppBuilderV3Build.forOwner(ownerID), using: client)
    }
    let filesTask = Task {
      try await files.task(AppBuilderV3File.ordered, using: client)
    }
    defer {
      buildsTask.cancel()
      filesTask.cancel()
    }

    let buildUUID = UUID(uuidString: swiftBuildID)!
    let model = withDependencies {
      $0.defaultInstantSwiftData = client
      $0.date.now = Date(timeIntervalSince1970: 1_784_467_200)
      $0.uuid = .constant(buildUUID)
      $0.instantPlatformAppClient = InstantPlatformAppClient { request in
        InstantPlatformApp(
          id: "platform-app-swift",
          title: request.title,
          orgID: request.orgID,
          createdAt: request.createdAt
        )
      }
      $0.appBuilderCodeGenerator = AppBuilderCodeGeneratorClient { _ in
        AsyncThrowingStream { continuation in
          continuation.yield(.init(kind: .reasoning, text: swiftReasoning))
          continuation.yield(.init(kind: .code, text: swiftCode))
          continuation.finish()
        }
      }
    } operation: {
      AppBuilderV3Model(prompt: "Build a workout tracker")
    }

    await model.generateButtonTapped(ownerID: ownerID, orgID: "app-builder-v3-live")
    guard model.message == "App ready" else {
      throw failure(
        operation: "generate Swift App Builder build",
        message: "The app model finished with status '\(model.message)'."
      )
    }
    let swiftBuild = try await waitForBuild(
      id: swiftBuildID,
      builds: builds,
      files: files,
      expectedCode: swiftCode
    )
    onSwiftBuildReady()

    let typeScriptBuild = try await waitForBuild(
      id: typeScriptBuildID,
      builds: builds,
      files: files,
      expectedCode: typeScriptCode
    )
    onTypeScriptBuildObserved()

    buildsTask.cancel()
    filesTask.cancel()
    _ = try? await buildsTask.value
    _ = try? await filesTask.value
    let status = try await client.connectionStatus()
    let pendingMutationCount = await client.pendingMutations().count
    _ = try await client.closeConnection()

    return ValidationEvidenceRow(
      caseID: "validation.live.app-builder-v3",
      side: "swift",
      event: "typescript-build-observed",
      appID: appID,
      entityID: typeScriptBuildID,
      timestampMs: milliseconds(Date()),
      ok: true,
      details: InstantAppBuilderV3LiveValidationDetails(
        swiftBuild: swiftBuild,
        typeScriptBuild: typeScriptBuild,
        connectionState: status.state.rawValue,
        pendingMutationCount: pendingMutationCount
      )
    )
  }

  private static func liveClient(
    appID: String,
    apiURI: URL,
    websocketURI: URL,
    persistenceURL: URL?
  ) async throws -> InstantSwiftDataClient {
    try await withDependencies {
      $0.context = .live
      $0.instantLiveTransport = .live
      try await $0.bootstrapInstantSwiftData(
        appID: appID,
        apiURI: apiURI,
        websocketURI: websocketURI,
        persistenceURL: persistenceURL
          ?? FileManager.default.temporaryDirectory
          .appendingPathComponent("instant-app-builder-v3-live-\(UUID().uuidString).sqlite"),
        context: .live,
        initialAttributes: AppBuilderV3Schema.attributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client
      return client
    }
  }

  private static func authenticate(
    _ client: InstantSwiftDataClient,
    refreshToken: String,
    expectedUserID: String
  ) async throws {
    let session = try await client.signInWithRefreshToken(
      refreshToken,
      userID: "untrusted-app-builder-v3-user"
    )
    guard session.userID == expectedUserID else {
      throw failure(
        operation: "authenticate App Builder V3",
        message: "Server-verified App Builder user did not match the expected user."
      )
    }
    _ = try await client.connect()
    let deadline = ContinuousClock.now + .seconds(15)
    while ContinuousClock.now < deadline {
      if try await client.connectionStatus().state == .authenticated { return }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw failure(
      operation: "wait for App Builder V3 authentication",
      message: "The live client did not reach authenticated state."
    )
  }

  @MainActor
  private static func waitForBuild(
    id: String,
    builds: FetchAll<AppBuilderV3Build>,
    files: FetchAll<AppBuilderV3File>,
    expectedCode: String
  ) async throws -> InstantAppBuilderV3LiveBuildDetails {
    let deadline = ContinuousClock.now + .seconds(30)
    while ContinuousClock.now < deadline {
      if let build = builds.wrappedValue.first(where: { $0.id.rawValue == id }),
        build.code == expectedCode,
        build.isPreviewable == true,
        let fileID = build.file,
        let file = files.wrappedValue.first(where: { $0.id == fileID })
      {
        let contents = try await remoteContents(file)
        guard contents == expectedCode else {
          throw failure(
            operation: "verify App Builder V3 storage",
            message: "Linked file '\(file.path)' did not contain the build code."
          )
        }
        return InstantAppBuilderV3LiveBuildDetails(
          id: build.id.rawValue,
          instantAppID: build.instantAppID,
          code: build.code,
          reasoning: build.reasoning,
          isPreviewable: build.isPreviewable,
          title: build.title,
          ownerID: build.owner.rawValue,
          file: InstantAppBuilderV3LiveFileDetails(
            id: file.id.rawValue,
            path: file.path,
            url: file.url,
            contents: contents
          )
        )
      }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw failure(
      operation: "observe App Builder V3 build",
      message: "Timed out waiting for build '\(id)' and its linked file."
    )
  }

  private static func remoteContents(_ file: AppBuilderV3File) async throws -> String {
    guard let url = URL(string: file.url) else {
      throw failure(
        operation: "verify App Builder V3 storage",
        message: "The linked file URL was invalid."
      )
    }
    let (data, response) = try await URLSession.shared.data(from: url)
    guard let response = response as? HTTPURLResponse,
      (200..<300).contains(response.statusCode),
      let contents = String(data: data, encoding: .utf8)
    else {
      throw failure(
        operation: "verify App Builder V3 storage",
        message: "The linked file could not be downloaded as UTF-8 text."
      )
    }
    return contents
  }

  private static func milliseconds(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1_000).rounded())
  }

  private static func failure(operation: String, message: String) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: operation,
      message: message,
      recovery: "Inspect the App Builder V3 live contract, storage, schema, and permissions."
    )
  }
}
