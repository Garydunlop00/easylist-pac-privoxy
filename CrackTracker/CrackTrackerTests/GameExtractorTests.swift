import XCTest
@testable import CrackTracker

final class GameExtractorTests: XCTestCase {
    private func context(hint: CrackStatus? = nil) -> GameExtractor.Context {
        GameExtractor.Context(sourceID: "test", sourceName: "Test",
                              baseURL: URL(string: "https://tracker.example/list")!, hint: hint)
    }

    func testCrackWatchStyleJSON() throws {
        let json = """
        [{"_id":"1","title":"Uncracked Game","slug":"uncracked-game","isAAA":true,
          "releaseDate":"2023-03-01T00:00:00.000Z","crackDate":null,
          "protections":["Denuvo"],"groups":[],"image":"https://img.example/a.jpg"},
         {"_id":"2","title":"Cracked Game","releaseDate":"2023-01-01T00:00:00.000Z",
          "crackDate":"2023-01-15T00:00:00.000Z","groups":["EMPRESS"],"protections":["Denuvo"]}]
        """
        let reports = GameExtractor.extract(data: Data(json.utf8), context: context())
        XCTAssertEqual(reports.count, 2)

        let uncracked = try XCTUnwrap(reports.first { $0.title == "Uncracked Game" })
        XCTAssertEqual(uncracked.status, .uncracked)
        XCTAssertEqual(uncracked.protections, ["Denuvo"])
        XCTAssertEqual(uncracked.isAAA, true)
        XCTAssertEqual(uncracked.pageURL?.absoluteString, "https://tracker.example/uncracked-game")

        let cracked = try XCTUnwrap(reports.first { $0.title == "Cracked Game" })
        XCTAssertEqual(cracked.status, .cracked)
        XCTAssertEqual(cracked.groups, ["EMPRESS"])
        XCTAssertNotNil(cracked.crackDate)
    }

    func testGameStatusStyleJSONWithWrapperKey() throws {
        let json = """
        {"list_crack_games":[{"title":"Some Game","readable_status":"Cracked","hacked_groups":"RUNE, TENOKE",
          "release_date":"2024-02-10","crack_date":"2024-03-01","protections":"Denuvo","steam_prod_id":123,"is_AAA":true}]}
        """
        let reports = GameExtractor.extract(data: Data(json.utf8), context: context())
        let game = try XCTUnwrap(reports.first)
        XCTAssertEqual(game.status, .cracked)
        XCTAssertEqual(game.groups, ["RUNE", "TENOKE"])
        XCTAssertEqual(game.steamAppID, "123")
    }

    func testListKeyImpliesStatus() {
        let json = """
        {"uncrackedGames":[{"name":"Holdout","release_date":"2022-05-05"}]}
        """
        let reports = GameExtractor.extract(data: Data(json.utf8), context: context())
        XCTAssertEqual(reports.first?.status, .uncracked)
    }

    func testIgnoresObjectsThatAreNotGames() {
        let json = """
        {"user":{"name":"bob","status":"online"},"groups":[{"name":"EMPRESS"}]}
        """
        XCTAssertTrue(GameExtractor.extract(data: Data(json.utf8), context: context()).isEmpty)
    }

    func testNextDataInHTML() {
        let html = """
        <html><body><script id="__NEXT_DATA__" type="application/json">
        {"props":{"pageProps":{"games":[{"title":"Next Game","status":"Uncracked","releaseDate":"2024-01-01"}]}}}
        </script></body></html>
        """
        let reports = GameExtractor.extract(data: Data(html.utf8), context: context())
        XCTAssertEqual(reports.first?.title, "Next Game")
        XCTAssertEqual(reports.first?.status, .uncracked)
    }

    func testHTMLTable() throws {
        let html = """
        <table><thead><tr><th>Game</th><th>Release Date</th><th>Crack Date</th><th>Group</th><th>DRM</th></tr></thead>
        <tbody>
        <tr><td><a href="/game/foo">Foo &amp; Bar</a></td><td>Jan 5, 2024</td><td>Feb 1, 2024</td><td>RUNE</td><td>Denuvo</td></tr>
        <tr><td>Baz</td><td>2024-03-01</td><td>-</td><td></td><td>Denuvo</td></tr>
        </tbody></table>
        """
        let reports = GameExtractor.extract(data: Data(html.utf8), context: context())
        XCTAssertEqual(reports.count, 2)
        let foo = try XCTUnwrap(reports.first { $0.title == "Foo & Bar" })
        XCTAssertEqual(foo.status, .cracked)
        XCTAssertEqual(foo.pageURL?.absoluteString, "https://tracker.example/game/foo")
        let baz = try XCTUnwrap(reports.first { $0.title == "Baz" })
        XCTAssertEqual(baz.status, .uncracked)
    }

    func testHintAppliesWhenPageIsSilent() {
        let json = """
        [{"title":"Quiet Game","release_date":"2024-01-01"}]
        """
        let reports = GameExtractor.extract(data: Data(json.utf8), context: context(hint: .cracked))
        XCTAssertEqual(reports.first?.status, .cracked)
    }
}

final class ParsingTests: XCTestCase {
    func testTitleNormalizationMergesVariants() {
        XCTAssertEqual(TitleNormalizer.key("Assassin's Creed® Shadows"), TitleNormalizer.key("assassins creed shadows"))
        XCTAssertEqual(TitleNormalizer.key("Ratchet & Clank"), TitleNormalizer.key("Ratchet and Clank"))
        XCTAssertEqual(TitleNormalizer.key("Pokémon"), "pokemon")
    }

    func testDateFormats() {
        for s in ["2024-03-01", "2024-03-01T10:00:00Z", "2024-03-01T10:00:00.123Z", "Mar 1, 2024",
                  "March 1st, 2024", "01.03.2024", "1 March 2024", "1709287200", "1709287200000"] {
            XCTAssertNotNil(DateParser.parse(string: s), s)
        }
        XCTAssertNil(DateParser.parse(string: "TBA"))
        XCTAssertNil(DateParser.parse(string: "-"))
    }

    func testGameMergingRules() {
        let release = Date(timeIntervalSinceNow: -100 * 86_400)
        let a = SourceReport(sourceID: "a", sourceName: "A", title: "X", status: .uncracked, releaseDate: release)
        let b = SourceReport(sourceID: "b", sourceName: "B", title: "X", status: .cracked,
                             releaseDate: release, crackDate: Date(timeIntervalSinceNow: -40 * 86_400))
        let uncracked = Game(id: "x", reports: [a])
        XCTAssertEqual(uncracked.status, .uncracked)
        XCTAssertTrue((99...100).contains(uncracked.daysUncracked() ?? 0)) // DST can shave an hour

        let merged = Game(id: "x", reports: [a, b])
        XCTAssertEqual(merged.status, .cracked)
        XCTAssertTrue(merged.hasConflict)
        XCTAssertTrue((59...60).contains(merged.daysToCrack ?? 0))
        XCTAssertNil(merged.daysUncracked())
    }
}
