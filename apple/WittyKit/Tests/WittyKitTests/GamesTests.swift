import XCTest
@testable import WittyKit

/// WittyPlay on a TV: the server's answers, controllers into states, and what the stream carries.
/// The answers here are cut from the local server's own, so a change of shape shows up.
final class GamesTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: Answers

    func testGameAndHomeDecode() throws {
        let home = try decode(GamesHome.self, """
        {"hero":[{"id":1930,"libraryId":11,"kind":"game","title":"SNES Example 00","year":null,"overview":"A small first program.",
          "tagline":"USA","genres":["Demo"],"rating":null,"contentRating":"","studio":"Doug Fraker","poster":"/x/SNES_00-poster.jpg",
          "backdrop":"","sizeBytes":262144,"updatedAt":1793847351,"console":"snes"}],
         "continue":[{"item":{"id":1922,"title":"240p Test Suite (NES)","console":"nes","poster":""},"plays":3,"lastPlayed":1793849000,
           "save":{"slot":0,"updatedAt":1793849000,"hasThumb":true}}],
         "recent":[],"favourites":[],"favouriteIds":null,"mostPlayed":[],
         "shelves":[{"kind":"genre","name":"Demo","count":4,"items":[]}]}
        """)
        let hero = try XCTUnwrap(home.hero?.first)
        XCTAssertEqual(hero.title, "SNES Example 00")
        XCTAssertTrue(hero.hasPoster)
        XCTAssertFalse(hero.hasBackdrop)
        XCTAssertEqual(hero.studio, "Doug Fraker")
        XCTAssertNil(hero.rating)
        XCTAssertEqual(home.continue?.first?.save?.slot, 0)
        XCTAssertFalse(home.continue?.first?.item.hasPoster ?? true)
        XCTAssertEqual(home.shelves?.first?.id, "genre|Demo")
    }

    func testConsoleDecodes() throws {
        let consoles = try decode([GameConsole].self, """
        [{"id":"nes","name":"Nintendo Entertainment System","short":"NES","cores":[{"id":"fceumm","name":"FCEUmm","license":"GPL-2.0"}],
          "bios":[{"file":"disksys.rom","for":"Famicom Disk System games","required":false}],"installed":[],"ready":false,
          "pad":{"face":[{"id":0,"label":"B"},{"id":8,"label":"A"}],"meta":[{"id":2,"label":"Select"},{"id":3,"label":"Start"}],"art":"two"},
          "count":6}]
        """)
        let nes = try XCTUnwrap(consoles.first)
        XCTAssertEqual(nes.shortName, "NES")
        XCTAssertEqual(nes.pad?.buttons.map(\.label), ["B", "A", "Select", "Start"])
        XCTAssertEqual(nes.ready, false)
        XCTAssertEqual(nes.cores?.first?.license, "GPL-2.0")
    }

    func testSessionTakesModesEitherWay() throws {
        let full = try decode(GameSession.self, """
        {"id":"g1","itemId":1922,"console":"nes","aspect":1.306,"turns":0,"discs":1,
         "modes":[{"id":"webrtc","video":["h264","vp8"]},{"id":"ws-h264","video":["h264"]},{"id":"ws-jpeg","video":["jpeg"]}]}
        """)
        XCTAssertEqual(GameModes.order(full.modes), ["ws-h264", "ws-jpeg"])
        let names = try decode(GameSession.self, #"{"id":"g2","modes":["ws-jpeg","later-thing"]}"#)
        XCTAssertEqual(GameModes.order(names.modes), ["ws-jpeg"])
        XCTAssertEqual(GameModes.order(nil), ["ws-h264", "ws-jpeg"])
        XCTAssertEqual(GameModes.video(for: "ws-jpeg"), "jpeg")
        XCTAssertEqual(GameModes.video(for: "ws-h264"), "h264")
    }

    func testControlsKeepNullsAsTakenAway() throws {
        let controls = try decode(GameControls.self, """
        {"console":"nes","defaults":{"gamepad":{"0":{"b":0},"8":{"b":1},"3":{"b":9}},
          "remote":{"0":"MediaPlayPause","4":"ArrowUp","8":"Enter"},"options":{"deadzone":0.15,"threshold":0.5,"stickDpad":true,"turboHz":12}},
         "saved":{"gamepad":{},"keyboard":null,"touch":{}},"targets":[{"id":4,"label":"D-pad up","group":"dpad"}]}
        """)
        let resolved = try decode(ResolvedPad.self, #"{"map":{"0":{"b":2},"3":null},"options":{"turbo":[0]},"profile":{"id":12,"name":"Couch"}}"#)
        XCTAssertEqual(resolved.map?["3"], .some(nil))
        let mapper = PadMapper(defaults: controls.defaults?.gamepad, layers: [resolved.map], options: resolved.options, defaultOptions: controls.defaults?.options)
        XCTAssertEqual(mapper.map[0], .button(2))
        XCTAssertNil(mapper.map[3], "null takes Start away")
        XCTAssertEqual(mapper.map[8], .button(1))
        XCTAssertEqual(mapper.options.turbo, [0])
        XCTAssertEqual(mapper.options.deadzone, 0.15)
    }

    func testSettingsValues() throws {
        let settings = try decode(GameSettings.self, """
        {"resolved":{"values":{"display.scanlines":0.4,"display.integer":true,"display.rotate":"90","states.quickSlot":3,"display.bezelColor":"#14161e"}},
         "limits":{"maxSpeed":4}}
        """)
        XCTAssertEqual(settings.number("display.scanlines", 0), 0.4)
        XCTAssertTrue(settings.flag("display.integer", false))
        XCTAssertEqual(settings.text("display.rotate", "0"), "90")
        XCTAssertEqual(settings.text("states.quickSlot", "1"), "3")
        XCTAssertEqual(settings.text("missing", "fallback"), "fallback")
        XCTAssertEqual(settings.limits?.maxSpeed, 4)
    }

    func testPrepare() throws {
        let unpacking = try decode(GamePrepare.self, #"{"state":"unpacking","done":50,"total":200}"#)
        XCTAssertFalse(unpacking.ready)
        XCTAssertEqual(unpacking.fraction, 0.25)
        XCTAssertNil(try decode(GamePrepare.self, #"{"state":"reading","done":5,"total":0}"#).fraction)
        XCTAssertTrue(try decode(GamePrepare.self, #"{"state":"ready"}"#).ready)
    }

    func testActionsEncodeAsTheServerTakesThem() throws {
        func text(_ a: GameAction) throws -> String {
            let e = JSONEncoder()
            e.outputFormatting = .sortedKeys
            return String(data: try e.encode(a), encoding: .utf8)!
        }
        XCTAssertEqual(try text(.save(3)), #"{"slot":3,"type":"save"}"#)
        XCTAssertEqual(try text(.pause(true)), #"{"on":true,"type":"pause"}"#)
        XCTAssertEqual(try text(.reset), #"{"type":"reset"}"#)
        XCTAssertEqual(try text(.device(port: 0, device: 261)), #"{"device":261,"port":0,"type":"device"}"#)
    }

    func testSocketAddressCarriesNoToken() throws {
        let client = WittyClient(base: "http://127.0.0.1:9797", token: "secret")
        let request = try XCTUnwrap(client.gameSocketRequest("g/1", video: "h264"))
        XCTAssertEqual(request.url?.absoluteString, "ws://127.0.0.1:9797/api/v1/play/g%2F1/ws?video=h264")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        XCTAssertFalse(request.url!.absoluteString.contains("secret"))
        let secure = WittyClient(base: "https://media.example", token: "t")
        XCTAssertEqual(secure.gameSocketRequest("a", video: "jpeg")?.url?.scheme, "wss")
    }

    // MARK: Words

    func testWords() {
        XCTAssertEqual(GameWords.slotName(0), "Automatic save")
        XCTAssertEqual(GameWords.slotName(100), "Before the last load")
        XCTAssertEqual(GameWords.slotName(101), "Before starting over")
        XCTAssertEqual(GameWords.slotName(7), "Slot 7")
        XCTAssertTrue(GameWords.canSave(to: 1))
        XCTAssertFalse(GameWords.canSave(to: 0))
        XCTAssertFalse(GameWords.canSave(to: 100))
        XCTAssertEqual(GameWords.played(7500), "2 h 5 min")
        XCTAssertEqual(GameWords.played(20), "1 min")
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(GameWords.ago(1_000_000 - 30, now: now), "just now")
        XCTAssertEqual(GameWords.ago(1_000_000 - 600, now: now), "10 minutes ago")
        XCTAssertEqual(GameWords.ago(1_000_000 - 3600, now: now), "1 hour ago")
        XCTAssertEqual(GameWords.ago(1_000_000 - 100_000, now: now), "yesterday")
        XCTAssertEqual(GameWords.players(1), "1 player")
        XCTAssertEqual(GameWords.players(4), "Up to 4 players")
        XCTAssertEqual(GameWords.released("1994"), "1994")
    }

    func testResumeChoice() {
        XCTAssertEqual(ResumeChoice(setting: "ask"), .offer)
        XCTAssertEqual(ResumeChoice(setting: "always"), .always)
        XCTAssertEqual(ResumeChoice(setting: "never"), .never)
        XCTAssertTrue(ResumeChoice.offer.resumes(hasAutoSave: true))
        XCTAssertFalse(ResumeChoice.offer.resumes(hasAutoSave: false))
        XCTAssertFalse(ResumeChoice.never.resumes(hasAutoSave: true))
        XCTAssertEqual(GameStart.slot(4).slotToLoad, 4)
        XCTAssertFalse(GameStart.slot(4).resumes)
        XCTAssertTrue(GameStart.safe(resume: true).resumes)
        XCTAssertTrue(GameStart.safe(resume: false).safeMode)
    }

    // MARK: Controller states

    func testStateIsThirteenLittleEndianBytes() {
        let state = PadState(port: 1, buttons: 0x0109, lx: -32768, ly: 1, rx: 0, ry: 32767, l2: 255, r2: 7)
        XCTAssertEqual([UInt8](state.encoded()), [1, 0x09, 0x01, 0x00, 0x80, 0x01, 0x00, 0, 0, 0xff, 0x7f, 255, 7])
        XCTAssertEqual(state.encoded(tag: 0x0403_0201).suffix(4), Data([1, 2, 3, 4]))
        XCTAssertTrue(PadState(port: 2).isReleased)
    }

    /// The NES defaults as the server sends them: by position, bottom is B and right is A.
    private let nes: PadMap = ["0": .button(0), "2": .button(8), "3": .button(9), "4": .button(12), "5": .button(13),
                               "6": .button(14), "7": .button(15), "8": .button(1)]

    func testDefaultsMapByPosition() {
        let mapper = PadMapper(defaults: nes, options: PadOptions(deadzone: 0.15, threshold: 0.5, stickDpad: true))
        var pad = StandardPadReading()
        pad[button: StandardPadReading.south] = 1
        pad[button: StandardPadReading.start] = 1
        let state = mapper.state(pad, port: 0)
        XCTAssertTrue(state.pressed(RetroPad.b))
        XCTAssertTrue(state.pressed(RetroPad.start))
        XCTAssertFalse(state.pressed(RetroPad.a))
        pad = StandardPadReading()
        pad[button: StandardPadReading.east] = 1
        pad[button: StandardPadReading.left] = 1
        let other = mapper.state(pad, port: 3)
        XCTAssertEqual(other.port, 3)
        XCTAssertEqual(other.buttons, RetroPad.bit(RetroPad.a) | RetroPad.bit(RetroPad.left))
    }

    func testStickSteersTheDpadPastTheDeadZone() {
        let mapper = PadMapper(defaults: nes, options: PadOptions(deadzone: 0.2, threshold: 0.5, stickDpad: true))
        XCTAssertEqual(mapper.state(StandardPadReading(axes: [0.15, 0.1, 0, 0]), port: 0).buttons, 0, "inside the dead zone")
        XCTAssertEqual(mapper.state(StandardPadReading(axes: [0, -0.9, 0, 0]), port: 0).buttons, RetroPad.bit(RetroPad.up))
        XCTAssertEqual(mapper.state(StandardPadReading(axes: [0.95, 0.95, 0, 0]), port: 0).buttons,
                       RetroPad.bit(RetroPad.right) | RetroPad.bit(RetroPad.down))
        let off = PadMapper(defaults: nes, options: PadOptions(stickDpad: false))
        XCTAssertEqual(off.state(StandardPadReading(axes: [1, 0, 0, 0]), port: 0).buttons, 0)
    }

    func testSticksAndTriggers() {
        let map: PadMap = ["16": .axis(0, -1), "17": .axis(0, 1), "18": .axis(1, -1), "19": .axis(1, 1),
                           "12": .button(6), "13": .button(7), "22": .button(12)]
        let mapper = PadMapper(defaults: map, options: PadOptions(deadzone: 0, threshold: 0.5, stickDpad: false))
        var pad = StandardPadReading(axes: [-1, 0.5, 0, 0])
        pad[button: StandardPadReading.l2] = 0.4
        pad[button: StandardPadReading.r2] = 0.8
        pad[button: StandardPadReading.up] = 1
        let state = mapper.state(pad, port: 0)
        XCTAssertEqual(state.lx, -32767)
        XCTAssertEqual(state.ly, 16384)
        XCTAssertEqual(state.ry, -32767, "a button can push a stick")
        XCTAssertEqual(state.l2, 102)
        XCTAssertEqual(state.r2, 204)
        XCTAssertFalse(state.pressed(RetroPad.l2), "not past the press point")
        XCTAssertTrue(state.pressed(RetroPad.r2))
    }

    func testTriggerThatRestsAtOneEnd() {
        let mapper = PadMapper(defaults: ["13": PadSource(a: 5, d: 1, r: -1)], options: PadOptions(threshold: 0.5))
        XCTAssertEqual(mapper.state(StandardPadReading(axes: [0, 0, 0, 0, 0, -1]), port: 0).r2, 0)
        XCTAssertEqual(mapper.state(StandardPadReading(axes: [0, 0, 0, 0, 0, 1]), port: 0).r2, 255)
    }

    func testTurboBeats() {
        let held = RetroPad.bit(RetroPad.b) | RetroPad.bit(RetroPad.up)
        XCTAssertEqual(PadMapper.turbo(held, ids: [RetroPad.b], hz: 10, now: 0.01), held)
        XCTAssertEqual(PadMapper.turbo(held, ids: [RetroPad.b], hz: 10, now: 0.06), RetroPad.bit(RetroPad.up))
        XCTAssertEqual(PadMapper.turbo(held, ids: [], hz: 10, now: 0.06), held)
    }

    func testRemoteKeys() {
        let remote = KeyMapper(["0": "MediaPlayPause", "4": "ArrowUp", "8": "Enter", "3": "MediaFastForward", "18": "ArrowUp"])
        let state = remote.state(held: ["ArrowUp", "Enter"])
        XCTAssertEqual(state.buttons, RetroPad.bit(RetroPad.up) | RetroPad.bit(RetroPad.a))
        XCTAssertEqual(state.ly, -32767, "a key can push the stick, as on the Nintendo 64")
        XCTAssertTrue(remote.knows("MediaPlayPause"))
        XCTAssertFalse(remote.knows("Escape"))
    }

    func testMergingTakesEitherController() {
        let a = PadState(port: 0, buttons: RetroPad.bit(RetroPad.a), lx: 100)
        let b = PadState(port: 0, buttons: RetroPad.bit(RetroPad.up), lx: -2000, l2: 9)
        let both = a.merged(b)
        XCTAssertEqual(both.buttons, RetroPad.bit(RetroPad.a) | RetroPad.bit(RetroPad.up))
        XCTAssertEqual(both.lx, -2000)
        XCTAssertEqual(both.l2, 9)
    }

    // MARK: Every button, as the server sends each console's controls

    /// `defaults` cut from the local server's own answers to `GET /consoles/{id}/controls`.
    private static let consoleControls: [String: (gamepad: PadMap, keyboard: [String: String], targets: [Int])] = [
        "nes": (["0": .button(0), "2": .button(8), "3": .button(9), "4": .button(12), "5": .button(13), "6": .button(14), "7": .button(15), "8": .button(1)],
                ["0": "KeyZ", "2": "ShiftRight", "3": "Enter", "4": "ArrowUp", "5": "ArrowDown", "6": "ArrowLeft", "7": "ArrowRight", "8": "KeyX"],
                [4, 5, 6, 7, 0, 8, 2, 3]),
        "snes": (["0": .button(0), "1": .button(2), "10": .button(4), "11": .button(5), "2": .button(8), "3": .button(9), "4": .button(12), "5": .button(13),
                  "6": .button(14), "7": .button(15), "8": .button(1), "9": .button(3)],
                 ["0": "KeyZ", "1": "KeyA", "10": "KeyQ", "11": "KeyW", "2": "ShiftRight", "3": "Enter", "4": "ArrowUp", "5": "ArrowDown", "6": "ArrowLeft",
                  "7": "ArrowRight", "8": "KeyX", "9": "KeyS"],
                 [4, 5, 6, 7, 1, 9, 0, 8, 10, 11, 2, 3]),
    ]

    func testEveryButtonOfEachConsoleFromAPad() {
        // The DS's controls are the Super Nintendo's, with a touch screen as well.
        var all = Self.consoleControls
        all["nds"] = all["snes"]
        for (console, controls) in all {
            let mapper = PadMapper(defaults: controls.gamepad, options: PadOptions(deadzone: 0.15, threshold: 0.5, stickDpad: true))
            for target in controls.targets {
                guard let source = controls.gamepad[String(target)] ?? nil, let w3c = source.b else {
                    XCTFail("\(console): nothing presses \(target)")
                    continue
                }
                var pad = StandardPadReading()
                pad[button: w3c] = 1
                XCTAssertEqual(mapper.state(pad, port: 2).buttons, RetroPad.bit(target), "\(console): W3C \(w3c) presses only RetroPad \(target)")
            }
            // Nothing the pad has presses a button the console doesn't have.
            var everything = StandardPadReading()
            for n in 0...15 { everything[button: n] = 1 }
            let pressed = mapper.state(everything, port: 0).buttons
            let expected = controls.targets.reduce(UInt16(0)) { $0 | RetroPad.bit($1) }
            XCTAssertEqual(pressed, expected, console)
            // The left stick steers the D-pad too, at full range.
            XCTAssertEqual(mapper.state(StandardPadReading(axes: [-1, 0, 0, 0]), port: 0).buttons, RetroPad.bit(RetroPad.left), console)
        }
    }

    func testEveryButtonOfEachConsoleFromAKeyboard() {
        for (console, controls) in Self.consoleControls {
            let keys = KeyMapper(controls.keyboard)
            for target in controls.targets {
                guard let name = controls.keyboard[String(target)] else {
                    XCTFail("\(console): no key for \(target)")
                    continue
                }
                XCTAssertEqual(keys.state(held: [name]).buttons, RetroPad.bit(target), "\(console): \(name)")
            }
        }
    }

    func testAnalogTriggersAndSticksPassThrough() {
        // A console with sticks and analog triggers, mapped as the server maps them.
        let map: PadMap = ["16": .axis(0, -1), "17": .axis(0, 1), "18": .axis(1, -1), "19": .axis(1, 1),
                           "20": .axis(2, -1), "21": .axis(2, 1), "22": .axis(3, -1), "23": .axis(3, 1),
                           "12": .button(6), "13": .button(7)]
        let mapper = PadMapper(defaults: map, options: PadOptions(deadzone: 0, threshold: 0.5, stickDpad: false))
        var pad = StandardPadReading(axes: [1, -1, -0.5, 0.25])
        pad[button: StandardPadReading.l2] = 1
        pad[button: StandardPadReading.r2] = 0.25
        let state = mapper.state(pad, port: 3)
        XCTAssertEqual(state.lx, 32767)
        XCTAssertEqual(state.ly, -32767)
        XCTAssertEqual(state.rx, -16384)
        XCTAssertEqual(state.ry, 8192)
        XCTAssertEqual(state.l2, 255)
        XCTAssertEqual(state.r2, 64)
        XCTAssertEqual([UInt8](state.encoded()).count, 13)
        XCTAssertEqual(state.encoded().first, 3, "player 4")
    }

    // MARK: Shortcuts

    func testStartAndSelectOpenTheMenu() {
        var shortcuts = PadShortcuts(settings: nil, consoleButtons: [0, 2, 3, 8])
        let select = RetroPad.bit(RetroPad.select), start = RetroPad.bit(RetroPad.start)
        XCTAssertEqual(shortcuts.filter(select).buttons, select, "the game sees the shortcut button")
        let both = shortcuts.filter(select | start)
        XCTAssertEqual(both.started, [.menu])
        XCTAssertEqual(both.buttons, 0)
        XCTAssertEqual(shortcuts.filter(select | start).started, [], "only once while held")
        XCTAssertEqual(shortcuts.filter(0).buttons, 0)
        XCTAssertEqual(shortcuts.filter(start).buttons, start)
    }

    func testShortcutsWithSelect() throws {
        let settings = GameSettings(values: ["hotkeys.pad.quickSave": .text("r2"), "hotkeys.pad.fastForward": .text("r"), "hotkeys.padModifier": .text("select")])
        var shortcuts = PadShortcuts(settings: settings, consoleButtons: [0, 2, 3, 8, 10, 11, 12, 13])
        let select = RetroPad.bit(RetroPad.select), r = RetroPad.bit(RetroPad.r), r2 = RetroPad.bit(RetroPad.r2)
        _ = shortcuts.filter(select)
        let fast = shortcuts.filter(select | r)
        XCTAssertEqual(fast.started, [.fastForward])
        XCTAssertEqual(fast.buttons, select, "R is the shortcut's, not the game's")
        XCTAssertEqual(shortcuts.filter(select | r | r2).started, [.quickSave])
        let up = shortcuts.filter(select)
        XCTAssertEqual(up.ended, [.fastForward])
        XCTAssertEqual(shortcuts.filter(r).buttons, r, "without Select, R is the game's again")
    }

    func testEndingShortcutsStopsHeldOnes() {
        let settings = GameSettings(values: ["hotkeys.pad.fastForward": .text("r"), "hotkeys.pad.quickSave": .text("r2")])
        var shortcuts = PadShortcuts(settings: settings, consoleButtons: [])
        let select = RetroPad.bit(RetroPad.select), r = RetroPad.bit(RetroPad.r), r2 = RetroPad.bit(RetroPad.r2)
        _ = shortcuts.filter(select)
        _ = shortcuts.filter(select | r | r2)
        XCTAssertEqual(shortcuts.endAll(), [.fastForward], "a pad that goes away mid fast-forward stops it; quick save was done once")
        XCTAssertEqual(shortcuts.endAll(), [])
        XCTAssertEqual(shortcuts.filter(r).buttons, r, "after that, nothing is held back")
    }

    func testShortcutsOff() {
        let settings = GameSettings(values: ["hotkeys.padCombos": .flag(false)])
        var shortcuts = PadShortcuts(settings: settings, consoleButtons: [])
        let select = RetroPad.bit(RetroPad.select), r = RetroPad.bit(RetroPad.r), start = RetroPad.bit(RetroPad.start)
        XCTAssertEqual(shortcuts.filter(select | r).started, [])
        XCTAssertEqual(shortcuts.filter(select | r | start).started, [.menu], "Start and Select always open the menu")
    }

    func testModifierTheConsoleDoesntHave() {
        // The Nintendo 64 has no Select: the game never sees it.
        var shortcuts = PadShortcuts(settings: nil, consoleButtons: [0, 1, 3, 10, 11])
        XCTAssertEqual(shortcuts.filter(RetroPad.bit(RetroPad.select)).buttons, 0)
    }

    func testTouchScreenState() {
        XCTAssertEqual([UInt8](PointerState(pressed: true, x: -1, y: 1).encoded()), [255, 1, 0x01, 0x80, 0xff, 0x7f])
        XCTAssertEqual([UInt8](PointerState().encoded()), [255, 0, 0, 0, 0, 0])
        // A touchpad's up is the picture's top.
        let top = PointerState.touchpad(x: 0, y: 1, pressed: true)
        XCTAssertEqual(top.y, -1)
        XCTAssertEqual([UInt8](PointerState(pressed: false, x: 2, y: -3).encoded()).suffix(4), [0xff, 0x7f, 0x01, 0x80], "held to the picture")
    }

    func testPadIdentity() {
        XCTAssertEqual(PadIdentity.key(productCategory: "DualSense", vendorName: "DualSense Wireless Controller"), "054c:0ce6")
        XCTAssertEqual(PadIdentity.key(productCategory: "Xbox One", vendorName: "Xbox Wireless Controller"), "045e:0b13")
        XCTAssertEqual(PadIdentity.key(productCategory: "MFi", vendorName: "Some Pad"), "id:Some Pad")
        XCTAssertEqual(PadIdentity.key(productCategory: "MFi", vendorName: nil), "id:MFi")
        XCTAssertEqual(PadIdentity.key(productCategory: "Joy-Con (L)", vendorName: "Joy-Con (L)"), "057e:2006")
        XCTAssertTrue(PadIdentity.isRemote(productCategory: "Siri Remote"))
        XCTAssertFalse(PadIdentity.isRemote(productCategory: "Joy-Con (R)"))
    }

    // MARK: The stream

    func testBinaryMessages() {
        XCTAssertEqual(GameStreamMessage.parse(Data([1, 1, 0, 0, 1, 0x67])), .video(keyframe: true, annexB: Data([0, 0, 1, 0x67])))
        XCTAssertEqual(GameStreamMessage.parse(Data([1, 0, 9])), .video(keyframe: false, annexB: Data([9])))
        XCTAssertEqual(GameStreamMessage.parse(Data([2, 0xff, 0xd8])), .jpeg(Data([0xff, 0xd8])))
        // 32040 Hz, then one stereo frame and a stray byte, which is left out.
        XCTAssertEqual(GameStreamMessage.parse(Data([3, 0x28, 0x7d, 0, 0, 1, 2, 3, 4, 5])), .pcm(rate: 32040, samples: Data([1, 2, 3, 4])))
        XCTAssertEqual(GameStreamMessage.parse(Data([0xF2, 1])), .timing(Data([1])))
        XCTAssertEqual(GameStreamMessage.parse(Data([42])), .unknown(42))
        XCTAssertNil(GameStreamMessage.parse(Data()))
        XCTAssertNil(GameStreamMessage.parse(Data([3, 1, 2])))
    }

    func testEvents() {
        XCTAssertEqual(GameEvent.parse(#"{"type":"hello","video":"h264"}"#), .hello(video: "h264"))
        XCTAssertEqual(GameEvent.parse(#"{"type":"rumble","port":1,"effect":0,"strength":65535}"#), .rumble(port: 1, strength: 1))
        XCTAssertEqual(GameEvent.parse(#"{"type":"geometry","width":320,"height":240,"aspect":1.333}"#), .geometry(width: 320, height: 240, aspect: 1.333))
        XCTAssertEqual(GameEvent.parse(#"{"type":"ended","text":"The game stopped responding."}"#), .ended("The game stopped responding."))
        XCTAssertEqual(GameEvent.parse(#"{"type":"disc","index":1,"count":3}"#), .disc(index: 1, count: 3))
        XCTAssertEqual(GameEvent.parse(#"{"type":"shutdown"}"#), .shutdown)
        XCTAssertEqual(GameEvent.parse(#"{"type":"new-thing"}"#), .unknown("new-thing"))
        XCTAssertNil(GameEvent.parse("not json"))
    }

    func testAnnexBSplitsUnits() {
        let sps: [UInt8] = [0x67, 0x42, 0xe0, 0x1f], pps: [UInt8] = [0x68, 0xce, 0x3c, 0x80], idr: [UInt8] = [0x65, 0x88, 0x84, 0x00, 0x21]
        let stream = Data([0, 0, 0, 1, 0x09, 0xf0] + [0, 0, 0, 1] + sps + [0, 0, 1] + pps + [0, 0, 0, 1] + idr)
        let units = AnnexB.units(stream)
        XCTAssertEqual(units.map { AnnexB.type($0) }, [9, 7, 8, 5])
        XCTAssertEqual(units[1], Data(sps))
        XCTAssertEqual(units[3], Data(idr), "a zero inside the last unit stays")
        let frame = AnnexB.frame(stream)
        XCTAssertEqual(frame.sps, Data(sps))
        XCTAssertEqual(frame.pps, Data(pps))
        XCTAssertEqual(frame.picture, [Data(idr)])
        XCTAssertEqual([UInt8](AnnexB.lengthPrefixed([Data(pps)])), [0, 0, 0, 4] + pps)
    }

    // MARK: The picture

    func testPictureFitsAtTheGamesShape() {
        let plain = GameSettings(values: [:])
        let fit = PictureLayout.fit(settings: plain, aspect: 4.0 / 3.0, frame: (256, 224), turns: 0, box: (1920, 1080))
        XCTAssertEqual(fit.height, 1080)
        XCTAssertEqual(fit.width, 1440, accuracy: 0.01)
        let wide = PictureLayout.fit(settings: GameSettings(values: ["display.aspect": .text("16:9")]), aspect: 4.0 / 3.0, frame: (256, 224), turns: 0, box: (1920, 1080))
        XCTAssertEqual(wide.width, 1920, accuracy: 0.01)
        let stretch = PictureLayout.fit(settings: GameSettings(values: ["display.aspect": .text("stretch")]), aspect: 4.0 / 3.0, frame: (256, 224), turns: 0, box: (1920, 1080))
        XCTAssertEqual(stretch.width, 1920)
        XCTAssertEqual(stretch.height, 1080)
    }

    func testWholeMultiplesAndTurns() {
        let integer = GameSettings(values: ["display.integer": .flag(true)])
        let fit = PictureLayout.fit(settings: integer, aspect: 4.0 / 3.0, frame: (256, 224), turns: 0, box: (1920, 1080))
        XCTAssertEqual(fit.height, 896, "four times 224")
        let turned = PictureLayout.fit(settings: GameSettings(values: ["display.rotate": .text("90")]), aspect: 4.0 / 3.0, frame: (320, 240), turns: 0, box: (1920, 1080))
        XCTAssertEqual(turned.turns, 1)
        XCTAssertEqual(turned.height, 1080)
        XCTAssertEqual(turned.width, 810, accuracy: 0.01)
        let both = PictureLayout.fit(settings: GameSettings(values: ["display.rotate": .text("270")]), aspect: 1, frame: (1, 1), turns: 1, box: (100, 100))
        XCTAssertEqual(both.turns, 0, "the game's own turn and the person's add up")
    }

    func testSoundLatency() {
        XCTAssertLessThan(GameSoundLatency.seconds("lowest"), GameSoundLatency.seconds("balanced"))
        XCTAssertLessThan(GameSoundLatency.seconds("balanced"), GameSoundLatency.seconds("smooth"))
    }

    /// The local server's NES (fceumm) and SNES (Mesen-S) sessions, as they list their ports.
    func testAThirdPlayerGetsAGamepadWhereThePortIsOnAuto() throws {
        let nes = try JSONDecoder().decode([GamePortDevices].self, from: Data("""
        [{"port":0,"current":1,"types":[{"id":1,"name":"Auto"},{"id":513,"name":"Gamepad"},{"id":258,"name":"Zapper"}]},
         {"port":2,"current":1,"types":[{"id":1,"name":"Auto"},{"id":513,"name":"Gamepad"},{"id":259,"name":"Power Pad A"},{"id":515,"name":"Power Pad B"}]},
         {"port":3,"current":1,"types":[{"id":1,"name":"Auto"},{"id":513,"name":"Gamepad"}]}]
        """.utf8))
        XCTAssertEqual(nes[1].padForNewPlayer(plugged: nil)?.id, 513, "player 3 plays through the Four Score once a gamepad is in")
        XCTAssertEqual(nes[2].padForNewPlayer(plugged: 1)?.id, 513)
        XCTAssertNil(nes[1].padForNewPlayer(plugged: 259), "a Power Pad someone chose stays")
        XCTAssertNil(nes[1].padForNewPlayer(plugged: 513), "already a gamepad")
        let snes = try JSONDecoder().decode(GamePortDevices.self, from: Data("""
        {"port":1,"current":1,"types":[{"id":0,"name":"None"},{"id":257,"name":"SNES Controller"},{"id":513,"name":"Multitap"}]}
        """.utf8))
        XCTAssertNil(snes.padForNewPlayer(plugged: nil), "not on Auto: left as the server plugged it")
    }
}
