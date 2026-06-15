import Foundation

public enum AuthRecipeExample {
  public static let recipeSlug = "auth"
  public static let localEmailUserIDPrefix = "email:"

  public static func userEmail(from session: InstantAuthSession?) -> String? {
    guard let userID = session?.userID,
      userID.hasPrefix(localEmailUserIDPrefix)
    else { return nil }

    return String(userID.dropFirst(localEmailUserIDPrefix.count))
  }

  public static func isDashboardVisible(for session: InstantAuthSession?) -> Bool {
    session != nil
  }

  public static func isLoginVisible(for session: InstantAuthSession?) -> Bool {
    session == nil
  }

  public static func isEmailEntryVisible(
    session: InstantAuthSession?,
    challenge: InstantMagicCodeChallenge?
  ) -> Bool {
    session == nil && challenge == nil
  }

  public static func isCodeEntryVisible(
    session: InstantAuthSession?,
    challenge: InstantMagicCodeChallenge?
  ) -> Bool {
    session == nil && challenge != nil
  }
}
