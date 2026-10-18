import Foundation

public enum ClockStyle: String, CaseIterable, Sendable { case system, twelveHour, twentyFourHour }

public enum ClockFormat {
    public static func uses24Hour(style: ClockStyle, locale: Locale = .current) -> Bool {
        switch style {
        case .twelveHour: return false
        case .twentyFourHour: return true
        case .system:
            let f = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? ""
            return !f.contains("a")
        }
    }

    public static func string(for date: Date, style: ClockStyle, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = locale
        f.dateFormat = uses24Hour(style: style, locale: locale) ? "HH:mm" : "h:mm a"
        return f.string(from: date)
    }

    /// Widest plausible string, so the island width doesn't change every minute.
    public static func measurementString(style: ClockStyle, locale: Locale = .current) -> String {
        uses24Hour(style: style, locale: locale) ? "00:00" : "00:00 PM"
    }

    public static func nextMinuteBoundary(after date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .minute, for: date)?.end ?? date.addingTimeInterval(60)
    }
}
