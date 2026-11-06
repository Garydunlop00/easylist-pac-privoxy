import Foundation
import SwiftUI

/// Fetches all trackers, merges their reports, and persists everything locally.
@MainActor
final class GameStore: ObservableObject {
    static let shared = GameStore()

    struct RunStatus: Codable, Hashable {
        var date: Date
        var count: Int
        var errors: [String]
    }

    @Published private(set) var games: [Game] = []
    @Published private(set) var runStatus: [String: RunStatus] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var watchlist: Set<String> = []
    @Published private(set) var manualReports: [SourceReport] = []
    @Published var sources: [SourceConfig] = SourceConfig.defaults {
        didSet { rebuild(); save() }
    }

    private var cache: [String: [SourceReport]] = [:]
    private var lastKnownStatus: [String: CrackStatus] = [:]

    init() {
        load()
        rebuild()
    }

    // MARK: Lists

    var uncracked: [Game] { games.filter { $0.status == .uncracked && $0.isReleased } }
    var upcoming: [Game] { games.filter { $0.status != .cracked && !$0.isReleased } }
    var cracked: [Game] { games.filter { $0.status == .cracked } }
    var watched: [Game] { games.filter { watchlist.contains($0.id) } }

    func game(id: String) -> Game? { games.first { $0.id == id } }
    func isWatched(_ game: Game) -> Bool { watchlist.contains(game.id) }

    var isStale: Bool {
        guard let lastRefresh else { return true }
        return Date().timeIntervalSince(lastRefresh) > 3600
    }

    // MARK: Refresh

    /// Refreshes every enabled source, or just the given ones.
    func refresh(only ids: Set<String>? = nil) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let targets = sources.filter { $0.isEnabled && (ids == nil || ids!.contains($0.id)) }
        let fetcher = SourceFetcher()
        let results = await withTaskGroup(of: SourceRunResult.self, returning: [SourceRunResult].self) { group in
            for source in targets {
                group.addTask { await fetcher.run(source) }
            }
            var all: [SourceRunResult] = []
            for await result in group { all.append(result) }
            return all
        }

        for result in results {
            // Keep the previous data when a source fails, so a blip doesn't empty the list.
            if !result.reports.isEmpty { cache[result.sourceID] = result.reports }
            runStatus[result.sourceID] = RunStatus(date: result.date, count: result.reports.count, errors: result.errors)
        }
        let knownIDs = Set(sources.map(\.id))
        cache = cache.filter { knownIDs.contains($0.key) }

        lastRefresh = Date()
        rebuild()
        notifyNewCracks()
        save()
    }

    private func rebuild() {
        let enabled = Set(sources.filter(\.isEnabled).map(\.id))
        var all = manualReports
        for (id, reports) in cache where enabled.contains(id) { all += reports }
        let grouped = Dictionary(grouping: all) { TitleNormalizer.key($0.title) }
        games = grouped
            .filter { !$0.key.isEmpty }
            .map { key, reports in
                // Manual entries first so their title/dates take priority in the UI.
                Game(id: key, reports: reports.sorted { a, b in
                    (a.sourceID == SourceReport.manualSourceID ? 0 : 1) < (b.sourceID == SourceReport.manualSourceID ? 0 : 1)
                })
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Notifies about watched games that went from uncracked to cracked.
    private func notifyNewCracks() {
        for game in games where watchlist.contains(game.id) {
            if lastKnownStatus[game.id] == .uncracked && game.status == .cracked {
                Notifier.gameCracked(game)
            }
        }
        for game in games { lastKnownStatus[game.id] = game.status }
    }

    // MARK: Watchlist & manual games

    func toggleWatch(_ game: Game) {
        if watchlist.contains(game.id) {
            watchlist.remove(game.id)
        } else {
            watchlist.insert(game.id)
            lastKnownStatus[game.id] = game.status
            Notifier.requestAuthorization()
        }
        save()
    }

    func addManual(title: String, releaseDate: Date?, status: CrackStatus, crackDate: Date?, watch: Bool) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let key = TitleNormalizer.key(trimmed)
        manualReports.removeAll { TitleNormalizer.key($0.title) == key }
        manualReports.append(SourceReport(
            sourceID: SourceReport.manualSourceID,
            sourceName: "Manual",
            title: trimmed,
            status: status,
            releaseDate: releaseDate,
            crackDate: status == .cracked ? crackDate : nil))
        rebuild()
        if watch, let game = game(id: key), !watchlist.contains(key) { toggleWatch(game) }
        save()
    }

    func removeManual(_ game: Game) {
        manualReports.removeAll { TitleNormalizer.key($0.title) == game.id }
        rebuild()
        save()
    }

    func resetSources() {
        sources = SourceConfig.defaults
        runStatus = [:]
    }

    // MARK: Persistence

    private struct Snapshot: Codable {
        var cache: [String: [SourceReport]]
        var manualReports: [SourceReport]
        var watchlist: [String]
        var sources: [SourceConfig]
        var lastRefresh: Date?
        var lastKnownStatus: [String: CrackStatus]
        var runStatus: [String: RunStatus]
    }

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cracktracker.json")
    }

    private func save() {
        let snapshot = Snapshot(cache: cache, manualReports: manualReports, watchlist: Array(watchlist),
                                sources: sources, lastRefresh: lastRefresh,
                                lastKnownStatus: lastKnownStatus, runStatus: runStatus)
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("CrackTracker: save failed: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        cache = snapshot.cache
        manualReports = snapshot.manualReports
        watchlist = Set(snapshot.watchlist)
        lastRefresh = snapshot.lastRefresh
        lastKnownStatus = snapshot.lastKnownStatus
        runStatus = snapshot.runStatus
        sources = snapshot.sources
    }
}
