/// Rohe Seitenzaehler des Kernels. `freePages` enthaelt keine spekulativen Seiten.
public struct RawMemoryStats: Equatable, Sendable {
    public var totalBytes: UInt64
    public var pageSize: UInt64
    public var freePages: UInt64
    public var inactivePages: UInt64
    public var speculativePages: UInt64
    public var purgeablePages: UInt64
    public var activePages: UInt64
    public var wiredPages: UInt64
    public var compressedPages: UInt64

    public init(
        totalBytes: UInt64, pageSize: UInt64,
        freePages: UInt64, inactivePages: UInt64, speculativePages: UInt64, purgeablePages: UInt64,
        activePages: UInt64, wiredPages: UInt64, compressedPages: UInt64
    ) {
        self.totalBytes = totalBytes
        self.pageSize = pageSize
        self.freePages = freePages
        self.inactivePages = inactivePages
        self.speculativePages = speculativePages
        self.purgeablePages = purgeablePages
        self.activePages = activePages
        self.wiredPages = wiredPages
        self.compressedPages = compressedPages
    }
}

public protocol MemoryStatsProviding: Sendable {
    func read() throws -> RawMemoryStats
}

public struct MemoryCollector: Sendable {
    private let provider: any MemoryStatsProviding

    public init(provider: any MemoryStatsProviding = MachMemoryStatsProvider()) {
        self.provider = provider
    }

    public func collect() throws -> MemorySample {
        let raw = try provider.read()
        let availablePages = raw.freePages + raw.inactivePages + raw.speculativePages + raw.purgeablePages
        let availableBytes = min(availablePages * raw.pageSize, raw.totalBytes)
        let percent = raw.totalBytes == 0 ? 0 : Double(availableBytes) / Double(raw.totalBytes) * 100

        return MemorySample(
            totalBytes: raw.totalBytes,
            usedBytes: raw.totalBytes - availableBytes,
            compressedBytes: raw.compressedPages * raw.pageSize,
            availablePercent: percent
        )
    }
}
