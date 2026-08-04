import Foundation
@testable import InstantSwiftDataCore
import Testing

/// Reconciles `InstantParityCoverage` against reality in both directions.
///
/// **Upstream source of truth**
/// - Repository: `https://github.com/instantdb/instant`
/// - Checkout this repository vendors (gitignored, cloned beside the package):
///   `<package root>/upstream/instant`
///   (override with `INSTANT_UPSTREAM_CHECKOUT`)
/// - Test suite read by this file:
///   `<package root>/upstream/instant/client/packages/core/__tests__/src`
/// - Pinned commit: `e71017612aed4031710a35e2fcace30d38d557ac` (2026-06-11)
/// - Inventory of that commit:
///   `docs/porting/upstream-typescript-test-inventory.md`
///   (186 declarations / 225 runtime cases / 1 benchmark)
///
/// The vendored checkout — not any other clone on the machine — is the source of
/// truth, because every `sourceFile` in the registry is written relative to it
/// (`upstream/instant/client/packages/...`). Reconciling against a different clone
/// silently compares the registry to an upstream it was never written against.
///
/// The registry is a set of *claims*: "this upstream test is covered by this Swift
/// test." Nothing verified either side of that claim, so all four of these drifted
/// silently and were only found by hand:
///
/// * a Swift test was renamed and four records kept citing the old name
///   (`staticFetchAllStartsObservationWithoutTaskOrLoad`, which had gained an
///   `OnFirstRead`)
/// * records stored a paraphrase where upstream's literal test name belongs, so no
///   tool could answer "did upstream add a test we have not ported?"
/// * a record cited an upstream test that does not exist in upstream
/// * upstream's only benchmark had no record at all
///
/// These are source invariants rather than runtime assertions on purpose: the
/// failure mode is a *name* that no longer resolves, which no amount of running the
/// suite can detect — a stale record simply never gets checked against anything.
///
/// `swiftTestNamesResolve` needs nothing but this checkout and always runs. The two
/// upstream-facing tests need the pinned `instantdb/instant` checkout; when it is
/// absent they record why and return rather than failing, so the suite still runs on
/// a machine that does not have it.
@Suite(.serialized)
struct InstantUpstreamParityReconciliationTests {
  // MARK: Swift side

