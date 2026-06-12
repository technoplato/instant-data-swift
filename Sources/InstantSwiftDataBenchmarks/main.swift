import Foundation

let row: [String: Any] = [
  "case": "benchmarks",
  "side": "swift",
  "event": "blocked-not-implemented",
  "timestampMs": Int(Date().timeIntervalSince1970 * 1000),
  "ok": false,
  "details": [
    "reason": "Benchmark scaffold exists, but InstantSwiftData benchmark suites are not implemented yet."
  ],
]

let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
exit(2)

