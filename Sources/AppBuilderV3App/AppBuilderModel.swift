import Dependencies
import Foundation
import InstantSwiftData
import Observation

@MainActor
@Observable
public final class AppBuilderV3Model {
  public var prompt: String
  public var isGenerating = false
  public var message = "Ready"
  public private(set) var selectedBuildID: InstantID<AppBuilderV3Build>?
  public private(set) var generatedFileID: InstantID<AppBuilderV3File>?
  public private(set) var code = ""
  public private(set) var reasoning = ""

  @ObservationIgnored @Dependency(\.appBuilderCodeGenerator)
  private var codeGenerator
  @ObservationIgnored @Dependency(\.date.now) private var now
  @ObservationIgnored @Dependency(\.defaultInstantSwiftData) private var db
  @ObservationIgnored @Dependency(\.instantPlatformAppClient) private var platformAppClient
  @ObservationIgnored @Dependency(\.uuid) private var uuid

  public init(prompt: String = "Build a Tic Tac Toe game") {
    self.prompt = prompt
  }

  public func generateButtonTapped(
    ownerID: InstantID<AppBuilderV3User>,
    orgID: String = AppBuilderExample.defaultOrgID
  ) async {
    let requestedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !requestedPrompt.isEmpty, !isGenerating else { return }

    isGenerating = true
    message = "Creating build"
    code = ""
    reasoning = ""
    generatedFileID = nil
    defer { isGenerating = false }

    let buildID = InstantID<AppBuilderV3Build>(
      rawValue: uuid().uuidString.lowercased()
    )
    let title = AppBuilderExample.friendlyTitle(for: requestedPrompt)

    do {
      let platformApp = try await platformAppClient.createApp(
        InstantPlatformAppCreateRequest(
          title: title,
          orgID: orgID,
          createdAt: InstantTimestamp(
            milliseconds: Int64((now.timeIntervalSince1970 * 1_000).rounded())
          ),
          makeID: { buildID.rawValue }
        )
      )
      try await transact(
        CreateAppBuilderV3Build(
          buildID: buildID,
          ownerID: ownerID,
          instantAppID: platformApp.id,
          title: title
        )
      )
      selectedBuildID = buildID
      message = "Generating app"

      let stream = try await codeGenerator.generate(
        AppBuilderGenerationRequest(
          prompt: requestedPrompt,
          buildID: buildID.rawValue,
          instantAppID: platformApp.id
        )
      )
      for try await chunk in stream {
        switch chunk.kind {
        case .code:
          code += chunk.text
        case .reasoning:
          reasoning += chunk.text
        }
        try await transact(
          UpdateAppBuilderV3Build(
            buildID: buildID,
            code: code,
            reasoning: reasoning,
            isPreviewable: false
          )
        )
      }

      let file = try await uploadGeneratedCode(buildID: buildID)
      let fileID = InstantID<AppBuilderV3File>(rawValue: file.id)
      do {
        try await transact(
          UpdateAppBuilderV3Build(
            buildID: buildID,
            code: code,
            reasoning: reasoning,
            isPreviewable: true,
            fileID: fileID
          )
        )
      } catch {
        _ = try? await db.deleteStoredFile(id: file.id)
        throw error
      }
      generatedFileID = fileID
      prompt = ""
      message = "App ready"
    } catch let error as InstantError {
      message = error.recoveryMessage
    } catch {
      message = String(describing: error)
    }
  }

  private func transact<Message: InstantMessage>(_ message: Message) async throws {
    let prepared = try await message.prepare(using: db)
    _ = try await db.transact {
      for mutation in prepared.mutations { mutation }
    }
  }

  private func uploadGeneratedCode(
    buildID: InstantID<AppBuilderV3Build>
  ) async throws -> InstantStoredFile {
    let name = AppBuilderExample.generatedCodeFileName(buildID: buildID.rawValue)
    let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(name)
    defer { try? FileManager.default.removeItem(at: sourceURL) }
    try Data(code.utf8).write(to: sourceURL, options: .atomic)
    return try await db.uploadFile(
      from: sourceURL,
      name: name,
      contentType: AppBuilderExample.generatedCodeContentType
    )
  }
}
