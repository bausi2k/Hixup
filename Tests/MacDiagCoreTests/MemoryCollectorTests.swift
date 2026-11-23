import Testing
@testable import MacDiagCore

struct StubMemoryProvider: MemoryStatsProviding {
    let stats: RawMemoryStats
    func read() throws -> RawMemoryStats { stats }
}

struct FailingMemoryProvider: MemoryStatsProviding {
    func read() throws -> RawMemoryStats { throw CollectorError.systemCallFailed("host_statistics64") }
}

@Suite struct MemoryCollectorTests {
    private let page: UInt64 = 16_384

    @Test func availablePercentCountsFreeInactiveSpeculativeAndPurgeable() throws {
        let raw = RawMemoryStats(
            totalBytes: 100 * page, pageSize: page,
            freePages: 10, inactivePages: 5, speculativePages: 3, purgeablePages: 2,
            activePages: 50, wiredPages: 20, compressedPages: 10
        )
        let sample = try MemoryCollector(provider: StubMemoryProvider(stats: raw)).collect()
        #expect(sample.availablePercent == 20.0)
    }

    @Test func usedBytesExcludeAvailableMemory() throws {
        let raw = RawMemoryStats(
            totalBytes: 100 * page, pageSize: page,
            freePages: 10, inactivePages: 10, speculativePages: 0, purgeablePages: 0,
            activePages: 60, wiredPages: 20, compressedPages: 0
        )
        let sample = try MemoryCollector(provider: StubMemoryProvider(stats: raw)).collect()
        #expect(sample.usedBytes == 80 * page)
        #expect(sample.compressedBytes == 0)
    }

    @Test func zeroTotalMemoryYieldsZeroPercentInsteadOfCrashing() throws {
        let raw = RawMemoryStats(
            totalBytes: 0, pageSize: page,
            freePages: 0, inactivePages: 0, speculativePages: 0, purgeablePages: 0,
            activePages: 0, wiredPages: 0, compressedPages: 0
        )
        let sample = try MemoryCollector(provider: StubMemoryProvider(stats: raw)).collect()
        #expect(sample.availablePercent == 0)
    }

    @Test func providerErrorsArePropagated() {
        #expect(throws: CollectorError.self) {
            try MemoryCollector(provider: FailingMemoryProvider()).collect()
        }
    }

    @Test func systemProviderReturnsPlausibleValues() throws {
        let sample = try MemoryCollector().collect()
        #expect(sample.totalBytes > 1_000_000_000)
        #expect((0.0...100.0).contains(sample.availablePercent))
    }
}
