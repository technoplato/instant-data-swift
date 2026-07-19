import CustomDump
import Foundation
import InstantSwiftDataTesting
import Testing

// Canonical source:
// pointfreeco/sqlite-data@0c79d7a5748fc6d9ce7a1ba2b50f31b175305049
@Suite
struct InstantRemindersV3LiveValidationTests {
  @Test
  func fixturesMatchTheCanonicalTypeScriptContract() {
    expectNoDifference(
      InstantRemindersV3LiveValidation.listID,
      "00000000-0000-4000-8000-000000000401"
    )
    expectNoDifference(
      InstantRemindersV3LiveValidation.swiftReminderID,
      "00000000-0000-4000-8000-000000000402"
    )
    expectNoDifference(
      InstantRemindersV3LiveValidation.shareID,
      "00000000-0000-4000-8000-000000000403"
    )
    expectNoDifference(
      InstantRemindersV3LiveValidation.ownerMembershipID,
      "00000000-0000-4000-8000-000000000404"
    )
    expectNoDifference(
      InstantRemindersV3LiveValidation.readerMembershipID,
      "00000000-0000-4000-8000-000000000405"
    )
    expectNoDifference(
      InstantRemindersV3LiveValidation.typeScriptReminderID,
      "00000000-0000-4000-8000-000000000406"
    )
    expectNoDifference(
      InstantRemindersV3LiveValidation.swiftTagID,
      "00000000-0000-4000-8000-000000000407"
    )
    expectNoDifference(
      InstantRemindersV3LiveValidation.typeScriptTagID,
      "00000000-0000-4000-8000-000000000408"
    )
  }

  @Test
  func evidenceRoundTripsExactSharingAndReminderShapes() throws {
    let details = InstantRemindersV3LiveValidationDetails(
      list: InstantRemindersV3LiveListEvidence(
        id: InstantRemindersV3LiveValidation.listID,
        title: "Family",
        color: "#4a99ef",
        position: 0,
        ownerID: "owner-user",
        readerIDs: [],
        writerIDs: ["reader-user"],
        shareID: InstantRemindersV3LiveValidation.shareID,
        membershipRoles: ["owner-user:owner", "reader-user:writer"]
      ),
      swiftReminder: InstantRemindersV3LiveReminderEvidence(
        id: InstantRemindersV3LiveValidation.swiftReminderID,
        title: "Pack lunch from TypeScript",
        notes: "Fruit and water",
        isCompleted: false,
        isFlagged: true,
        dueDateMilliseconds: 1_700_086_400_000,
        priority: 3,
        position: 0,
        tagIDs: [InstantRemindersV3LiveValidation.swiftTagID]
      ),
      typeScriptReminderObservedBySwift: InstantRemindersV3LiveReminderEvidence(
        id: InstantRemindersV3LiveValidation.typeScriptReminderID,
        title: "TypeScript reminder",
        notes: "Created by @instantdb/core",
        isCompleted: false,
        isFlagged: false,
        dueDateMilliseconds: nil,
        priority: 2,
        position: 1,
        tagIDs: [InstantRemindersV3LiveValidation.typeScriptTagID]
      ),
      connectionState: "authenticated",
      pendingMutationCount: 0
    )

    let encoded = try JSONEncoder().encode(details)
    expectNoDifference(
      try JSONDecoder().decode(InstantRemindersV3LiveValidationDetails.self, from: encoded),
      details
    )
  }
}
