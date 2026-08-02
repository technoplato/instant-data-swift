import CustomDump
import Foundation
import Testing

@Suite
struct RecipesV3PackagingContractTests {
  @Test
  func iOSAndMacBundlesRegisterTheAuthCallback() throws {
    for relativePath in [
      "Examples/RecipesV3/iOS-Info.plist",
      "Examples/RecipesV3/macOS-Info.plist",
    ] {
      let info = try propertyList(at: relativePath)
      let urlTypes = try #require(info["CFBundleURLTypes"] as? [[String: Any]])
      let schemes = urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }

      expectNoDifference(schemes, ["instant-recipes-v3"])
      expectNoDifference(
        info["InstantOAuthRedirectURL"] as? String,
        "instant-recipes-v3://oauth-callback"
      )
    }
  }

  @Test
  func iOSAndMacHostsCarryTheAppleCapability() throws {
    for relativePath in [
      "Examples/RecipesV3/RecipesV3iOS.entitlements",
      "Examples/RecipesV3/RecipesV3macOS.entitlements",
    ] {
      let entitlements = try propertyList(at: relativePath)
      expectNoDifference(
        entitlements["com.apple.developer.applesignin"] as? [String],
        ["Default"]
      )
    }

    let projectSpecification = try String(
      contentsOf: packageRootURL().appendingPathComponent("Examples/RecipesV3/project.yml"),
      encoding: .utf8
    )
    #expect(projectSpecification.contains("CODE_SIGN_ENTITLEMENTS: RecipesV3iOS.entitlements"))
    #expect(projectSpecification.contains("CODE_SIGN_ENTITLEMENTS: RecipesV3macOS.entitlements"))
  }

  private func propertyList(at relativePath: String) throws -> [String: Any] {
    let data = try Data(contentsOf: packageRootURL().appendingPathComponent(relativePath))
    return try #require(
      PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    )
  }

  private func packageRootURL(filePath: String = #filePath) -> URL {
    URL(fileURLWithPath: filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }
}
