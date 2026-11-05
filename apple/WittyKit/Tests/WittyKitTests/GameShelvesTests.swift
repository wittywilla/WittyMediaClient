import XCTest
@testable import WittyKit

/// Shelves, against WittyPlay's console table and the website's rules (GameShelves.tsx).
final class GameShelvesTests: XCTestCase {
    private func console(_ json: String) throws -> GameConsole {
        try JSONDecoder().decode(GameConsole.self, from: Data(json.utf8))
    }

    func testTheServersShelfWins() throws {
        let snes = try console(#"{"id":"snes","name":"Super Nintendo","short":"SNES","era":"16-bit","launched":1990,"ended":2003,"media":"cart","shelf":{"case":{"kind":"box","aspect":1.39,"height":0.68},"cart":{"kind":"cart","aspect":1.18,"height":0.82}}}"#)
        XCTAssertEqual(GameShelves.era(snes), "16-bit")
        XCTAssertEqual(GameShelves.caseShape(snes), ShelfShape(kind: "box", aspect: 1.39, height: 0.68), "an SNES box lies on its side")
        XCTAssertEqual(GameShelves.cartShape(snes).kind, "cart")
        // The server can say something else than the table, and is believed.
        let odd = try console(#"{"id":"nes","name":"NES","shelf":{"case":{"kind":"keep","aspect":0.7,"height":0.9},"cart":{"kind":"card","aspect":1,"height":0.5}}}"#)
        XCTAssertEqual(GameShelves.caseShape(odd).kind, "keep")
    }

    func testAServerWithoutItUsesWittyPlaysTable() throws {
        let ds = try console(#"{"id":"nds","name":"Nintendo DS","short":"DS"}"#)
        XCTAssertEqual(GameShelves.era(ds), "pocket")
        XCTAssertEqual(GameShelves.media(ds), "pocket")
        XCTAssertEqual(GameShelves.caseShape(ds), ShelfShape(kind: "keep", aspect: 0.91, height: 0.72))
        XCTAssertEqual(GameShelves.cartShape(ds).kind, "card")
        let ps1 = try console(#"{"id":"ps1","name":"PlayStation","short":"PS1"}"#)
        XCTAssertEqual(GameShelves.caseShape(ps1).kind, "jewel")
        XCTAssertEqual(GameShelves.cartShape(ps1).kind, "disc")
        // A console nobody describes: a box and a cartridge, or a keep case and a disc.
        let custom = try console(#"{"id":"custom-pico","name":"Pico Thing","short":"Pico"}"#)
        XCTAssertEqual(GameShelves.caseShape(custom), ShelfShape(kind: "box", aspect: 0.72, height: 1))
        XCTAssertEqual(GameShelves.cartShape(custom), ShelfShape(kind: "cart", aspect: 0.88, height: 0.85))
        let discs = try console(#"{"id":"custom-cd","name":"A CD thing","media":"disc"}"#)
        XCTAssertEqual(GameShelves.caseShape(discs).kind, "keep")
        XCTAssertEqual(GameShelves.cartShape(discs).kind, "disc")
        XCTAssertEqual(GameShelves.looks.count, GameShelves.traits.count, "both tables cover the same consoles")
    }

    func testSpines() throws {
        XCTAssertEqual(GameShelves.spineWidth(title: "Thwaite"), 38, "as the website works it out")
        XCTAssertEqual(GameShelves.spineWidth(title: "240p Test Suite (NES)"), 46)
        XCTAssertEqual(GameShelves.spineWidth(title: String(repeating: "A", count: 80)), 48, "never wider than 48")
        XCTAssertEqual(GameShelves.footName(try console(#"{"id":"nes","name":"NES","short":"NES"}"#)), "NES")
        XCTAssertEqual(GameShelves.footName(try console(#"{"id":"custom-pico8","name":"Pico-8 Fantasy","short":"Fantasy console"}"#)), "PICO", "too long: the id")
        XCTAssertEqual(GameShelves.footName(nil), "")
    }

    func testLetterDividers() {
        XCTAssertEqual(GameShelves.initial("  zelda"), "Z")
        XCTAssertEqual(GameShelves.initial("240p Test Suite"), "#")
        XCTAssertEqual(GameShelves.initial("Été"), "#", "A to Z only, as the website's")
        XCTAssertEqual(GameShelves.dividers(["Alpha", "Apple", "Bravo", "1942", "Charlie"]), [0: "A", 2: "B", 3: "#", 4: "C"])
    }

    func testACoversColour() throws {
        // Red and a little grey: the colourful part counts more.
        let red: [UInt8] = [255, 0, 0, 255, 128, 128, 128, 255]
        let t = try XCTUnwrap(GameShelves.tint(rgba: red))
        XCTAssertEqual(t.hue, 0)
        XCTAssertGreaterThan(t.saturation, 0.6)
        let grey = try XCTUnwrap(GameShelves.tint(rgba: [90, 90, 90, 255]))
        XCTAssertEqual(grey.saturation, 0)
        XCTAssertNil(GameShelves.tint(rgba: []))
        // Deep, whatever the theme: at least 38% saturation, 30% lightness.
        let deep = GameShelves.deepColour(tint: (200, 0.1), title: "x")
        XCTAssertEqual(deep.hue, 200)
        XCTAssertEqual(deep.saturation, 0.38)
        XCTAssertEqual(deep.lightness, 0.30)
        // No picture: a colour from its title, the website's same one.
        XCTAssertEqual(GameShelves.deepColour(tint: nil, title: "Thwaite").hue, 228)
        XCTAssertEqual(GameShelves.titleHue("240p Test Suite (NES)"), 293)
        XCTAssertEqual(GameShelves.titleHue("Super Tilt Bro."), 61)
        XCTAssertEqual(GameShelves.titleHue("Été 🎮"), 138, "a character past the basic plane counts once, by its first unit")
    }

    func testTheViewIsRemembered() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "wittyplay-shelves-test"))
        defaults.removePersistentDomain(forName: "wittyplay-shelves-test")
        XCTAssertEqual(ShelfView.saved(defaults), .cases, "Cases unless another was chosen")
        ShelfView.spines.save(defaults)
        XCTAssertEqual(ShelfView.saved(defaults), .spines)
        XCTAssertEqual(ShelfView.allCases.map(\.label), ["Cases", "Cartridges", "Shelf"])
        defaults.removePersistentDomain(forName: "wittyplay-shelves-test")
    }
}

final class GamesQueryTests: XCTestCase {
    func testMadeForTwoAsksForPlayers() {
        XCTAssertEqual(WittyClient.gamesPath(library: 4, players: 2, limit: 24),
                       "/items?library=4&kind=game&sort=popular&desc=0&offset=0&limit=24&players=2")
        XCTAssertEqual(WittyClient.gamesPath(library: 4, console: "nes", sort: "added"),
                       "/items?library=4&kind=game&sort=added&desc=1&offset=0&limit=60&console=nes")
        XCTAssertFalse(WittyClient.gamesPath(library: 4, players: 1).contains("players"), "one player is every game")
    }
}
