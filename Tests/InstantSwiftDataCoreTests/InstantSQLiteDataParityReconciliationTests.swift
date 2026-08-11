import Foundation
@testable import InstantSwiftDataCore
import Testing

/// Reconciles `InstantParityCoverage` SQLiteData rows against the vendored
/// Point-Free SQLiteData test suite.
///
/// **Upstream source of truth**
/// - Repository: `https://github.com/pointfreeco/sqlite-data`
/// - Vendored checkout: `<package root>/upstream/sqlite-data`
///   (override with `SQLITE_DATA_UPSTREAM_CHECKOUT`)
/// - Pinned commit: `97987458b49f0311717ecfbf7e8ac4c406afbf55`
/// - Inventory: `docs/porting/upstream-sqlitedata-test-inventory.md`
///   (314 runtime tests)
///
/// Same failure mode the Instant TypeScript inventory fixed: claims that
/// nothing checks rot when upstream renames a test or we invent coverage.
@Suite(.serialized)
struct InstantSQLiteDataParityReconciliationTests {
  @Test
  func swiftTestNamesResolveForCoveredSQLiteRecords() throws {
    let declared = try declaredSwiftTestNames()
    var unresolved: [String] = []

    for record in InstantSwiftDataParityCoverage.records where record.sourceKind == .sqliteData {
      guard record.status == .exact || record.status == .adapted else { continue }
      for name in Self.split(record.swiftTestName) where !declared.contains(name) {
        unresolved.append("\(record.id) -> \(name)")
      }
    }

    #expect(
      unresolved.isEmpty,
      """
      \(unresolved.count) SQLiteData parity record(s) name a Swift test that does not exist:
      \(unresolved.sorted().joined(separator: "\n      "))
      """
    )
  }

  @Test
  func everyUpstreamSQLiteDataTestHasARecord() throws {
    guard let root = Self.upstreamRootURL() else {
      Self.reportMissingCheckout()
      return
    }
    let upstream = try Self.upstreamTestNames(in: root)
    var claimed: [UpstreamTestKey: Int] = [:]
    for record in InstantSwiftDataParityCoverage.records where record.sourceKind == .sqliteData {
      let sourceFiles = Self.sqliteDataTestFiles(record.sourceFile)
      let sourceTestNames = Self.split(record.sourceTestName).filter { !$0.hasPrefix("@") }
      for sourceFile in sourceFiles {
        for sourceTestName in sourceTestNames {
          claimed[
            UpstreamTestKey(file: sourceFile, name: sourceTestName),
            default: 0
          ] += 1
        }
      }
    }

    var unported: [String] = []
    for test in upstream {
      let key = UpstreamTestKey(file: test.file, name: test.name)
      if claimed[key, default: 0] > 0 {
        claimed[key, default: 0] -= 1
      } else {
        unported.append("\(test.file):\(test.line) \(test.name)")
      }
    }

    #expect(
      unported.isEmpty,
      """
      \(unported.count) upstream SQLiteData test(s) have no parity record:
      \(unported.sorted().joined(separator: "\n      "))
      """
    )
  }

  @Test
  func upstreamSurfaceMatchesTheRecordedInventory() throws {
    guard let root = Self.upstreamRootURL() else {
      Self.reportMissingCheckout()
      return
    }
    let tests = try Self.upstreamTestNames(in: root)
    let files = Set(tests.map(\.file))
    #expect(files.count == 48, "Expected 48 SQLiteData test files, found \(files.count).")
    #expect(
      tests.count == 314,
      """
      Expected 314 upstream SQLiteData runtime tests, found \(tests.count). \
      Re-run docs/porting/upstream-sqlitedata-test-inventory.md and update pins.
      """
    )
  }

  @Test
  func upstreamCheckoutIsAtThePinnedCommit() throws {
    guard Self.upstreamRootURL() != nil else {
      Self.reportMissingCheckout()
      return
    }
    guard let head = Self.upstreamHeadCommit() else {
      Issue.record("Could not read HEAD of the SQLiteData checkout.")
      return
    }
    #expect(
      head == Self.pinnedUpstreamCommit,
      """
      SQLiteData checkout is at \(head) but docs/porting/ was written against \
      \(Self.pinnedUpstreamCommit).
      """
    )
  }

  // MARK: - Extraction

  private struct UpstreamTest {
    var file: String
    var line: Int
    var name: String
  }

  private struct UpstreamTestKey: Hashable {
    var file: String
    var name: String
  }

  private static func upstreamTestNames(in root: URL) throws -> [UpstreamTest] {
    var results: [UpstreamTest] = []
    guard
      let walker = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: nil
      )
    else { return results }

    for case let url as URL in walker {
      let path = url.path
      if path.contains("/.build/") { continue }
      let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
      let isTestTree =
        relative.hasPrefix("Tests/")
        || relative.range(of: #"Examples/.+Tests/"#, options: .regularExpression) != nil
      guard isTestTree, url.pathExtension == "swift" else { continue }
      guard let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
      results.append(contentsOf: testNames(in: source, file: relative))
    }
    return results
  }

  private static func testNames(in source: String, file: String) -> [UpstreamTest] {
    var results: [UpstreamTest] = []
    let lines = source.components(separatedBy: "\n")
    var index = 0
    while index < lines.count {
      let line = lines[index]
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      // Skip commented-out @Test (the one false positive in SharingTests).
      if trimmed.hasPrefix("//") {
        index += 1
        continue
      }
      if trimmed.hasPrefix("@Test") || trimmed.contains("@Test(") || trimmed.contains("@Test ")
        || trimmed == "@Test" || trimmed.hasPrefix("@Test(")
      {
        // multi-line @Test attributes
        if line.contains("@Test"), !line.contains("func ") {
          var j = index + 1
          while j < min(index + 25, lines.count) {
            let candidate = lines[j]
            if candidate.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
              j += 1
              continue
            }
            if let name = functionName(in: candidate) {
              results.append(UpstreamTest(file: file, line: j + 1, name: name))
              index = j
              break
            }
            if candidate.contains("@Test") { break }
            j += 1
          }
        } else if let name = functionName(in: line) {
          results.append(UpstreamTest(file: file, line: index + 1, name: name))
        } else {
          var j = index + 1
          while j < min(index + 25, lines.count) {
            if let name = functionName(in: lines[j]) {
              results.append(UpstreamTest(file: file, line: j + 1, name: name))
              index = j
              break
            }
            j += 1
          }
        }
      }
      index += 1
    }
    return results
  }

  private static func functionName(in line: String) -> String? {
    // func name( or func name<
    guard let range = line.range(of: #"\bfunc\s+([A-Za-z_]\w*)\s*(?:<|\()"#, options: .regularExpression)
    else { return nil }
    let snippet = String(line[range])
    guard let nameRange = snippet.range(of: #"([A-Za-z_]\w*)\s*(?:<|\()"#, options: .regularExpression)
    else { return nil }
    var name = String(snippet[nameRange])
    name = name.replacingOccurrences(of: #"[\s<\(].*"#, with: "", options: .regularExpression)
    if name.hasPrefix("func ") {
      name = String(name.dropFirst(5)).trimmingCharacters(in: .whitespaces)
    }
    // better extract
    if let m = line.range(of: #"func\s+([A-Za-z_]\w*)"#, options: .regularExpression) {
      let s = String(line[m]).replacingOccurrences(of: "func ", with: "")
      return s.trimmingCharacters(in: .whitespaces)
    }
    return nil
  }

  private static func split(_ value: String) -> [String] {
    value
      .components(separatedBy: " / ")
      .flatMap { $0.components(separatedBy: " + ") }
      .flatMap { $0.components(separatedBy: "; ") }
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private static func sqliteDataTestFiles(_ value: String) -> [String] {
    let prefix = "upstream/sqlite-data/"
    return split(value).compactMap { file in
      let normalized = file.hasPrefix(prefix)
        ? String(file.dropFirst(prefix.count))
        : file
      let isTestTree =
        normalized.hasPrefix("Tests/")
        || normalized.range(of: #"Examples/.+Tests/"#, options: .regularExpression) != nil
      return isTestTree ? normalized : nil
    }
  }

  private func declaredSwiftTestNames() throws -> Set<String> {
    let testsRoot = Self.packageRootURL().appending(path: "Tests", directoryHint: .isDirectory)
    var names: Set<String> = []
    guard
      let walker = FileManager.default.enumerator(
        at: testsRoot,
        includingPropertiesForKeys: nil
      )
    else { return names }

    let pattern = try NSRegularExpression(
      pattern: #"(?m)^\s*(?:public\s+|private\s+|internal\s+)?(?:static\s+)?func\s+([A-Za-z_]\w*)\s*\("#
    )
    for case let url as URL in walker where url.pathExtension == "swift" {
      guard let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
      let range = NSRange(source.startIndex..., in: source)
      for match in pattern.matches(in: source, range: range) {
        guard let nameRange = Range(match.range(at: 1), in: source) else { continue }
        names.insert(String(source[nameRange]))
      }
    }
    return names
  }

  static let pinnedUpstreamCommit = "97987458b49f0311717ecfbf7e8ac4c406afbf55"

  private static func upstreamRootURL() -> URL? {
    if let override = ProcessInfo.processInfo.environment["SQLITE_DATA_UPSTREAM_CHECKOUT"],
      !override.isEmpty
    {
      let url = URL(fileURLWithPath: override)
      return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    let url = packageRootURL().appending(path: "upstream/sqlite-data", directoryHint: .isDirectory)
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
  }

  private static func reportMissingCheckout() {
    Issue.record(
      """
      Skipping SQLiteData reconciliation: no checkout at upstream/sqlite-data \
      (or SQLITE_DATA_UPSTREAM_CHECKOUT). Clone pointfreeco/sqlite-data there at \
      \(pinnedUpstreamCommit).
      """
    )
  }

  private static func upstreamHeadCommit() -> String? {
    guard let path = upstreamRootURL()?.path else { return nil }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", path, "rev-parse", "HEAD"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    guard (try? process.run()) != nil else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    return String(decoding: data, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func packageRootURL(filePath: String = #filePath) -> URL {
    URL(fileURLWithPath: filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }
}
