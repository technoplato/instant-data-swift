import CustomDump
import Foundation
import InstantSwiftDataCore
import Testing

extension InstantStoreTests {
  @Test
  func localEphemeralAppTrimsTitleAndMarksLocalTransport() throws {
    let app = try InstantEphemeralApps.makeLocal(
      title: "  Reminders Port  ",
      createdAt: InstantTimestamp(milliseconds: 1_234),
      makeID: "APP-1"
    )

    expectNoDifference(
      app,
      InstantEphemeralApp(
        appID: "local-ephemeral-app-1",
        title: "Reminders Port",
        createdAt: InstantTimestamp(milliseconds: 1_234),
        isLocalOnly: true,
        transport: "local-cache-only"
      )
    )

    do {
      _ = try InstantEphemeralApps.makeLocal(title: "   ")
      #expect(Bool(false), "Expected empty local ephemeral app titles to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "create local ephemeral app")
    }
  }
}