  /// Every Swift test a record names must exist in `Tests/`.
  @Test
  func swiftTestNamesResolve() throws {
    let declared = try declaredSwiftTestNames()
    var unresolved: [String] = []

    for record in InstantSwiftDataParityCoverage.records {
      guard record.status != .blocked, record.status != .notApplicable else { continue }
      for name in Self.split(record.swiftTestName) where !declared.contains(name) {
        unresolved.append("\(record.id) -> \(name)")
      }
    }

    #expect(
      unresolved.isEmpty,
      """
      \(unresolved.count) parity record(s) name a Swift test that does not exist. \
      A renamed test leaves its record pointing at nothing, and the record then \
      claims coverage forever without being checked against anything:
      \(unresolved.sorted().joined(separator: "\n      "))
      """
    )
  }

  /// A record that claims `.exact` or `.adapted` has to name something on both sides.
  @Test
  func coveredRecordsNameBothSides() {
    var incomplete: [String] = []
    for record in InstantSwiftDataParityCoverage.records {
      guard record.status == .exact || record.status == .adapted else { continue }
      if record.swiftTestName.trimmingCharacters(in: .whitespaces).isEmpty {
        incomplete.append("\(record.id): empty swiftTestName")
      }
      if record.sourceTestName.trimmingCharacters(in: .whitespaces).isEmpty {
        incomplete.append("\(record.id): empty sourceTestName")
      }
    }
    #expect(
      incomplete.isEmpty,
      """
      A record marked exact/adapted asserts a real correspondence, so both sides \
      must be named. Use .blocked or .not-applicable when one side does not exist:
      \(incomplete.sorted().joined(separator: "\n      "))
      """
    )
  }

  // MARK: Upstream side

  /// Every upstream test name a record cites must exist in the upstream checkout.
  @Test
  func citedUpstreamTestNamesExist() throws {
    guard let upstream = Self.upstreamCoreTestsDirectory() else {
      Self.reportMissingCheckout()
      return
    }
    let upstreamNames = Set(try Self.upstreamTestNames(in: upstream).map(\.name))
    var unresolved: [String] = []

    for record in InstantSwiftDataParityCoverage.records {
      guard record.sourceKind == .instantTypeScript else { continue }
      guard record.sourceFile.contains("packages/core/__tests__") else { continue }
      guard record.status != .blocked else { continue }
      let cited = Self.split(record.sourceTestName)
      guard !cited.isEmpty else { continue }
      if !cited.contains(where: { upstreamNames.contains($0) }) {
        unresolved.append("\(record.id): \(record.sourceTestName)")
      }
    }

    #expect(
      unresolved.isEmpty,
      """
      \(unresolved.count) record(s) cite an upstream test name that is not in the \
      upstream checkout. `sourceTestName` must hold upstream's literal test name, \
      joined with " / " when one Swift test covers several — a paraphrase makes it \
      impossible to detect a test upstream added or renamed:
      \(unresolved.sorted().joined(separator: "\n      "))
      """
    )
  }

  /// The extractor must see the same upstream surface the inventory documented.
  ///
  /// Without this, the two upstream-facing tests above can pass vacuously: an
  /// extractor that quietly stops recognizing a declaration form finds fewer tests,
  /// so fewer names need records and everything goes green while coverage silently
  /// drops. Both numbers were converged across three independent methods (a hand
  /// parser, vitest's own collector, and a TypeScript-compiler AST pass) before
  /// being pinned here.
  @Test
  func upstreamSurfaceMatchesTheRecordedInventory() throws {
    guard let upstream = Self.upstreamCoreTestsDirectory() else {
      Self.reportMissingCheckout()
      return
    }
    let tests = try Self.upstreamTestNames(in: upstream)
    let files = Set(tests.map(\.file))
    let declarations = Set(tests.map { "\($0.file):\($0.line)" })

    #expect(
      files.count == 19,
      "Expected 19 upstream core test files, found \(files.count): \(files.sorted())"
    )
    #expect(
      declarations.count == 186,
      "Expected 186 upstream declarations, found \(declarations.count)."
    )
    #expect(
      tests.count == 225,
      """
      Expected 225 upstream runtime cases, found \(tests.count). Either upstream \
      changed — re-run the inventory in docs/porting/ and update these pins — or \
      the extractor stopped recognizing a declaration form, which would make \
      citedUpstreamTestNamesExist and everyUpstreamTestHasARecord pass vacuously.
      """
    )
  }

  /// Every upstream test must be claimed by some record.
  @Test
  func everyUpstreamTestHasARecord() throws {
    guard let upstream = Self.upstreamCoreTestsDirectory() else {
      Self.reportMissingCheckout()
      return
    }
    var claimed: Set<String> = []
    for record in InstantSwiftDataParityCoverage.records {
      claimed.formUnion(Self.split(record.sourceTestName))
    }

    let unported = try Self.upstreamTestNames(in: upstream)
      .filter { !claimed.contains($0.name) }
      .map { "\($0.file):\($0.line) \($0.name)" }

    #expect(
      unported.isEmpty,
      """
      \(unported.count) upstream test(s) have no parity record. Either port them \
      and add a record, or add a record with status .blocked or .not-applicable \
      that says why they do not apply to Swift:
      \(unported.sorted().joined(separator: "\n      "))
      """
    )
  }

  // MARK: Support

  /// Names joined by " / " (one Swift test covering several upstream tests) or by
  /// " + " (several Swift tests covering one upstream test).
  private static func split(_ value: String) -> [String] {
    value
      .components(separatedBy: " / ")
      .flatMap { $0.components(separatedBy: " + ") }
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
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

  private struct UpstreamTest {
    var file: String
    var line: Int
    var name: String
  }

  /// Extracts every `test(…)` / `it(…)` name from the upstream core suite.
  ///
  /// Upstream builds custom test functions from `makeE2ETest(...)` and binds them to
  /// file-local identifiers (`authTest`, a shadowing `test`, `e2eTest as test`).
  /// Calls through those are real tests, so the recognized identifiers are
  /// discovered per file rather than hard-coded — a fixed list silently loses four
  /// auth cases.
  private static func upstreamTestNames(in directory: URL) throws -> [UpstreamTest] {
    var results: [UpstreamTest] = []
    guard
      let walker = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: nil
      )
    else { return results }

    let factoryBinding = try NSRegularExpression(
      pattern: #"(?m)^\s*(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*makeE2ETest\s*\("#
    )
    let aliasImport = try NSRegularExpression(
      pattern: #"import\s*\{([^}]*)\}\s*from\s*['"][^'"]*utils/e2e['"]"#
    )

    for case let url as URL in walker {
      let name = url.lastPathComponent
      guard name.hasSuffix(".test.ts") || name.hasSuffix(".test.js") else { continue }
      guard let source = try? String(contentsOf: url, encoding: .utf8) else { continue }

      var identifiers: Set<String> = ["test", "it"]
      let full = NSRange(source.startIndex..., in: source)
      for match in factoryBinding.matches(in: source, range: full) {
        if let r = Range(match.range(at: 1), in: source) { identifiers.insert(String(source[r])) }
      }
      for match in aliasImport.matches(in: source, range: full) {
        guard let r = Range(match.range(at: 1), in: source) else { continue }
        for clause in source[r].components(separatedBy: ",") {
          let bound = clause.components(separatedBy: " as ").last ?? clause
          let trimmed = bound.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !trimmed.isEmpty, trimmed != "makeE2ETest", trimmed != "apiUrl" else { continue }
          identifiers.insert(trimmed)
        }
      }

      let relative = url.path.components(separatedBy: "__tests__/").last ?? url.path
      results.append(
        contentsOf: testNames(in: source, identifiers: identifiers, file: relative)
      )
    }
    return results
  }

  private static func testNames(
    in source: String,
    identifiers: Set<String>,
    file: String
  ) -> [UpstreamTest] {
    var results: [UpstreamTest] = []
    var inBlockComment = false

    let lines = source.components(separatedBy: "\n")
    for (index, rawLine) in lines.enumerated() {
      var line = rawLine[...]
      if inBlockComment {
        guard let end = line.range(of: "*/") else { continue }
        line = line[end.upperBound...]
        inBlockComment = false
      }
      if let start = line.range(of: "/*") {
        if let end = line.range(of: "*/", range: start.upperBound..<line.endIndex) {
          line = line[line.startIndex..<start.lowerBound] + line[end.upperBound...]
        } else {
          line = line[line.startIndex..<start.lowerBound]
          inBlockComment = true
        }
      }

      let trimmed = line.drop { $0 == " " || $0 == "\t" }
      guard let identifier = identifiers.first(where: { trimmed.hasPrefix($0) }) else { continue }
      var rest = trimmed.dropFirst(identifier.count)
      // `describe` also starts with a recognized prefix only by accident; require
      // the identifier to end here or at a modifier chain.
      guard rest.first == "(" || rest.first == "." else { continue }
      let isEach = rest.hasPrefix(".each")
      while rest.first == "." {
        rest = rest.dropFirst()
        rest = rest.drop { $0.isLetter }
      }
      guard rest.first == "(" else { continue }

      // The name is not always on the declaration's own line: upstream's e2e files
      // write `authTest(\n  'name',\n  async ({ db }) => …)`, so a line-local read
      // silently loses all four auth cases. Read from the declaration onward through
      // the rest of the file instead.
      let tail = lines[index...].joined(separator: "\n")
      let afterIdentifier = tail.dropFirst(rawLine.count - rest.count)

      if isEach {
        // `test.each([...])('title %s', …)` is one declaration and N runtime cases,
        // named by substituting each row's label into the title.
        let (title, labels) = Self.eachTitleAndLabels(in: afterIdentifier)
        guard let title else { continue }
        for label in labels {
          results.append(
            UpstreamTest(
              file: file,
              line: index + 1,
              name: title.replacingOccurrences(of: "%s", with: label)
            )
          )
        }
        continue
      }

      guard
        let literal = Self.firstStringLiteral(in: afterIdentifier, allowingLeadingParen: false)
      else { continue }

      // A template-literal name means a surrounding loop generates the cases —
      // upstream does this in dates.test.ts with a plain `for...of` and a `.forEach`
      // rather than `.each`, so one declaration becomes 28 and 2 runtime cases.
      // Counting it as one silently loses 28 date formats, which is exactly the kind
      // of coverage hole this suite exists to prevent.
      if literal.contains("${") {
        let key = "\(file):\(index + 1)"
        guard let generated = Self.loopGeneratedCaseCounts[key] else {
          Issue.record(
            """
            \(key) declares a parameterized test whose expansion is unknown: \
            \(literal). Resolve how many cases its driving collection produces and \
            add it to `loopGeneratedCaseCounts`, rather than letting it count as one.
            """
          )
          continue
        }
        // Every generated case carries the template name so a record can cite the one
        // name that appears in upstream source; the repetition is what makes the
        // runtime-case count honest.
        results.append(
          contentsOf: Array(
            repeating: UpstreamTest(file: file, line: index + 1, name: literal),
            count: generated
          )
        )
        continue
      }

      results.append(UpstreamTest(file: file, line: index + 1, name: literal))
    }
    return results
  }

  /// Upstream declarations whose cases come from a surrounding loop rather than
  /// `.each`, with the size of the collection driving them.
  ///
  /// Keyed by `<file>:<line>` at the pinned commit. Anything parameterized and absent
  /// from this table fails loudly rather than being counted as a single case.
  ///
  /// `src/utils/dates.test.ts:43` — `for (const [dateString, expected] of
  /// Object.entries(validDateStrings))`, 31 entries.
  /// `src/utils/dates.test.ts:55` — `invalidDateStrings.forEach(…)`, 2 elements.
  private static let loopGeneratedCaseCounts: [String: Int] = [
    "src/utils/dates.test.ts:43": 31,
    "src/utils/dates.test.ts:55": 2,
  ]

  /// Splits `.each([[label, …], …])('title %s', …)` into its title and row labels.
  private static func eachTitleAndLabels(in text: Substring) -> (String?, [String]) {
    let characters = Array(text)
    guard let open = characters.firstIndex(of: "[") else { return (nil, []) }

    var depth = 0
    var end = open
    while end < characters.count {
      if characters[end] == "[" { depth += 1 }
      if characters[end] == "]" {
        depth -= 1
        if depth == 0 { break }
      }
      end += 1
    }
    guard end < characters.count else { return (nil, []) }

    var labels: [String] = []
    var index = open
    depth = 0
    while index <= end {
      let character = characters[index]
      if character == "[" || character == "{" || character == "(" {
        depth += 1
      } else if character == "]" || character == "}" || character == ")" {
        depth -= 1
      } else if depth == 2, character == "\"" || character == "'" || character == "`" {
        var value = ""
        index += 1
        while index <= end, characters[index] != character {
          value.append(characters[index])
          index += 1
        }
        labels.append(value)
        // One label per row: skip to the end of this row before looking again.
        while index <= end, depth >= 2 {
          if characters[index] == "[" || characters[index] == "{" { depth += 1 }
          if characters[index] == "]" || characters[index] == "}" { depth -= 1 }
          index += 1
        }
        continue
      }
      index += 1
    }

    // Step past the `)` that closes `.each(<table>)`; reading from it would see an
    // unbalanced close and give up before reaching the title.
    var titleStart = end + 1
    while titleStart < characters.count, characters[titleStart] == " " || characters[titleStart] == "\n" {
      titleStart += 1
    }
    if titleStart < characters.count, characters[titleStart] == ")" { titleStart += 1 }
    let afterTable = text[text.index(text.startIndex, offsetBy: titleStart)...]
    let title = firstStringLiteral(in: afterTable, allowingLeadingParen: true)
    return (title, labels)
  }

  private static func firstStringLiteral(
    in text: Substring,
    allowingLeadingParen: Bool
  ) -> String? {
    let characters = Array(text)
    var index = 0
    var depth = 0
    while index < characters.count {
      let character = characters[index]
      if character == "\"" || character == "'" || character == "`" {
        var value = ""
        index += 1
        while index < characters.count, characters[index] != character {
          if characters[index] == "\\", index + 1 < characters.count {
            value.append(characters[index + 1])
            index += 2
            continue
          }
          value.append(characters[index])
          index += 1
        }
        return value
      }
      if character == "(" || character == "[" || character == "{" {
        depth += 1
      } else if character == ")" || character == "]" || character == "}" {
        depth -= 1
        if depth < 0 { return nil }
      } else if (character == "," || character == ";"), depth <= 1, !allowingLeadingParen {
        return nil
      }
      index += 1
    }
    return nil
  }

  /// The pinned upstream checkout, overridable so CI can point elsewhere.
  private static func upstreamCoreTestsDirectory() -> URL? {
    let directory = upstreamCheckoutURL()
      .appending(path: "client/packages/core/__tests__/src", directoryHint: .isDirectory)
    var isDirectory: ObjCBool = false
    guard
      FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else { return nil }
    return directory
  }

  private static func upstreamCheckoutURL() -> URL {
    if let override = ProcessInfo.processInfo.environment[upstreamCheckoutEnvironmentKey],
      !override.isEmpty
    {
      return URL(fileURLWithPath: override)
    }
    return packageRootURL().appending(path: "upstream/instant", directoryHint: .isDirectory)
  }

  private static func reportMissingCheckout() {
    let configured = upstreamCheckoutURL().path
    Issue.record(
      """
      Skipping upstream reconciliation: no instantdb/instant checkout at \
      \(configured)/client/packages/core/__tests__/src. That path is gitignored, so \
      a fresh clone will not have it — clone https://github.com/instantdb/instant \
      there at \(pinnedUpstreamCommit), or set \(upstreamCheckoutEnvironmentKey). \
      Until then nothing detects an upstream test that has not been ported.
      """
    )
  }

  /// The commit the inventory in `docs/porting/` was taken at.
  ///
  /// Checked rather than merely documented: a header comment naming a SHA rots the
  /// moment someone pulls the checkout forward, and every count in this file's sibling
  /// documents would then describe a different upstream than the one on disk.
  static let pinnedUpstreamCommit = "e71017612aed4031710a35e2fcace30d38d557ac"

  @Test
  func upstreamCheckoutIsAtThePinnedCommit() throws {
    guard Self.upstreamCoreTestsDirectory() != nil else {
      Self.reportMissingCheckout()
      return
    }
    guard let head = Self.upstreamHeadCommit() else {
      Issue.record("Could not read HEAD of the upstream checkout; is it a git worktree?")
      return
    }
    #expect(
      head == Self.pinnedUpstreamCommit,
      """
      The upstream checkout is at \(head) but docs/porting/ was written against \
      \(Self.pinnedUpstreamCommit). Every count in \
      docs/porting/upstream-typescript-test-inventory.md describes the pinned \
      commit, so they no longer describe what is on disk. Re-run the inventory and \
      update both the documents and `pinnedUpstreamCommit`, or check the pinned \
      commit back out.
      """
    )
  }

  private static func upstreamHeadCommit() -> String? {
    let path = upstreamCheckoutURL().path
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

  private static let upstreamCheckoutEnvironmentKey = "INSTANT_UPSTREAM_CHECKOUT"

  private static func packageRootURL(filePath: String = #filePath) -> URL {
    URL(fileURLWithPath: filePath)
      .deletingLastPathComponent()  // InstantSwiftDataCoreTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // package root
  }
}
