import XCTest
@testable import WittyKit

/// Shelves, against WittyPlay's console table and the website's rules (Shelves.tsx).
final class GameShelvesTests: XCTestCase {
    private func console(_ json: String) throws -> GameConsole {
        try JSONDecoder().decode(GameConsole.self, from: Data(json.utf8))
    }

    func testTheServersShelfWins() throws {
        let snes = try console(#"{"id":"snes","name":"Super Nintendo","short":"SNES","era":"16-bit","launched":1990,"ended":2003,"media":"cart","shelf":{"case":{"kind":"box","aspect":1.39,"height":0.68},"cart":{"kind":"cart","aspect":1.18,"height":0.82}}}"#)
        XCTAssertEqual(Shelves.era(snes), "16-bit")
        XCTAssertEqual(Shelves.caseShape(snes), ShelfShape(kind: "box", aspect: 1.39, height: 0.68), "an SNES box lies on its side")
        XCTAssertEqual(Shelves.cartShape(snes).kind, "cart")
        // The server can say something else than the table, and is believed.
        let odd = try console(#"{"id":"nes","name":"NES","shelf":{"case":{"kind":"keep","aspect":0.7,"height":0.9},"cart":{"kind":"card","aspect":1,"height":0.5}}}"#)
        XCTAssertEqual(Shelves.caseShape(odd).kind, "keep")
    }

    func testAServerWithoutItUsesWittyPlaysTable() throws {
        let ds = try console(#"{"id":"nds","name":"Nintendo DS","short":"DS"}"#)
        XCTAssertEqual(Shelves.era(ds), "pocket")
        XCTAssertEqual(Shelves.media(ds), "pocket")
        XCTAssertEqual(Shelves.caseShape(ds), ShelfShape(kind: "keep", aspect: 0.91, height: 0.72))
        XCTAssertEqual(Shelves.cartShape(ds).kind, "card")
        let ps1 = try console(#"{"id":"ps1","name":"PlayStation","short":"PS1"}"#)
        XCTAssertEqual(Shelves.caseShape(ps1).kind, "jewel")
        XCTAssertEqual(Shelves.cartShape(ps1).kind, "disc")
        // A console nobody describes: a box and a cartridge, or a keep case and a disc.
        let custom = try console(#"{"id":"custom-pico","name":"Pico Thing","short":"Pico"}"#)
        XCTAssertEqual(Shelves.caseShape(custom), ShelfShape(kind: "box", aspect: 0.72, height: 1))
        XCTAssertEqual(Shelves.cartShape(custom), ShelfShape(kind: "cart", aspect: 0.88, height: 0.85))
        let discs = try console(#"{"id":"custom-cd","name":"A CD thing","media":"disc"}"#)
        XCTAssertEqual(Shelves.caseShape(discs).kind, "keep")
        XCTAssertEqual(Shelves.cartShape(discs).kind, "disc")
        XCTAssertEqual(Shelves.looks.count, Shelves.traits.count, "both tables cover the same consoles")
    }

    func testSpines() throws {
        XCTAssertEqual(Shelves.spineWidth(title: "Thwaite"), 38, "as the website works it out")
        XCTAssertEqual(Shelves.spineWidth(title: "240p Test Suite (NES)"), 46)
        XCTAssertEqual(Shelves.spineWidth(title: String(repeating: "A", count: 80)), 48, "never wider than 48")
        XCTAssertEqual(Shelves.footName(try console(#"{"id":"nes","name":"NES","short":"NES"}"#)), "NES")
        XCTAssertEqual(Shelves.footName(try console(#"{"id":"custom-pico8","name":"Pico-8 Fantasy","short":"Fantasy console"}"#)), "PICO", "too long: the id")
        XCTAssertEqual(Shelves.footName(nil), "")
    }

    func testLetterDividers() {
        XCTAssertEqual(Shelves.initial("  zelda"), "Z")
        XCTAssertEqual(Shelves.initial("240p Test Suite"), "#")
        XCTAssertEqual(Shelves.initial("Été"), "#", "A to Z only, as the website's")
        XCTAssertEqual(Shelves.dividers(["Alpha", "Apple", "Bravo", "1942", "Charlie"]), [0: "A", 2: "B", 3: "#", 4: "C"])
    }

    func testACoversColour() throws {
        // Red and a little grey: the colourful part counts more.
        let red: [UInt8] = [255, 0, 0, 255, 128, 128, 128, 255]
        let t = try XCTUnwrap(Shelves.tint(rgba: red))
        XCTAssertEqual(t.hue, 0)
        XCTAssertGreaterThan(t.saturation, 0.6)
        let grey = try XCTUnwrap(Shelves.tint(rgba: [90, 90, 90, 255]))
        XCTAssertEqual(grey.saturation, 0)
        XCTAssertNil(Shelves.tint(rgba: []))
        // Deep, whatever the theme: at least 38% saturation, 30% lightness.
        let deep = Shelves.deepColour(tint: (200, 0.1), title: "x")
        XCTAssertEqual(deep.hue, 200)
        XCTAssertEqual(deep.saturation, 0.38)
        XCTAssertEqual(deep.lightness, 0.30)
        // No picture: a colour from its title, the website's same one.
        XCTAssertEqual(Shelves.deepColour(tint: nil, title: "Thwaite").hue, 228)
        XCTAssertEqual(Shelves.titleHue("240p Test Suite (NES)"), 293)
        XCTAssertEqual(Shelves.titleHue("Super Tilt Bro."), 61)
        XCTAssertEqual(Shelves.titleHue("Été 🎮"), 138, "a character past the basic plane counts once, by its first unit")
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
