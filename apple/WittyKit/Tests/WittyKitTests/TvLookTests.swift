import XCTest
@testable import WittyKit

final class TvLookTests: XCTestCase {
    private struct Vector: Decodable {
        let id: String
        let over: [String: String]
        let want: [String: String]
    }

    // What themeTokens in the server's web/src/pages/tv/tvThemes.ts works out for these.
    private let vectors = #"""
    [{"id":"classic","over":{},"want":{"bg":"#06164a","panel":"#0a2270","cell":"#1a43b8","cellText":"#ffffff","live":"#0f6a7f","liveText":"#ffffff","hi":"#ffd60a","hiText":"#000000","accent":"#ffd60a","text":"#ffffff","soft":"#c3c7d4","line":"#4967b5"}},{"id":"satellite","over":{},"want":{"bg":"#07090d","panel":"#10131a","cell":"#14171e","cellText":"#ffffff","live":"#2e2300","liveText":"#ffffff","hi":"#ffb300","hiText":"#000000","accent":"#ffb300","text":"#ffffff","soft":"#c3c4c5","line":"#6a7181"}},{"id":"teletext","over":{},"want":{"bg":"#000000","panel":"#000000","cell":"#000000","cellText":"#ffffff","live":"#003c00","liveText":"#ffffff","hi":"#00ffff","hiText":"#000000","accent":"#ffff00","text":"#ffffff","soft":"#c2c2c2","line":"#006e6e"}},{"id":"listings","over":{},"want":{"bg":"#f5f0e4","panel":"#f5f0e4","cell":"#f5f0e4","cellText":"#1b1813","live":"#ebdfb8","liveText":"#1b1813","hi":"#1b1813","hiText":"#ffffff","accent":"#9c1c12","text":"#1b1813","soft":"#4f4c45","line":"#857f72"}},{"id":"classic","over":{"bg":"#f0f0f0"},"want":{"bg":"#f0f0f0","panel":"#e2e2e2","cell":"#cecece","cellText":"#000000","live":"#d9d0a3","liveText":"#000000","hi":"#9c8407","hiText":"#000000","accent":"#605104","text":"#000000","soft":"#3a3a3a","line":"#868686"}},{"id":"modern","over":{"bg":"#102030","accent":"#ffb300"},"want":{"bg":"#102030","panel":"#1e2d3c","cell":"#313f4d","cellText":"#ffffff","live":"#5e593c","liveText":"#ffffff","hi":"#ffffff","hiText":"#000000","accent":"#ffb300","text":"#ffffff","soft":"#c6c9cd","line":"#616c76"}},{"id":"listings","over":{"hi":"#0044cc"},"want":{"bg":"#f5f0e4","panel":"#f5f0e4","cell":"#f5f0e4","cellText":"#1b1813","live":"#ebdfb8","liveText":"#1b1813","hi":"#0044cc","hiText":"#ffffff","accent":"#9c1c12","text":"#1b1813","soft":"#4f4c45","line":"#857f72"}},{"id":"satellite","over":{"cell":"#202020","text":"#eeeeee"},"want":{"bg":"#07090d","panel":"#10131a","cell":"#202020","cellText":"#eeeeee","live":"#514019","liveText":"#eeeeee","hi":"#ffb300","hiText":"#000000","accent":"#ffb300","text":"#eeeeee","soft":"#b7b7b8","line":"#6f7480"}},{"id":"custom","over":{"bg":"#000000","cell":"#2a2a2a","live":"#3a3a3a","hi":"#ffffff","accent":"#c9a2ff"},"want":{"bg":"#000000","panel":"#0f0f0f","cell":"#2a2a2a","cellText":"#ffffff","live":"#3a3a3a","liveText":"#ffffff","hi":"#ffffff","hiText":"#000000","accent":"#c9a2ff","text":"#ffffff","soft":"#c2c2c2","line":"#707070"}},{"id":"outline","over":{"live":"#ff0000"},"want":{"bg":"#0f1115","panel":"#16181d","cell":"#23262d","cellText":"#ffffff","live":"#ff0000","liveText":"#000000","hi":"#7955ff","hiText":"#ffffff","accent":"#b39dff","text":"#ffffff","soft":"#c5c6c7","line":"#656973"}},{"id":"teletext","over":{"accent":"#000000"},"want":{"bg":"#000000","panel":"#000000","cell":"#000000","cellText":"#ffffff","live":"#000000","liveText":"#ffffff","hi":"#00ffff","hiText":"#000000","accent":"#adadad","text":"#ffffff","soft":"#c2c2c2","line":"#006e6e"}}]
    """#

    func testColoursMatchTheServersOwnCode() throws {
        for v in try JSONDecoder().decode([Vector].self, from: Data(vectors.utf8)) {
            let c = TvLook.colours(theme: v.id, overrides: v.over, app: .fallback)
            let got = ["bg": c.bg, "panel": c.panel, "cell": c.cell, "cellText": c.cellText, "live": c.live, "liveText": c.liveText, "hi": c.hi, "hiText": c.hiText, "accent": c.accent, "text": c.text, "soft": c.soft, "line": c.line]
            XCTAssertEqual(got, v.want, "\(v.id) \(v.over)")
        }
    }

    func testAThemeThatFollowsTheAppHasTheAppsColours() {
        let app = TvAppColours.fallback
        let modern = TvLook.colours(theme: "modern", overrides: [:], app: app)
        XCTAssertEqual(modern.bg, app.bg)
        XCTAssertEqual(modern.hi, app.fg)
        XCTAssertEqual(modern.hiText, app.bg)
        let outline = TvLook.colours(theme: "outline", overrides: [:], app: app)
        XCTAssertEqual(outline.hi, app.accent)
        XCTAssertEqual(outline.hiText, app.accentFg)
    }

    func testYourChoiceThenTheOwners() {
        func theme(_ saved: TvSaved?, _ owner: String?, layout: String? = nil, skin: String? = nil) -> String {
            TvLook.choice(saved: saved, ownerTheme: owner, ownerLayout: layout, ownerSkin: skin).theme
        }
        XCTAssertEqual(theme(TvSaved(theme: "teletext"), "listings"), "teletext")
        XCTAssertEqual(theme(nil, "listings"), "listings")
        XCTAssertEqual(theme(TvSaved(theme: "no such theme"), "listings"), "listings")
        XCTAssertEqual(theme(nil, nil), "classic")
        // An owner can't start people on someone's Custom.
        XCTAssertEqual(theme(nil, "custom"), "classic")
        XCTAssertEqual(theme(nil, nil, layout: "classic", skin: "satellite"), "satellite")
    }

    func testAChangedColourComesWithItsTheme() {
        let saved = TvSaved(theme: "classic", themeColours: ["classic": ["hi": "#ff0000"], "modern": ["hi": "#00ff00"]])
        XCTAssertEqual(TvLook.choice(saved: saved, ownerTheme: nil, ownerLayout: nil, ownerSkin: nil).colours, ["hi": "#ff0000"])
    }

    func testALookSavedBeforeThereWereThemes() {
        func was(_ layout: String?, _ colours: String?, bg: String? = nil, accent: String? = nil) -> (theme: String, colours: [String: String]) {
            TvLook.choice(saved: TvSaved(layout: layout, colours: colours, customBg: bg, customAccent: accent), ownerTheme: nil, ownerLayout: nil, ownerSkin: nil)
        }
        XCTAssertEqual(was("classic", "cable").theme, "classic")
        XCTAssertEqual(was("classic", "satellite").theme, "satellite")
        XCTAssertEqual(was("streaming", "theme").theme, "modern")
        XCTAssertEqual(was("streaming", "cable").colours["hi"], "#ffd60a")
        let own = was("classic", "custom", bg: "#101010", accent: "#ffb300")
        XCTAssertEqual(own.theme, "custom")
        XCTAssertEqual(own.colours, ["bg": "#101010", "accent": "#ffb300", "hi": "#ffb300"])
    }

    func testABadColourIsIgnored() {
        let c = TvLook.colours(theme: "classic", overrides: ["hi": "yellow", "bg": "#12"], app: .fallback)
        XCTAssertEqual(c, TvLook.colours(theme: "classic", overrides: [:], app: .fallback))
    }

    func testAccountChoicesReadTheLookAndLeaveTheRest() throws {
        let json = #"{"homeRows":["a"],"tvLook":{"theme":"satellite","logos":false,"density":"large","hours":2}}"#
        let u = try JSONDecoder().decode(AccountChoices.self, from: Data(json.utf8))
        XCTAssertEqual(u.tvLook?.theme, "satellite")
        XCTAssertEqual(u.tvLook?.logos, false)
    }
}
