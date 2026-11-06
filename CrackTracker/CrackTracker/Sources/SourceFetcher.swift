import Foundation

enum FetchError: LocalizedError {
    case http(Int)
    case timeout
    case invalidURL(String)

    var errorDescription: String? {
        switch self {
        case .http(let code) where code == 403 || code == 503:
            return "HTTP \(code): blocked, probably bot protection. Try turning on \"Render JavaScript\" for this endpoint."
        case .http(let code): return "HTTP \(code)"
        case .timeout: return "Timed out"
        case .invalidURL(let s): return "Invalid URL: \(s)"
        }
    }
}

struct SourceRunResult {
    var sourceID: String
    var reports: [SourceReport]
    var errors: [String]
    var date = Date()
}

/// Downloads and parses every endpoint of a tracker.
struct SourceFetcher {
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

    var session: URLSession = .shared

    func run(_ config: SourceConfig) async -> SourceRunResult {
        var reports: [SourceReport] = []
        var errors: [String] = []

        for endpoint in config.endpoints {
            let paginated = endpoint.url.contains("{page")
            let pageCount = paginated ? max(1, endpoint.pages) : 1

            for page in 1...pageCount {
                let urlString = endpoint.url
                    .replacingOccurrences(of: "{page0}", with: "\(page - 1)")
                    .replacingOccurrences(of: "{page}", with: "\(page)")
                let label = URL(string: urlString).map { ($0.host ?? "") + $0.path } ?? urlString
                do {
                    guard let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true else {
                        throw FetchError.invalidURL(urlString)
                    }
                    let data = try await download(url, useWebView: endpoint.useWebView)
                    let context = GameExtractor.Context(sourceID: config.id, sourceName: config.name,
                                                        baseURL: url, hint: endpoint.hint)
                    let found = GameExtractor.extract(data: data, context: context)
                    if found.isEmpty {
                        if page == 1 {
                            errors.append("\(label): no games found. The layout may have changed, or the page needs \"Render JavaScript\".")
                        }
                        break
                    }
                    reports += found
                } catch {
                    errors.append("\(label): \(error.localizedDescription)")
                    break
                }
            }
        }

        // The same game can appear on several endpoints of one site; keep the most specific.
        var merged: [String: SourceReport] = [:]
        var order: [String] = []
        for r in reports {
            let key = TitleNormalizer.key(r.title)
            if let existing = merged[key] {
                if existing.status == .unknown || (r.status == .cracked && existing.status != .cracked) {
                    merged[key] = r
                }
            } else {
                merged[key] = r
                order.append(key)
            }
        }
        return SourceRunResult(sourceID: config.id, reports: order.compactMap { merged[$0] }, errors: errors)
    }

    private func download(_ url: URL, useWebView: Bool) async throws -> Data {
        if useWebView {
            let html = try await WebPageRenderer.render(url)
            return Data(html.utf8)
        }
        var request = URLRequest(url: url, timeoutInterval: 25)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/html;q=0.9, */*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FetchError.http(http.statusCode)
        }
        return data
    }
}
