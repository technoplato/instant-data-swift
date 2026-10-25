import Darwin
import Foundation

@testable import InstantSwiftDataCore

// #1147 (2026-10-24): which code makes an operation's allocations, so a fix starts from the call sites that make them
// instead of from a reading of the code. While installed, libmalloc's logger hook records every allocation's size and
// return addresses into memory reserved beforehand; afterwards each address is named (`atos` for this test bundle's
// code, which holds the library; `dladdr` for system libraries) and the allocations are grouped by the first library
// function on their stack, with the standard-library function that allocated and the library function that called it.
//
// The hook must not allocate: it takes a slot under an unfair lock and walks the frame pointers (`backtrace`), both
// free of malloc. Counts are process-wide, as `RealSizeAllocations`' are, so a recording runs alone.
//
// History:
// - 2026-10-24: #1147: the sampler.

enum MemoryAllocationSites {
  /// Allocations grouped by where they were made.
  struct Site: Sendable {
    /// The first library function on the stack (`InstantSwiftDataCore.`), or the first named frame when none is.
    var function: String
    /// The function that allocated: the frame just below `function` (`Dictionary`, `Array`, `swift_allocObject`, ...).
    var allocator: String
    /// The library function that called `function`.
    var caller: String
    var allocations: Int
    var bytes: Int
    /// One allocation's whole stack, innermost first, for the sites that need more than three frames to place.
    var sample: [String] = []
  }

  struct Recording: Sendable {
    var allocations: Int
    var bytes: Int
    /// Allocations past the reserved capacity, counted but not recorded.
    var dropped: Int
    var sites: [Site]
  }

  /// Records the allocations `body` makes, grouped by site, largest count first.
  static func record(depth: Int = 64, capacity: Int = 200_000, _ body: () async throws -> Void) async throws -> Recording {
    precondition(depth > 0 && capacity > 0)
    let buffer = Buffer(depth: depth, capacity: capacity)
    defer { buffer.deallocate() }
    guard let slot = loggerSlot else {
      preconditionFailure("libmalloc's malloc_logger is missing: allocations cannot be recorded on this system.")
    }
    current = buffer.state
    slot.pointee = hook
    do {
      try await body()
    } catch {
      slot.pointee = nil
      current = nil
      throw error
    }
    slot.pointee = nil
    current = nil
    return buffer.sites()
  }

  /// One line per site: `MEMORY-SITE <label> rank=… allocations=… bytes=… site=… allocator=… caller=…`.
  static func print(_ label: String, _ recording: Recording, top: Int = 40, iterations: Int = 1) {
    Swift.print(
      "MEMORY-SITES \(label) allocations=\(recording.allocations / max(1, iterations))"
        + " bytes=\(recording.bytes / max(1, iterations)) dropped=\(recording.dropped) sites=\(recording.sites.count)"
    )
    // `INSTANT_MEMORY_SITES_STACKS=n`: one whole stack for each of the top n sites.
    let stacks = ProcessInfo.processInfo.environment["INSTANT_MEMORY_SITES_STACKS"].flatMap(Int.init) ?? 0
    for (rank, site) in recording.sites.prefix(top).enumerated() {
      Swift.print(
        "MEMORY-SITE \(label) rank=\(rank + 1) allocations=\(site.allocations / max(1, iterations))"
          + " bytes=\(site.bytes / max(1, iterations)) site=\(site.function) allocator=\(site.allocator)"
          + " caller=\(site.caller)"
      )
      if rank < stacks {
        Swift.print("MEMORY-SITE-STACK \(label) rank=\(rank + 1) " + site.sample.prefix(24).joined(separator: " <- "))
      }
    }
    let byBytes = recording.sites.sorted { $0.bytes > $1.bytes }
    for (rank, site) in byBytes.prefix(top / 2).enumerated() {
      Swift.print(
        "MEMORY-SITE-BYTES \(label) rank=\(rank + 1) bytes=\(site.bytes / max(1, iterations))"
          + " allocations=\(site.allocations / max(1, iterations)) site=\(site.function) allocator=\(site.allocator)"
          + " caller=\(site.caller)"
      )
    }
  }

  // MARK: - Recording

  private typealias Logger = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void

  /// What the hook writes: a slot counter under a lock, and the records. Raw memory reserved before the hook is installed,
  /// so the hook touches no Swift object (no exclusivity check, no retain) while malloc calls it.
  private struct State {
    var lock = os_unfair_lock()
    var count = 0
    var dropped = 0
    var droppedBytes = 0
    var depth = 0
    var capacity = 0
    var frames: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
    var sizes: UnsafeMutablePointer<Int>?
  }

  private final class Buffer: @unchecked Sendable {
    // SAFETY: the hook writes only through `state`, a slot at a time under its lock; this object reads it after the hook
    // is removed.
    let state: UnsafeMutablePointer<State>

