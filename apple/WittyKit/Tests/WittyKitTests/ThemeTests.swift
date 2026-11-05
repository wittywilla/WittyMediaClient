import XCTest
@testable import WittyKit

final class ThemeTests: XCTestCase {
    func testColoursAreReadInEachForm() {
        XCTAssertEqual(ThemeColour(hex: "#abc")?.hex, "#aabbcc")
        XCTAssertEqual(ThemeColour(hex: "#0B1120")?.hex, "#0b1120")
        XCTAssertEqual(ThemeColour(hex: "#E6ECF71A")?.alpha ?? 0, 26.0 / 255, accuracy: 0.0001)
        XCTAssertNil(ThemeColour(hex: "rgb(1, 2, 3)"))
        XCTAssertNil(ThemeColour(hex: "#12345"))
        XCTAssertNil(ThemeColour(hex: "red"))
    }

    func testAServerThemeTranslates() throws {
        let json = ##"{"id":"midnight","name":"Midnight","scheme":"dark","colors":{"accent":"#2F6FED","accent-2":"#2560D4","accent-fg":"#FFFFFF","accent-text":"#6EA4FF","bg":"#0B1120","bg-2":"#111A2E","bg-3":"#18233B","bg-4":"#22304D","border":"#E6ECF71A","control-line":"#496BB4","danger":"#FF6B78","fg":"#E6ECF7","fg-2":"#A8B4CA","fg-3":"#8592AA","ok":"#3AD29F","overlay":"#00000099","warn":"#E8AE3F"},"lengths":{"radius":10,"sidebar":240},"webOnly":false}"##
        let theme = ThemeTranslator.translate(try JSONDecoder().decode(ThemeTokens.self, from: Data(json.utf8)))
        XCTAssertEqual(theme.background.hex, "#0b1120")
        XCTAssertEqual(theme.panel.hex, "#111a2e")
        XCTAssertEqual(theme.card.hex, "#18233b")
        XCTAssertEqual(theme.raised.hex, "#22304d")
        XCTAssertEqual(theme.border.hex, "#e6ecf71a")
        XCTAssertEqual(theme.control.hex, "#496bb4")
        XCTAssertEqual(theme.textHint.hex, "#8592aa")
        XCTAssertEqual(theme.accentText.hex, "#6ea4ff")
        XCTAssertEqual(theme.onAccent.hex, "#ffffff")
        XCTAssertEqual(theme.scrim.hex, "#00000099")
        XCTAssertFalse(theme.isLight)
        XCTAssertEqual(theme.radius, 10)
        XCTAssertEqual(theme.radii.large, 14)
        XCTAssertEqual(theme.name, "Midnight")
    }

    func testAnUploadedThemeMissingTokensFallsBack() throws {
        // Only three colours, an unrecognised one, an odd radius, and no scheme: the rest is worked out.
        let json = ##"{"id":"mine","colors":{"bg":"#f6f2ea","accent":"oklch(0.6 0.2 30)","fg-2":"#555"},"lengths":{"radius":"18"}}"##
        let preview = ThemeList.ThemeSummary.Preview(bg: nil, surface: "#ece6da", text: "#221d16", accent: "#a14b1b")
        let theme = ThemeTranslator.translate(try JSONDecoder().decode(ThemeTokens.self, from: Data(json.utf8)), preview: preview)
        XCTAssertEqual(theme.background.hex, "#f6f2ea")
        XCTAssertEqual(theme.text.hex, "#221d16")
        XCTAssertEqual(theme.accent.hex, "#a14b1b") // from the preview, as the token isn't a colour this reads
        XCTAssertEqual(theme.card.hex, "#ece6da")
        XCTAssertEqual(theme.textSecondary.hex, "#555555")
        XCTAssertTrue(theme.isLight)
        XCTAssertEqual(theme.radius, 18)
        XCTAssertEqual(theme.name, "mine")
        XCTAssertEqual(theme.border, theme.text.opacity(0.10))
        // White words on that accent read better than ink.
        XCTAssertEqual(theme.onAccent.hex, "#ffffff")
    }

    func testThemeListReads() throws {
        let json = ##"{"default":"default","themes":[{"id":"default","name":"Witty","scheme":"dark","builtin":true,"preview":{"bg":"#0f1115","surface":"#1f232c","text":"#e8eaf0","accent":"#7955ff"}},{"id":"x","webOnly":true}]}"##
        let list = try JSONDecoder().decode(ThemeList.self, from: Data(json.utf8))
        XCTAssertEqual(list.default, "default")
        XCTAssertEqual(list.themes.first?.preview?.accent, "#7955ff")
        XCTAssertEqual(list.themes.last?.shownName, "x")
        XCTAssertEqual(list.themes.last?.webOnly, true)
    }

    /// The same examples Android's port is tested against, worked out with the website's own makeTheme.
    func testThemeMakerMatchesTheWebsite() throws {
        struct Examples: Decodable {
            struct Case: Decodable {
                struct Output: Decodable { let vars: [String: String]; let radius: Int; let adjusted: Bool }
                let input: ThemeMakerInput
                let output: Output
            }
            let cases: [Case]
        }
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/data/theme-maker-examples.json")
        let examples = try JSONDecoder().decode(Examples.self, from: Data(contentsOf: file))
        XCTAssertGreaterThanOrEqual(examples.cases.count, 6)
        for example in examples.cases {
            let made = ThemeMaker.make(example.input)
            XCTAssertEqual(made.vars, example.output.vars, example.input.name)
            XCTAssertEqual(made.radius, example.output.radius, example.input.name)
            XCTAssertEqual(made.adjusted, example.output.adjusted, example.input.name)
        }
    }

    func testAMadeThemeTranslates() {
        let theme = ThemeTranslator.translate(made: ThemeMakerInput(name: "Mine", scheme: "light", accent: "#e0457b", tint: "#e0457b", corners: "round"))
        XCTAssertTrue(theme.isLight)
        XCTAssertEqual(theme.radius, 18)
        XCTAssertEqual(theme.name, "Mine")
        XCTAssertGreaterThanOrEqual(theme.text.contrast(with: theme.background), 4.5)
        XCTAssertGreaterThanOrEqual(theme.onAccent.contrast(with: theme.accent), 4.5)
    }
}
