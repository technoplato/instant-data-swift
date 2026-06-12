actor AsyncSerialGate {
  private var isRunning = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func enter() async {
    if !isRunning {
      isRunning = true
      return
    }

    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func leave() {
    if waiters.isEmpty {
      isRunning = false
    } else {
      let continuation = waiters.removeFirst()
      continuation.resume()
    }
  }
}
