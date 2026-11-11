import Foundation

/// What the server refused, in terms a person can act on from a log line alone (#296).
///
/// Instant answers a permission refusal with a hint such as
/// `{"expected": "perms-pass?", "input": ["recordings", "object"]}`: the check that failed and the namespace whose
/// rule refused. This names that namespace and lists the refused transaction's entities, attributes, and short scalar
/// values in it, so a log can say "the recordings rule refused updatedAtMs 1790720435698.8 on 52e9a666" rather than
/// "Permission denied: not perms-pass?".
///
/// A validation refusal's hint lists what the server found missing instead:
/// `{"records": [{"etype": "recordings", "entity_id": "f592cdd1-...", "label": "startedAtMs", ...}]}` for "Missing
/// required attribute". Its namespace, entities and attributes come from those records (#2046). Every refusal also
/// names the namespaces the write set and the links it made, since a link can touch a row the write never names: a
/// link declared forward on the target keeps its fact on the target, and the server checks the target's required
/// attributes in the same transaction.
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
  /// Every namespace the refused write set, sorted (#2046).
  var writeNamespaces: [String]
  /// The links the refused write made, `entity-prefix/label->target-prefix`, at most ``maximumLinks`` (#2046).
  var writeLinks: [String]

  static let maximumEntities = 4
  static let maximumValues = 12
  static let maximumLinks = 4
  static let maximumStringLength = 48

  init(hint: InstantLiveJSONValue?, transaction: InstantStoreTransaction?) {
    var entityIDs: Set<String> = []
    var attributes: Set<String> = []
    var values: [String] = []
    if case let .object(fields) = hint {
      if case let .array(input) = fields["input"], case let .string(namespace) = input.first {
        self.namespace = namespace
      }
      if case let .string(check) = fields["expected"] {
        self.check = check
      }
      // #2046: a validation refusal's records, one per missing attribute of a row (the server's validate-required!).
      if case let .array(records) = fields["records"] {
        var namespaces: Set<String> = []
        for case let .object(record) in records {
          guard case let .string(entityID) = record["entity_id"], case let .string(label) = record["label"] else {
            continue
          }
          if case let .string(namespace) = record["etype"] { namespaces.insert(namespace) }
          entityIDs.insert(entityID)
          attributes.insert(label)
        }
        if namespace == nil, !namespaces.isEmpty { namespace = namespaces.sorted().joined(separator: ",") }
        if check == nil, !entityIDs.isEmpty { check = "required attributes" }
      }
    }
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
    var writeNamespaces: Set<String> = []
    var writeLinks: [String] = []
    for operation in transaction?.operations ?? [] {
      let triple: InstantTriple
      switch operation {
      case let .insert(inserted), let .merge(inserted): triple = inserted
      default: continue
      }
      guard let slash = triple.attributeID.firstIndex(of: "/") else { continue }
      writeNamespaces.insert(String(triple.attributeID[..<slash]))
      if case let .ref(target) = triple.value, writeLinks.count < Self.maximumLinks {
        let label = triple.attributeID[triple.attributeID.index(after: slash)...]
        writeLinks.append("\(triple.entityID.prefix(8))/\(label)->\(target.prefix(8))")
      }
    }
    self.writeNamespaces = writeNamespaces.sorted()
    self.writeLinks = writeLinks
  }

  /// Diagnostic metadata: `refusedNamespace`, `refusedCheck`, `refusedEntityIDs`, `refusedAttributes`, `refusedValues`,
  /// `refusedWriteNamespaces` and `refusedWriteLinks`.
  var metadata: [String: String] {
    [
      "refusedNamespace": namespace ?? "",
      "refusedCheck": check ?? "",
      "refusedEntityIDs": entityIDs.joined(separator: ","),
      "refusedAttributes": attributes.joined(separator: ","),
      "refusedValues": values.joined(separator: "; "),
      "refusedWriteNamespaces": writeNamespaces.joined(separator: ","),
      "refusedWriteLinks": writeLinks.joined(separator: ","),
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
