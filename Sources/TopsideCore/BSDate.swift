import Foundation

public struct BSDate: Equatable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public var romanized: String {
        let names = ["Baisakh", "Jestha", "Asar", "Shrawan", "Bhadra", "Ashwin",
                     "Kartik", "Mangsir", "Poush", "Magh", "Falgun", "Chaitra"]
        return "\(day) \(names[month - 1]) \(year) BS"
    }
}

/// Bounded AD -> Nepali Bikram Sambat conversion. BS 2070-2084 is the
/// officially cross-checked range. BS 2085-2099 uses matching projected tables
/// from independent implementations and is suitable for display, not legal use.
public enum BSDateConverter {
    public static let supportedBSYears = 2070...2099
    public static let officiallyVerifiedThrough = 2084

    private static let monthDays: [[Int]] = [
        [31,31,31,32,31,31,29,30,30,29,30,30], // 2070
        [31,31,32,31,31,31,30,29,30,29,30,30], // 2071
        [31,32,31,32,31,30,30,29,30,29,30,30], // 2072
        [31,32,31,32,31,30,30,30,29,29,30,31], // 2073
        [31,31,31,32,31,31,30,29,30,29,30,30], // 2074
        [31,31,32,31,31,31,30,29,30,29,30,30], // 2075
        [31,32,31,32,31,30,30,30,29,29,30,30], // 2076
        [31,32,31,32,31,30,30,30,29,30,29,31], // 2077
        [31,31,31,32,31,31,30,29,30,29,30,30], // 2078
        [31,31,32,31,31,31,30,29,30,29,30,30], // 2079
        [31,32,31,32,31,30,30,30,29,29,30,30], // 2080
        [31,32,31,32,31,30,30,30,29,30,29,31], // 2081
        [31,31,32,31,31,31,30,29,30,29,30,30], // 2082
        [31,31,32,31,31,31,30,29,30,29,30,30], // 2083
        [31,31,32,31,31,30,30,30,29,30,30,30], // 2084
        [31,32,31,32,30,31,30,30,29,30,30,30], // 2085 projected
        [30,32,31,32,31,30,30,30,29,30,30,30], // 2086 projected
        [31,31,32,31,31,31,30,30,29,30,30,30], // 2087 projected
        [30,31,32,32,30,31,30,30,29,30,30,30], // 2088 projected
        [30,32,31,32,31,30,30,30,29,30,30,30], // 2089 projected
        [30,32,31,32,31,30,30,30,29,30,30,30], // 2090 projected
        [31,31,32,31,31,31,30,30,29,30,30,30], // 2091 projected
        [30,31,32,32,31,30,30,30,29,30,30,30], // 2092 projected
        [30,32,31,32,31,30,30,30,29,30,30,30], // 2093 projected
        [31,31,32,31,31,30,30,30,29,30,30,30], // 2094 projected
        [31,31,32,31,31,31,30,29,30,30,30,30], // 2095 projected
        [30,31,32,32,31,30,30,29,30,29,30,30], // 2096 projected
        [31,32,31,32,31,30,30,30,29,30,30,30], // 2097 projected
        [31,31,32,31,31,31,29,30,29,30,29,31], // 2098 projected
        [31,31,32,31,31,31,30,29,29,30,30,30], // 2099 projected
    ]

    private static let utc: TimeZone = TimeZone(secondsFromGMT: 0)!

    public static func convert(_ date: Date, in timeZone: TimeZone = .current) -> BSDate? {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        let parts = local.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }

        var stable = Calendar(identifier: .gregorian)
        stable.timeZone = utc
        guard let civilDate = stable.date(from: DateComponents(timeZone: utc, year: year, month: month, day: day)),
              let anchor = stable.date(from: DateComponents(timeZone: utc, year: 2013, month: 4, day: 14)),
              var offset = stable.dateComponents([.day], from: anchor, to: civilDate).day,
              offset >= 0 else { return nil }

        for (yearIndex, months) in monthDays.enumerated() {
            let yearLength = months.reduce(0, +)
            if offset >= yearLength {
                offset -= yearLength
                continue
            }
            for (monthIndex, length) in months.enumerated() {
                if offset < length {
                    return BSDate(year: supportedBSYears.lowerBound + yearIndex,
                                  month: monthIndex + 1, day: offset + 1)
                }
                offset -= length
            }
        }
        return nil
    }
}

public struct DualDateText: Equatable, Sendable {
    public let ad: String
    public let bs: String
    public var combined: String { "AD: \(ad)\nBS: \(bs)" }

    /// "Tuesday" from "Tuesday, 20 October 2026". Falls back to the whole string.
    public var weekday: String { ad.components(separatedBy: ", ").first ?? ad }

    /// "20 October 2026 · 3 Kartik 2083 BS": the quieter second line under the weekday.
    public var detailLine: String {
        var parts: [String] = []
        if let range = ad.range(of: ", ") { parts.append(String(ad[range.upperBound...])) }
        if !bs.isEmpty { parts.append(bs) }
        return parts.joined(separator: " · ")
    }
}

public enum DualDateFormatter {
    public static func string(for date: Date, timeZone: TimeZone = .current) -> DualDateText {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEEE, d MMMM yyyy"
        let ad = formatter.string(from: date)
        let bs = BSDateConverter.convert(date, in: timeZone)?.romanized ?? "Unavailable"
        return DualDateText(ad: ad, bs: bs)
    }
}
