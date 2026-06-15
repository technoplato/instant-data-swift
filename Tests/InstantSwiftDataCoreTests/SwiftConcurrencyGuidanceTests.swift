import Foundation
import CustomDump
import Testing

@Suite
struct SwiftConcurrencyGuidanceTests {
  @Test
  func uncheckedSendableConformancesDocumentProtectionMechanism() throws {
    let sourcesURL = packageRootURL().appendingPathComponent("Sources", isDirectory: true)
    let failures = try swiftFiles(under: sourcesURL).flatMap { fileURL in
      try undocumentedUncheckedSendableConformances(in: fileURL, relativeTo: sourcesURL)
    }

    #expect(
      failures.isEmpty,
      """
      Every production @unchecked Sendable conformance must include a nearby \
      SAFETY: comment naming the actor, lock, or executor that protects it.
      Missing comments:
      \(failures.joined(separator: "\n"))
      """
    )
  }

  @Test
  func coreSchemaAndCLIDoNotDependOnMainActorIsolation() throws {
    let packageRoot = packageRootURL()
    let targetPaths = [
      "Sources/InstantSwiftDataCore",
      "Sources/InstantSwiftDataSchema",
      "Sources/InstantSwiftDataCLI",
      "Sources/instant-swift-data",
    ]
    let failures = try targetPaths.flatMap { targetPath in
      try forbiddenSourceReferences(
        to: ["@MainActor", "MainActor"],
        under: packageRoot.appendingPathComponent(targetPath, isDirectory: true),
        relativeTo: packageRoot
      )
    }

    expectNoDifference(
      failures,
      [],
      """
      Instant core, schema, and CLI targets must not require main-actor isolation.
      Main-actor adaptation belongs in UI adapters and examples.
      """
    )
  }

  @Test
  func productionSourcesDoNotUsePreconcurrencyEscapes() throws {
    let packageRoot = packageRootURL()
    let failures = try forbiddenSourceReferences(
      to: ["@preconcurrency"],
      under: packageRoot.appendingPathComponent("Sources", isDirectory: true),
      relativeTo: packageRoot
    )

    expectNoDifference(
      failures,
      [],
      """
      Production sources should not add @preconcurrency to hide concurrency
      diagnostics. Model the Sendable/isolation boundary instead.
      """
    )
  }
}

private func undocumentedUncheckedSendableConformances(
  in fileURL: URL,
  relativeTo sourcesURL: URL
) throws -> [String] {
  let contents = try String(contentsOf: fileURL, encoding: .utf8)
  let lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

  var failures: [String] = []
  for (index, line) in lines.enumerated() where line.contains("@unchecked Sendable") {
    let safetyComment = safetyComment(before: index, in: lines).lowercased()
    let namesProtectionMechanism = [
      "lock",
      "actor",
      "executor",
    ].contains { safetyComment.contains($0) }

    if !safetyComment.contains("safety:") || !namesProtectionMechanism {
      failures.append("\(relativePath(fileURL, relativeTo: sourcesURL)):\(index + 1)")
    }
  }
  return failures
}

private func safetyComment(before index: Int, in lines: [String]) -> String {
  var cursor = index - 1
  var comments: [String] = []

  while cursor >= 0 {
    let line = lines[cursor].trimmingCharacters(in: .whitespaces)
    guard line.hasPrefix("//") else { break }
    comments.insert(line, at: 0)
    cursor -= 1
  }

  return comments.joined(separator: "\n")
}

private func swiftFiles(under root: URL) throws -> [URL] {
  guard
    let enumerator = FileManager.default.enumerator(
      at: root,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles]
    )
  else { return [] }

  var files: [URL] = []
  for case let fileURL as URL in enumerator {
    guard fileURL.pathExtension == "swift" else { continue }
    let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
    guard resourceValues.isRegularFile == true else { continue }
    files.append(fileURL)
  }
  return files.sorted { $0.path < $1.path }
}

private func forbiddenSourceReferences(
  to forbiddenReferences: [String],
  under root: URL,
  relativeTo packageRoot: URL
) throws -> [String] {
  try swiftFiles(under: root).flatMap { fileURL in
    let contents = try String(contentsOf: fileURL, encoding: .utf8)
    return contents
      .split(separator: "\n", omittingEmptySubsequences: false)
      .enumerated()
      .compactMap { index, line -> String? in
        guard let forbiddenReference = forbiddenReferences.first(where: line.contains)
        else { return nil }
        return "\(relativePath(fileURL, relativeTo: packageRoot)):\(index + 1): \(forbiddenReference)"
      }
  }
}

private func relativePath(_ fileURL: URL, relativeTo directoryURL: URL) -> String {
  let filePath = fileURL.standardizedFileURL.path
  let directoryPath = directoryURL.standardizedFileURL.path
  guard filePath.hasPrefix(directoryPath + "/") else { return filePath }
  return String(filePath.dropFirst(directoryPath.count + 1))
}

private func packageRootURL(filePath: String = #filePath) -> URL {
  URL(fileURLWithPath: filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
}
