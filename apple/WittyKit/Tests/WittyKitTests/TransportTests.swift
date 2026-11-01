import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import WittyKit

/// What the client does over real connections, against a stand-in server on this machine.
final class TransportTests: XCTestCase {
    private let goodCaps = #"{"server":"WittyMediaServer","version":"0.6.0-alpha","apiVersion":1,"apiRevision":5,"apiVersions":[1],"setupRequired":false,"features":["pairing"]}"#
    private let goodStatus = #"{"name":"WittyMediaServer","version":"0.6.0-alpha","setupRequired":false,"theme":"dark"}"#

    private func server(_ respond: @escaping @Sendable (StandInServer.Request) -> Data) throws -> StandInServer {
        let made = try StandInServer(respond: respond)
        addTeardownBlock { made.stop() }
        return made
    }

    private func serving(caps: String) throws -> StandInServer {
        let status = goodStatus
        return try server { request in
            request.path.hasSuffix("/capabilities") ? StandInServer.answer(body: caps) : StandInServer.answer(body: status)
        }
    }

    func testARealServerIsFound() async throws {
        let stand = try serving(caps: goodCaps)
        guard case .found(let status) = await WittyClient.probe(stand.address, appVersion: "0.2.0") else { return XCTFail("not found") }
        XCTAssertEqual(status.theme, "dark")
        XCTAssertFalse(stand.requests.contains(where: \.hasToken), "no token goes to an address being tried")
    }

    func testAServerBelowTheRevisionIsToldToUpdate() async throws {
        let old = goodCaps.replacingOccurrences(of: #""apiRevision":5"#, with: #""apiRevision":4"#)
        let stand = try serving(caps: old)
        let result = await WittyClient.probe(stand.address, appVersion: "0.2.0")
        XCTAssertEqual(result, .failed("server-old"))
    }

    func testAnAppBelowTheServersMinimumIsToldToUpdate() async throws {
        let caps = goodCaps.replacingOccurrences(of: #""features""#, with: #""minClientVersions":{"apple":"0.3.0","android":"0.1.0"},"features""#)
        let stand = try serving(caps: caps)
        let old = await WittyClient.probe(stand.address, appVersion: "0.2.0")
        XCTAssertEqual(old, .failed("app-old"))
        guard case .found = await WittyClient.probe(stand.address, appVersion: "0.3.0-alpha") else { return XCTFail("the same version works") }
    }

    func testAnOversizedAnswerFromAnUnprovedAddressIsDropped() async throws {
        let huge = String(repeating: "x", count: 2 * 1024 * 1024)
        let announced = try server { _ in StandInServer.answer(body: huge) }
        let first = await WittyClient.probe(announced.address, appVersion: "0.2.0")
        XCTAssertEqual(first, .failed("not-server"))
        let unannounced = try server { _ in StandInServer.answer(body: huge, announceLength: false) }
        let second = await WittyClient.probe(unannounced.address, appVersion: "0.2.0")
        XCTAssertEqual(second, .failed("not-server"))
    }

    func testAnOversizedPictureIsDropped() async throws {
        let huge = String(repeating: "x", count: AnswerLimit.picture + 1024)
        let stand = try server { _ in StandInServer.answer(body: huge, announceLength: false) }
        let client = WittyClient(base: stand.address, token: "secret-token-value")
        do {
            _ = try await client.imageData(try XCTUnwrap(URL(string: stand.address + "/poster")))
            XCTFail("read the whole of it")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 0)
        }
    }

    func testAPictureAddressOnAnotherServerGetsNoSignIn() async throws {
        let other = try server { _ in StandInServer.answer(body: "picture") }
        let client = WittyClient(base: "http://127.0.0.1:1", token: "secret-token-value")
        do {
            _ = try await client.imageData(try XCTUnwrap(URL(string: other.address + "/poster")))
            XCTFail("fetched it")
        } catch {
            XCTAssertTrue(other.requests.isEmpty, "nothing was sent there at all")
        }
    }

    func testARedirectToAnotherServerIsNotFollowed() async throws {
        let elsewhere = try server { _ in StandInServer.answer(body: "{}") }
        let target = elsewhere.address
        let stand = try server { _ in StandInServer.answer(status: "302 Found", headers: ["Location: \(target)/api/v1/home"]) }
        let client = WittyClient(base: stand.address, token: "secret-token-value")
        do {
            _ = try await client.home()
            XCTFail("followed it")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 302)
        }
        XCTAssertTrue(elsewhere.requests.isEmpty, "the sign-in never left for another port")
    }

    func testARedirectWithinTheServerIsFollowed() async throws {
        let stand = try server { request in
            if request.path == "/api/v1/home" { return StandInServer.answer(status: "302 Found", headers: ["Location: /api/v1/home2"]) }
            return StandInServer.answer(body: #"{"hubs":[],"featured":[],"libraries":[]}"#)
        }
        let client = WittyClient(base: stand.address, token: "secret-token-value")
        let home = try await client.home()
        XCTAssertEqual(home.hubs, [])
        XCTAssertEqual(stand.requests.count, 2)
    }

    func testHttpMovingToHttpsOnTheSameHostIsReportedAndNeverFollowed() async throws {
        let stand = try server { _ in StandInServer.answer(status: "301 Moved Permanently", headers: ["Location: https://127.0.0.1:8443/api/v1/capabilities"]) }
        let result = await WittyClient.probe(stand.address, appVersion: "0.2.0")
        XCTAssertEqual(result, .moved("https://127.0.0.1:8443"))
        XCTAssertEqual(stand.requests.count, 1)
    }

    func testHttpMovingToAnotherHostIsNotAServer() async throws {
        let stand = try server { _ in StandInServer.answer(status: "301 Moved Permanently", headers: ["Location: https://elsewhere.example/"]) }
        let result = await WittyClient.probe(stand.address, appVersion: "0.2.0")
        XCTAssertEqual(result, .failed("not-server"))
    }

    func testNothingListeningIsUnreachable() async throws {
        let stand = try server { _ in Data() }
        stand.stop()
        let result = await WittyClient.probe(stand.address, appVersion: "0.2.0")
        XCTAssertEqual(result, .failed("unreachable"))
    }

    func testAServersErrorWordsAreCleanedBeforeShowing() async throws {
        let body = #"{"error":"Bad\u0007 ‮code"}"#
        let stand = try server { _ in StandInServer.answer(status: "400 Bad Request", body: body) }
        do {
            _ = try await WittyClient(base: stand.address, token: "").home()
            XCTFail("no error")
        } catch let error as APIError {
            XCTAssertEqual(error.message, "Bad code")
        }
    }

    func testLeavingAScreenCountsAsCancelledNotAProblem() async throws {
        let stand = try server { _ in
            Thread.sleep(forTimeInterval: 2)
            return StandInServer.answer(body: "{}")
        }
        let client = WittyClient(base: stand.address)
        let task = Task { try await client.home() }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("it finished")
        } catch {
            XCTAssertEqual(Problem.of(error), .cancelled)
        }
    }

    func testAFailedProbeOfAnAddressThatIsNotHttpAtAll() async throws {
        let stand = try server { _ in Data("hello".utf8) }
        let result = await WittyClient.probe(stand.address, appVersion: "0.2.0")
        guard case .failed = result else { return XCTFail("\(result)") }
    }
}
