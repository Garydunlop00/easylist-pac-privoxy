import SwiftUI

struct GameRow: View {
    @EnvironmentObject private var store: GameStore
    let game: Game

    private var subtitle: String {
        var parts: [String] = []
        if !game.protections.isEmpty { parts.append(game.protections.joined(separator: ", ")) }
        if let release = game.releaseDate { parts.append(game.isReleased ? "Released \(Fmt.date(release))" : "Out \(Fmt.date(release))") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            CoverImage(url: game.imageURL)
                .frame(width: 92, height: 43)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(game.title).font(.headline).lineLimit(2)
                    if store.isWatched(game) {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                    }
                }
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }

            Spacer(minLength: 4)
            StatusBadge(game: game)
        }
        .padding(.vertical, 2)
    }
}

struct StatusBadge: View {
    let game: Game

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            switch game.status {
            case .cracked:
                Text("Cracked").font(.caption.bold()).foregroundStyle(.green)
                if let days = game.daysToCrack {
                    Text("in \(Fmt.days(days))").font(.caption2).foregroundStyle(.secondary)
                }
                if let group = game.groups.first {
                    Text(group).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            case .uncracked:
                if let days = game.daysUncracked() {
                    Text(Fmt.days(days))
                        .font(.title3.monospacedDigit().bold())
                        .foregroundStyle(Self.color(forDays: days))
                    Text("uncracked").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text(game.isReleased ? "Uncracked" : "Upcoming")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }
            case .unknown:
                Text("?").font(.title3.bold()).foregroundStyle(.secondary)
            }
        }
    }

    static func color(forDays days: Int) -> Color {
        switch days {
        case ..<30: return .yellow
        case ..<180: return .orange
        default: return .red
        }
    }
}

struct CoverImage: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "gamecontroller").foregroundStyle(.secondary)
                }
            }
        }
    }
}
