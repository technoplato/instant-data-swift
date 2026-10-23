// History
// 2026-10-23  #1020  Created. A scripted live session's wait for 51 sent messages had no bound, and on a loaded Mac
//                    mini a run that sent fewer parked the whole InstantSwiftDataCoreTests bundle for 11-16 minutes at
//                    0% CPU. A live test wait now fails at a deadline with what it saw.

import Foundation
@testable import InstantSwiftDataCore

/// Why a live test-support wait gave up (#1020): what the scripted side had seen by its deadline, so a run that sends
/// too little fails in seconds with the messages it did send, instead of parking the suite until someone kills it.
struct InstantLiveTestWaitTimedOut: Error, CustomStringConvertible {
  var wait: String
  var timeout: Duration
  var observed: [String]

  var description: String {
    "Timed out after \(timeout) waiting for \(wait); saw \(observed.count): "
      + observed.joined(separator: ", ")
  }
}

enum InstantLiveTestWait {
  /// A live run sends its next message within milliseconds. 10 s leaves a loaded Mac room and still ends a run that
  /// never will (#1020).
  static let defaultTimeout: Duration = .seconds(10)

  /// One message as a timed-out wait reports it: its op and client event ID.
  static func summary(_ message: InstantLiveMessage) -> String {
    [message.op, message.clientEventID].compactMap { $0 }.joined(separator: " ")
  }
}

