import CustomDump
import InstantSwiftDataCore
import InstantSwiftDataSchema
import Testing

@Suite
struct MobileChatContractTests {
  @Test
  func schemaPreservesTheCanonicalMobileChatGraphAndRoomPayloads() {
    let document = InstantSchemaExamples.mobileChatDocument

    expectNoDifference(
      document.attributes.sorted { $0.id < $1.id },
      MobileChatExample.attributes.sorted { $0.id < $1.id }
    )
    expectNoDifference(
      document.entities.map(\.namespace),
      ["$files", "$users", "mobileProfiles", "mobileChannels", "mobileMessages"]
    )
    expectNoDifference(
      document.links.map(\.name),
      [
        "mobileUsersLinkedPrimaryUser",
        "mobileProfilesUser",
        "mobileMessagesAuthor",
        "mobileMessagesChannel",
      ]
    )

    let room = document.rooms.first
    expectNoDifference(room?.name, "chat")
    expectNoDifference(room?.presence.attributes.map(\.name), ["profileID", "displayName"])
    expectNoDifference(room?.topics.map(\.name), ["typing", "emoji"])
    expectNoDifference(
      room?.topics.first { $0.name == "typing" }?.payload.attributes.map(\.name),
      ["isTyping"]
    )
    expectNoDifference(
      room?.topics.first { $0.name == "emoji" }?.payload.attributes.map(\.name),
      ["name", "directionAngle", "rotationAngle"]
    )
  }

  @Test
  func permissionsRequireAuthenticationAndProfileOwnership() {
    let permissions = Dictionary(
      uniqueKeysWithValues: InstantSchemaExamples.mobileChatPermissions.namespaces.map {
        ($0.namespace, $0)
      }
    )

    expectNoDifference(permissions["$users"]?.allow, [.view: "auth.id != null"])
    expectNoDifference(
      permissions["mobileProfiles"]?.allow,
      [
        .view: "auth.id != null",
        .create: "isSelf",
        .update: "isSelf",
        .delete: "isSelf",
      ]
    )
    expectNoDifference(
      permissions["mobileProfiles"]?.bind,
      [InstantPermissionBinding("isSelf", "auth.id in data.ref('user.id')")]
    )
    expectNoDifference(
      permissions["mobileMessages"]?.allow,
      [
        .view: "auth.id != null",
        .create: "isAuthor",
        .update: "isAuthor",
        .delete: "isAuthor",
      ]
    )
    expectNoDifference(
      permissions["mobileMessages"]?.bind,
      [InstantPermissionBinding("isAuthor", "auth.id in data.ref('author.user.id')")]
    )
  }
}
