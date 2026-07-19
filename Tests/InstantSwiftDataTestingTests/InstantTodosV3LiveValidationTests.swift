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

  @Test
  func sessionEvidenceDecodesViewerAndOfflineReplay() throws {
    let data = Data(
      #"{"roomType":"todos","roomID":"main","peerCount":1,"pendingWhileOffline":1,"online":{"direction":"swift-to-typescript","id":"00000000-0000-4000-8000-000000000001","text":"Swift live todo","isCompleted":true,"createdAtMilliseconds":1700000000000,"connectionState":"authenticated","pendingMutationCount":0},"offline":{"direction":"swift-offline-to-typescript","id":"00000000-0000-4000-8000-000000000002","text":"Swift offline todo","isCompleted":false,"createdAtMilliseconds":1700000002000,"connectionState":"authenticated","pendingMutationCount":0}}"#.utf8
    )
    let details = try JSONDecoder().decode(
      InstantTodosV3SessionValidationDetails.self,
      from: data
    )

    expectNoDifference(details.roomType, "todos")
    expectNoDifference(details.roomID, "main")
    expectNoDifference(details.peerCount, 1)
    expectNoDifference(details.pendingWhileOffline, 1)
    expectNoDifference(details.online.isCompleted, true)
    expectNoDifference(details.offline.direction, "swift-offline-to-typescript")
    expectNoDifference(details.offline.pendingMutationCount, 0)
    expectNoDifference(details.performance, nil)
  }

  @Test
  func sessionEvidenceDecodesLiveActorHopMeasurements() throws {
    let data = Data(
      #"{"roomType":"todos","roomID":"main","peerCount":1,"pendingWhileOffline":1,"performance":{"authenticateAndConnect":{"durationNanoseconds":100,"actorHopCount":3,"actorHopBreakdown":{"live-session":1,"operation-gate":2}},"acceptedMutations":{"durationNanoseconds":200,"actorHopCount":4,"actorHopBreakdown":{"live-session":2,"persistence":2}},"offlineEnqueue":{"durationNanoseconds":300,"actorHopCount":5,"actorHopBreakdown":{"operation-gate":2,"outbox":1,"persistence":2}},"reconnectDrain":{"durationNanoseconds":400,"actorHopCount":6,"actorHopBreakdown":{"live-session":2,"operation-gate":2,"persistence":2}}},"online":{"direction":"swift-to-typescript","id":"one","text":"online","isCompleted":true,"createdAtMilliseconds":1,"connectionState":"authenticated","pendingMutationCount":0},"offline":{"direction":"swift-offline-to-typescript","id":"two","text":"offline","isCompleted":false,"createdAtMilliseconds":2,"connectionState":"authenticated","pendingMutationCount":0}}"#.utf8
    )

    let details = try JSONDecoder().decode(
      InstantTodosV3SessionValidationDetails.self,
      from: data
    )
    let performance = try #require(details.performance)
    expectNoDifference(performance.authenticateAndConnect.actorHopCount, 3)
    expectNoDifference(
      performance.authenticateAndConnect.actorHopBreakdown,
      ["live-session": 1, "operation-gate": 2]
    )
    expectNoDifference(performance.acceptedMutations.durationNanoseconds, 200)
    expectNoDifference(performance.offlineEnqueue.actorHopCount, 5)
    expectNoDifference(performance.reconnectDrain.actorHopCount, 6)
  }
}
