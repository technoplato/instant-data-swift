import Foundation

#if canImport(Darwin)
  import Darwin
#endif

/// Process memory samples for performance budgets.
///
/// **VSZ / virtual size is not RAM.** On Apple Silicon a Debug GUI process often
/// reports hundreds of gigabytes of virtual address space (dyld shared cache,
/// stack guards, reserved regions). Gate releases on **physical footprint** and
/// **resident** size — the same numbers that Jetsam and Activity Monitor care
/// about.
public struct InstantProcessMemorySample: Hashable, Sendable {
  public var physicalFootprintBytes: UInt64
  public var residentBytes: UInt64
  public var virtualBytes: UInt64

  public init(
    physicalFootprintBytes: UInt64,
    residentBytes: UInt64,
    virtualBytes: UInt64
  ) {
    self.physicalFootprintBytes = physicalFootprintBytes
    self.residentBytes = residentBytes
    self.virtualBytes = virtualBytes
  }
}

public enum InstantProcessMemory {
  /// Best-effort live sample. Returns `nil` on unsupported platforms or if the
  /// kernel call fails.
  public static func sample() -> InstantProcessMemorySample? {
    #if canImport(Darwin)
      var info = task_vm_info_data_t()
      var count = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
      )
      let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
          task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
        }
      }
      guard result == KERN_SUCCESS else { return nil }
      return InstantProcessMemorySample(
        physicalFootprintBytes: UInt64(info.phys_footprint),
        residentBytes: UInt64(info.resident_size),
        virtualBytes: UInt64(info.virtual_size)
      )
    #else
      return nil
    #endif
  }
}
