import Darwin

/// Listet laufende Prozesse ueber `libproc`. Nicht lesbare Prozesse werden uebersprungen.
public struct SystemProcessLister: ProcessListing {
    public init() {}

    public func list() throws -> [RawProcess] {
        let pidCount = proc_listallpids(nil, 0)
        guard pidCount > 0 else { throw CollectorError.systemCallFailed("proc_listallpids") }

        var pids = [pid_t](repeating: 0, count: Int(pidCount) + 32)
        let bytes = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { throw CollectorError.systemCallFailed("proc_listallpids") }

        let timebase = Self.timebase()
        return pids.prefix(Int(bytes) / MemoryLayout<pid_t>.size)
            .filter { $0 > 0 }
            .compactMap { rawProcess(pid: $0, timebase: timebase) }
    }

    private func rawProcess(pid: pid_t, timebase: mach_timebase_info_data_t) -> RawProcess? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return nil }

        var nameBuffer = [CChar](repeating: 0, count: 256)
        proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
        let nameBytes = nameBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let name = String(decoding: nameBytes, as: UTF8.self)

        let ticks = info.pti_total_user + info.pti_total_system
        let nanoseconds = ticks * UInt64(timebase.numer) / UInt64(timebase.denom)

        return RawProcess(
            pid: pid,
            name: name.isEmpty ? "pid \(pid)" : name,
            residentBytes: info.pti_resident_size,
            cpuTimeNanoseconds: nanoseconds
        )
    }

    private static func timebase() -> mach_timebase_info_data_t {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info.denom == 0 ? mach_timebase_info_data_t(numer: 1, denom: 1) : info
    }
}
