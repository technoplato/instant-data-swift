import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// #296: a refusal names the namespace whose rule refused, the check, and the refused entity, attributes, and values,
/// so a device log alone can say what was refused. Shapes mirror Recording 023's refused recordings write.
@Suite
struct InstantMutationRefusalTests {
  @Test
  func namesTheNamespaceCheckEntityAttributesAndShortValuesOfTheRefusedWrite() {
    let recordingID = "52e9a666-e30d-4978-9fab-39834bcc64ab"
    let transaction = InstantStoreTransaction(
      id: "199b37fb-718b-4c36-b728-73f91f3c4696",
      operations: [
        .insert(triple(recordingID, "recordings/durationSeconds", .number(2_210.230_867))),
        .insert(triple(recordingID, "recordings/updatedAtMs", .number(1_790_720_435_698.833))),
        .insert(triple("af09826f", "transcriptions/wordCount", .number(3_000))),
      ]
    )
    let hint = InstantLiveJSONValue.object([
      "expected": .string("perms-pass?"),
      "input": .array([.string("recordings"), .string("object")]),
    ])

    let refusal = InstantMutationRefusal(hint: hint, transaction: transaction)

    expectNoDifference(
      refusal.metadata,
      [
        "refusedNamespace": "recordings",
        "refusedCheck": "perms-pass?",
        "refusedEntityIDs": recordingID,
        "refusedAttributes": "durationSeconds,updatedAtMs",
        "refusedValues":
          "52e9a666/durationSeconds=2210.230867; 52e9a666/updatedAtMs=1790720435698.833",
      ]
    )
  }

  @Test
  func showsLongTextAsItsLengthAndKnowsTheNamespaceWithoutTheTransaction() {
    let longText = String(repeating: "word ", count: 20)
    let refusal = InstantMutationRefusal(
      hint: .object(["input": .array([.string("transcriptionSegments"), .string("object")])]),
      transaction: InstantStoreTransaction(
        id: "5630a405",
        operations: [.insert(triple("e042229a-segment", "transcriptionSegments/text", .string(longText)))]
      )
    )
    expectNoDifference(refusal.values, ["e042229a/text=<100 characters>"])

    let hintOnly = InstantMutationRefusal(
      hint: .object(["input": .array([.string("recordings"), .string("object")])]),
      transaction: nil
    )
    expectNoDifference(hintOnly.namespace, "recordings")
    expectNoDifference(hintOnly.check, nil)
    expectNoDifference(hintOnly.entityIDs, [])
  }

  @Test
  func writesTheHintAsPlainJSON() {
    let hint = InstantLiveJSONValue.object(["input": .array([.string("recordings"), .string("object")])])
    expectNoDifference(hint.compactJSONText, #"{"input":["recordings","object"]}"#)
  }
}

private func triple(_ entityID: String, _ attributeID: String, _ value: InstantValue) -> InstantTriple {
  InstantTriple(
    entityID: entityID,
    attributeID: attributeID,
    value: value,
    txID: "tx",
    txTime: InstantTimestamp(milliseconds: 1)
  )
}
