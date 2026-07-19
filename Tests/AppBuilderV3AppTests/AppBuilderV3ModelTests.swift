import AppBuilderV3App
import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import InstantSwiftData
import Testing

@Suite
struct AppBuilderV3ModelTests {
  @Test @MainActor
  func generationCreatesStreamsUploadsAndFinishesTheBuild() async throws {
    let persistenceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("app-builder-v3-model-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: persistenceURL) }
    let ownerID = InstantID<AppBuilderV3User>(
      rawValue: "00000000-0000-4000-8000-000000000601"
    )
    let buildUUID = UUID(uuidString: "00000000-0000-4000-8000-000000000602")!
    let buildID = InstantID<AppBuilderV3Build>(rawValue: buildUUID.uuidString.lowercased())
    let ids = AppBuilderV3IDSequence([
      "00000000-0000-4000-8000-000000000610",
      "00000000-0000-4000-8000-000000000611",
      "00000000-0000-4000-8000-000000000612",
      "00000000-0000-4000-8000-000000000603",
      "00000000-0000-4000-8000-000000000613",
    ])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-builder-v3-model-tests",
        persistenceURL: persistenceURL,
        initialAttributes: AppBuilderV3Schema.attributes,
        makeID: { ids.next() }
      )
    )
    let client = InstantSwiftDataClient(runtime: runtime)
    _ = try await runtime.signInWithRefreshToken(
      "builder-refresh",
      userID: ownerID.rawValue
    )
    _ = try await runtime.transact(
      InstantStoreTransaction(
        id: "seed-owner",
        operations: [
          .insert(
            InstantTriple(
              entityID: ownerID.rawValue,
              attributeID: "$users/id",
              value: .string(ownerID.rawValue),
              txID: "seed-owner",
              txTime: InstantTimestamp(milliseconds: 1_700_000_000_000)
            )
          )
        ]
      ),
      createdAt: InstantTimestamp(milliseconds: 1_700_000_000_000)
    )

    let model = withDependencies {
      $0.defaultInstantSwiftData = client
      $0.date.now = Date(timeIntervalSince1970: 1_700_000_000)
      $0.uuid = .constant(buildUUID)
      $0.instantPlatformAppClient = InstantPlatformAppClient { request in
        InstantPlatformApp(
          id: "platform-app-1",
          title: request.title,
          orgID: request.orgID,
          createdAt: request.createdAt
        )
      }
      $0.appBuilderCodeGenerator = AppBuilderCodeGeneratorClient { _ in
        AsyncThrowingStream { continuation in
          continuation.yield(.init(kind: .reasoning, text: "Plan the screen."))
          continuation.yield(.init(kind: .code, text: "export default function App() {}"))
          continuation.finish()
        }
      }
    } operation: {
      AppBuilderV3Model(prompt: " Build a workout tracker ")
    }

    await model.generateButtonTapped(ownerID: ownerID, orgID: "org-1")

    expectNoDifference(model.isGenerating, false)
    expectNoDifference(model.message, "App ready")
    expectNoDifference(model.prompt, "")
    expectNoDifference(model.selectedBuildID, buildID)
    expectNoDifference(
      model.generatedFileID,
      InstantID(rawValue: "00000000-0000-4000-8000-000000000603")
    )
    expectNoDifference(model.reasoning, "Plan the screen.")
    expectNoDifference(model.code, "export default function App() {}")

    let build = try #require(try await client.query(AppBuilderV3Build.byID(buildID)).first)
    expectNoDifference(build.instantAppID, "platform-app-1")
    expectNoDifference(build.owner, ownerID)
    expectNoDifference(build.title, "Build a workout tracker")
    expectNoDifference(build.isPreviewable, true)
    expectNoDifference(build.reasoning, "Plan the screen.")
    expectNoDifference(build.code, "export default function App() {}")
    expectNoDifference(build.file, model.generatedFileID)

    let contents = try await client.storedFileContents(
      id: try #require(model.generatedFileID).rawValue
    )
    expectNoDifference(
      contents.file.name,
      AppBuilderExample.generatedCodeFileName(buildID: buildID.rawValue)
    )
    expectNoDifference(contents.file.contentType, "text/typescript")
    expectNoDifference(contents.file.ownerUserID, ownerID.rawValue)
    expectNoDifference(contents.data, Data(model.code.utf8))
  }
}

private final class AppBuilderV3IDSequence: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String]

  init(_ values: [String]) {
    self.values = values
  }

  func next() -> String {
    lock.lock()
    defer { lock.unlock() }
    return values.removeFirst()
  }
}