    init(depth: Int, capacity: Int) {
      let frames = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: depth * capacity)
      frames.initialize(repeating: nil, count: depth * capacity)
      let sizes = UnsafeMutablePointer<Int>.allocate(capacity: capacity)
      sizes.initialize(repeating: 0, count: capacity)
      state = .allocate(capacity: 1)
      state.initialize(to: State(depth: depth, capacity: capacity, frames: frames, sizes: sizes))
    }

    func deallocate() {
      state.pointee.frames?.deallocate()
      state.pointee.sizes?.deallocate()
      state.deallocate()
    }

    func sites() -> Recording {
      let depth = state.pointee.depth
      let recorded = min(state.pointee.count, state.pointee.capacity)
      let frames = state.pointee.frames!
      let sizes = state.pointee.sizes!
      func pc(_ record: Int, _ frame: Int) -> UInt { UInt(bitPattern: frames[record * depth + frame]) }
      var images: [UInt: (path: String, base: UInt)] = [:]
      var unique = Set<UInt>()
      for record in 0..<recorded {
        for frame in 0..<depth {
          let address = pc(record, frame)
          if address == 0 { break }
          unique.insert(address)
        }
      }
      for address in unique {
        var info = Dl_info()
        if dladdr(UnsafeRawPointer(bitPattern: address), &info) != 0, let path = info.dli_fname {
          images[address] = (String(cString: path), UInt(bitPattern: info.dli_fbase))
        }
      }
      let names = MemoryAllocationSites.names(of: unique, images: images)
      var grouped: [String: Site] = [:]
      var bytes = 0
      for record in 0..<recorded {
        bytes += sizes[record]
        var stack: [Frame] = []
        for frame in 0..<depth {
          let address = pc(record, frame)
          if address == 0 { break }
          stack.append(names[address] ?? Frame(function: "?", location: "", isLibrary: false))
        }
        var site = MemoryAllocationSites.site(of: stack)
        let key = site.function + "|" + site.allocator + "|" + site.caller
        if grouped[key] == nil { site.sample = stack.map(\.described) }
        grouped[key, default: site].allocations += 1
        grouped[key, default: site].bytes += sizes[record]
      }
      let sites = grouped.values.sorted { ($0.allocations, $0.bytes) > ($1.allocations, $1.bytes) }
      return Recording(
        allocations: recorded + state.pointee.dropped, bytes: bytes + state.pointee.droppedBytes,
        dropped: state.pointee.dropped, sites: sites
      )
    }
  }

  nonisolated(unsafe) private static var current: UnsafeMutablePointer<State>?

  nonisolated(unsafe) private static let loggerSlot: UnsafeMutablePointer<Logger?>? =
    dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger")?.assumingMemoryBound(to: Logger?.self)

  // libmalloc's malloc_logger types (malloc/malloc.h's MALLOC_LOG_TYPE_*, private), as `RealSizeAllocations` reads them.
  private static let allocateBit: UInt32 = 2
  private static let deallocateBit: UInt32 = 4
  private static let hasZoneBit: UInt32 = 8

  private static let hook: Logger = { type, _, argument2, argument3, _, _ in
    guard type & MemoryAllocationSites.hasZoneBit != 0, type & MemoryAllocationSites.allocateBit != 0,
      let state = MemoryAllocationSites.current
    else { return }
    let size = Int(type & MemoryAllocationSites.deallocateBit != 0 ? argument3 : argument2)
    os_unfair_lock_lock(&state.pointee.lock)
    let slot = state.pointee.count
    let capacity = state.pointee.capacity
    if slot < capacity {
      state.pointee.count += 1
    } else {
      state.pointee.dropped += 1
      state.pointee.droppedBytes += size
    }
    os_unfair_lock_unlock(&state.pointee.lock)
    guard slot < capacity, let frames = state.pointee.frames, let sizes = state.pointee.sizes else { return }
    let depth = state.pointee.depth
    sizes[slot] = size
    let record = frames + slot * depth
    let walked = Int(backtrace(record, Int32(depth)))
    for frame in 0..<walked {
      // Return addresses, without pointer-authentication bits.
      record[frame] = UnsafeMutableRawPointer(bitPattern: UInt(bitPattern: record[frame]) & 0x0000_7FFF_FFFF_FFFF)
    }
  }

  // MARK: - Naming

  /// One return address, named.
  private struct Frame {
    var function: String
    /// `File.swift:line`, when the image has line information.
    var location: String
    /// Whether the code is the library's: its file is one of `Sources/InstantSwiftDataCore`'s.
    var isLibrary: Bool

    var described: String { location.isEmpty ? function : "\(function)@\(location)" }
  }

  /// The library's source folder, found from this file's path, to tell its frames from the tests' in the one image both
  /// are linked into.
  private static let librarySources: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // RealSize
    .deletingLastPathComponent()  // InstantSwiftDataCoreTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()
    .appendingPathComponent("Sources/InstantSwiftDataCore", isDirectory: true)

  /// Each address's frame: `atos` for this bundle's image (the library and the tests), `dladdr` for system libraries.
  private static func names(of pcs: Set<UInt>, images: [UInt: (path: String, base: UInt)]) -> [UInt: Frame] {
    var names: [UInt: Frame] = [:]
    var byImage: [String: (base: UInt, pcs: [UInt])] = [:]
    for pc in pcs {
      guard let image = images[pc] else { continue }
      if image.path.contains("InstantSwiftData") || image.path.contains("PackageTests") {
        byImage[image.path, default: (image.base, [])].pcs.append(pc)
      } else {
        var info = Dl_info()
        let function: String
        if dladdr(UnsafeRawPointer(bitPattern: pc), &info) != 0, let symbol = info.dli_sname {
          function = shortened(demangled(String(cString: symbol)))
        } else {
          function = (image.path as NSString).lastPathComponent
        }
        names[pc] = Frame(function: function, location: "", isLibrary: false)
      }
    }
    var libraryFiles: [String: Bool] = [:]
    for (path, image) in byImage {
      for batch in stride(from: 0, to: image.pcs.count, by: 2_000) {
        let pcs = Array(image.pcs[batch..<min(image.pcs.count, batch + 2_000)])
        for (pc, line) in zip(pcs, atos(path: path, base: image.base, pcs: pcs)) {
          // `function (in image) (File.swift:123)`
          var function = line
          var location = ""
          if let range = line.range(of: " (in ") {
            function = String(line[..<range.lowerBound])
            if let open = line.range(of: ") (", range: range.upperBound..<line.endIndex) {
              location = String(line[open.upperBound...].dropLast())
            }
          }
          let file = String(location.split(separator: ":").first ?? "")
          let isLibrary: Bool
          if file.isEmpty {
            isLibrary = false
          } else if let known = libraryFiles[file] {
            isLibrary = known
          } else {
            isLibrary = FileManager.default.fileExists(atPath: librarySources.appendingPathComponent(file).path)
            libraryFiles[file] = isLibrary
          }
          names[pc] = Frame(function: shortened(function), location: location, isLibrary: isLibrary)
        }
      }
    }
    return names
  }

  /// `atos -o <image> -l <load address> <addresses...>`: one line per address.
  private static func atos(path: String, base: UInt, pcs: [UInt]) -> [String] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/atos")
    // Return addresses point after the call; one byte back is inside it.
    process.arguments = ["-o", path, "-l", String(format: "0x%llx", UInt64(base))]
      + pcs.map { String(format: "0x%llx", UInt64($0 - 1)) }
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return pcs.map { _ in "?" } }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let lines = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
    return pcs.indices.map { $0 < lines.count ? String(lines[$0]) : "?" }
  }

  private static func demangled(_ symbol: String) -> String {
    typealias Demangle = @convention(c) (UnsafePointer<CChar>?, Int, UnsafeMutablePointer<CChar>?, UnsafeMutablePointer<Int>?, UInt32) -> UnsafeMutablePointer<CChar>?
    guard let address = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "swift_demangle") else { return symbol }
    let demangle = unsafeBitCast(address, to: Demangle.self)
    return symbol.withCString { mangled in
      guard let result = demangle(mangled, strlen(mangled), nil, nil, 0) else { return symbol }
      defer { free(result) }
      return String(cString: result)
    }
  }

  /// The first library frame, the frame below it that allocated, and the library frame above it.
  private static func site(of stack: [Frame]) -> Site {
    guard let first = stack.firstIndex(where: \.isLibrary) else {
      let skipped = ["malloc", "_malloc", "swift_slowAlloc", "_ZN5swift20swift_slowAlloc", "swift_allocObject",
        "swift_task_alloc", "_ZN5swift", "?"]
      let named = stack.first { frame in
        !frame.function.contains("MemoryAllocationSites") && !skipped.contains { frame.function.hasPrefix($0) }
      }
      return Site(function: "(no library frame) " + (named?.described ?? "?"), allocator: "-", caller: "-", allocations: 0, bytes: 0)
    }
    let allocator = first > 0 ? stack[first - 1].function : "-"
    let caller = stack[(first + 1)...].first(where: \.isLibrary)?.described ?? "-"
    return Site(function: stack[first].described, allocator: allocator, caller: caller, allocations: 0, bytes: 0)
  }

  /// A function's name without its module, generic context or spaces.
  private static func shortened(_ name: String) -> String {
    var name = name
    for prefix in ["InstantSwiftDataCore.", "Swift.", "Foundation."] {
      name = name.replacingOccurrences(of: prefix, with: "")
    }
    if let range = name.range(of: " in ") { name = String(name[range.upperBound...]) + "{closure}" }
    name = name.replacingOccurrences(of: " ", with: "")
    return String(name.prefix(140))
  }
}
