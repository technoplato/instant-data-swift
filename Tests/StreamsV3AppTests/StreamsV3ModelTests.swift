import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import InstantSwiftData
import StreamsV3App
import Testing

@Suite(.serialized)
struct StreamsV3ModelTests {
  @Test @MainActor
  func writeAndResumeUseServerStyleIDsAndUTF8ByteOffsets() async throws {
    let persistenceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("streams-v3-model-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: persistenceURL) }
    let ids = StreamsV3IDSequence([
      "00000000-0000-0000-0000-000000000300",
      "00000000-0000-0000-0000-000000000301",
      "00000000-0000-0000-0000-000000000302",
      "00000000-0000-0000-0000-000000000303",
      "00000000-0000-0000-0000-000000000304",
      "00000000-0000-0000-0000-000000000305",
      "00000000-0000-0000-0000-000000000306",
      "00000000-0000-0000-0000-000000000307",
      "00000000-0000-0000-0000-000000000308",
    ])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "streams-v3-model-tests",
        persistenceURL: persistenceURL,
        makeID: { ids.next() }
      )
    )
    _ = try await runtime.signInAsGuest()
    let client = InstantSwiftDataClient(runtime: runtime)
    let model = withDependencies {
      $0.defaultInstantSwiftData = client
    } operation: {
      StreamsV3Model(clientID: "chat-1")
    }

    var completed: InstantStreamMetadata?
    await model.write(["hello ", "🚀"]) { completed = $0 }

    expectNoDifference(model.status, "Complete")
    expectNoDifference(model.streamID, "00000000-0000-0000-0000-000000000302")
    expectNoDifference(completed?.size, 10)
    model.resume()
    for _ in 0..<100 where !model.isDone {
      await Task.yield()
    }
    expectNoDifference(model.content, "hello 🚀")
    expectNoDifference(model.byteCount, 10)
    expectNoDifference(model.isDone, true)
    expectNoDifference(model.status, "Complete")
  }
}

private final class StreamsV3IDSequence: @unchecked Sendable {
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
