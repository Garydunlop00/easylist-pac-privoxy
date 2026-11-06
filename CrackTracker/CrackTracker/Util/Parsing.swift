import Foundation

/// Turns a game title into a key used to merge entries across trackers.
enum TitleNormalizer {
    static func key(_ title: String) -> String {
        let folded = title
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: #"['’`´]"#, with: "", options: .regularExpression)
        let chars = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(chars).split(separator: " ").joined(separator: " ")
    }
}

/// Lenient date parser for the formats trackers tend to use.
enum DateParser {
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let formatters: [DateFormatter] = [
        "yyyy-MM-dd'T'HH:mm:ss.SSS",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd",
        "yyyy/MM/dd",
        "dd.MM.yyyy",
        "dd/MM/yyyy",
        "MMM d, yyyy",
        "MMMM d, yyyy",
        "MMM d yyyy",
        "d MMM yyyy",
        "d MMMM yyyy",
        "d MMM, yyyy",
        "EEE, d MMM yyyy",
    ].map { format in
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = format
        return f
    }

    static func parse(_ value: Any?) -> Date? {
        guard let value, !(value is NSNull) else { return nil }
        if let string = value as? String { return parse(string: string) }
        if let number = value as? NSNumber { return fromEpoch(number.doubleValue) }
        return nil
    }

    static func parse(string raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count >= 4 else { return nil }
        if s.allSatisfy(\.isNumber), s.count >= 9, let n = Double(s) { return fromEpoch(n) }
        if let d = isoFractional.date(from: s) ?? iso.date(from: s) { return d }
        // Strip ordinal suffixes: "March 3rd, 2024" -> "March 3, 2024"
        let cleaned = s.replacingOccurrences(of: #"(\d)(st|nd|rd|th)\b"#, with: "$1", options: .regularExpression)
        for f in formatters {
            if let d = f.date(from: cleaned) { return d }
        }
        // Last resort: an ISO date at the start of the string.
        if cleaned.count > 10, let d = formatters[3].date(from: String(cleaned.prefix(10))) { return d }
        return nil
    }

    private static func fromEpoch(_ n: Double) -> Date? {
        let seconds = n > 1e12 ? n / 1000 : n
        guard seconds > 1e8 else { return nil } // anything before 1973 is not a timestamp
        return Date(timeIntervalSince1970: seconds)
    }
}

/// Tiny HTML helpers (regex based; good enough for scraping tables and embedded JSON).
enum HTML {
    static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
        }
    }

    static func firstMatch(_ pattern: String, in text: String) -> String? {
        matches(pattern, in: text).first.flatMap { $0.count > 1 ? $0[1] : nil }
    }

    static func text(_ html: String) -> String {
        let noTags = html
            .replacingOccurrences(of: #"<br\s*/?>"#, with: ", ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return decodeEntities(noTags)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = s
        let named = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
                     "&nbsp;": " ", "&trade;": "™", "&reg;": "®", "&copy;": "©", "&ndash;": "–", "&mdash;": "—"]
        for (k, v) in named { out = out.replacingOccurrences(of: k, with: v) }
        for m in matches(#"&#(x?)([0-9a-fA-F]+);"#, in: out) {
            let radix = m[1].isEmpty ? 10 : 16
            if let code = UInt32(m[2], radix: radix), let scalar = Unicode.Scalar(code) {
                out = out.replacingOccurrences(of: m[0], with: String(Character(scalar)))
            }
        }
        return out
    }
}
