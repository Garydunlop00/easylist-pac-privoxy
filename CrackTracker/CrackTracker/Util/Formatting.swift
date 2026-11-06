import Foundation

enum Fmt {
    /// Compact duration, e.g. "12d", "4mo", "2y 3mo".
    static func days(_ d: Int) -> String {
        if d < 60 { return "\(d)d" }
        let years = d / 365
        let months = (d % 365) / 30
        if years == 0 { return "\(months)mo" }
        return months == 0 ? "\(years)y" : "\(years)y \(months)mo"
    }

    /// Long duration, e.g. "412 days (1 yr, 1 mth)".
    static func longDays(_ d: Int) -> String {
        let unit = d == 1 ? "day" : "days"
        guard d >= 60 else { return "\(d) \(unit)" }
        let f = DateComponentsFormatter()
        f.allowedUnits = [.year, .month, .day]
        f.unitsStyle = .short
        f.maximumUnitCount = 2
        let pretty = f.string(from: TimeInterval(d) * 86_400) ?? ""
        return "\(d) \(unit) (\(pretty))"
    }

    /// Live counter, e.g. "412d 05h 12m 09s".
    static func elapsed(from start: Date, to end: Date) -> String {
        let c = Calendar.current.dateComponents([.day, .hour, .minute, .second], from: start, to: end)
        return String(format: "%dd %02dh %02dm %02ds", c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    static func relative(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named))
    }
}
