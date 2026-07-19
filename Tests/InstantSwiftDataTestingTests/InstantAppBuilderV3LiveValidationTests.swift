import CustomDump
import Foundation
import InstantSwiftDataTesting
import Testing

@Suite
struct InstantAppBuilderV3LiveValidationTests {
  @Test
  func evidencePreservesBuildLinksAndDownloadedFileContents() throws {
    let json = Data(
      #"{"swiftBuild":{"id":"00000000-0000-4000-8000-000000000602","instantAppID":"platform-app-swift","code":"export default function SwiftGeneratedApp() {}","reasoning":"Plan the Swift-generated screen.","isPreviewable":true,"title":"Build a workout tracker","ownerID":"00000000-0000-4000-8000-000000000601","file":{"id":"server-file-1","path":"00000000-0000-4000-8000-000000000602-App.tsx","url":"https://files.example/swift","contents":"export default function SwiftGeneratedApp() {}"}},"typeScriptBuild":{"id":"00000000-0000-4000-8000-000000000604","instantAppID":"platform-app-typescript","code":"export default function TypeScriptGeneratedApp() {}","reasoning":"Plan the TypeScript-generated screen.","isPreviewable":true,"title":"Build a notes app","ownerID":"00000000-0000-4000-8000-000000000601","file":{"id":"server-file-2","path":"00000000-0000-4000-8000-000000000604-App.tsx","url":"https://files.example/typescript","contents":"export default function TypeScriptGeneratedApp() {}"}},"connectionState":"authenticated","pendingMutationCount":0}"#.utf8
    )

    let details = try JSONDecoder().decode(
      InstantAppBuilderV3LiveValidationDetails.self,
      from: json
    )

    expectNoDifference(
      details.swiftBuild.id,
      InstantAppBuilderV3LiveValidation.swiftBuildID
    )
    expectNoDifference(details.swiftBuild.file?.id, "server-file-1")
    expectNoDifference(details.swiftBuild.file?.contents, details.swiftBuild.code)
    expectNoDifference(
      details.typeScriptBuild.id,
      InstantAppBuilderV3LiveValidation.typeScriptBuildID
    )
    expectNoDifference(details.typeScriptBuild.file?.id, "server-file-2")
    expectNoDifference(details.typeScriptBuild.file?.contents, details.typeScriptBuild.code)
    expectNoDifference(details.connectionState, "authenticated")
    expectNoDifference(details.pendingMutationCount, 0)
  }
}
