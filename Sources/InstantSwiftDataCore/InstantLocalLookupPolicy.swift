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

  /// Checks that each named attribute is in the schema passed at bootstrap, holds one value per entity, and stays in
  /// memory: a lookup compares one stored value, and a deferred value is never filtered by.
  package func validate(
    attributes: [InstantAttribute],
    deferredValueResidency: InstantDeferredValueResidencyPolicy
  ) throws {
    guard isEnabled else { return }
    let attributesByID = Dictionary(attributes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    for attributeID in attributeIDs.sorted() {
      guard let attribute = attributesByID[attributeID] else {
        throw Self.invalid(
          attributeID,
          message: "Local lookup names attribute '\(attributeID)', which is not in the Instant schema passed at bootstrap.",
          recovery: "Add '\(attributeID)' to the app's Instant attributes, or remove it from InstantLocalLookupPolicy."
        )
      }
      guard attribute.cardinality == .one else {
        throw Self.invalid(
          attributeID,
          message: "Local lookup attribute '\(attributeID)' holds many values per entity; a lookup compares one.",
          recovery: "Name a cardinality-one attribute, such as the parent's id on each child row."
        )
      }
      guard !deferredValueResidency.attributeIDs.contains(attributeID) else {
        throw Self.invalid(
          attributeID,
          message: "Local lookup attribute '\(attributeID)' is also a deferred value, which no query filters by.",
          recovery: "Remove '\(attributeID)' from one of the two policies."
        )
      }
    }
  }

  private static func invalid(_ attributeID: String, message: String, recovery: String) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: "validate local lookup",
      path: attributeID,
      message: message,
      recovery: recovery
    )
  }
}
