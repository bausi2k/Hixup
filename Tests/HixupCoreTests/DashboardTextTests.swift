import Foundation
import Testing
@testable import HixupCore

@Suite struct DashboardTextTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test func groupsItemsByDayNewestFirst() {
        let day = 86_400.0
        let dates = [10.0, day + 5, 20.0, 2 * day + 1].map { Date(timeIntervalSince1970: $0) }

        let groups = DayGrouping.group(dates, date: { $0 }, calendar: utc)

        #expect(groups.count == 3)
        #expect(groups.map(\.items.count) == [1, 1, 2])
        #expect(groups[0].items == [Date(timeIntervalSince1970: 2 * day + 1)])
        #expect(groups[2].items == [Date(timeIntervalSince1970: 20), Date(timeIntervalSince1970: 10)])
        #expect(groups[2].day == Date(timeIntervalSince1970: 0))
    }

    @Test func emptyInputGivesNoGroups() {
        #expect(DayGrouping.group([Date](), date: { $0 }, calendar: utc).isEmpty)
    }

    @Test func valuesAreFormattedWithUnits() {
        #expect(StatusPresentation.cpuText(240.4) == "240 %")
        #expect(StatusPresentation.energyText(1.46) == "1,5 W")
        #expect(StatusPresentation.memoryText(bytes: 512 * 1_048_576) == "512 MB")
        #expect(StatusPresentation.memoryText(bytes: UInt64(2.5 * 1_073_741_824)) == "2,5 GB")
    }
}
