import CustomDump
import SyncUpsV3App
import Testing

@Suite
struct SyncUpsV3AppTests {
  @Test
  func environmentConfigurationSelectsLocalAndLiveModes() {
    expectNoDifference(
      SyncUpsV3AppConfiguration.environment([:]),
      SyncUpsV3AppConfiguration(appID: "syncups-v3-local", enablesLiveSync: false)
    )
    expectNoDifference(
      SyncUpsV3AppConfiguration.environment(["INSTANT_APP_ID": "syncups-live"]),
      SyncUpsV3AppConfiguration(appID: "syncups-live", enablesLiveSync: true)
    )
  }
}
