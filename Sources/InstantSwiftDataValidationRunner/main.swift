import Foundation

let row: [String: Any] = [
  "case": "runner",
  "side": "swift",
  "event": "blocked-not-implemented",
  "timestampMs": Int(Date().timeIntervalSince1970 * 1000),
  "ok": false,
  "details": [
    "reason": "Swift validation runner scaffold exists, but InstantSwiftData behavior is not implemented yet."
  ],
]

let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
exit(2)

