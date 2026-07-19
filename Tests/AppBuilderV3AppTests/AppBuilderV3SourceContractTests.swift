import AppBuilderV3App
import CustomDump
import InstantSwiftData
import Testing

@Suite
struct AppBuilderV3SourceContractTests {
  @Test
  func typedEntitiesAndQueriesPreserveThePinnedContract() {
    let ownerID = InstantID<AppBuilderV3User>(rawValue: "user-1")
    let buildID = InstantID<AppBuilderV3Build>(rawValue: "build-1")
    let ownerBuilds = FetchAll(AppBuilderV3Build.forOwner(ownerID))
    let detail = FetchOne(AppBuilderV3Build.byID(buildID))
    let files = FetchAll(AppBuilderV3File.ordered)

    _ = ownerBuilds
    _ = detail
    _ = files
    _ = AppBuilderV3Build.Draft(
      instantAppID: "generated-app-1",
      code: "export default function App() {}",
      owner: ownerID
    )
  }

  @Test
  func entityMetadataPreservesSourceFieldsAndStorageAdaptation() {
    expectNoDifference(AppBuilderV3User.instantNamespace, "$users")
    expectNoDifference(AppBuilderV3File.instantNamespace, "$files")
    expectNoDifference(AppBuilderV3Build.instantNamespace, "builds")
    expectNoDifference(
      AppBuilderV3File.instantAttributes.map(\.name),
      ["id", "path", "url"]
    )
    expectNoDifference(
      AppBuilderV3Build.instantAttributes.map(\.name),
      [
        "id", "instantAppId", "code", "reasoning", "slug", "error",
        "isPreviewable", "title", "file", "owner",
      ]
    )
    expectNoDifference(
      AppBuilderV3Build.instantAttributes.filter { $0.valueType == .ref }.map(\.name),
      ["file", "owner"]
    )
    expectNoDifference(
      AppBuilderV3Build.instantAttributes.first { $0.name == "owner" }?.isRequired,
      true
    )
    expectNoDifference(
      AppBuilderV3Build.instantAttributes.first { $0.name == "file" }?.isRequired,
      false
    )
  }

  @Test
  func buildErrorPreservesTheExactJSONShape() throws {
    let error = AppBuilderV3BuildError(
      from: "openai",
      status: 429,
      message: "Rate limited"
    )
    expectNoDifference(
      error.instantValue,
      .json(
        .object([
          "from": .string("openai"),
          "status": .number(429),
          "message": .string("Rate limited"),
        ])
      )
    )
    expectNoDifference(
      try AppBuilderV3BuildError.decodeInstantValue(
        error.instantValue,
        namespace: "builds",
        path: "error",
        localID: "build-1",
        operation: "test"
      ),
      error
    )
  }
}
