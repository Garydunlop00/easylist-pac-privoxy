import SwiftUI

struct GameDetailView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    let gameID: String

    var body: some View {
        if let game = store.game(id: gameID) {
            content(game)
        } else {
            ContentUnavailableView("Game not found", systemImage: "questionmark.square.dashed")
        }
    }

    private func content(_ game: Game) -> some View {
        List {
            if game.imageURL != nil {
                Section {
                    CoverImage(url: game.imageURL)
                        .aspectRatio(460.0 / 215.0, contentMode: .fit)
                        .listRowInsets(EdgeInsets())
                }
            }

            Section("Status") {
                LabeledContent("Status") {
                    Text(game.status.label)
                        .bold()
                        .foregroundStyle(game.status == .cracked ? Color.green : (game.status == .uncracked ? Color.orange : Color.secondary))
                }
                if game.status != .cracked, let release = game.releaseDate {
                    if release <= Date() {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            LabeledContent("Uncracked for") {
                                Text(Fmt.elapsed(from: release, to: context.date)).monospacedDigit()
                            }
                        }
                    } else {
                        LabeledContent("Releases in", value: Fmt.longDays(Calendar.current.dateComponents([.day], from: Date(), to: release).day ?? 0))
                    }
                }
                LabeledContent("Released", value: Fmt.date(game.releaseDate))
                if game.status == .cracked {
                    LabeledContent("Cracked", value: Fmt.date(game.crackDate))
                    if let days = game.daysToCrack {
                        LabeledContent("Time to crack", value: Fmt.longDays(days))
                    }
                }
                if game.isAAA { LabeledContent("AAA", value: "Yes") }
                if game.hasConflict {
                    Label("Trackers disagree on this game's status. See below.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            if !game.protections.isEmpty {
                Section("Protection") {
                    ForEach(game.protections, id: \.self) { Text($0) }
                }
            }

            if !game.groups.isEmpty {
                Section("Cracked by") {
                    ForEach(game.groups, id: \.self) { Text($0) }
                }
            }

            Section("Reported by") {
                ForEach(Array(game.reports.enumerated()), id: \.offset) { _, report in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(report.sourceName).font(.headline)
                            Spacer()
                            Text(report.status.label).foregroundStyle(.secondary)
                        }
                        if let crack = report.crackDate {
                            Text("Cracked \(Fmt.date(crack))").font(.caption).foregroundStyle(.secondary)
                        }
                        if let url = report.pageURL {
                            Link("Open on \(report.sourceName)", destination: url).font(.caption)
                        }
                    }
                }
            }

            Section {
                Button {
                    store.toggleWatch(game)
                } label: {
                    Label(store.isWatched(game) ? "Stop watching" : "Watch & notify when cracked",
                          systemImage: store.isWatched(game) ? "star.slash" : "star")
                }
                if let appID = game.steamAppID, let url = URL(string: "https://store.steampowered.com/app/\(appID)") {
                    Link(destination: url) { Label("View on Steam", systemImage: "cart") }
                }
                if game.isManual {
                    Button(role: .destructive) {
                        store.removeManual(game)
                        if store.game(id: game.id) == nil { dismiss() }
                    } label: {
                        Label("Delete manual entry", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle(game.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                store.toggleWatch(game)
            } label: {
                Image(systemName: store.isWatched(game) ? "star.fill" : "star")
            }
        }
    }
}
