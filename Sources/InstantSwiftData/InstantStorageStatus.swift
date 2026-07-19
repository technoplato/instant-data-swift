import Dependencies
import Foundation

public protocol InstantStoredFileMatcher: Sendable {
  static func matches(_ file: InstantStoredFile) -> Bool
}

public struct InstantStorageFilesClearedEvent: Hashable, Sendable {
  public var fileCount: Int
  public var bytesRemoved: Int64

  public init(fileCount: Int, bytesRemoved: Int64) {
    self.fileCount = fileCount
    self.bytesRemoved = bytesRemoved
  }
}

#if canImport(SwiftUI)
  import SwiftUI

  @MainActor
  public final class InstantStorageStatusState: ObservableObject {
    @Published public private(set) var snapshot: InstantStorageSnapshot
    @Published public private(set) var isLoading = false
    @Published public private(set) var lastError: InstantError?

    private var didStartLoading = false
    private var loadGeneration = 0
    private var activeLoad: Task<Void, Never>?
    private var clearGeneration = 0
    private var activeClear: Task<Void, Never>?

    public init(snapshot: InstantStorageSnapshot = .empty) {
      self.snapshot = snapshot
    }

    public var localCacheSize: Int64 { snapshot.localCacheSize }
    public var streamCacheSize: Int64 { snapshot.streamCacheSize }
    public var downloadedFileSize: Int64 { snapshot.downloadedFileSize }
    public var downloadedFileCount: Int { snapshot.downloadedFileCount }

    public func loadIfNeeded() {
      @Dependency(\.defaultInstantSwiftData) var client
      loadIfNeeded(using: client)
    }

    public func loadIfNeeded(using client: InstantSwiftDataClient) {
      guard !didStartLoading else { return }
      didStartLoading = true
      _ = load(using: client)
    }

    @discardableResult
    public func load() -> Task<Void, Never> {
      @Dependency(\.defaultInstantSwiftData) var client
      return load(using: client)
    }

    @discardableResult
    public func load(using client: InstantSwiftDataClient) -> Task<Void, Never> {
      activeLoad?.cancel()
      loadGeneration += 1
      let generation = loadGeneration
      isLoading = true
      let task = Task { @MainActor [weak self] in
        do {
          let snapshot = try await client.storageSnapshot()
          try Task.checkCancellation()
          guard let self, self.loadGeneration == generation else { return }
          self.snapshot = snapshot
          self.lastError = nil
          self.isLoading = false
          self.activeLoad = nil
        } catch is CancellationError {
          guard let self, self.loadGeneration == generation else { return }
          self.isLoading = false
          self.activeLoad = nil
        } catch {
          guard let self, self.loadGeneration == generation else { return }
          self.lastError = Self.storageError(error, operation: "load storage status")
          self.isLoading = false
          self.activeLoad = nil
        }
      }
      activeLoad = task
      return task
    }

    @discardableResult
    public func clearDownloadedFiles<Matcher: InstantStoredFileMatcher>(
      matching matcher: Matcher.Type,
      onCleared: @escaping @MainActor @Sendable (InstantStorageFilesClearedEvent) -> Void = { _ in },
      onFailure: @escaping @MainActor @Sendable (InstantError) -> Void = { _ in }
    ) -> Task<Void, Never> {
      @Dependency(\.defaultInstantSwiftData) var client
      return clearDownloadedFiles(
        matching: matcher,
        using: client,
        onCleared: onCleared,
        onFailure: onFailure
      )
    }

    @discardableResult
    public func clearDownloadedFiles<Matcher: InstantStoredFileMatcher>(
      matching matcher: Matcher.Type,
      using client: InstantSwiftDataClient,
      onCleared: @escaping @MainActor @Sendable (InstantStorageFilesClearedEvent) -> Void = { _ in },
      onFailure: @escaping @MainActor @Sendable (InstantError) -> Void = { _ in }
    ) -> Task<Void, Never> {
      activeClear?.cancel()
      clearGeneration += 1
      let generation = clearGeneration
      let task = Task { @MainActor [weak self] in
        do {
          let files = try await client.storedFiles().filter(Matcher.matches)
          var deleted: [InstantStoredFile] = []
          for file in files {
            deleted.append(try await client.deleteStoredFile(id: file.id))
          }
          let snapshot = try await client.storageSnapshot()
          try Task.checkCancellation()
          guard let self, self.clearGeneration == generation else { return }
          self.snapshot = snapshot
          self.lastError = nil
          self.activeClear = nil
          onCleared(
            InstantStorageFilesClearedEvent(
              fileCount: deleted.count,
              bytesRemoved: deleted.reduce(0) { $0 + $1.byteCount }
            )
          )
        } catch is CancellationError {
          guard let self, self.clearGeneration == generation else { return }
          self.activeClear = nil
        } catch {
          guard let self, self.clearGeneration == generation else { return }
          let error = Self.storageError(error, operation: "clear downloaded files")
          self.lastError = error
          self.activeClear = nil
          onFailure(error)
        }
      }
      activeClear = task
      return task
    }

    private static func storageError(_ error: Error, operation: String) -> InstantError {
      if let error = error as? InstantError { return error }
      return InstantError(
        code: .persistenceFailed,
        operation: operation,
        message: String(describing: error),
        recovery: "Inspect the local Instant cache and retry the storage action."
      )
    }
  }

  @MainActor
  @propertyWrapper
  public struct InstantStorageStatus: DynamicProperty {
    @StateObject private var state: InstantStorageStatusState

    public init() {
      _state = StateObject(wrappedValue: InstantStorageStatusState())
    }

    public var wrappedValue: InstantStorageStatusState { state }

    public mutating func update() {
      state.loadIfNeeded()
    }
  }
#endif
