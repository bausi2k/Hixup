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
        let shortName = String(decoding: nameBytes, as: UTF8.self)
        let name = ProcessNaming.displayName(path: executablePath(pid: pid), fallback: shortName, pid: pid)

        let ticks = info.pti_total_user + info.pti_total_system
        let nanoseconds = ticks * UInt64(timebase.numer) / UInt64(timebase.denom)
        let usage = resourceUsage(pid: pid)

        return RawProcess(
            pid: pid,
            name: name,
            residentBytes: info.pti_resident_size,
            cpuTimeNanoseconds: nanoseconds,
            energyNanojoules: usage?.ri_energy_nj ?? 0,
            wakeups: usage.map { $0.ri_pkg_idle_wkups + $0.ri_interrupt_wkups } ?? 0
        )
    }

    private func executablePath(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4_096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    /// Energie- und Wakeup-Zaehler; fehlt bei Prozessen, auf die ohne Rechte nicht zugegriffen werden darf.
    private func resourceUsage(pid: pid_t) -> rusage_info_v6? {
        var usage = rusage_info_v6()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
            }
        }
        return result == 0 ? usage : nil
    }

    private static func timebase() -> mach_timebase_info_data_t {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info.denom == 0 ? mach_timebase_info_data_t(numer: 1, denom: 1) : info
    }
}
