// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

final class ProfilePicturesTests: XCTestCase {
    /// Every point a shape touches, handles included: a curve stays inside the hull of its points.
    private func points(_ steps: [PathStep]) -> [(Double, Double)] {
        steps.flatMap { step -> [(Double, Double)] in
            switch step {
            case .move(let x, let y), .line(let x, let y): return [(x, y)]
            case .curve(let x1, let y1, let x2, let y2, let x, let y): return [(x1, y1), (x2, y2), (x, y)]
            case .close: return []
            }
        }
    }

    func testAChoiceIsTakenApartAndUnknownOnesShowTheInitial() {
        let star = ProfilePicture.parse("star:blue")
        XCTAssertEqual(star?.name, "star")
        XCTAssertEqual(star?.colour, AvatarLook.colours[5])
        XCTAssertEqual(star?.value, "star:blue")
        // The web's table: purple and pink skip one of the shared colours.
        XCTAssertEqual(ProfilePicture.parse("moon:purple")?.colour, AvatarLook.colours[7])
        XCTAssertEqual(ProfilePicture.parse("moon:pink")?.colour, AvatarLook.colours[8])
        XCTAssertNil(ProfilePicture.parse(""))
        XCTAssertNil(ProfilePicture.parse(nil))
        XCTAssertNil(ProfilePicture.parse("star"))
        XCTAssertNil(ProfilePicture.parse("unicorn:blue"))
        XCTAssertNil(ProfilePicture.parse("star:mauve"))
        XCTAssertNil(ProfilePicture.parse("star:blue:extra"))
        XCTAssertEqual(ProfilePicture.label("gamepad"), "Gamepad")
    }

    func testEveryPictureTheServerOffersCanBeDrawnOnTheGrid() {
        XCTAssertEqual(Set(ProfilePicture.names), Set(ProfilePicture.shapes.keys))
        for name in ProfilePicture.names {
            let steps = ProfilePicture.steps(for: name)
            XCTAssertFalse(steps.isEmpty, name)
            guard case .move = steps[0] else { return XCTFail("\(name) doesn't start with a move") }
            XCTAssertEqual(steps.last, .close, name)
            for (x, y) in points(steps) {
                XCTAssertTrue(x.isFinite && y.isFinite, name)
                // A little outside for a curve's handles, never far.
                XCTAssertTrue((-1.5...25.5).contains(x) && (-1.5...25.5).contains(y), "\(name) leaves the grid at \(x), \(y)")
            }
        }
        for colour in ProfilePicture.colourNames { XCTAssertNotNil(ProfilePicture.colour(named: colour)) }
        let lists = ParentalLists(avatars: ["star", "unicorn"], avatarColours: ["blue", "mauve"])
        XCTAssertEqual(lists.pictureNames, ["star"])
        XCTAssertEqual(lists.pictureColours, ["blue"])
        XCTAssertEqual(ParentalLists().pictureNames, ProfilePicture.names)
    }

    func testPathDataIsReadAsIconFilesWriteIt() {
        // Numbers run together: "6.6.8-4.9" is 6.6, 0.8 and -4.9.
        XCTAssertEqual(PathData.parse("M1 2l6.6.8-4.9 4.6z"),
                       [.move(x: 1, y: 2), .line(x: 7.6, y: 2.8), .line(x: 7.6 - 4.9, y: 2.8 + 4.6), .close])
        XCTAssertEqual(PathData.parse("M11 1h2v4h-2z"), [.move(x: 11, y: 1), .line(x: 13, y: 1), .line(x: 13, y: 5), .line(x: 11, y: 5), .close])
        XCTAssertEqual(PathData.parse("M0 0H5V5L1 1"), [.move(x: 0, y: 0), .line(x: 5, y: 0), .line(x: 5, y: 5), .line(x: 1, y: 1)])
        // After a close, a relative move starts from where the outline began.
        XCTAssertEqual(PathData.parse("M2 2h1zm1 1h1"), [.move(x: 2, y: 2), .line(x: 3, y: 2), .close, .move(x: 3, y: 3), .line(x: 4, y: 3)])
        XCTAssertEqual(PathData.parse("M0 0c1 0 2 1 2 2s1 2 2 2"),
                       [.move(x: 0, y: 0), .curve(x1: 1, y1: 0, x2: 2, y2: 1, x: 2, y: 2), .curve(x1: 2, y1: 3, x2: 3, y2: 4, x: 4, y: 4)])
        // Something that can't be read stops the shape; it never draws a guess.
        XCTAssertEqual(PathData.parse("M0 0L1"), [.move(x: 0, y: 0)])
        XCTAssertEqual(PathData.parse("5 5"), [])
        XCTAssertEqual(PathData.parse(""), [])
    }

    func testArcsBecomeCurvesThatStayOnTheCircle() {
        // The sun's disc: two half turns around (12, 12) with radius 5, flags written against the next number.
        let steps = PathData.parse("M12 7a5 5 0 100 10 5 5 0 000-10z")
        XCTAssertEqual(steps.first, .move(x: 12, y: 7))
        XCTAssertEqual(steps.last, .close)
        var ends: [(Double, Double)] = []
        for step in steps { if case .curve(_, _, _, _, let x, let y) = step { ends.append((x, y)) } }
        XCTAssertEqual(ends.count, 4)
        for (x, y) in ends { XCTAssertEqual(((x - 12) * (x - 12) + (y - 12) * (y - 12)).squareRoot(), 5, accuracy: 0.001) }
        XCTAssertEqual(ends[1].0, 12, accuracy: 0.001)
        XCTAssertEqual(ends[1].1, 17, accuracy: 0.001)
        XCTAssertEqual(ends[3].0, 12, accuracy: 0.001)
        XCTAssertEqual(ends[3].1, 7, accuracy: 0.001)
        // Sweep flag 0 from the top goes round by the left: the first quarter ends at (7, 12).
        XCTAssertEqual(ends[0].0, 7, accuracy: 0.001)
        XCTAssertEqual(ends[0].1, 12, accuracy: 0.001)
        // A radius too small to reach is grown, and one of nothing is a line.
        XCTAssertEqual(PathData.arc(fromX: 0, fromY: 0, rx: 0, ry: 5, turn: 0, large: false, sweep: true, toX: 4, toY: 0), [.line(x: 4, y: 0)])
        let grown = PathData.arc(fromX: 0, fromY: 0, rx: 1, ry: 1, turn: 0, large: false, sweep: true, toX: 4, toY: 0)
        guard case .curve(_, _, _, _, let x, let y)? = grown.last else { return XCTFail("no curve") }
        XCTAssertEqual(x, 4, accuracy: 0.0001)
        XCTAssertEqual(y, 0, accuracy: 0.0001)
        XCTAssertEqual(PathData.arc(fromX: 1, fromY: 1, rx: 2, ry: 2, turn: 0, large: true, sweep: true, toX: 1, toY: 1), [])
    }
}
