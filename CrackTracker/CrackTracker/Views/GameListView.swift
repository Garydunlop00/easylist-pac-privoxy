import SwiftUI

enum ListMode {
    case uncracked, cracked, watchlist

    var title: String {
        switch self {
        case .uncracked: return "Uncracked"
        case .cracked: return "Cracked"
        case .watchlist: return "Watchlist"
        }
    }

    var sorts: [SortOrder] {
        switch self {
        case .uncracked: return [.longestUncracked, .newestRelease, .title]
        case .cracked: return [.recentlyCracked, .fastestCrack, .slowestCrack, .newestRelease, .title]
        case .watchlist: return [.longestUncracked, .recentlyCracked, .newestRelease, .title]
        }
    }
}

enum SortOrder: String, CaseIterable, Identifiable {
    case longestUncracked = "Longest uncracked"
    case newestRelease = "Newest release"
    case recentlyCracked = "Recently cracked"
    case fastestCrack = "Fastest crack"
    case slowestCrack = "Slowest crack"
    case title = "A–Z"

    var id: String { rawValue }

    func sort(_ games: [Game]) -> [Game] {
        let distantPast = Date.distantPast
        switch self {
        case .longestUncracked:
            return games.sorted {
                // Uncracked first (longest wait at the top), then everything else.
                ($0.daysUncracked() ?? -1, $1.title) > ($1.daysUncracked() ?? -1, $0.title)
            }
        case .newestRelease:
            return games.sorted { ($0.releaseDate ?? distantPast) > ($1.releaseDate ?? distantPast) }
        case .recentlyCracked:
            return games.sorted { ($0.crackDate ?? distantPast) > ($1.crackDate ?? distantPast) }
        case .fastestCrack:
            return games.sorted { ($0.daysToCrack ?? .max) < ($1.daysToCrack ?? .max) }
        case .slowestCrack:
            return games.sorted { ($0.daysToCrack ?? -1) > ($1.daysToCrack ?? -1) }
        case .title:
            return games.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }
}

struct GameListView: View {
    @EnvironmentObject private var store: GameStore
    let mode: ListMode

    @State private var search = ""
    @State private var sort: SortOrder
    @State private var showingAdd = false
    @AppStorage("aaaOnly") private var aaaOnly = false

    init(mode: ListMode) {
        self.mode = mode
        _sort = State(initialValue: mode.sorts[0])
    }

    private func filtered(_ games: [Game]) -> [Game] {
        sort.sort(games.filter { game in
            (!aaaOnly || game.isAAA || game.isManual)
                && (search.isEmpty || game.title.localizedCaseInsensitiveContains(search)
                    || game.groups.contains { $0.localizedCaseInsensitiveContains(search) }
                    || game.protections.contains { $0.localizedCaseInsensitiveContains(search) })
        })
    }

    private var mainGames: [Game] {
        switch mode {
        case .uncracked: return filtered(store.uncracked)
        case .cracked: return filtered(store.cracked)
        case .watchlist: return filtered(store.watched)
        }
    }

    private var upcomingGames: [Game] {
        mode == .uncracked ? SortOrder.title.sort(filtered(store.upcoming)) : []
    }

    var body: some View {
        NavigationStack {
            List {
                if mode != .watchlist {
                    SummaryHeader(mode: mode, count: mainGames.count)
                }

                Section {
                    ForEach(mainGames) { game in
                        NavigationLink(value: game.id) { GameRow(game: game) }
                    }
                } header: {
                    if !mainGames.isEmpty { Text("\(mainGames.count) games · \(sort.rawValue)") }
                }

                if !upcomingGames.isEmpty {
                    Section("Not released yet") {
                        ForEach(upcomingGames) { game in
                            NavigationLink(value: game.id) { GameRow(game: game) }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if mainGames.isEmpty && upcomingGames.isEmpty {
                    emptyState
                }
            }
            .navigationTitle(mode.title)
            .navigationDestination(for: String.self) { id in GameDetailView(gameID: id) }
            .searchable(text: $search, prompt: "Game, group or DRM")
            .refreshable { await store.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if store.isRefreshing { ProgressView() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if mode == .watchlist {
                        Button { showingAdd = true } label: { Image(systemName: "plus") }
                    }
                    Menu {
                        Picker("Sort", selection: $sort) {
                            ForEach(mode.sorts) { Text($0.rawValue).tag($0) }
                        }
                        Toggle("AAA games only", isOn: $aaaOnly)
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) { AddGameView() }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if store.isRefreshing {
            ProgressView("Checking trackers…")
        } else if !search.isEmpty {
            ContentUnavailableView.search(text: search)
        } else if mode == .watchlist {
            ContentUnavailableView("No watched games",
                                   systemImage: "star",
                                   description: Text("Tap the star on any game to get notified when it's cracked, or add one with +."))
        } else {
            ContentUnavailableView("No games yet",
                                   systemImage: "antenna.radiowaves.left.and.right.slash",
                                   description: Text("Pull to refresh. If a tracker keeps failing, check its URLs in the Sources tab."))
        }
    }
}

/// Top-of-list stats and a warning if trackers failed.
private struct SummaryHeader: View {
    @EnvironmentObject private var store: GameStore
    let mode: ListMode

    let count: Int

    private var failing: [String] {
        store.sources.filter { s in
            s.isEnabled && (store.runStatus[s.id]?.errors.isEmpty == false) && (store.runStatus[s.id]?.count ?? 0) == 0
        }.map(\.name)
    }

    var body: some View {
        Section {
            if mode == .uncracked, let longest = store.uncracked.max(by: { ($0.daysUncracked() ?? 0) < ($1.daysUncracked() ?? 0) }),
               let days = longest.daysUncracked() {
                LabeledContent("Longest holdout") {
                    Text("\(longest.title) · \(Fmt.days(days))").multilineTextAlignment(.trailing)
                }
            }
            if mode == .cracked {
                let recent = store.cracked.filter { ($0.crackDate ?? .distantPast) > Date().addingTimeInterval(-7 * 86_400) }.count
                LabeledContent("Cracked in the last 7 days", value: "\(recent)")
            }
            if let last = store.lastRefresh {
                LabeledContent("Updated", value: Fmt.relative(last))
            }
            if !failing.isEmpty {
                Label("Couldn't load: \(failing.joined(separator: ", ")). See Sources.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .font(.subheadline)
    }
}
