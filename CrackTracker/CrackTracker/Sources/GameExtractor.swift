import Foundation

/// Pulls game entries out of whatever a tracker returns, without being tied to
/// one site's exact schema:
///
/// * JSON: walks the whole tree looking for objects that look like games
///   (a title plus crack/release/status/group/DRM fields), using common key aliases.
/// * HTML: parses embedded JSON (`__NEXT_DATA__`, JSON-LD, inline JSON) and
///   any `<table>` with a recognisable header row.
enum GameExtractor {
    struct Context {
        var sourceID: String
        var sourceName: String
        var baseURL: URL
        var hint: CrackStatus?
    }

    // Lower-cased key aliases seen across trackers.
    static let titleKeys = ["title", "name", "game", "game_name", "gamename", "game_title", "gametitle"]
    static let releaseKeys = ["release_date", "releasedate", "released", "release", "releasedat", "released_at", "date_release", "releaseddate"]
    static let crackKeys = ["crack_date", "crackdate", "cracked_date", "crackeddate", "cracked_at", "crackedat", "date_crack", "hacked_date", "crack_release_date"]
    static let statusKeys = ["status", "readable_status", "crack_status", "crackstatus", "state", "verdict"]
    static let boolKeys = ["is_cracked", "iscracked", "cracked", "hacked", "is_hacked"]
    static let groupKeys = ["groups", "hacked_groups", "crack_groups", "group", "cracked_by", "crackedby", "scene_group", "cracker", "crackers"]
    static let protectionKeys = ["protections", "protection", "drm", "drms", "anti_tamper", "antitamper"]
    static let imageKeys = ["image", "short_image", "imageposter", "image_url", "imageurl", "cover", "cover_url", "poster", "thumbnail", "header_image", "full_image", "img"]
    static let urlKeys = ["url", "link", "permalink", "href", "slug"]
    static let steamKeys = ["steam_prod_id", "steamid", "steam_id", "steam_appid", "steamappid", "appid", "app_id"]
    static let aaaKeys = ["is_aaa", "isaaa", "aaa"]

    // MARK: Entry point

