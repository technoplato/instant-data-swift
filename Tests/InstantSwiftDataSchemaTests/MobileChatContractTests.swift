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
      document.attributes.map(\.id).sorted(),
      [
        "$files/id",
        "$files/path",
        "$files/url",
        "$users/email",
        "$users/id",
        "$users/imageURL",
        "$users/linkedPrimaryUser",
        "$users/type",
        "channels/id",
        "channels/name",
        "messages/author",
        "messages/channel",
        "messages/content",
        "messages/id",
        "messages/timestamp",
        "profiles/displayName",
        "profiles/id",
        "profiles/user",
      ]
    )
    expectNoDifference(
      document.entities.map(\.namespace),
      ["$files", "$users", "profiles", "channels", "messages"]
    )
    expectNoDifference(
      document.links.map(\.name),
      [
        "$usersLinkedPrimaryUser",
        "userProfile",
        "authorMessages",
        "channelMessages",
      ]
    )

    let room = document.rooms.first
    expectNoDifference(room?.name, "chat")
    expectNoDifference(room?.presence.attributes.map(\.name), ["profileId", "displayName"])
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
      permissions["profiles"]?.allow,
      [
        .view: "auth.id != null",
        .create: "isSelf",
        .update: "isSelf",
        .delete: "isSelf",
      ]
    )
    expectNoDifference(
      permissions["profiles"]?.bind,
      [InstantPermissionBinding("isSelf", "auth.id in data.ref('user.id')")]
    )
    expectNoDifference(
      permissions["messages"]?.allow,
      [
        .view: "auth.id != null",
        .create: "isAuthor",
        .update: "isAuthor",
        .delete: "isAuthor",
      ]
    )
    expectNoDifference(
      permissions["messages"]?.bind,
      [InstantPermissionBinding("isAuthor", "auth.id in data.ref('author.user.id')")]
    )
  }
}
