import XCTest
@testable import WittyKit

/// The touch controls against the local server's own answers (`GET /consoles/{c}/controls?device=`)
/// and the website player's rules.
final class TouchControlsTests: XCTestCase {
    private static let snes = """
    {"console":"snes","pad":{"face":[{"id":1,"label":"Y"},{"id":9,"label":"X"},{"id":0,"label":"B"},{"id":8,"label":"A"}],"shoulder":[{"id":10,"label":"L"},{"id":11,"label":"R"}],"meta":[{"id":2,"label":"Select"},{"id":3,"label":"Start"}],"art":"four"},"controls":[{"key":"dpad","id":-1,"label":"D-pad","kind":"dpad"},{"key":"b1","id":1,"label":"Y","kind":"face"},{"key":"b9","id":9,"label":"X","kind":"face"},{"key":"b0","id":0,"label":"B","kind":"face"},{"key":"b8","id":8,"label":"A","kind":"face"},{"key":"b10","id":10,"label":"L","kind":"shoulder"},{"key":"b11","id":11,"label":"R","kind":"shoulder"},{"key":"b2","id":2,"label":"Select","kind":"meta"},{"key":"b3","id":3,"label":"Start","kind":"meta"}],"defaults":{"touch":{"landscape":{"b0":{"x":0.87,"y":0.79,"size":0.15,"opacity":0.55},"b1":{"x":0.785,"y":0.62,"size":0.15,"opacity":0.55},"b10":{"x":0.1,"y":0.14,"size":0.12,"opacity":0.55},"b11":{"x":0.9,"y":0.14,"size":0.12,"opacity":0.55},"b2":{"x":0.435,"y":0.91,"size":0.108,"opacity":0.55},"b3":{"x":0.565,"y":0.91,"size":0.108,"opacity":0.55},"b8":{"x":0.955,"y":0.62,"size":0.15,"opacity":0.55},"b9":{"x":0.87,"y":0.44999999999999996,"size":0.15,"opacity":0.55},"dpad":{"x":0.13,"y":0.62,"size":0.36,"opacity":0.55}},"portrait":{"b0":{"x":0.76,"y":0.8049999999999999,"size":0.125,"opacity":0.55},"b1":{"x":0.61,"y":0.72,"size":0.125,"opacity":0.55},"b10":{"x":0.1,"y":0.56,"size":0.1,"opacity":0.55},"b11":{"x":0.9,"y":0.56,"size":0.1,"opacity":0.55},"b2":{"x":0.39,"y":0.93,"size":0.09,"opacity":0.55},"b3":{"x":0.61,"y":0.93,"size":0.09,"opacity":0.55},"b8":{"x":0.91,"y":0.72,"size":0.125,"opacity":0.55},"b9":{"x":0.76,"y":0.635,"size":0.125,"opacity":0.55},"dpad":{"x":0.24,"y":0.72,"size":0.3,"opacity":0.55}}}},"saved":{"touch":{}}}
    """

    /// The Nintendo 64's, landscape only: its D-pad is the stick, and C buttons push the right stick.
    private static let n64 = """
    {"console":"n64","controls":[{"key":"dpad","id":-1,"label":"D-pad","kind":"dpad","stick":true},{"key":"b0","id":0,"label":"A","kind":"face"},{"key":"b20","id":20,"label":"C left","kind":"face"},{"key":"b21","id":21,"label":"C right","kind":"face"},{"key":"b22","id":22,"label":"C up","kind":"face"},{"key":"b23","id":23,"label":"C down","kind":"face"},{"key":"b12","id":12,"label":"Z","kind":"shoulder"}],"defaults":{"touch":{"landscape":{"b0":{"x":0.93375,"y":0.552,"size":0.15,"opacity":0.55},"b12":{"x":0.95075,"y":0.24,"size":0.12,"opacity":0.55},"b20":{"x":0.669,"y":0.32,"size":0.105,"opacity":0.55},"b21":{"x":0.771,"y":0.32,"size":0.105,"opacity":0.55},"b22":{"x":0.72,"y":0.218,"size":0.105,"opacity":0.55},"b23":{"x":0.72,"y":0.422,"size":0.105,"opacity":0.55},"dpad":{"x":0.13,"y":0.62,"size":0.36,"opacity":0.55}}}},"saved":{"touch":{}}}
    """

