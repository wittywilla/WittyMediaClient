// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

final class VoiceFxTests: XCTestCase {
    func testOffIsAsRecorded() {
        XCTAssertTrue(VoiceFx.off.isOff)
        XCTAssertEqual(VoiceFx.off.presetId, "off")
        XCTAssertEqual(VoiceFx.off.presetName, "As recorded")
        XCTAssertEqual(VoiceFx.controls.count, 15)
        XCTAssertEqual(Set(VoiceFx.controls.map(\.id)), Set(VoiceFx.offValues.keys))
    }

    func testNinePresetsEachDifferent() {
        XCTAssertEqual(VoiceFx.voicePresets.count, 9)
        let shapes = VoiceFx.presets.map { VoiceFx.preset($0.id) }
        XCTAssertEqual(Set(shapes.map { $0.values.description }).count, VoiceFx.presets.count, "the panel can say which is chosen")
        for range in VoiceFx.ranges {
            for level in VoiceFx.levels {
                let p = try? XCTUnwrap(VoiceFx.voicePreset(range: range.id, level: level.id))
                XCTAssertEqual(VoiceFx.preset(p?.id ?? "").presetId, p?.id)
            }
        }
        XCTAssertEqual(VoiceFx.preset("mid-medium")["compress"], 50)
        XCTAssertEqual(VoiceFx.preset("mid-medium")["echoTime"], 320, "what a preset leaves out is off")
    }

    func testMovingAControlLeavesThePreset() {
        let moved = VoiceFx.preset("female-high").with("echo", 40)
        XCTAssertEqual(moved.presetId, "")
        XCTAssertEqual(moved.presetName, "Your own settings")
    }

    func testValuesStayInTheirRanges() {
        let fx = VoiceFx(["lowCut": 5000, "pan": -900, "room": .nan, "reverb": .infinity, "nonsense": 3])
        XCTAssertEqual(fx["lowCut"], 400)
        XCTAssertEqual(fx["pan"], -100)
        XCTAssertEqual(fx["room"], 1.6, "broken values go back to off")
        XCTAssertEqual(fx["reverb"], 0)
        XCTAssertNil(fx.values["nonsense"])
        XCTAssertEqual(VoiceFx.off.stepped("room", by: 1)["room"], 1.7, accuracy: 1e-9)
        XCTAssertEqual(VoiceFx.off.stepped("lowCut", by: -1)["lowCut"], 20)
    }

    func testWords() {
        let c = { (id: String) in VoiceFx.controls.first { $0.id == id }! }
        XCTAssertEqual(VoiceFx.words(c("pan"), 0), "Centre")
        XCTAssertEqual(VoiceFx.words(c("pan"), -20), "20% left")
        XCTAssertEqual(VoiceFx.words(c("pan"), 35), "35% right")
        XCTAssertEqual(VoiceFx.words(c("lowCut"), 20), "Off")
        XCTAssertEqual(VoiceFx.words(c("lowCut"), 180), "180 Hz")
        XCTAssertEqual(VoiceFx.words(c("bass"), 3), "+3 dB")
        XCTAssertEqual(VoiceFx.words(c("bass"), -2), "-2 dB")
        XCTAssertEqual(VoiceFx.words(c("room"), 1.4), "1.4 s")
        XCTAssertEqual(VoiceFx.words(c("echo"), 35), "35%")
        XCTAssertEqual(VoiceFx.words(c("echoTime"), 320), "320 ms")
    }

    func testNodesAsTheWebsiteWorksThemOut() {
        let off = VoiceFx.off.nodes
        XCTAssertEqual(off.thresholdDb, 0)
        XCTAssertEqual(off.ratio, 1)
        XCTAssertEqual(off.pocketDb, 0)
        let n = VoiceFx(["compress": 50, "echo": 50, "pocket": 4, "pan": -50, "double": 100]).nodes
        XCTAssertEqual(n.thresholdDb, -20, accuracy: 1e-9)
        XCTAssertEqual(n.ratio, 4.5, accuracy: 1e-9)
        XCTAssertEqual(n.makeUpDb, 3, accuracy: 1e-9)
        XCTAssertEqual(n.echo, 0.4, accuracy: 1e-9)
        XCTAssertEqual(n.pocketDb, -4)
        XCTAssertEqual(n.pan, -0.5)
        XCTAssertEqual(n.double, 0.7, accuracy: 1e-9)
        XCTAssertEqual(VoiceFxNodes.wetDry(0), 0)
        XCTAssertEqual(VoiceFxNodes.wetDry(1), 50, accuracy: 1e-9)
        XCTAssertEqual(VoiceFxNodes.wetDry(.nan), 0)
        XCTAssertEqual(VoiceFxNodes.roomIndex(0.3), 0)
        XCTAssertEqual(VoiceFxNodes.roomIndex(1.6), 2)
        XCTAssertEqual(VoiceFxNodes.roomIndex(5), 4)
    }

    func testKeptForEachPersonOnEachServer() throws {
        let name = "voicefx-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let mine = VoiceFxStore(server: "http://tv.local:9797", profile: "7", defaults: defaults)
        let theirs = VoiceFxStore(server: "http://tv.local:9797", profile: "8", defaults: defaults)
        mine.save(VoiceFx.preset("low-low"))
        XCTAssertEqual(mine.load().presetId, "low-low")
        XCTAssertTrue(theirs.load().isOff)
        mine.save(.off)
        XCTAssertTrue(mine.load().isOff)
    }
}
