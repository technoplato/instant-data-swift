// History:
// - 2026-10-23: added (#1006): a local read filtered by a named attribute also reads what this device keeps on disk.

import Foundation

/// Attributes whose values this device's store indexes on disk, so a local read filtered by one of them finds every
/// entity the device keeps, also those on disk but not in memory (#1006).
///
/// The in-memory store caches the SQLite store. After a relaunch it holds only the entities a stored query result owns
/// and those an unsent write touches; the rest of what this device wrote or received stays on disk, where no query
/// reached it. A one-shot read through `InstantSwiftDataClient.localReader()` whose filters include
/// `attribute == value` for an attribute named here also reads the matching entities from disk, without loading them
/// into memory.
///
/// ```swift
/// let lookup = InstantLocalLookupPolicy(attributeIDs: ["transcriptionSegments/recordingID"])
/// ```
///
/// Each named attribute costs one index entry per stored value. Name the few attributes that scope many rows to one
/// parent, such as a recording's lines, not every filtered field.
public struct InstantLocalLookupPolicy: Hashable, Sendable {
  public static let none = Self(attributeIDs: Set<String>())

  public var attributeIDs: Set<String>

  public init(attributeIDs: [String]) {
    self.attributeIDs = Set(attributeIDs)
  }

  public init(attributeIDs: Set<String>) {
    self.attributeIDs = attributeIDs
  }

  package var isEnabled: Bool {
    !attributeIDs.isEmpty
  }
}
