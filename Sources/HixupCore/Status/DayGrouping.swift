import Foundation

/// Gruppiert Eintraege nach Kalendertag, neueste Tage und neueste Eintraege zuerst.
public enum DayGrouping {
    public static func group<T>(
        _ items: [T], date: (T) -> Date, calendar: Calendar = .current
    ) -> [(day: Date, items: [T])] {
        let byDay = Dictionary(grouping: items) { calendar.startOfDay(for: date($0)) }
        return byDay.keys.sorted(by: >).map { day in
            (day: day, items: byDay[day]!.sorted { date($0) > date($1) })
        }
    }
}
