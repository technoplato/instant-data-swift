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
        "INSTANT_APP_ID": "app-123",
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
        launchRecipe: .customCursors
      )
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
  }

  @Test
  func combinedSchemaContainsEveryDurableRecipeNamespace() {
    expectNoDifference(
      Set(RecipesV3AppConfiguration.initialAttributes.map(\.namespace)),
      Set(["todos", "boards", "$users"])
    )
  }
}
