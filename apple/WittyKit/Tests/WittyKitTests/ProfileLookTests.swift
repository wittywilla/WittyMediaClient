import XCTest
@testable import WittyKit

/// The examples in docs/APP-DESIGN.md, which the Android app checks too, worked out with the web's rule.
final class ProfileLookTests: XCTestCase {
    func testColoursMatchTheWeb() {
        XCTAssertEqual(AvatarLook.colour(for: "test"), "#bd2f85")
        XCTAssertEqual(AvatarLook.colour(for: "Ann"), "#0a6fb8")
        XCTAssertEqual(AvatarLook.colour(for: "Émile"), "#0e7c6f")
        // Outside the first plane the web adds the high surrogate, not the whole code point.
        XCTAssertEqual(AvatarLook.colour(for: "Mum 👩"), "#99690a")
        XCTAssertEqual(AvatarLook.colourIndex(for: ""), 0)
    }

    func testInitial() {
        XCTAssertEqual(AvatarLook.initial(of: "  ann"), "A")
        XCTAssertEqual(AvatarLook.initial(of: "émile"), "É")
        XCTAssertEqual(AvatarLook.initial(of: "   "), "?")
    }

    func testBothNamesOnlyWhenTheyDiffer() {
        let plain = Profile(id: 1, name: "ann")
        XCTAssertEqual(plain.shownName, "ann")
        XCTAssertFalse(plain.showsUsername)

        let named = Profile(id: 2, name: "ann", displayName: "Mum")
        XCTAssertEqual(named.shownName, "Mum")
        XCTAssertTrue(named.showsUsername)

        let same = Profile(id: 3, name: "Ann", displayName: "Ann")
        XCTAssertFalse(same.showsUsername)

        // Kept on purpose: the username is what to type, even when it only differs in capitals.
        let capitals = Profile(id: 5, name: "ziggy", displayName: "Ziggy")
        XCTAssertTrue(capitals.showsUsername)

        let blank = Profile(id: 4, name: "ann", displayName: "   ")
        XCTAssertEqual(blank.shownName, "ann")
        XCTAssertFalse(blank.showsUsername)
    }

    func testCornerFollowsTheChoice() {
        XCTAssertEqual(User(id: 1, name: "ann", displayName: "Mum").cornerName, "Mum")
        XCTAssertEqual(User(id: 1, name: "ann", displayName: "Mum", showUsername: true).cornerName, "ann")
    }

    func testProfilesDecodeTheProfileName() throws {
        let json = #"{"style":"profiles","profiles":[{"id":1,"name":"ann","displayName":"Mum","kind":"kids","hasPassword":false}]}"#
        let profiles = try JSONDecoder().decode(Profiles.self, from: Data(json.utf8))
        XCTAssertEqual(profiles.profiles?.first?.shownName, "Mum")
        XCTAssertEqual(profiles.profiles?.first?.isKids, true)
    }

    func testTwoFactorRefusalIsRecognised() async throws {
        let error = APIError(status: 401, message: "a code is needed", twoFactor: true)
        XCTAssertTrue(error.twoFactor)
        XCTAssertFalse(APIError(status: 401, message: "no").twoFactor)
    }
}
