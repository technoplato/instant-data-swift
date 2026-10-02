import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// Transport dates go through one shared formatter (#403). It writes exactly what the per-value formatter wrote, and
/// that is what @instantdb/core puts on the wire.
struct InstantTransportDateFormatterTests {
  /// `validation/fixtures/transport-date-encoding.json` holds the core's own output: an update through its transform,
  /// stringified as `Connection.send` does (`validation/ts-runner/src/transport-date-encoding-fixture.ts`, core 1.0.49).
  @Test
  func transportDatesMatchTheTypeScriptCoresWireEncoding() throws {
    let fixture = try JSONDecoder().decode(
      TransportDateFixture.self,
      from: Data(contentsOf: packageRootURL().appendingPathComponent(
        "validation/fixtures/transport-date-encoding.json"
      ))
    )
    #expect(fixture.entries.count == 79)
    expectNoDifference(
      fixture.entries.map { entry in
        InstantTransportValue(
          InstantValue.date(Date(timeIntervalSince1970: Double(entry.milliseconds) / 1_000))
        )
      },
      fixture.entries.map { InstantTransportValue.string($0.encoded) }
    )
  }

  /// Byte-identical to the formatter each value used to create, sub-millisecond rounding included.
  @Test
  func sharedFormatterMatchesAFreshFormatter() {
    var dates: [Date] = [
      Date(timeIntervalSince1970: 0),
      Date(timeIntervalSince1970: 1_700_000_000.0005),
      Date(timeIntervalSince1970: 1_700_000_000.9995),
      Date(timeIntervalSince1970: 1_700_000_000.12345),
      Date(timeIntervalSince1970: -1.25),
    ]
    var state: UInt64 = 0x9E37_79B9_7F4A_7C15
    for _ in 0..<2_000 {
      state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      dates.append(Date(timeIntervalSince1970: Double(state % 4_102_444_800_000_000) / 1_000_000))
    }
    let fresh = ISO8601DateFormatter()
    fresh.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    expectNoDifference(
      dates.map(InstantTransportDateFormatter.shared.string(from:)),
      dates.map(fresh.string(from:))
    )
  }

  @Test
  func concurrentCallersGetWholeStrings() async {
    let date = Date(timeIntervalSince1970: 1_700_000_000.456)
    let expected = InstantTransportDateFormatter.shared.string(from: date)
    let results = await withTaskGroup(of: [String].self) { group in
      for _ in 0..<16 {
        group.addTask { (0..<200).map { _ in InstantTransportDateFormatter.shared.string(from: date) } }
      }
      var all: [String] = []
      for await batch in group { all.append(contentsOf: batch) }
      return all
    }
    expectNoDifference(results.count, 3_200)
    expectNoDifference(Set(results), [expected])
  }
}

private struct TransportDateFixture: Decodable {
  struct Entry: Decodable {
    var milliseconds: Int64
    var encoded: String
  }

  var entries: [Entry]
}

private func packageRootURL(filePath: String = #filePath) -> URL {
  URL(fileURLWithPath: filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
}
