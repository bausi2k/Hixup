import Foundation
import Testing
@testable import HixupCore

private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

private func detail() -> SystemDetail {
    SystemDetail(
        memoryPressure: .warning, swapUsedBytes: 1, swapTotalBytes: 2, thermal: .nominal, lowPowerMode: false,
        network: NetworkDetail(interface: "en0", kind: .ethernet, gateway: nil, internet: nil)
    )
}

@Suite struct MarkerNoteStorageTests {
    @Test func noteCanBeSetAfterwardsAndKeepsTimestampAndDetail() throws {
        let store = try SQLiteEventStore(path: ":memory:")
        try store.addMarker(Marker(timestamp: date(100), note: nil))
        try store.setMarkerDetail(detail(), at: date(100))

        try store.setMarkerNote("Citrix hängt", at: date(100))

        let marker = try #require(store.markers(from: date(0), to: date(200)).first)
        #expect(marker.note == "Citrix hängt")
        #expect(marker.timestamp == date(100))
        #expect(marker.detail == detail())
    }

    @Test func noteCanBeChangedAndRemoved() throws {
        let store = try SQLiteEventStore(path: ":memory:")
        try store.addMarker(Marker(timestamp: date(100), note: "alt"))

        try store.setMarkerNote("neu", at: date(100))
        #expect(try store.markers(from: date(0), to: date(200)).first?.note == "neu")

        try store.setMarkerNote(nil, at: date(100))
        #expect(try store.markers(from: date(0), to: date(200)).first?.note == nil)
    }

    @Test func onlyTheMarkerWithThatTimestampChanges() throws {
        let store = try SQLiteEventStore(path: ":memory:")
        try store.addMarker(Marker(timestamp: date(100), note: "a"))
        try store.addMarker(Marker(timestamp: date(200), note: "b"))

        try store.setMarkerNote("x", at: date(100))

        let notes = try store.markers(from: date(0), to: date(300)).map(\.note)
        #expect(notes == ["x", "b"])
    }
}

@Suite struct MarkerRecorderNoteTests {
    private func recorder() throws -> (MarkerRecorder, SQLiteEventStore) {
        let store = try SQLiteEventStore(path: ":memory:")
        return (MarkerRecorder(events: store, now: { date(100) }), store)
    }

    @Test func updateNoteTrimsWhitespaceAndStoresTheText() throws {
        let (recorder, store) = try recorder()
        let marker = try recorder.mark()

        let updated = try recorder.updateNote("  Ton knackst \n", for: marker)

        #expect(updated.note == "Ton knackst")
        #expect(try store.markers(from: date(0), to: date(200)).first?.note == "Ton knackst")
    }

    @Test func emptyOrBlankNoteRemovesTheNote() throws {
        let (recorder, store) = try recorder()
        let marker = try recorder.mark(note: "alt")

        let updated = try recorder.updateNote("   ", for: marker)

        #expect(updated.note == nil)
        #expect(try store.markers(from: date(0), to: date(200)).first?.note == nil)
    }

    @Test func veryLongNotesAreShortened() throws {
        let (recorder, _) = try recorder()
        let marker = try recorder.mark()
        let updated = try recorder.updateNote(String(repeating: "a", count: 500), for: marker)
        #expect(updated.note?.count == MarkerRecorder.maxNoteLength)
    }

    @Test func updateKeepsTheDeepMeasurementOfTheMarker() throws {
        let (recorder, _) = try recorder()
        let marker = Marker(timestamp: date(100), note: nil, detail: detail())
        let updated = try recorder.updateNote("x", for: marker)
        #expect(updated.detail == detail())
    }
}
