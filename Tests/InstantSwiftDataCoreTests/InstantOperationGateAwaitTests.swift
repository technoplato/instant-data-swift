import Foundation
import Testing
@testable import InstantSwiftDataCore

/// #303: the library builds with `NonisolatedNonsendingByDefault`, and `InstantRuntime` is a class, so its async methods
/// ran on their caller's executor. Scribe observes the auth session from the main actor: `observeAuthSession()` took
/// the operation gate on main, and each of its awaits resumed on main. While SwiftUI's first render held the main
/// thread, the gate stayed held for 23-101 s, and every write, delivery claim, and observation waited behind it.
@Suite(.serialized)
struct InstantOperationGateAwaitTests {
  /// One-shot release for a suspended hook, settable from any task.
  final class Release: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func wait() async {
      await withCheckedContinuation { continuation in
        lock.lock()
        if released {
          lock.unlock()
          continuation.resume()
        } else {
          self.continuation = continuation
          lock.unlock()
        }
      }
    }

    func release() {
      lock.lock()
      released = true
      let continuation = self.continuation
      self.continuation = nil
      lock.unlock()
      continuation?.resume()
    }

    var isReleased: Bool {
      lock.lock()
      defer { lock.unlock() }
      return released
    }
  }

  /// Blocks the calling thread until `semaphore` is signalled, as a long main-thread render does.
  nonisolated static func blockCurrentThread(until semaphore: DispatchSemaphore) {
    semaphore.wait()
  }

  @Test
  func aMainActorCallerCannotHoldTheOperationGateWhileMainIsBusy() async throws {
    let (entered, enteredContinuation) = AsyncStream<Void>.makeStream()
    let release = Release()
    var configuration = InstantRuntimeConfiguration(
      appID: "operation-gate-main-actor",
      persistenceURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("operation-gate-main-actor-\(UUID().uuidString).sqlite"),
      initialAttributes: TodoExample.attributes
    )
    configuration.onAuthSessionObservationHoldsOperationGateForTesting = {
      enteredContinuation.yield(())
      await release.wait()
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    // 1. A main-actor caller takes the gate and suspends inside it, as Scribe's root view does.
    let observing = Task { @MainActor in
      _ = try await runtime.observeAuthSession()
    }
    var enteredIterator = entered.makeAsyncIterator()
    _ = await enteredIterator.next()

    // 2. The main thread gets busy, as during a first render under load, and stays busy until the write below has
    // returned. The write returning while main is still blocked shows it did not need main. This blocked main for 3 s
    // and required the write within 1.5 s, which the whole bundle's load broke on an idle machine (#1021).
    let mainIsBlocked = Release()
    let unblockMain = DispatchSemaphore(value: 0)
    let mainFinished = Release()
    let mainBusy = Task { @MainActor in
      mainIsBlocked.release()
      Self.blockCurrentThread(until: unblockMain)
      mainFinished.release()
    }
    defer { unblockMain.signal() }
    await mainIsBlocked.wait()

    // 3. The observation may continue. Its remaining work must not need the main thread.
    release.release()

    // 4. A write from another task must not wait for main. A write that needed main fails at the hang bound.
    _ = try await instantLiveWithTimeout(
      operation: "write while the main thread is blocked",
      timeoutMilliseconds: InstantTestWait.hangMilliseconds
    ) {
      try await runtime.transact(
        InstantStoreTransaction(
          id: "write-while-main-is-busy",
          operations: [
            .insert(InstantTriple(
              entityID: "todo-while-main-is-busy",
              attributeID: "todos/text",
              value: .string("written while main is busy"),
              txID: "write-while-main-is-busy",
              txTime: InstantTimestamp(milliseconds: 1)
            ))
          ]
        )
      )
    }
    #expect(!mainFinished.isReleased, "the write waited for the main thread")
    unblockMain.signal()
    await mainBusy.value
    _ = try await observing.value
  }
}
