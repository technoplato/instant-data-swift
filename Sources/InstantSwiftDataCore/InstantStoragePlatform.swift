import Foundation

/// The platform the library chooses its default folders for.
///
/// tvOS lets an app write only its Caches and tmp folders. On an Apple TV, creating a folder in
/// Application Support or Library fails with `EPERM` (`NSCocoaErrorDomain` 513), though the tvOS
/// simulator allows it. So on tvOS every default folder the library writes is under Caches. The
/// system may purge Caches when the device runs low on space; the local store is then rebuilt
/// from the server on the next launch.
public enum InstantStoragePlatform: Sendable, Hashable {
  case iOS
  case macOS
  case tvOS
  case visionOS
  case watchOS

  /// The platform this code is running on.
  public static var current: Self {
    #if os(tvOS)
      .tvOS
    #elseif os(watchOS)
      .watchOS
    #elseif os(visionOS)
      .visionOS
    #elseif os(iOS)
      .iOS
    #else
      .macOS
    #endif
  }

  /// The folder an app keeps its data in between launches.
  public var applicationDataDirectory: FileManager.SearchPathDirectory {
    self == .tvOS ? .cachesDirectory : .applicationSupportDirectory
  }

  /// The folder that holds the `Logs` folder.
  public var logsParentDirectory: FileManager.SearchPathDirectory {
    self == .tvOS ? .cachesDirectory : .libraryDirectory
  }
}
