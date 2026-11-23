import Darwin

/// Liest Speicherzaehler ueber `host_statistics64` und `sysctl`.
public struct MachMemoryStatsProvider: MemoryStatsProviding {
    public init() {}

    public func read() throws -> RawMemoryStats {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            throw CollectorError.systemCallFailed("host_statistics64")
        }

        let memsize = try sysctlValue("hw.memsize", as: UInt64.self)
        let pageSize = try sysctlValue("hw.pagesize", as: UInt64.self)

        // free_count enthaelt spekulative Seiten; getrennt ausweisen, um Doppelzaehlung zu vermeiden.
        let speculative = UInt64(stats.speculative_count)
        let free = UInt64(stats.free_count)

        return RawMemoryStats(
            totalBytes: memsize,
            pageSize: pageSize,
            freePages: free > speculative ? free - speculative : 0,
            inactivePages: UInt64(stats.inactive_count),
            speculativePages: speculative,
            purgeablePages: UInt64(stats.purgeable_count),
            activePages: UInt64(stats.active_count),
            wiredPages: UInt64(stats.wire_count),
            compressedPages: UInt64(stats.compressor_page_count)
        )
    }

    private func sysctlValue<T: FixedWidthInteger>(_ name: String, as type: T.Type) throws -> T {
        var value: T = 0
        var size = MemoryLayout<T>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else {
            throw CollectorError.systemCallFailed("sysctl \(name)")
        }
        return value
    }
}
