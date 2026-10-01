import Foundation

/// What the server refused, in terms a person can act on from a log line alone (#296).
///
/// Instant answers a permission refusal with a hint such as
/// `{"expected": "perms-pass?", "input": ["recordings", "object"]}`: the check that failed and the namespace whose
/// rule refused. This names that namespace and lists the refused transaction's entities, attributes, and short scalar
/// values in it, so a log can say "the recordings rule refused updatedAtMs 1790720435698.8 on 52e9a666" rather than
/// "Permission denied: not perms-pass?".
///
/// ```swift
/// let refusal = InstantMutationRefusal(hint: error.hint, transaction: failedMutation.transaction)
/// InstantDiagnostics.shared.record(.error, ..., metadata: refusal.metadata)
/// ```
struct InstantMutationRefusal: Equatable, Sendable {
  /// The namespace whose rule refused, from the hint's `input`.
  var namespace: String?
  /// The server's failed check, from the hint's `expected` (for example `perms-pass?`).
  var check: String?
  /// Refused entities in `namespace`, sorted, at most ``maximumEntities``.
  var entityIDs: [String]
  /// Refused attributes in `namespace`, without the namespace prefix, sorted.
  var attributes: [String]
  /// `entity-prefix/attribute=value` for short scalar values in `namespace`, at most ``maximumValues``. Long strings
  /// (text, JSON) are shown as their length.
  var values: [String]

  static let maximumEntities = 4
  static let maximumValues = 12
  static let maximumStringLength = 48

  init(hint: InstantLiveJSONValue?, transaction: InstantStoreTransaction?) {
    if case let .object(fields) = hint {
      if case let .array(input) = fields["input"], case let .string(namespace) = input.first {
        self.namespace = namespace
      }
      if case let .string(check) = fields["expected"] {
        self.check = check
      }
    }
    var entityIDs: Set<String> = []
    var attributes: Set<String> = []
    var values: [String] = []
    if let namespace, let transaction {
      let prefix = namespace + "/"
      for operation in transaction.operations {
        guard case let .insert(triple) = operation, triple.attributeID.hasPrefix(prefix) else { continue }
        entityIDs.insert(triple.entityID)
        let attribute = String(triple.attributeID.dropFirst(prefix.count))
        attributes.insert(attribute)
        if values.count < Self.maximumValues, let shown = Self.shown(triple.value) {
          values.append("\(triple.entityID.prefix(8))/\(attribute)=\(shown)")
        }
      }
    }
    self.entityIDs = Array(entityIDs.sorted().prefix(Self.maximumEntities))
    self.attributes = attributes.sorted()
    self.values = values
  }

  /// Diagnostic metadata: `refusedNamespace`, `refusedCheck`, `refusedEntityIDs`, `refusedAttributes`, `refusedValues`.
  var metadata: [String: String] {
    [
      "refusedNamespace": namespace ?? "",
      "refusedCheck": check ?? "",
      "refusedEntityIDs": entityIDs.joined(separator: ","),
      "refusedAttributes": attributes.joined(separator: ","),
      "refusedValues": values.joined(separator: "; "),
    ]
  }

  private static func shown(_ value: InstantValue) -> String? {
    switch value {
    case let .number(number):
      return String(number)
    case let .bool(bool):
      return String(bool)
    case .null:
      return "null"
    case let .string(string):
      return string.count <= maximumStringLength ? string : "<\(string.count) characters>"
    case .date, .json, .ref, .lookupRef:
      return nil
    }
  }
}

extension InstantLiveJSONValue {
  /// Compact JSON text for a log line.
  var compactJSONText: String {
    guard
      let data = try? JSONEncoder().encode(self),
      let text = String(data: data, encoding: .utf8)
    else { return String(describing: self) }
    return text
  }
}
