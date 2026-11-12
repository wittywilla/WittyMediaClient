// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest

#if os(tvOS)
/// The Apple TV's remote, worked by hand from the Mac, for trying the live TV guide in a simulator
/// against a test server: the simulator takes no remote keys from `simctl`, and a check run alone
/// can't look at what it sees. Not part of any script's checks; it skips itself unless asked.
///
/// TEST_RUNNER_DRIVE_DIR names a folder on the Mac. Each time a file `cmd` appears there, the lines in
/// it are done in order and what they say goes in `out`, then `done` is written. Lines:
///   launch [arguments…]   start the app afresh        activate / terminate
///   k <key> [times]       up down left right select menu playpause home
///   hold <key> <seconds>  a long press               type <text>    wait <seconds>
///   shot <name>           a picture, <name>.png       focus          what has the focus
///   tree                  everything on the screen, in tree.txt       quit
@MainActor
final class LiveTvDriver: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.wittywilla.wittymediaclient")

    func testDrive() throws {
        guard let dir = ProcessInfo.processInfo.environment["DRIVE_DIR"], !dir.isEmpty else {
            throw XCTSkip("DRIVE_DIR isn't set")
        }
        let folder = URL(fileURLWithPath: dir)
        let cmd = folder.appendingPathComponent("cmd")
        let files = FileManager.default
        while true {
            guard let text = try? String(contentsOf: cmd, encoding: .utf8) else {
                Thread.sleep(forTimeInterval: 0.2)
                continue
            }
            try? files.removeItem(at: cmd)
            var out = ""
            var quit = false
            for line in text.split(separator: "\n") {
                let words = line.split(separator: " ").map(String.init)
                guard let verb = words.first else { continue }
                out += "> \(line)\n"
                out += run(verb, Array(words.dropFirst()), line: String(line), folder: folder, quit: &quit)
            }
            try? out.write(to: folder.appendingPathComponent("out"), atomically: true, encoding: .utf8)
            try? "".write(to: folder.appendingPathComponent("done"), atomically: true, encoding: .utf8)
            if quit { return }
        }
    }

    private func run(_ verb: String, _ args: [String], line: String, folder: URL, quit: inout Bool) -> String {
        let remote = XCUIRemote.shared
        switch verb {
        case "launch":
            app.launchArguments = args
            app.launch()
        case "activate": app.activate()
        case "terminate": app.terminate()
        case "k", "hold":
            guard let name = args.first, let button = button(name) else { return "unknown key\n" }
            if verb == "hold" {
                remote.press(button, forDuration: Double(args.dropFirst().first ?? "1") ?? 1)
            } else {
                for _ in 0..<(Int(args.dropFirst().first ?? "1") ?? 1) {
                    remote.press(button)
                    Thread.sleep(forTimeInterval: 0.15)
                }
            }
        case "type": app.typeText(String(line.dropFirst(5)))
        case "wait": Thread.sleep(forTimeInterval: Double(args.first ?? "1") ?? 1)
        case "shot":
            let png = XCUIScreen.main.screenshot().pngRepresentation
            try? png.write(to: folder.appendingPathComponent((args.first ?? "shot") + ".png"))
        case "focus":
            let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
            return focused.exists ? "\(focused.elementType.rawValue) '\(focused.identifier)' '\(focused.label)'\n" : "nothing has the focus\n"
        case "tree":
            try? app.debugDescription.write(to: folder.appendingPathComponent("tree.txt"), atomically: true, encoding: .utf8)
        case "quit": quit = true
        default: return "unknown\n"
        }
        return ""
    }

    private func button(_ name: String) -> XCUIRemote.Button? {
        switch name {
        case "up": .up
        case "down": .down
        case "left": .left
        case "right": .right
        case "select": .select
        case "menu": .menu
        case "playpause": .playPause
        case "home": .home
        default: nil
        }
    }
}
#endif