    private func controls(_ json: String) throws -> GameControls {
        try JSONDecoder().decode(GameControls.self, from: Data(json.utf8))
    }

    private func layout(_ c: GameControls, _ w: Double, _ h: Double, saved: TouchLayouts? = nil) -> TouchScreenLayout {
        TouchScreenLayout(controls: c.controls ?? [], defaults: c.defaults?.touch, saved: saved ?? c.saved?.touch, width: w, height: h)
    }

    private func placed(_ l: TouchScreenLayout, _ key: String) throws -> PlacedTouchControl {
        try XCTUnwrap(l.controls.first { $0.control.key == key })
    }

    func testTheServersLayoutDecodes() throws {
        let c = try controls(Self.snes)
        XCTAssertEqual(c.controls?.count, 9)
        XCTAssertEqual(c.defaults?.touch?.landscape?["dpad"], TouchPlacement(x: 0.13, y: 0.62, size: 0.36, opacity: 0.55))
        XCTAssertEqual(c.defaults?.touch?.portrait?.count, 9, "every control in both")
        XCTAssertEqual(c.saved?.touch, TouchLayouts(), "nothing saved for this device")
    }

    func testWhereEachControlSits() throws {
        // An iPhone held sideways.
        let l = layout(try controls(Self.snes), 844, 390)
        XCTAssertEqual(l.orientation, .landscape)
        XCTAssertEqual(l.controls.count, 9)
        let dpad = try placed(l, "dpad")
        XCTAssertEqual(dpad.centerX, 0.13 * 844, accuracy: 0.001)
        XCTAssertEqual(dpad.centerY, 0.62 * 390, accuracy: 0.001)
        XCTAssertEqual(dpad.width, 0.36 * 390, accuracy: 0.001, "a fraction of the shorter side")
        XCTAssertEqual(dpad.height, dpad.width)
        let start = try placed(l, "b3")
        XCTAssertEqual(start.height, 0.55 * start.width, accuracy: 0.001, "meta buttons are pills")
        XCTAssertEqual(start.top, start.centerY - start.width / 2, accuracy: 0.001, "and keep the square's top")
        let shoulder = try placed(l, "b10")
        XCTAssertEqual(shoulder.height, 0.62 * shoulder.width, accuracy: 0.001)
        XCTAssertEqual(l.pictureArea.height, 390, "landscape: the picture has the whole screen")
    }

    func testPortraitPutsThePictureAbove() throws {
        let l = layout(try controls(Self.snes), 390, 844)
        XCTAssertEqual(l.orientation, .portrait)
        XCTAssertEqual(l.pictureArea.height, 844 * 0.52, accuracy: 0.001)
        XCTAssertEqual(try placed(l, "dpad").centerX, 0.24 * 390, accuracy: 0.001, "the portrait layout")
        XCTAssertEqual(TouchOrientation(width: 500, height: 500), .portrait, "square counts as portrait")
    }

    func testWhatThisDeviceSavedReplacesThatControl() throws {
        let saved = TouchLayouts(landscape: ["b8": TouchPlacement(x: 0.5, y: 0.5, size: 0.2, opacity: 1),
                                             "b9": TouchPlacement(x: 0.87, y: 0.45, size: 0.15, opacity: 0.55, hidden: true)])
        let l = layout(try controls(Self.snes), 844, 390, saved: saved)
        XCTAssertEqual(try placed(l, "b8").centerX, 422, accuracy: 0.001)
        XCTAssertNil(l.controls.first { $0.control.key == "b9" }, "hidden: not drawn, not pressed")
        XCTAssertEqual(try placed(l, "b0").placement.x, 0.87, "the rest stay the server's")
        XCTAssertEqual(layout(try controls(Self.snes), 390, 844, saved: saved).controls.count, 9, "only the way it was saved for")
    }

