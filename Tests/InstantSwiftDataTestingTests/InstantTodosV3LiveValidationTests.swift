import CustomDump
import Foundation
import InstantSwiftDataTesting
import Testing

@Suite
struct InstantTodosV3LiveValidationTests {
  @Test
  func evidenceDecodesTheExactAppTodoShape() throws {
    let data = Data(
      #"{"direction":"swift-to-typescript","id":"todos-v3-swift","text":"Swift live todo","isCompleted":true,"createdAtMilliseconds":1700000000000,"connectionState":"authenticated","pendingMutationCount":0}"#.utf8
    )
    let details = try JSONDecoder().decode(
      InstantTodosV3LiveValidationDetails.self,
      from: data
    )

    expectNoDifference(details.direction, "swift-to-typescript")
    expectNoDifference(details.id, "todos-v3-swift")
    expectNoDifference(details.text, "Swift live todo")
    expectNoDifference(details.isCompleted, true)
    expectNoDifference(details.createdAtMilliseconds, 1_700_000_000_000)
    expectNoDifference(details.connectionState, "authenticated")
    expectNoDifference(details.pendingMutationCount, 0)
  }
}
