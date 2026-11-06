import Foundation

/// Crack status as reported by a tracker.
enum CrackStatus: String, Codable, CaseIterable, Identifiable {
    case cracked
    case uncracked
    case unknown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cracked: return "Cracked"
        case .uncracked: return "Uncracked"
        case .unknown: return "Unknown"
        }
    }
}

/// One tracker's view of one game.
struct SourceReport: Codable, Hashable {
    var sourceID: String
    var sourceName: String
    var title: String
    var status: CrackStatus
    var releaseDate: Date?
    var crackDate: Date?
    var groups: [String] = []
    var protections: [String] = []
    var imageURL: URL?
    var pageURL: URL?
    var steamAppID: String?
    var isAAA: Bool?

    static let manualSourceID = "manual"
}

/// A game merged from every tracker that reports on it.
struct Game: Identifiable, Hashable {
    /// Normalised title, used to merge the same game across trackers.
    let id: String
    var reports: [SourceReport]

    var title: String { reports.first?.title ?? id }

    /// If any tracker says it is cracked, it is cracked.
    var status: CrackStatus {
        if reports.contains(where: { $0.status == .cracked }) { return .cracked }
        if reports.contains(where: { $0.status == .uncracked }) { return .uncracked }
        return .unknown
    }

    /// Trackers disagree about the status.
    var hasConflict: Bool {
        Set(reports.map(\.status)).subtracting([.unknown]).count > 1
    }

    var crackDate: Date? {
        reports.filter { $0.status == .cracked }.compactMap(\.crackDate).min()
    }

    var releaseDate: Date? { reports.compactMap(\.releaseDate).min() }
    var groups: [String] { uniqued(reports.flatMap(\.groups)) }
    var protections: [String] { uniqued(reports.flatMap(\.protections)) }
    var imageURL: URL? { reports.lazy.compactMap(\.imageURL).first }
    var steamAppID: String? { reports.lazy.compactMap(\.steamAppID).first }
    var isAAA: Bool { reports.contains { $0.isAAA == true } }
    var sourceNames: [String] { uniqued(reports.map(\.sourceName)) }
    var isManual: Bool { reports.contains { $0.sourceID == SourceReport.manualSourceID } }

    var isReleased: Bool {
        guard let releaseDate else { return true }
        return releaseDate <= Date()
    }

    /// Whole days since release without a crack, or nil if cracked / unreleased / unknown date.
    func daysUncracked(asOf now: Date = Date()) -> Int? {
        guard status != .cracked, let releaseDate, releaseDate <= now else { return nil }
        return Calendar.current.dateComponents([.day], from: releaseDate, to: now).day
    }

    /// Days between release and crack.
    var daysToCrack: Int? {
        guard status == .cracked, let releaseDate, let crackDate else { return nil }
        return max(0, Calendar.current.dateComponents([.day], from: releaseDate, to: crackDate).day ?? 0)
    }
}

/// Case-insensitive de-duplication that keeps the first spelling seen.
func uniqued(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for raw in values {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, seen.insert(value.lowercased()).inserted else { continue }
        result.append(value)
    }
    return result
}