    func testFingersPressWhatTheyAreOn() throws {
        let l = layout(try controls(Self.snes), 844, 390)
        let a = try placed(l, "b8"), y = try placed(l, "b1")
        var f = TouchFingers()
        f.down(1, x: a.centerX, y: a.centerY, layout: l, stylus: false)
        XCTAssertEqual(f.output(l).buttons, RetroPad.bit(RetroPad.a))
        f.down(2, x: y.centerX, y: y.centerY, layout: l, stylus: false)
        XCTAssertEqual(f.output(l).buttons, RetroPad.bit(RetroPad.a) | RetroPad.bit(RetroPad.y), "two fingers, two buttons")
        // Sliding off Y onto B lets go of Y.
        let b = try placed(l, "b0")
        f.move(2, x: b.centerX, y: b.centerY)
        XCTAssertEqual(f.output(l).buttons, RetroPad.bit(RetroPad.a) | RetroPad.bit(RetroPad.b))
        // Just outside the circle a finger still presses (1.18 of the half); further out, nothing.
        f.up(2)
        f.move(1, x: a.centerX - a.half * 1.15, y: a.centerY)
        XCTAssertEqual(f.output(l).buttons, RetroPad.bit(RetroPad.a))
        f.move(1, x: a.centerX - a.half * 1.25, y: a.centerY)
        XCTAssertEqual(f.output(l).buttons, 0)
        f.up(1)
        XCTAssertTrue(f.isEmpty)
    }

    func testTheDpadHasEightDirections() {
        let up = RetroPad.bit(RetroPad.up), down = RetroPad.bit(RetroPad.down)
        let left = RetroPad.bit(RetroPad.left), right = RetroPad.bit(RetroPad.right)
        XCTAssertEqual(TouchScreenLayout.dpad(dx: 50, dy: 0, half: 100), right)
        XCTAssertEqual(TouchScreenLayout.dpad(dx: 0, dy: -50, half: 100), up, "screen y points down")
        XCTAssertEqual(TouchScreenLayout.dpad(dx: 40, dy: -40, half: 100), up | right)
        XCTAssertEqual(TouchScreenLayout.dpad(dx: -40, dy: 40, half: 100), down | left)
        XCTAssertEqual(TouchScreenLayout.dpad(dx: -50, dy: 0, half: 100), left)
        XCTAssertEqual(TouchScreenLayout.dpad(dx: 10, dy: 10, half: 100), 0, "nothing in the middle")
        XCTAssertEqual(TouchScreenLayout.dpad(dx: 50, dy: 15, half: 100), right, "22° is still right")
    }

    func testTheStick() throws {
        XCTAssertEqual(TouchScreenLayout.stick(dx: 5, dy: 5, half: 100).x, 0, "inside the dead zone")
        let edge = TouchScreenLayout.stick(dx: 100, dy: 0, half: 100)
        XCTAssertEqual(edge.x, 1, accuracy: 0.0001, "full at the edge")
        XCTAssertEqual(TouchScreenLayout.stick(dx: 0, dy: 300, half: 100).y, 1, accuracy: 0.0001, "and no further")
        XCTAssertEqual(TouchScreenLayout.stick(dx: 56, dy: 0, half: 100).x, 0.5, accuracy: 0.0001)

        // The Nintendo 64's D-pad is its stick: a finger that lands on it steers until lifted.
        let l = layout(try controls(Self.n64), 844, 390)
        let stick = try XCTUnwrap(l.stick)
        var f = TouchFingers()
        f.down(1, x: stick.centerX, y: stick.centerY, layout: l, stylus: false)
        f.move(1, x: stick.centerX + stick.half * 3, y: stick.centerY)
        XCTAssertEqual(f.output(l).leftX, 1, accuracy: 0.0001, "wherever it goes")
        XCTAssertEqual(f.output(l).padState(port: 0).lx, 32767)
        XCTAssertEqual(f.output(l).buttons, 0, "a stick, not arrows")
        // A finger that slides onto it doesn't take it.
        var g = TouchFingers()
        g.down(2, x: 10, y: 10, layout: l, stylus: false)
        g.move(2, x: stick.centerX + stick.half / 2, y: stick.centerY)
        XCTAssertEqual(g.output(l).leftX, 0)
    }