    static func extract(data: Data, context: Context) -> [SourceReport] {
        if let first = data.first(where: { !($0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09) }),
           first == UInt8(ascii: "{") || first == UInt8(ascii: "["),
           let json = try? JSONSerialization.jsonObject(with: data) {
            return fromJSON(json, context: context)
        }
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return [] }
        return fromHTML(html, context: context)
    }

    static func fromJSON(_ json: Any, context: Context) -> [SourceReport] {
        var out: [SourceReport] = []
        walk(json, hint: context.hint, depth: 0, context: context, into: &out)
        return dedupe(out)
    }

    static func fromHTML(_ html: String, context: Context) -> [SourceReport] {
        var out: [SourceReport] = []

        // 1. Embedded JSON in <script> tags.
        for m in HTML.matches(#"<script\b([^>]*)>(.*?)</script>"#, in: html) {
            let attrs = m[1].lowercased()
            let body = m[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let looksJSON = attrs.contains("json") || attrs.contains("__next_data__")
                || body.hasPrefix("{") || body.hasPrefix("[")
            guard looksJSON, let data = body.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            walk(json, hint: context.hint, depth: 0, context: context, into: &out)
        }

        // 2. JSON shown as text (an API opened in a WebView ends up inside <pre>).
        if out.isEmpty, let pre = HTML.firstMatch(#"<pre\b[^>]*>(.*?)</pre>"#, in: html) {
            let text = HTML.decodeEntities(pre)
            if let data = text.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) {
                walk(json, hint: context.hint, depth: 0, context: context, into: &out)
            }
        }

        // 3. HTML tables.
        out += tables(in: html, context: context)
        return dedupe(out)
    }

    // MARK: JSON walking

    private static func walk(_ node: Any, hint: CrackStatus?, depth: Int, context: Context, into out: inout [SourceReport]) {
        guard depth < 40 else { return }
        if let dict = node as? [String: Any] {
            if let report = report(from: dict, hint: hint, context: context) {
                out.append(report)
                return
            }
            for (key, value) in dict {
                walk(value, hint: hintFromKey(key) ?? hint, depth: depth + 1, context: context, into: &out)
            }
        } else if let array = node as? [Any] {
            for value in array {
                walk(value, hint: hint, depth: depth + 1, context: context, into: &out)
            }
        }
    }

    /// Lists named like `uncracked_games` or `recentlyCracked` imply a status.
    private static func hintFromKey(_ key: String) -> CrackStatus? {
        let k = key.lowercased()
        if k.contains("uncrack") || k.contains("notcrack") || k.contains("not_crack") { return .uncracked }
        if k.contains("crack") || k.contains("hacked") { return .cracked }
        return nil
    }

    /// Builds a report if the object looks like a game; nil otherwise.
    static func report(from raw: [String: Any], hint: CrackStatus?, context: Context) -> SourceReport? {
        var dict: [String: Any] = [:]
        for (k, v) in raw where dict[k.lowercased()] == nil { dict[k.lowercased()] = v }

        guard let rawTitle = firstString(dict, titleKeys) else { return nil }
        let title = HTML.text(rawTitle)
        guard !title.isEmpty, title.count < 200 else { return nil }

        let statusText = firstString(dict, statusKeys)
        let hasStrongSignal = (releaseKeys + crackKeys + boolKeys + groupKeys + protectionKeys).contains { dict[$0] != nil }
        let statusMentionsCrack = statusText.map { statusFromText($0) != nil } ?? false
        guard hasStrongSignal || statusMentionsCrack else { return nil }

        let releaseDate = DateParser.parse(first(dict, releaseKeys))
        let crackKeyPresent = crackKeys.contains { dict[$0] != nil }
        var crackDate = DateParser.parse(first(dict, crackKeys))

        // Explicit flags win.
        var status: CrackStatus?
        for key in boolKeys {
            guard let value = dict[key], !(value is NSNull) else { continue }
            if let s = value as? String, let d = DateParser.parse(string: s) {
                crackDate = crackDate ?? d
                status = .cracked
            } else if let b = bool(value) {
                status = b ? .cracked : .uncracked
            } else if let s = value as? String, let fromText = statusFromText(s) {
                status = fromText
            }
            if status != nil { break }
        }
        if status == nil, let statusText { status = statusFromText(statusText) }
        if status == nil, crackDate != nil { status = .cracked }
        if status == nil, let hint { status = hint }
        if status == nil, crackKeyPresent { status = .uncracked } // crack date field exists but is empty

        let steam: String? = first(dict, steamKeys).flatMap { value in
            if let n = value as? NSNumber { return n.intValue > 0 ? n.stringValue : nil }
            if let s = value as? String, !s.isEmpty, s.allSatisfy(\.isNumber) { return s }
            return nil
        }

        return SourceReport(
            sourceID: context.sourceID,
            sourceName: context.sourceName,
            title: title,
            status: status ?? .unknown,
            releaseDate: releaseDate,
            crackDate: status == .cracked ? crackDate : nil,
            groups: stringList(first(dict, groupKeys)),
            protections: stringList(first(dict, protectionKeys)),
            imageURL: url(first(dict, imageKeys), base: context.baseURL),
            pageURL: url(first(dict, urlKeys), base: context.baseURL),
            steamAppID: steam,
            isAAA: first(dict, aaaKeys).flatMap(bool)
        )
    }

    static func statusFromText(_ text: String) -> CrackStatus? {
        let t = text.lowercased()
        if t.contains("uncrack") || t.contains("not cracked") || t.contains("not yet cracked")
            || t.contains("no crack") || t.contains("unbroken") || t.contains("not_cracked") {
            return .uncracked
        }
        if t.contains("crack") || t.contains("bypass") || t.contains("hacked") || t.contains("hypervisor") {
            return .cracked
        }
        return nil
    }

    // MARK: Tables

    private static func tables(in html: String, context: Context) -> [SourceReport] {
        var out: [SourceReport] = []
        for table in HTML.matches(#"<table\b[^>]*>(.*?)</table>"#, in: html) {
            let rows = HTML.matches(#"<tr\b[^>]*>(.*?)</tr>"#, in: table[1]).map { $0[1] }
            guard rows.count > 1 else { continue }

            let headerCells = cells(rows[0]).map { HTML.text($0).lowercased() }
            var columns: [Int: String] = [:]
            for (i, h) in headerCells.enumerated() {
                if h.contains("crack") && (h.contains("date") || h.contains("on") || h.contains("when")) { columns[i] = "crack_date" }
                else if h.contains("release") { columns[i] = "release_date" }
                else if h.contains("group") || h.contains("cracked by") || h.contains("scene") || h.contains("cracker") { columns[i] = "groups" }
                else if h.contains("drm") || h.contains("protection") { columns[i] = "protections" }
                else if h.contains("status") || h == "cracked" || h.contains("cracked?") { columns[i] = "status" }
                else if h.contains("game") || h.contains("title") || h == "name" { columns[i] = "title" }
            }
            guard columns.values.contains("title"), columns.count > 1 else { continue }

            for row in rows.dropFirst() {
                let rowCells = cells(row)
                var dict: [String: Any] = [:]
                for (i, cell) in rowCells.enumerated() {
                    guard let field = columns[i] else { continue }
                    dict[field] = HTML.text(cell)
                    if field == "title", let href = HTML.firstMatch(#"href\s*=\s*["']([^"']+)["']"#, in: cell) {
                        dict["url"] = HTML.decodeEntities(href)
                    }
                }
                if let src = HTML.firstMatch(#"<img\b[^>]*\bsrc\s*=\s*["']([^"']+)["']"#, in: row) {
                    dict["image"] = HTML.decodeEntities(src)
                }
                if let r = report(from: dict, hint: context.hint, context: context) { out.append(r) }
            }
        }
        return out
    }

    private static func cells(_ row: String) -> [String] {
        HTML.matches(#"<t[hd]\b[^>]*>(.*?)</t[hd]>"#, in: row).map { $0[1] }
    }

    // MARK: Value helpers

    private static func first(_ dict: [String: Any], _ keys: [String]) -> Any? {
        for key in keys {
            if let v = dict[key], !(v is NSNull) { return v }
        }
        return nil
    }

    private static func firstString(_ dict: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let s = dict[key] as? String, !s.trimmingCharacters(in: .whitespaces).isEmpty { return s }
        }
        return nil
    }

    static func bool(_ value: Any) -> Bool? {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.intValue != 0 }
        if let s = value as? String {
            switch s.lowercased().trimmingCharacters(in: .whitespaces) {
            case "true", "yes", "1", "y": return true
            case "false", "no", "0", "n": return false
            default: return nil
            }
        }
        return nil
    }

    static func stringList(_ value: Any?) -> [String] {
        guard let value else { return [] }
        if let s = value as? String {
            let text = HTML.text(s)
            guard !["", "-", "—", "n/a", "none", "null"].contains(text.lowercased()) else { return [] }
            return uniqued(text.components(separatedBy: CharacterSet(charactersIn: ",|;")))
        }
        if let array = value as? [Any] {
            return uniqued(array.flatMap { item -> [String] in
                if let d = item as? [String: Any] {
                    return stringList(d["name"] ?? d["title"] ?? d["label"] ?? d["Name"])
                }
                return stringList(item)
            })
        }
        if let d = value as? [String: Any] { return stringList(d["name"] ?? d["title"]) }
        return []
    }

    private static func url(_ value: Any?, base: URL) -> URL? {
        guard let s = (value as? String)?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if s.hasPrefix("http://") || s.hasPrefix("https://") { return URL(string: s) }
        if s.hasPrefix("//") { return URL(string: "https:" + s) }
        let path = s.hasPrefix("/") ? s : "/" + s
        return URL(string: path, relativeTo: base)?.absoluteURL
    }

    private static func dedupe(_ reports: [SourceReport]) -> [SourceReport] {
        var byKey: [String: SourceReport] = [:]
        var order: [String] = []
        for r in reports {
            let key = TitleNormalizer.key(r.title)
            guard !key.isEmpty else { continue }
            if let existing = byKey[key] {
                // Prefer the more informative entry.
                if score(r) > score(existing) { byKey[key] = r }
            } else {
                byKey[key] = r
                order.append(key)
            }
        }
        return order.compactMap { byKey[$0] }
    }

    private static func score(_ r: SourceReport) -> Int {
        var s = 0
        if r.status != .unknown { s += 4 }
        if r.releaseDate != nil { s += 2 }
        if r.crackDate != nil { s += 2 }
        if r.imageURL != nil { s += 1 }
        s += min(r.groups.count + r.protections.count, 3)
        return s
    }
}
