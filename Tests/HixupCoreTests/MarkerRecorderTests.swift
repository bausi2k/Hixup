import Foundation
import Testing
@testable import HixupCore

@Suite struct MarkerRecorderTests {
    @Test func recordsMarkerAtTheCurrentTime() throws {
        let events = try SQLiteEventStore(path: ":memory:")
        let now = Date(timeIntervalSince1970: 500)
        let recorder = MarkerRecorder(events: events, now: { now })

        let marker = try recorder.mark()

        #expect(marker == Marker(timestamp: now, note: nil))
        #expect(try events.markers(from: .distantPast, to: .distantFuture) == [marker])
    }

    @Test func storesTheNote() throws {
        let events = try SQLiteEventStore(path: ":memory:")
        let recorder = MarkerRecorder(events: events, now: { Date(timeIntervalSince1970: 1) })

        try recorder.mark(note: "Citrix ruckelt")

        #expect(try events.markers(from: .distantPast, to: .distantFuture).first?.note == "Citrix ruckelt")
    }
}

@Suite struct WatchedNamesParsingTests {
    @Test func splitsOnCommasAndNewlinesAndTrims() {
        let names = AgentSettings.parseWatchedNames("Citrix Viewer, MsTeamsVdi\n  Slack  ")
        #expect(names == ["Citrix Viewer", "MsTeamsVdi", "Slack"])
    }

    @Test func dropsEmptyEntriesAndDuplicatesKeepingOrder() {
        #expect(AgentSettings.parseWatchedNames("a,, b,a,\n,b") == ["a", "b"])
    }

    @Test func emptyTextYieldsNoNames() {
        #expect(AgentSettings.parseWatchedNames("  \n ").isEmpty)
    }
}
