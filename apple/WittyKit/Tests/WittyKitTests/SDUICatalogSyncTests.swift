// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation
import XCTest
@testable import WittyKit

/// The catalogue the apps draw with before the server answers is the server's own, bundled: it can't drift
/// into a table kept by hand. apple/scripts/sync-sdui-catalog.sh writes it.
final class SDUICatalogSyncTests: XCTestCase {
    private static func bundled() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "sdui-catalog", withExtension: "json"), "no bundled catalogue")
        return try Data(contentsOf: url)
    }

    func testTheBundledCatalogueIsWholeAndOfThisAppsRevision() throws {
        let catalog = SDUICatalog.builtIn
        XCTAssertEqual(catalog.revision, SDUI.catalog, "the bundled catalogue is of another revision than this app speaks: bump SDUI.catalog with it")
        // Every row the server wrote is one this app reads: nothing is quietly left out.
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Self.bundled()) as? [String: Any])
        XCTAssertEqual(catalog.cardStyles.count, (raw["cardStyles"] as? [Any])?.count)
        XCTAssertEqual(catalog.routes.count, (raw["routes"] as? [Any])?.count)
        XCTAssertEqual(catalog.commands.count, (raw["commands"] as? [Any])?.count)
        XCTAssertFalse(catalog.cardStyles.isEmpty || catalog.routes.isEmpty || catalog.commands.isEmpty)
        XCTAssertFalse(catalog.componentTokens.isEmpty, "the components' theme tokens")
        for op in ["watchLater.add", "watchLater.remove", "watched.set", "watched.clear", "refresh", "selectTab"] {
            XCTAssertNotNil(catalog.command(op), op)
        }
        XCTAssertEqual(catalog.command("watchLater.add")?.body, #"{"items":["{item}"]}"#)
    }

    #if os(macOS) || os(Linux)
    /// The server checkout beside this one, as the conformance tests find theirs, or WITTYMEDIASERVER_SRC.
    private static func serverCheckout() -> URL? {
        let files = FileManager.default
        func usable(_ url: URL) -> Bool { files.fileExists(atPath: url.appendingPathComponent("scripts/sdui-catalog/main.go").path) }
        if let named = ProcessInfo.processInfo.environment["WITTYMEDIASERVER_SRC"], !named.isEmpty {
            let url = URL(fileURLWithPath: named)
            return usable(url) ? url : nil
        }
        var folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<9 {
            folder = folder.deletingLastPathComponent()
            let beside = folder.appendingPathComponent("WittyMediaServer")
            if usable(beside) { return beside }
        }
        return nil
    }

    /// The bundled copy is what the server checkout beside this one prints now. It fails until
    /// apple/scripts/sync-sdui-catalog.sh is run after the server's catalogue changes.
    func testTheBundledCatalogueIsTheServers() throws {
        guard let server = Self.serverCheckout() else {
            throw XCTSkip("No WittyMediaServer checkout beside this one (or WITTYMEDIASERVER_SRC) to compare the bundled catalogue with.")
        }
        let go = Process()
        go.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        go.arguments = ["go", "run", "./scripts/sdui-catalog"]
        go.currentDirectoryURL = server
        let out = Pipe()
        go.standardOutput = out
        go.standardError = Pipe()
        do { try go.run() } catch { throw XCTSkip("Go isn't here to print the server's catalogue: \(error)") }
        let printed = out.fileHandleForReading.readDataToEndOfFile()
        go.waitUntilExit()
        guard go.terminationStatus == 0 else { throw XCTSkip("The server's catalogue couldn't be printed (go run exited \(go.terminationStatus)).") }
        let theirs = try XCTUnwrap(JSONSerialization.jsonObject(with: printed) as? NSDictionary)
        let ours = try XCTUnwrap(JSONSerialization.jsonObject(with: Self.bundled()) as? NSDictionary)
        XCTAssertEqual(ours["revision"] as? Int, theirs["revision"] as? Int, "revision: run apple/scripts/sync-sdui-catalog.sh")
        XCTAssertTrue(ours.isEqual(theirs), "the bundled catalogue differs from the server's at \(server.path): run apple/scripts/sync-sdui-catalog.sh")
    }
    #endif
}
