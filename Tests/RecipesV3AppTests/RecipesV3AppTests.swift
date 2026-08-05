import CustomDump
import Foundation
import RecipesV3App
import Testing

@Suite
struct RecipesV3AppTests {
  @Test
  func catalogMatchesTheUpstreamRecipeOrder() {
    expectNoDifference(
      InstantRecipeV3.allCases.map(\.rawValue),
      [
        "todos",
        "sharing",
        "linked-infinite",
        "cursors",
        "custom-cursors",
        "reactions",
        "typing-indicator",
        "avatar-stack",
        "merge-tile-game",
        "auth",
      ]
    )
  }

  @Test
  func environmentConfigurationEnablesLiveSyncAndLaunchesARecipe() {
    let configuration = RecipesV3AppConfiguration.environment(
      [
        "INSTANT_APPLE_AUTH_CLIENT_NAME": "apple-ios",
        "INSTANT_APP_ID": "app-123",
        "INSTANT_GOOGLE_AUTH_CLIENT_NAME": "google-web",
        "INSTANT_OAUTH_REDIRECT_URL": "instant-recipes-v3://oauth-callback",
        "INSTANT_PERSISTENCE_PATH": "/tmp/instant-recipes.sqlite",
        "INSTANT_RECIPE": "custom-cursors",
        "INSTANT_RECIPE_PROFILE_ID": "profile-123",
      ],
      arguments: ["recipes-v3"],
      infoDictionary: [:],
      makeProfileID: { "generated" }
    )

    expectNoDifference(
      configuration,
      RecipesV3AppConfiguration(
        appID: "app-123",
        persistenceURL: URL(fileURLWithPath: "/tmp/instant-recipes.sqlite"),
        enablesLiveSync: true,
        profileID: "profile-123",
        launchRecipe: .customCursors,
        authProviderConfiguration: configuration.authProviderConfiguration
      )
    )
    expectNoDifference(configuration.authProviderConfiguration.appleClientName, "apple-ios")
    expectNoDifference(configuration.authProviderConfiguration.googleClientName, "google-web")
    expectNoDifference(
      configuration.authProviderConfiguration.browserRedirectURL,
      URL(string: "instant-recipes-v3://oauth-callback")
    )
  }

  @Test
  func localConfigurationIgnoresUnexpandedBuildSettings() {
    let configuration = RecipesV3AppConfiguration.environment(
      [:],
      arguments: ["recipes-v3", "--recipe", "merge-tile-game"],
      infoDictionary: ["InstantAppID": "$(INSTANT_APP_ID)"],
      makeProfileID: { "generated-profile" }
    )

    expectNoDifference(
      configuration,
      RecipesV3AppConfiguration(
        appID: "recipes-v3-local",
        enablesLiveSync: false,
        profileID: "generated-profile",
        launchRecipe: .mergeTileGame
      )
    )
    expectNoDifference(
      configuration.authProviderConfiguration.browserRedirectURL,
      URL(string: "instant-recipes-v3://oauth-callback")
    )
  }

  @Test
  func bundleConfigurationUsesAppOwnedProviderMetadata() {
    let configuration = RecipesV3AppConfiguration.environment(
      [:],
      arguments: ["recipes-v3"],
      infoDictionary: [
        "InstantAppID": "app-from-bundle",
        "InstantAppleAuthClientName": "apple-mac",
        "InstantGoogleAuthClientName": "google",
        "InstantOAuthRedirectURL": "instant-recipes-v3://oauth-callback",
      ],
      makeProfileID: { "generated-profile" }
    )

    expectNoDifference(configuration.appID, "app-from-bundle")
    expectNoDifference(configuration.authProviderConfiguration.appleClientName, "apple-mac")
    expectNoDifference(configuration.authProviderConfiguration.googleClientName, "google")
    expectNoDifference(
      configuration.authProviderConfiguration.browserRedirectURL,
      URL(string: "instant-recipes-v3://oauth-callback")
    )
  }

  @Test
  func combinedSchemaContainsEveryDurableRecipeNamespace() {
    let namespaces = Set(RecipesV3AppConfiguration.initialAttributes.map(\.namespace))
    #expect(namespaces.isSuperset(of: [
      "todos",
      "boards",
      "$users",
      "linked_infinite_recordings",
      "linked_infinite_transcriptions",
      "linked_infinite_words",
      "recipe_public_counters",
      "recipe_account_counters",
      "recipe_private_notes",
    ]))
  }
}
