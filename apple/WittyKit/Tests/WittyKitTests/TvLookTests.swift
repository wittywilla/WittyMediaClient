import XCTest
@testable import WittyKit

final class TvLookTests: XCTestCase {
    private struct Vector: Decodable {
        let id: String
        let over: [String: String]
        let want: [String: String]
    }

    // What themeTokens in the server's web/src/pages/tv/tvThemes.ts works out for these, every token,
    // with its two washes (rgb with an opacity) written as #rrggbbaa.
    private let vectors = #"""
    [{"id":"classic","over":{},"want":{"bg":"#06164a","panel":"#0a2270","panel2":"#123391","head":"#16389e","ch":"#0c2a84","dim":"#0d2a7c","line":"#4967b5","text":"#ffffff","soft":"#c3c7d4","cell":"#1a43b8","cell2":"#143594","cellText":"#ffffff","cellSoft":"#c8d2ee","live":"#0f6a7f","live2":"#0b5466","liveText":"#ffffff","liveSoft":"#d9e7eb","hi":"#ffd60a","hiText":"#000000","accent":"#ffd60a","accentText":"#000000","keyA":"#ffd60a","keyB":"#4ce06a","keyC":"#7fc7ff","keyText":"#000000","err":"#ffe08a","lite":"#ffffff29","shade":"#00000024"}},{"id":"satellite","over":{},"want":{"bg":"#07090d","panel":"#10131a","panel2":"#22262f","head":"#14171e","ch":"#10131a","dim":"#0c0e13","line":"#6a7181","text":"#ffffff","soft":"#c3c4c5","cell":"#14171e","cell2":"#14171e","cellText":"#ffffff","cellSoft":"#c7c7c9","live":"#2e2300","live2":"#2e2300","liveText":"#ffffff","liveSoft":"#cdcac2","hi":"#ffb300","hiText":"#000000","accent":"#ffb300","accentText":"#000000","keyA":"#ffb300","keyB":"#5fd47d","keyC":"#8cc6ff","keyText":"#000000","err":"#ffd27a","lite":"#ffb3002e","shade":"#00000024"}},{"id":"teletext","over":{},"want":{"bg":"#000000","panel":"#000000","panel2":"#0000d0","head":"#0000d0","ch":"#000000","dim":"#000000","line":"#006e6e","text":"#ffffff","soft":"#c2c2c2","cell":"#000000","cell2":"#000000","cellText":"#ffffff","cellSoft":"#c2c2c2","live":"#003c00","live2":"#003c00","liveText":"#ffffff","liveSoft":"#c2d0c2","hi":"#00ffff","hiText":"#000000","accent":"#ffff00","accentText":"#000000","keyA":"#ff5a5a","keyB":"#00ff00","keyC":"#ffff00","keyText":"#000000","err":"#ff9d9d","lite":"#00ff0038","shade":"#00000024"}},{"id":"listings","over":{},"want":{"bg":"#f5f0e4","panel":"#f5f0e4","panel2":"#eae3d2","head":"#f5f0e4","ch":"#f5f0e4","dim":"#efe9db","line":"#857f72","text":"#1b1813","soft":"#4f4c45","cell":"#f5f0e4","cell2":"#f5f0e4","cellText":"#1b1813","cellSoft":"#4f4c45","live":"#ebdfb8","live2":"#ebdfb8","liveText":"#1b1813","liveSoft":"#4d483b","hi":"#1b1813","hiText":"#ffffff","accent":"#9c1c12","accentText":"#ffffff","keyA":"#1b1813","keyB":"#1b1813","keyC":"#1b1813","keyText":"#ffffff","err":"#9c1c12","lite":"#9c1c121f","shade":"#ffffff33"}},{"id":"classic","over":{"bg":"#f0f0f0"},"want":{"bg":"#f0f0f0","panel":"#e2e2e2","panel2":"#d3d3d3","head":"#cecece","ch":"#e2e2e2","dim":"#e2e2e2","line":"#868686","text":"#000000","soft":"#3a3a3a","cell":"#cecece","cell2":"#d4d4d4","cellText":"#000000","cellSoft":"#313131","live":"#d9d0a3","live2":"#ddd6b1","liveText":"#000000","liveSoft":"#343227","hi":"#9c8407","hiText":"#000000","accent":"#605104","accentText":"#ffffff","keyA":"#605104","keyB":"#605104","keyC":"#605104","keyText":"#ffffff","err":"#605104","lite":"#0000001a","shade":"#00000024"}},{"id":"modern","over":{"bg":"#102030","accent":"#ffb300"},"want":{"bg":"#102030","panel":"#1e2d3c","panel2":"#2d3b49","head":"#313f4d","ch":"#1e2d3c","dim":"#1e2d3c","line":"#616c76","text":"#ffffff","soft":"#c6c9cd","cell":"#313f4d","cell2":"#2b3948","cellText":"#ffffff","cellSoft":"#ced1d4","live":"#5e593c","live2":"#504f3a","liveText":"#ffffff","liveSoft":"#d8d7d0","hi":"#ffffff","hiText":"#000000","accent":"#ffb300","accentText":"#000000","keyA":"#ffb300","keyB":"#ffb300","keyC":"#ffb300","keyText":"#000000","err":"#ffb300","lite":"#ffffff29","shade":"#00000024"}},{"id":"listings","over":{"hi":"#0044cc"},"want":{"bg":"#f5f0e4","panel":"#f5f0e4","panel2":"#eae3d2","head":"#f5f0e4","ch":"#f5f0e4","dim":"#efe9db","line":"#857f72","text":"#1b1813","soft":"#4f4c45","cell":"#f5f0e4","cell2":"#f5f0e4","cellText":"#1b1813","cellSoft":"#4f4c45","live":"#ebdfb8","live2":"#ebdfb8","liveText":"#1b1813","liveSoft":"#4d483b","hi":"#0044cc","hiText":"#ffffff","accent":"#9c1c12","accentText":"#ffffff","keyA":"#1b1813","keyB":"#1b1813","keyC":"#1b1813","keyText":"#ffffff","err":"#9c1c12","lite":"#9c1c121f","shade":"#ffffff33"}},{"id":"satellite","over":{"cell":"#202020","text":"#eeeeee"},"want":{"bg":"#07090d","panel":"#10131a","panel2":"#22262f","head":"#14171e","ch":"#10131a","dim":"#0c0e13","line":"#6f7480","text":"#eeeeee","soft":"#b7b7b8","cell":"#202020","cell2":"#1c1c1d","cellText":"#eeeeee","cellSoft":"#bdbdbd","live":"#514019","live2":"#443617","liveText":"#eeeeee","liveSoft":"#c8c4bb","hi":"#ffb300","hiText":"#000000","accent":"#ffb300","accentText":"#000000","keyA":"#ffb300","keyB":"#5fd47d","keyC":"#8cc6ff","keyText":"#000000","err":"#ffd27a","lite":"#ffb3002e","shade":"#00000024"}},{"id":"custom","over":{"bg":"#000000","cell":"#2a2a2a","live":"#3a3a3a","hi":"#ffffff","accent":"#c9a2ff"},"want":{"bg":"#000000","panel":"#0f0f0f","panel2":"#1f1f1f","head":"#242424","ch":"#0f0f0f","dim":"#0f0f0f","line":"#707070","text":"#ffffff","soft":"#c2c2c2","cell":"#2a2a2a","cell2":"#222222","cellText":"#ffffff","cellSoft":"#cccccc","live":"#3a3a3a","live2":"#303030","liveText":"#ffffff","liveSoft":"#d0d0d0","hi":"#ffffff","hiText":"#000000","accent":"#c9a2ff","accentText":"#000000","keyA":"#c9a2ff","keyB":"#c9a2ff","keyC":"#c9a2ff","keyText":"#000000","err":"#c9a2ff","lite":"#ffffff29","shade":"#00000024"}},{"id":"outline","over":{"live":"#ff0000"},"want":{"bg":"#0f1115","panel":"#16181d","panel2":"#23262d","head":"#16181d","ch":"#16181d","dim":"#16181d","line":"#656973","text":"#ffffff","soft":"#c5c6c7","cell":"#23262d","cell2":"#23262d","cellText":"#ffffff","cellSoft":"#cacbcd","live":"#ff0000","live2":"#ed0202","liveText":"#000000","liveSoft":"#000000","hi":"#7955ff","hiText":"#ffffff","accent":"#b39dff","accentText":"#000000","keyA":"#b39dff","keyB":"#b39dff","keyC":"#b39dff","keyText":"#000000","err":"#b39dff","lite":"#ffffff29","shade":"#ffffff33"}},{"id":"teletext","over":{"accent":"#000000"},"want":{"bg":"#000000","panel":"#000000","panel2":"#0000d0","head":"#0000d0","ch":"#000000","dim":"#000000","line":"#006e6e","text":"#ffffff","soft":"#c2c2c2","cell":"#000000","cell2":"#000000","cellText":"#ffffff","cellSoft":"#c2c2c2","live":"#000000","live2":"#000000","liveText":"#ffffff","liveSoft":"#c2c2c2","hi":"#00ffff","hiText":"#000000","accent":"#adadad","accentText":"#000000","keyA":"#adadad","keyB":"#adadad","keyC":"#adadad","keyText":"#000000","err":"#ff9d9d","lite":"#00ff0038","shade":"#00000024"}},{"id":"compact","over":{"bg":"#ffffff"},"want":{"bg":"#ffffff","panel":"#f0f0f0","panel2":"#e0e0e0","head":"#dbdbdb","ch":"#f0f0f0","dim":"#f0f0f0","line":"#8f8f8f","text":"#000000","soft":"#3d3d3d","cell":"#dbdbdb","cell2":"#e1e1e1","cellText":"#000000","cellSoft":"#353535","live":"#d2cde3","live2":"#dad6e8","liveText":"#000000","liveSoft":"#323136","hi":"#7955ff","hiText":"#ffffff","accent":"#5e5285","accentText":"#ffffff","keyA":"#5e5285","keyB":"#5e5285","keyC":"#5e5285","keyText":"#ffffff","err":"#5e5285","lite":"#0000001a","shade":"#ffffff33"}},{"id":"bigpicture","over":{"hi":"#ff00ff","cell":"#334455"},"want":{"bg":"#0f1115","panel":"#16181d","panel2":"#23262d","head":"#16181d","ch":"#16181d","dim":"#16181d","line":"#656973","text":"#ffffff","soft":"#c5c6c7","cell":"#334455","cell2":"#2d3b49","cellText":"#ffffff","cellSoft":"#ced2d6","live":"#4f587a","live2":"#434b68","liveText":"#ffffff","liveSoft":"#d5d7df","hi":"#ff00ff","hiText":"#000000","accent":"#b39dff","accentText":"#000000","keyA":"#b39dff","keyB":"#b39dff","keyC":"#b39dff","keyText":"#000000","err":"#b39dff","lite":"#ffffff29","shade":"#00000024"}}]
    """#

    private func all(_ c: TvColours) -> [String: String] {
        ["bg": c.bg, "panel": c.panel, "panel2": c.panel2, "head": c.head, "ch": c.ch, "dim": c.dim, "line": c.line, "text": c.text, "soft": c.soft,
         "cell": c.cell, "cell2": c.cell2, "cellText": c.cellText, "cellSoft": c.cellSoft, "live": c.live, "live2": c.live2, "liveText": c.liveText, "liveSoft": c.liveSoft,
         "hi": c.hi, "hiText": c.hiText, "accent": c.accent, "accentText": c.accentText, "keyA": c.keyA, "keyB": c.keyB, "keyC": c.keyC, "keyText": c.keyText,
         "err": c.err, "lite": c.lite, "shade": c.shade]
    }

    func testColoursMatchTheServersOwnCode() throws {
        for v in try JSONDecoder().decode([Vector].self, from: Data(vectors.utf8)) {
            let got = all(TvLook.colours(theme: v.id, overrides: v.over, app: .fallback))
            for (name, want) in v.want {
                XCTAssertEqual(got[name], want, "\(v.id) \(v.over): \(name)")
            }
        }
    }

    func testAThemeThatFollowsTheAppHasTheAppsColours() {
        let app = TvAppColours.fallback
        let modern = TvLook.colours(theme: "modern", overrides: [:], app: app)
        XCTAssertEqual(modern.bg, app.bg)
        XCTAssertEqual(modern.panel2, app.bg3)
        XCTAssertEqual(modern.live, app.bg4)
        XCTAssertEqual(modern.hi, app.fg)
        XCTAssertEqual(modern.hiText, app.bg)
        XCTAssertEqual(modern.accentText, app.bg)
        XCTAssertEqual(modern.err, app.danger)
        XCTAssertEqual(modern.lite, "#7955ff3d", "the accent at 24%")
        let outline = TvLook.colours(theme: "outline", overrides: [:], app: app)
        XCTAssertEqual(outline.hi, app.accent)
        XCTAssertEqual(outline.hiText, app.accentFg)
        XCTAssertEqual(outline.keyA, app.accent)
    }

    func testYourChoiceThenTheAppsThenTheOwners() {
        func theme(_ saved: TvSaved?, _ owner: String?, suggestion: String? = nil, layout: String? = nil, skin: String? = nil) -> String {
            TvLook.choice(saved: saved, suggestion: suggestion, ownerTheme: owner, ownerLayout: layout, ownerSkin: skin).theme
        }
        XCTAssertEqual(theme(TvSaved(theme: "teletext"), "listings"), "teletext")
        XCTAssertEqual(theme(nil, "listings"), "listings")
        XCTAssertEqual(theme(nil, "listings", suggestion: "modern"), "modern", "an app theme's suggestion comes before the owner's")
        XCTAssertEqual(theme(TvSaved(theme: "compact"), "listings", suggestion: "modern"), "compact")
        XCTAssertEqual(theme(nil, "listings", suggestion: "custom"), "listings", "nothing suggests someone's Custom")
        XCTAssertEqual(theme(TvSaved(theme: "no such theme"), "listings"), "listings")
        XCTAssertEqual(theme(nil, nil), "classic")
        // An owner can't start people on someone's Custom.
        XCTAssertEqual(theme(nil, "custom"), "classic")
        XCTAssertEqual(theme(nil, nil, layout: "classic", skin: "satellite"), "satellite")
        XCTAssertEqual(TvLook.resolve(saved: nil, suggestion: "modern", ownerTheme: "listings", ownerLayout: nil, ownerSkin: nil).source, .app)
        XCTAssertEqual(TvLook.resolve(saved: nil, ownerTheme: "listings", ownerLayout: nil, ownerSkin: nil).source, .owner)
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
        // The old box with the app's colours is Custom on the box's shape, in plain type.
        let box = TvLook.resolve(saved: TvSaved(layout: "classic", colours: "theme"), ownerTheme: nil, ownerLayout: nil, ownerSkin: nil)
        XCTAssertEqual(box.theme, "custom")
        XCTAssertEqual(box.shape, .box)
        XCTAssertEqual(box.font, "system")
    }

    func testABadColourIsIgnored() {
        let c = TvLook.colours(theme: "classic", overrides: ["hi": "yellow", "bg": "#12"], app: .fallback)
        XCTAssertEqual(c, TvLook.colours(theme: "classic", overrides: [:], app: .fallback))
    }

    func testEachThemesShape() {
        let shapes = Dictionary(uniqueKeysWithValues: TvTheme.all.map { ($0.id, $0.shape) })
        XCTAssertEqual(shapes, ["modern": .modern, "classic": .box, "satellite": .receiver, "teletext": .teletext, "listings": .listings,
                                "bigpicture": .cinema, "outline": .outline, "compact": .compact, "custom": .modern])
        let custom = TvLook.resolve(saved: TvSaved(theme: "custom", custom: .init(shape: "listings", font: "mono")), ownerTheme: nil, ownerLayout: nil, ownerSkin: nil)
        XCTAssertEqual(custom.shape, .listings)
        XCTAssertEqual(custom.font, "mono")
        let wrong = TvLook.resolve(saved: TvSaved(theme: "custom", custom: .init(shape: "no such shape")), ownerTheme: nil, ownerLayout: nil, ownerSkin: nil)
        XCTAssertEqual(wrong.shape, .modern)
        XCTAssertEqual(TvLook.resolve(saved: TvSaved(theme: "teletext", custom: .init(shape: "listings", font: "serif")), ownerTheme: nil, ownerLayout: nil, ownerSkin: nil).font, "",
                       "only Custom takes a type of its own")
    }

    // rowHeight, previewAuto and previewLimit in tvThemes.ts for a 1920 by 1080 screen.
    func testRowsAndThePreviewAsTheServerSizesThemOnATV() {
        let rows: [TvShape: [Double]] = [.box: [58, 72, 90], .modern: [64, 80, 100], .receiver: [56, 70, 88], .teletext: [51, 64, 80], .listings: [58, 72, 90],
                                         .cinema: [51, 64, 80], .outline: [61, 76, 95], .compact: [45, 56, 70]]
        for (shape, want) in rows {
            XCTAssertEqual(["compact", "normal", "large"].map { TvLook.rowHeight(shape, width: 1920, density: $0) }, want, shape.rawValue)
        }
        let preview: [TvShape: Double] = [.box: 653, .modern: 730, .receiver: 653, .teletext: 653, .listings: 653, .cinema: 805, .outline: 691, .compact: 422]
        for (shape, want) in preview {
            XCTAssertEqual(TvLook.previewAuto(shape, pageWidth: 1920, pageHeight: 1080), want, shape.rawValue)
        }
        XCTAssertEqual(TvLook.previewLimit(pageWidth: 1920, pageHeight: 1080), 805)
    }

    func testTheOtherChoicesAndTheirDefaults() throws {
        let plain = TvLook.resolve(saved: nil, ownerTheme: "satellite", ownerLayout: nil, ownerSkin: nil)
        XCTAssertEqual(plain.density, "normal")
        XCTAssertEqual(plain.hours, 0)
        XCTAssertTrue(plain.nowLine && plain.progress && plain.subtitles && plain.logos && plain.art)
        XCTAssertEqual(plain.preview, "highlight")
        XCTAssertEqual(plain.previewSide, "right")
        XCTAssertFalse(plain.previewSound)
        XCTAssertEqual(TvLook.resolve(saved: nil, ownerTheme: "bigpicture", ownerLayout: nil, ownerSkin: nil).previewSide, "left", "Big picture starts on the left")

        let json = #"{"theme":"compact","density":"large","hours":3,"nowLine":false,"progress":false,"subtitles":false,"logos":false,"art":false,"preview":"last","previewSide":"left","previewW":500,"previewSound":true}"#
        let saved = try JSONDecoder().decode(TvSaved.self, from: Data(json.utf8))
        let look = TvLook.resolve(saved: saved, ownerTheme: nil, ownerLayout: nil, ownerSkin: nil)
        XCTAssertEqual(look.density, "large")
        XCTAssertEqual(look.hours, 3)
        XCTAssertFalse(look.nowLine || look.progress || look.subtitles || look.logos || look.art)
        XCTAssertEqual(look.preview, "last")
        XCTAssertEqual(look.previewSide, "left")
        XCTAssertEqual(look.previewW, 500)
        XCTAssertTrue(look.previewSound)
        XCTAssertEqual(TvLook.resolve(saved: TvSaved(hours: 7), ownerTheme: nil, ownerLayout: nil, ownerSkin: nil).hours, 0, "only the hours the page offers")
    }

    func testAPreviewPlacedBeforeThereWereSides() throws {
        let old = try JSONDecoder().decode(TvSaved.self, from: Data(#"{"previewPos":"bl","previewSize":"l"}"#.utf8))
        let look = TvLook.resolve(saved: old, ownerTheme: nil, ownerLayout: nil, ownerSkin: nil)
        XCTAssertEqual(look.previewSide, "left")
        XCTAssertEqual(look.previewW, 460)
    }

    func testWhatAnOlderAppIsToldBesideTheTheme() {
        // legacyOf in tvThemes.ts, for each theme on its own shape.
        let want: [String: (String, String)] = ["modern": ("streaming", "theme"), "classic": ("classic", "cable"), "satellite": ("classic", "satellite"), "teletext": ("classic", "cable"),
                                                "listings": ("streaming", "theme"), "bigpicture": ("streaming", "theme"), "outline": ("streaming", "theme"), "compact": ("streaming", "theme"), "custom": ("streaming", "theme")]
        for theme in TvTheme.all {
            let got = TvLook.legacyOf(theme.id, shape: theme.shape)
            XCTAssertEqual(got.layout, want[theme.id]?.0, theme.id)
            XCTAssertEqual(got.colours, want[theme.id]?.1, theme.id)
        }
        XCTAssertEqual(TvLook.legacyOf("custom", shape: .box).colours, "theme")
        XCTAssertEqual(TvLook.legacyOf("custom", shape: .box).layout, "classic")
    }

    func testAChannelsOwnColourIsMadeVisible() {
        XCTAssertNil(TvLook.channelAccent(nil, on: "#000000"))
        XCTAssertEqual(TvLook.channelAccent("#ff0000", on: "#000000"), "#ff0000")
        let pushed = TvLook.channelAccent("#101010", on: "#000000")!
        XCTAssertGreaterThanOrEqual(TvLook.contrast(pushed, "#000000"), 4.5)
    }

    func testAccountChoicesReadTheLookAndLeaveTheRest() throws {
        let json = #"{"homeRows":["a"],"tvLook":{"theme":"satellite","logos":false,"density":"large","hours":2,"custom":{"shape":"box","font":""},"preview":7}}"#
        let u = try JSONDecoder().decode(AccountChoices.self, from: Data(json.utf8))
        XCTAssertEqual(u.tvLook?.theme, "satellite")
        XCTAssertEqual(u.tvLook?.logos, false)
        XCTAssertEqual(u.tvLook?.hours, 2)
        XCTAssertEqual(u.tvLook?.custom?.shape, "box")
        XCTAssertNil(u.tvLook?.preview, "something of the wrong kind is as if it weren't chosen")
    }
}
