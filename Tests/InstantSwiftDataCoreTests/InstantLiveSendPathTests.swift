// History
// 2026-10-31  #1492  Created. The wire encoder built an index of every server attribute (2,283 on a phone) for every
//                    mutation it sent: about 1.2 ms of CPU a send on a Mac mini, 2-3 ms on a phone, on the live session
//                    actor. The attributes change only with init-ok or a refresh-ok that carries them.

import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

@Suite
struct InstantLiveSendPathTests {
  /// One resolver per server schema (#1492): a hundred sends on one connection build the attribute index once, and
  /// each still goes out with the server's attribute ids.
  @Test
  func aConnectionBuildsItsAttributeResolverOnceForEverySend() async throws {
    let wire = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: Self.attributes)])
    let live = InstantRuntimeLiveSession()
    try await live.open(
      request: InstantLiveSessionRequest(appID: "live-send-path-resolver"),
      transport: wire.transport,
      makeID: { UUID().uuidString.lowercased() }
    )

    for index in 0..<100 {
      let mutation = Self.lineWrite(index)
      try await live.sendMutations([mutation], claimToken: nil)
      // The server's answer, as the runtime records it, so the in-flight window never fills.
      await live.releaseMutationReservations([mutation.mutationID], timedOut: false)
    }

    let transacts = await wire.sentMessages().filter { $0.op == "transact" }
    // Counts use #expect: IssueReporting records nothing in release, where expectNoDifference passes silently.
    #expect(transacts.count == 100)
    expectNoDifference(
      transacts.last?.fields["tx-steps"],
      .array([
        .array([.string("add-triple"), .string("line-99"), .string("server-attr-41"), .string("line 99")]),
        .array([.string("add-triple"), .string("line-99"), .string("server-attr-2282"), .number(99)]),
      ])
    )
    let resolverBuilds = await live.attributeResolverBuildCountForTesting()
    #expect(resolverBuilds == 1)
    await live.close()
  }

  /// A real-size schema: 2,283 attributes, as a phone's init-ok carries (`RealSizeFixture`), across 41 namespaces.
  static let attributes: [InstantLiveJSONValue] = (0..<2_283).map { index in
    liveReactorServerAttr(
      id: "server-attr-\(index)",
      name: "field\(index)",
      namespace: "namespace\(index % 41)"
    )
  }

  /// A transcript line's write, naming two of the schema's attributes by their local `namespace/name`.
  static func lineWrite(_ index: Int) -> InstantTransportMutation {
    InstantTransportMutation(
      mutationID: "mutation-\(index)",
      transactionID: "transaction-\(index)",
      createdAt: InstantTimestamp(milliseconds: 1_793_400_000_000 + Int64(index)),
      status: .pending,
      preconditions: [],
      txSteps: [
        .addTriple(entity: .id("line-\(index)"), attributeID: "namespace0/field41", value: .string("line \(index)")),
        .addTriple(entity: .id("line-\(index)"), attributeID: "namespace27/field2282", value: .number(Double(index))),
      ]
    )
  }
}

extension ContentionHarness {
  /// What the library's energy meter measured over an exercise's window (#1492): each operation that ran, its count, its
  /// CPU, and its CPU per call, so a send's encode or an acknowledgement's CPU is read from the same run as the gate's.
  func reportEnergy(_ exercise: String, _ energy: InstantEnergySnapshot) {
    for operation in InstantEnergyOperation.allCases {
      let measure = energy[operation]
      guard measure.count > 0 else { continue }
      let cpuMilliseconds = Double(measure.cpuNanoseconds) / 1_000_000
      printFields(exercise, "energy", [
        ("op", operation.rawValue),
        ("n", String(measure.count)),
        ("cpu_ms", ContentionReport.milliseconds(cpuMilliseconds)),
        ("cpu_per_call_us", String(format: "%.1f", cpuMilliseconds * 1_000 / Double(measure.count))),
        ("wall_ms", ContentionReport.milliseconds(Double(measure.wallNanoseconds) / 1_000_000)),
      ])
    }
  }
}