    func testCButtonsPushTheRightStick() throws {
        let l = layout(try controls(Self.n64), 844, 390)
        var f = TouchFingers()
        let up = try placed(l, "b22"), right = try placed(l, "b21")
        f.down(1, x: up.centerX, y: up.centerY, layout: l, stylus: false)
        XCTAssertEqual(f.output(l).rightY, -1, "up is negative")
        f.down(2, x: right.centerX, y: right.centerY, layout: l, stylus: false)
        XCTAssertEqual(f.output(l).rightX, 1)
        XCTAssertEqual(f.output(l).buttons, 0)
        let z = try placed(l, "b12")
        f.down(3, x: z.centerX, y: z.centerY, layout: l, stylus: false)
        let state = f.output(l).padState(port: 0)
        XCTAssertTrue(state.pressed(RetroPad.l2))
        XCTAssertEqual(state.l2, 255, "a trigger at full as well as by its bit")
    }

    func testTheStylusOnATouchScreenConsole() throws {
        let l = layout(try controls(Self.snes), 390, 844)
        var f = TouchFingers()
        // On the picture, on no control: the stylus.
        f.down(1, x: 195, y: 300, layout: l, stylus: true)
        XCTAssertEqual(f.output(l).stylus?.x, 195)
        XCTAssertEqual(f.output(l).buttons, 0)
        // Only one stylus; a second finger on nothing presses nothing.
        f.down(2, x: 100, y: 200, layout: l, stylus: true)
        XCTAssertEqual(f.output(l).stylus?.x, 195)
        // A finger on a button is a button.
        let a = try placed(l, "b8")
        f.down(3, x: a.centerX, y: a.centerY, layout: l, stylus: true)
        XCTAssertEqual(f.output(l).buttons, RetroPad.bit(RetroPad.a))
        // Staying the stylus wherever it goes, even over a button.
        f.move(1, x: a.centerX, y: a.centerY)
        XCTAssertEqual(f.output(l).stylus?.x, a.centerX)
        // Not a touch-screen console: no stylus.
        var g = TouchFingers()
        g.down(1, x: 195, y: 300, layout: l, stylus: false)
        XCTAssertNil(g.output(l).stylus)
    }

    func testThePointerIsOnTheGamesOwnScreen() {
        let picture = (x: 0.0, y: 0.0, width: 390.0, height: 585.0)
        let middle = touchPointer(x: 195, y: 292.5, picture: picture, turns: 0, pressed: true)
        XCTAssertEqual(middle.x, 0, accuracy: 0.0001)
        XCTAssertEqual(middle.y, 0, accuracy: 0.0001)
        // The DS's lower screen is the picture's lower half.
        XCTAssertEqual(touchPointer(x: 195, y: 438.75, picture: picture, turns: 0, pressed: true).y, 0.5, accuracy: 0.0001)
        // Outside the picture it stays at the edge, still pressed.
        let below = touchPointer(x: 195, y: 800, picture: picture, turns: 0, pressed: true)
        XCTAssertEqual(below.y, 1)
        XCTAssertTrue(below.pressed)
        // A picture turned a quarter clockwise: its top left is drawn at the top right.
        let turned = touchPointer(x: 390, y: 0, picture: picture, turns: 1, pressed: true)
        XCTAssertEqual(turned.x, -1, accuracy: 0.0001)
        XCTAssertEqual(turned.y, -1, accuracy: 0.0001)
    }
}
