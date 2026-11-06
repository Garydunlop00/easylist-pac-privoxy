import Foundation

/// One URL to pull games from. Can be a JSON API or an HTML page.
struct SourceEndpoint: Codable, Hashable, Identifiable {
    var id = UUID()
    /// May contain `{page}` (1-based) or `{page0}` (0-based) for pagination.
    var url: String
    /// Status to assume for games on this page when the page itself doesn't say
    /// (e.g. a "Recently cracked" list).
    var hint: CrackStatus? = nil
    var pages: Int = 1
    /// Load the page in a hidden WebView so JavaScript-rendered sites and
    /// browser challenges work.
    var useWebView: Bool = false
}

/// A crack-tracking website.
struct SourceConfig: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var homepage: String
    var isEnabled: Bool = true
    var endpoints: [SourceEndpoint]

    /// Built-in trackers. These URLs are starting points: tracker sites change
    /// layouts and APIs often, so every endpoint can be edited in the app.
    static let defaults: [SourceConfig] = [
        SourceConfig(
            id: "crackwatch",
            name: "CrackWatch",
            homepage: "https://crackwatch.com",
            endpoints: [
                SourceEndpoint(url: "https://crackwatch.com/", useWebView: true),
                // Legacy public API (JSON). Kept for mirrors / revivals that use the same schema.
                SourceEndpoint(url: "https://api.crackwatch.com/api/games?page={page0}&sort_by=release_date&is_cracked=false&is_aaa=true",
                               hint: .uncracked, pages: 3),
                SourceEndpoint(url: "https://api.crackwatch.com/api/games?page={page0}&sort_by=crack_date&is_cracked=true",
                               hint: .cracked, pages: 2),
            ]),
        SourceConfig(
            id: "crackrelease",
            name: "CrackRelease",
            homepage: "https://crackrelease.com",
            endpoints: [
                SourceEndpoint(url: "https://crackrelease.com/"),
            ]),
        SourceConfig(
            id: "isitcracked",
            name: "IsItCracked",
            homepage: "https://isitcracked.com",
            endpoints: [
                SourceEndpoint(url: "https://isitcracked.com/", useWebView: true),
            ]),
        SourceConfig(
            id: "gamestatus",
            name: "GameStatus",
            homepage: "https://gamestatus.info",
            endpoints: [
                SourceEndpoint(url: "https://gamestatus.info/back/api/gameinfo/game/lastcrackedgames/", hint: .cracked),
                SourceEndpoint(url: "https://gamestatus.info/back/api/gameinfo/game/"),
            ]),
    ]
}
