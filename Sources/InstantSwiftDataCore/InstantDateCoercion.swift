import Foundation

enum InstantDateCoercion {
  private static let gregorianUTC: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }()

  private static let pgTimezoneOffsets: [String: TimeInterval] = [
    "ACDT": 37_800,
    "ACSST": 37_800,
    "ACST": 34_200,
    "ACT": -18_000,
    "ACWST": 31_500,
    "ADT": -10_800,
    "AEDT": 39_600,
    "AESST": 39_600,
    "AEST": 36_000,
    "AFT": 16_200,
    "AKDT": -28_800,
    "AKST": -32_400,
    "ALMST": 25_200,
    "ALMT": 21_600,
    "AMST": 14_400,
    "AMT": -14_400,
    "ANAST": 43_200,
    "ANAT": 43_200,
    "ARST": -10_800,
    "ART": -10_800,
    "AST": -14_400,
    "AWSST": 32_400,
    "AWST": 28_800,
    "AZOST": 0,
    "AZOT": -3_600,
    "AZST": 14_400,
    "AZT": 14_400,
    "BDST": 7_200,
    "BDT": 21_600,
    "BNT": 28_800,
    "BORT": 28_800,
    "BOT": -14_400,
    "BRA": -10_800,
    "BRST": -7_200,
    "BRT": -10_800,
    "BST": 3_600,
    "BTT": 21_600,
    "CADT": 37_800,
    "CAST": 34_200,
    "CCT": 28_800,
    "CDT": -18_000,
    "CEST": 7_200,
    "CET": 3_600,
    "CETDST": 7_200,
    "CHADT": 49_500,
    "CHAST": 45_900,
    "CHUT": 36_000,
    "CKT": -36_000,
    "CLST": -10_800,
    "CLT": -14_400,
    "COT": -18_000,
    "CST": -21_600,
    "CXT": 25_200,
    "DAVT": 25_200,
    "DDUT": 36_000,
    "EASST": -21_600,
    "EAST": -21_600,
    "EAT": 10_800,
    "EDT": -14_400,
    "EEST": 10_800,
    "EET": 7_200,
    "EETDST": 10_800,
    "EGST": 0,
    "EGT": -3_600,
    "EST": -18_000,
    "FET": 10_800,
    "FJST": 46_800,
    "FJT": 43_200,
    "FKST": -10_800,
    "FKT": -10_800,
    "FNST": -3_600,
    "FNT": -7_200,
    "GALT": -21_600,
    "GAMT": -32_400,
    "GEST": 14_400,
    "GET": 14_400,
    "GFT": -10_800,
    "GILT": 43_200,
    "GMT": 0,
    "GYT": -14_400,
    "HKT": 28_800,
    "HST": -36_000,
    "ICT": 25_200,
    "IDT": 10_800,
    "IOT": 21_600,
    "IRKST": 28_800,
    "IRKT": 28_800,
    "IRT": 12_600,
    "IST": 7_200,
    "JAYT": 32_400,
    "JST": 32_400,
    "KDT": 36_000,
    "KGST": 21_600,
    "KGT": 21_600,
    "KOST": 39_600,
    "KRAST": 25_200,
    "KRAT": 25_200,
    "KST": 32_400,
    "LHDT": 37_800,
    "LHST": 37_800,
    "LIGT": 36_000,
    "LINT": 50_400,
    "LKT": 19_800,
    "MAGST": 39_600,
    "MAGT": 39_600,
    "MART": -34_200,
    "MAWT": 18_000,
    "MDT": -21_600,
    "MEST": 7_200,
    "MESZ": 7_200,
    "MET": 3_600,
    "METDST": 7_200,
    "MEZ": 3_600,
    "MHT": 43_200,
    "MMT": 23_400,
    "MPT": 36_000,
    "MSD": 14_400,
    "MSK": 10_800,
    "MST": -25_200,
    "MUST": 18_000,
    "MUT": 14_400,
    "MVT": 18_000,
    "MYT": 28_800,
    "NDT": -9_000,
    "NFT": -12_600,
    "NOVST": 25_200,
    "NOVT": 25_200,
    "NPT": 20_700,
    "NST": -12_600,
    "NUT": -39_600,
    "NZDT": 46_800,
    "NZST": 43_200,
    "NZT": 43_200,
    "OMSST": 21_600,
    "OMST": 21_600,
    "PDT": -25_200,
    "PET": -18_000,
    "PETST": 43_200,
    "PETT": 43_200,
    "PGT": 36_000,
    "PHT": 28_800,
    "PKST": 21_600,
    "PKT": 18_000,
    "PMDT": -7_200,
    "PMST": -10_800,
    "PONT": 39_600,
    "PST": -28_800,
    "PWT": 32_400,
    "PYST": -10_800,
    "PYT": -14_400,
    "RET": 14_400,
    "SADT": 37_800,
    "SAST": 7_200,
    "SCT": 14_400,
    "SGT": 28_800,
    "TAHT": -36_000,
    "TFT": 18_000,
    "TJT": 18_000,
    "TKT": 46_800,
    "TMT": 18_000,
    "TOT": 46_800,
    "TRUT": 36_000,
    "TVT": 43_200,
    "UCT": 0,
    "ULAST": 32_400,
    "ULAT": 28_800,
    "UT": 0,
    "UTC": 0,
    "UYST": -7_200,
    "UYT": -10_800,
    "UZST": 21_600,
    "UZT": 18_000,
    "VET": -14_400,
    "VLAST": 36_000,
    "VLAT": 36_000,
    "VOLT": 10_800,
    "VUT": 39_600,
    "WADT": 28_800,
    "WAKT": 43_200,
    "WAST": 25_200,
    "WAT": 3_600,
    "WDT": 32_400,
    "WET": 0,
    "WETDST": 3_600,
    "WFT": 43_200,
    "WGST": -7_200,
    "WGT": -10_800,
    "XJT": 21_600,
    "YAKST": 32_400,
    "YAKT": 32_400,
    "YAPT": 36_000,
    "YEKST": 21_600,
    "YEKT": 18_000,
    "ZULU": 0,
  ]

  static func coerce(_ value: InstantValue) -> Date? {
    switch value {
    case let .date(date):
      return date
    case let .number(milliseconds):
      guard milliseconds.isFinite else { return nil }
      return Date(timeIntervalSince1970: milliseconds / 1000)
    case let .string(string):
      return parse(string)
    case .null, .bool, .json, .ref, .lookupRef:
      return nil
    }
  }

  static func parse(_ rawValue: String) -> Date? {
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }

    if value == "epoch" {
      return Date(timeIntervalSince1970: 0)
    }

    if
      let data = value.data(using: .utf8),
      let decoded = try? JSONDecoder().decode(String.self, from: data),
      decoded != value
    {
      return parse(decoded)
    }

    if value.firstMatch(#"^[0-9./-]+$"#) != nil {
      return parseLocalDate(value)
    }
    if let date = parseDateFormat("EEE MMM dd yyyy", value) {
      return date
    }
    if let date = parseDateFormat("M/d/yyyy, h:mm:ss a", value) {
      return date
    }
    if let date = parseDateFormat("EEE MMM dd yyyy HH:mm:ss 'GMT'Z", value) {
      return date
    }
    if let date = parseDateFormat("EEE, dd MMM yyyy HH:mm:ss zzz", value) {
      return date
    }
    if let date = parsePostgresTimezoneDate(value) {
      return date
    }

    return parseISO8601Like(value)
  }

  private static func parseLocalDate(_ value: String) -> Date? {
    guard let match = value.firstMatch(#"^(\d+)[./-](\d+)[./-](\d+)$"#),
      let part1 = Int(match[1]),
      let part2 = Int(match[2]),
      let part3 = Int(match[3]),
      part1 > 0,
      part2 > 0,
      part3 > 0
    else { return nil }

    let year: Int
    let month: Int
    let day: Int
    if part1 > 999 {
      year = part1
      month = part2
      day = part3
    } else {
      year = part3
      month = part1
      day = part2
    }
    return date(year: year, month: month, day: day)
  }

  private static func parseDateFormat(_ format: String, _ value: String) -> Date? {
    let formatter = DateFormatter()
    formatter.calendar = gregorianUTC
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = format
    formatter.isLenient = false
    return formatter.date(from: value)
  }

  private static func parsePostgresTimezoneDate(_ value: String) -> Date? {
    let abbreviations = pgTimezoneOffsets.keys
      .sorted { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }
      .joined(separator: "|")
    guard let match = value.firstMatch(#"^(.+?)("# + abbreviations + #")$"#) else { return nil }
    let timezone = match[2]
    guard let offset = pgTimezoneOffsets[timezone] else { return nil }
    let base = String(value.dropLast(timezone.count)) + "Z"
    guard let date = parseISO8601Like(base) else { return nil }
    return date.addingTimeInterval(-offset)
  }

  private static func parseISO8601Like(_ value: String) -> Date? {
    var normalized = value

    if let match = normalized.firstMatch(#"^(.+T.+)([+-]\d{2})$"#) {
      normalized = "\(match[1])\(match[2]):00"
    } else if let match = normalized.firstMatch(#"^(.+[T ].+)([+-]\d{2})(\d{2})$"#) {
      normalized = "\(match[1])\(match[2]):\(match[3])"
    }

    if let match = normalized.firstMatch(
      #"^(\d+)-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2})(?::(\d{1,2}))?(?::(\d{1,2})(?:\.(\d+))?)?(.*))?$"#
    ) {
      let year = match[1]
      let month = match[2].leftPadded(to: 2, with: "0")
      let day = match[3].leftPadded(to: 2, with: "0")
      if let hour = match[safe: 4], !hour.isEmpty {
        let minute = (match[safe: 5] ?? "0").leftPadded(to: 2, with: "0")
        let second = (match[safe: 6] ?? "0").leftPadded(to: 2, with: "0")
        let fraction = (match[safe: 7]).map { ".\($0)" } ?? ""
        let suffix = match[safe: 8] ?? ""
        normalized =
          "\(year)-\(month)-\(day)T\(hour.leftPadded(to: 2, with: "0")):\(minute):\(second)\(fraction)\(suffix)"
      } else {
        normalized = "\(year)-\(month)-\(day)"
      }
    }

    if normalized.contains(" "), normalized.firstMatch(#"^\d+-\d+-\d+ \d+.*$"#) != nil {
      normalized = normalized.replacingOccurrences(of: " ", with: "T")
    }

    if normalized.firstMatch(#"^\d+-\d+-\d+T\d+:\d+(?::\d+(?:\.\d+)?)?$"#) != nil {
      normalized += "Z"
    }

    if let date = iso8601Date(from: normalized) {
      return date
    }

    if
      normalized.firstMatch(#"^\d+-\d+-\d+$"#) != nil,
      let date = parseLocalDate(normalized)
    {
      return date
    }

    return nil
  }

  private static func iso8601Date(from value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) {
      return date
    }
    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: value) {
      return date
    }
    formatter.formatOptions = [.withFullDate]
    return formatter.date(from: value)
  }

  private static func date(year: Int, month: Int, day: Int) -> Date? {
    var components = DateComponents()
    components.calendar = gregorianUTC
    components.timeZone = TimeZone(secondsFromGMT: 0)
    components.year = year
    components.month = month
    components.day = day
    guard let date = components.date else { return nil }
    let roundTrip = gregorianUTC.dateComponents([.year, .month, .day], from: date)
    guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day else {
      return nil
    }
    return date
  }
}

private extension Array where Element == String {
  subscript(safe index: Int) -> String? {
    guard index >= 0, index < count, !self[index].isEmpty else { return nil }
    return self[index]
  }
}

private extension String {
  func firstMatch(_ pattern: String) -> [String]? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(startIndex..., in: self)
    guard let match = regex.firstMatch(in: self, range: range), match.range == range else {
      return nil
    }
    return (0..<match.numberOfRanges).map { index in
      let range = match.range(at: index)
      guard range.location != NSNotFound, let swiftRange = Range(range, in: self) else {
        return ""
      }
      return String(self[swiftRange])
    }
  }

  func leftPadded(to length: Int, with character: Character) -> String {
    guard count < length else { return self }
    return String(repeating: String(character), count: length - count) + self
  }
}
