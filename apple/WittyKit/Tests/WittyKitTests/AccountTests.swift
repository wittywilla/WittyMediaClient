import XCTest
@testable import WittyKit

final class AccountTests: XCTestCase {
    func testDeviceKinds() {
        XCTAssertEqual(DeviceKind.of("iPhone"), .phone)
        XCTAssertEqual(DeviceKind.of("iPad"), .tablet)
        XCTAssertEqual(DeviceKind.of("Apple TV"), .tv)
        XCTAssertEqual(DeviceKind.of("Android TV"), .tv)
        XCTAssertEqual(DeviceKind.of("Living room TV"), .tv)
        XCTAssertEqual(DeviceKind.of("Pixel 8"), .phone)
        XCTAssertEqual(DeviceKind.of("Firefox on macOS"), .browser)
        XCTAssertEqual(DeviceKind.of("WittyMediaClient on Windows"), .computer)
        // "tv" inside a word isn't a TV.
        XCTAssertEqual(DeviceKind.of("Tvorba laptop"), .browser)
        XCTAssertEqual(DeviceKind.of(""), .browser)
    }

    func testSessionsDecodeTheirPlace() throws {
        let json = #"[{"id":"ab","userId":1,"device":"iPhone","lastSeen":5,"where":"home","current":true}]"#
        let devices = try JSONDecoder().decode([SignedInDevice].self, from: Data(json.utf8))
        XCTAssertEqual(devices.first?.place, "home")
        XCTAssertEqual(devices.first?.isThisDevice, true)
        XCTAssertEqual(devices.first?.kind, .phone)
    }

    func testUnnamedDevice() {
        XCTAssertEqual(SignedInDevice(id: "x", device: "  ").name, "Unknown device")
    }

    func testSecretInGroupsOfFour() {
        let setup = TwoFactorSetup(secret: "ABCDEFGHIJ", uri: "otpauth://totp/x")
        XCTAssertEqual(setup.groupedSecret, "ABCD EFGH IJ")
    }

    func testSavedServerKeepsItsLogo() throws {
        let old = #"{"url":"http://127.0.0.1:9797","name":"WittyMediaServer"}"#
        let saved = try JSONDecoder().decode(SavedServer.self, from: Data(old.utf8))
        XCTAssertEqual(saved.brandLogo, "")
        let named = saved.with(name: "Home cinema", brandLogo: "7")
        XCTAssertEqual(named.name, "Home cinema")
        XCTAssertEqual(named.brandLogo, "7")
        XCTAssertEqual(named.moved(to: "http://10.0.0.2:9797").brandLogo, "7")
        XCTAssertEqual(saved.with(name: "  ", brandLogo: "").name, "WittyMediaServer")
        let again = try JSONDecoder().decode(SavedServer.self, from: JSONEncoder().encode(named))
        XCTAssertEqual(again, named)
    }

    func testProfileChangeLeavesOutWhatIsNil() throws {
        let data = try JSONEncoder().encode(ProfileChange(displayName: "Mum", username: nil, showUsername: nil))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"displayName":"Mum"}"#)
    }
}
