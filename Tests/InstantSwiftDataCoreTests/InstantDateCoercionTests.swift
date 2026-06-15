import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

@Suite
struct InstantDateCoercionTests {
  @Test
  func upstreamCoerceToDateParsesValidDateStrings() throws {
    for testCase in upstreamCoerceToDateValidStringCases {
      let date = try #require(
        InstantDateCoercion.coerce(.string(testCase.input)),
        "\(testCase.sourceFile) \(testCase.sourceTestName): \(testCase.input)"
      )
      expectNoDifference(
        isoString(date),
        testCase.expectedISOString,
        "\(testCase.sourceFile) \(testCase.sourceTestName): \(testCase.input)"
      )
    }
  }

  @Test
  func upstreamCoerceToDateRejectsInvalidDateStrings() {
    for testCase in upstreamCoerceToDateInvalidStringCases {
      expectNoDifference(
        InstantDateCoercion.coerce(.string(testCase.input)),
        nil,
        "\(testCase.sourceFile) \(testCase.sourceTestName): \(testCase.input)"
      )
    }
  }

  @Test
  func upstreamCoerceToDateHandlesDateAndNumberInputs() throws {
    let date = try #require(InstantDateCoercion.parse("2025-01-15T10:30:00Z"))
    let coercedDate = try #require(InstantDateCoercion.coerce(.date(date)))
    expectNoDifference(
      isoString(coercedDate),
      "2025-01-15T10:30:00.000Z",
      "upstream/instant/client/packages/core/__tests__/src/utils/dates.test.ts "
        + "additional edge cases: should handle Date instances"
    )

    let timestamp = 1_642_234_800_000.0
    let timestampDate = try #require(InstantDateCoercion.coerce(.number(timestamp)))
    expectNoDifference(
      Int64((timestampDate.timeIntervalSince1970 * 1000).rounded()),
      Int64(timestamp),
      "upstream/instant/client/packages/core/__tests__/src/utils/dates.test.ts "
        + "additional edge cases: should handle number timestamps"
    )
  }

  @Test
  func upstreamCoerceToDateRejectsUnsupportedTypes() {
    let source =
      "upstream/instant/client/packages/core/__tests__/src/utils/dates.test.ts "
      + "additional edge cases: should throw for unsupported types"
    expectNoDifference(InstantDateCoercion.coerce(.bool(true)), nil, source)
    expectNoDifference(InstantDateCoercion.coerce(.json(.object([:]))), nil, source)
    expectNoDifference(InstantDateCoercion.coerce(.null), nil, source)
  }
}

private struct DateParityCase {
  var input: String
  var expectedISOString: String
  var sourceFile: String
  var sourceTestName: String
}

private struct InvalidDateParityCase {
  var input: String
  var sourceFile: String
  var sourceTestName: String
}

private let upstreamDateTestSource =
  "upstream/instant/client/packages/core/__tests__/src/utils/dates.test.ts"

private func validDateCase(_ input: String, _ expectedISOString: String) -> DateParityCase {
  DateParityCase(
    input: input,
    expectedISOString: expectedISOString,
    sourceFile: upstreamDateTestSource,
    sourceTestName: "should parse \(input) to \(expectedISOString)"
  )
}

