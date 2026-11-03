import Foundation
import Darwin
#if os(iOS)
import os
#endif

/// Process memory and thermal readings used for on-device measurements and the stats UI.
public enum DeviceDiagnostics {
    /// Physical footprint of this process in bytes — the number iOS jetsam compares against the limit.
    public static func physicalFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    /// Bytes the app can still allocate before hitting its jetsam limit (iOS only; nil elsewhere).
    public static func availableMemory() -> UInt64? {
        #if os(iOS)
        return UInt64(os_proc_available_memory())
        #else
        return nil
        #endif
    }

    /// System-wide memory. Metal buffers made resident for the GPU are *wired*: they are not part of the
    /// process footprint (so iOS cannot reclaim them by killing the app), yet they shrink what every
    /// other process can use. This is what has to stay in check.
    public struct SystemMemory: Sendable, Hashable, CustomStringConvertible {
        public var wired: UInt64
        public var free: UInt64
        public var compressed: UInt64
        public var fileBacked: UInt64

        public var description: String {
            "wired \(wired.formattedGB), free \(free.formattedGB), compressed \(compressed.formattedGB), file \(fileBacked.formattedGB)"
        }
    }

    public static func systemMemory() -> SystemMemory? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let page = UInt64(pageSize)
        return SystemMemory(
            wired: UInt64(stats.wire_count) * page,
            free: UInt64(stats.free_count) * page,
            compressed: UInt64(stats.compressor_page_count) * page,
            fileBacked: UInt64(stats.external_page_count) * page
        )
    }

    public static var thermalState: ProcessInfo.ThermalState {
        ProcessInfo.processInfo.thermalState
    }

    public static var physicalMemory: UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }
}

public extension ProcessInfo.ThermalState {
    var label: String {
        switch self {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }
}

public extension UInt64 {
    /// Human readable size in GB with two decimals, e.g. "6.72 GB".
    var formattedGB: String { String(format: "%.2f GB", Double(self) / 1_000_000_000) }
}