private let upstreamCoerceToDateValidStringCases: [DateParityCase] = [
  validDateCase("Sat, 05 Apr 2025 18:00:31 GMT", "2025-04-05T18:00:31.000Z"),
  validDateCase("2025-01-01T00:00:00Z", "2025-01-01T00:00:00.000Z"),
  validDateCase("2025-01-01", "2025-01-01T00:00:00.000Z"),
  validDateCase("2025-01-02T00:00:00-08", "2025-01-02T08:00:00.000Z"),
  validDateCase("2025-11-2T00:00:00.000Z", "2025-11-02T00:00:00.000Z"),
  validDateCase("2025-1-2T00:00:00.000Z", "2025-01-02T00:00:00.000Z"),
  validDateCase("2025-9-29T23:59:59.999Z", "2025-09-29T23:59:59.999Z"),
  validDateCase("2025-1-2 00:00:00", "2025-01-02T00:00:00.000Z"),
  validDateCase("\"2025-01-02T00:00:00-08\"", "2025-01-02T08:00:00.000Z"),
  validDateCase("2025-01-15 20:53:08.200", "2025-01-15T20:53:08.200Z"),
  validDateCase("2025-01-15 20:53:08.892865", "2025-01-15T20:53:08.892Z"),
  validDateCase("\"2025-01-15 20:53:08\"", "2025-01-15T20:53:08.000Z"),
  validDateCase("Wed Jul 09 2025", "2025-07-09T00:00:00.000Z"),
  validDateCase("8/4/2025, 11:02:31 PM", "2025-08-04T23:02:31.000Z"),
  validDateCase("2024-12-30 20:19:41.892865+00", "2024-12-30T20:19:41.892Z"),
  validDateCase("epoch", "1970-01-01T00:00:00.000Z"),
  validDateCase("Mon Feb 24 2025 22:37:27 GMT+0000", "2025-02-24T22:37:27.000Z"),
  validDateCase("\t2025-03-02T16:08:53Z", "2025-03-02T16:08:53.000Z"),
  validDateCase("2024-05-29 01:51:06.11848+00", "2024-05-29T01:51:06.118Z"),
  validDateCase("2025-03-01T16:08:53+0000", "2025-03-01T16:08:53.000Z"),
  validDateCase("2025-12-31 21:11", "2025-12-31T21:11:00.000Z"),
  validDateCase("04-17-2025", "2025-04-17T00:00:00.000Z"),
  validDateCase("2025-06-12T10:56:31.924+0530", "2025-06-12T05:26:31.924Z"),
  validDateCase("72026-07-01", "+072026-07-01T00:00:00.000Z"),
  validDateCase("2025-06-05T17:00:00EST", "2025-06-05T22:00:00.000Z"),
  validDateCase("2025-06-05T17:00:00PDT", "2025-06-06T00:00:00.000Z"),
  validDateCase("2025-06-05T17:00:00CETDST", "2025-06-05T15:00:00.000Z"),
  validDateCase("2025-06-05T17:00:00CET", "2025-06-05T16:00:00.000Z"),
  validDateCase("2026-04-28T04:7:00.000Z", "2026-04-28T04:07:00.000Z"),
  validDateCase("2026-04-28T4:07:00.000Z", "2026-04-28T04:07:00.000Z"),
  validDateCase("2026-04-28T04:07:7.000Z", "2026-04-28T04:07:07.000Z"),
]

private let upstreamCoerceToDateInvalidStringCases: [InvalidDateParityCase] = [
  "2025-01-0",
  "\"2025-01-0\"",
].map {
  InvalidDateParityCase(
    input: $0,
    sourceFile: upstreamDateTestSource,
    sourceTestName: "throws for invalid date string: \($0)"
  )
}

private let utcCalendar: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0)!
  return calendar
}()

private func isoString(_ date: Date) -> String {
  let milliseconds = Int64((date.timeIntervalSince1970 * 1000).rounded())
  let roundedDate = Date(timeIntervalSince1970: Double(milliseconds) / 1000)
  let components = utcCalendar.dateComponents(
    [.year, .month, .day, .hour, .minute, .second],
    from: roundedDate
  )
  let year = components.year ?? 0
  let yearString =
    year > 9999
    ? "+\(String(format: "%06d", year))"
    : String(format: "%04d", year)
  return "\(yearString)-\(pad(components.month ?? 0, to: 2))"
    + "-\(pad(components.day ?? 0, to: 2))"
    + "T\(pad(components.hour ?? 0, to: 2))"
    + ":\(pad(components.minute ?? 0, to: 2))"
    + ":\(pad(components.second ?? 0, to: 2))"
    + ".\(pad(Int(milliseconds % 1_000), to: 3))Z"
}

private func pad(_ value: Int, to width: Int) -> String {
  let string = String(value)
  guard string.count < width else { return string }
  return String(repeating: "0", count: width - string.count) + string
}
