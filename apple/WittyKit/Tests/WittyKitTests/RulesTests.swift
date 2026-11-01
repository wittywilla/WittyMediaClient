import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import WittyKit

/// The decisions the screens lean on, which can run here without any screen.
final class RulesTests: XCTestCase {
    // MARK: Versions

    func testVersionsCompareByNumber() {
        XCTAssertEqual(Version.compare("0.2.0", "0.2.0"), .orderedSame)
        XCTAssertEqual(Version.compare("0.2", "0.2.0"), .orderedSame)
        XCTAssertEqual(Version.compare("0.10.0", "0.9.0"), .orderedDescending, "by number, not by text")
        XCTAssertEqual(Version.compare("0.2.0-alpha", "0.2.0"), .orderedSame)
        XCTAssertEqual(Version.compare("v1.2.3", "1.2.4"), .orderedAscending)
        XCTAssertEqual(Version.compare("1.2.3+45", "1.2.3"), .orderedSame)
    }

    func testAVersionThatCannotBeReadLocksNobodyOut() {
        XCTAssertNil(Version.compare("", "0.1.0"))
        XCTAssertNil(Version.compare("soon", "0.1.0"))
        XCTAssertNil(Version.compare("1..2", "0.1.0"))
        XCTAssertNil(Version.compare("1.٣", "0.1.0"))
        XCTAssertFalse(Version.isOlder("", than: "9.0.0"))
        XCTAssertFalse(Version.isOlder("0.1.0", than: "nonsense"))
        XCTAssertTrue(Version.isOlder("0.1.0", than: "0.2.0"))
    }

    private func caps(_ json: String) throws -> Capabilities {
        try JSONDecoder().decode(Capabilities.self, from: Data(json.utf8))
    }

    private let ok = #""server":"WittyMediaServer","apiVersions":[1],"apiRevision":5"#

    func testWhatMakesAServerUnusable() throws {
        XCTAssertNil(WittyClient.judge(try caps("{\(ok)}"), appVersion: "0.2.0"))
        XCTAssertEqual(WittyClient.judge(try caps(#"{"server":"Other","apiVersions":[1],"apiRevision":5}"#), appVersion: "0.2.0"), "not-server")
        XCTAssertEqual(WittyClient.judge(try caps(#"{"server":"WittyMediaServer","apiVersions":[2],"apiRevision":5}"#), appVersion: "0.2.0"), "app-old")
        XCTAssertEqual(WittyClient.judge(try caps(#"{"server":"WittyMediaServer","apiVersions":[1],"apiRevision":4}"#), appVersion: "0.2.0"), "server-old")
        XCTAssertEqual(WittyClient.judge(try caps(#"{"server":"WittyMediaServer","apiVersions":[1]}"#), appVersion: "0.2.0"), "server-old", "no revision is from before they were counted")
        XCTAssertEqual(WittyClient.judge(try caps("{\(ok),\"setupRequired\":true}"), appVersion: "0.2.0"), "not-set-up")
    }

    func testTheLowestClientVersionOnlyCountsForThisPlatform() throws {
        XCTAssertEqual(WittyClient.judge(try caps("{\(ok),\"minClientVersions\":{\"apple\":\"0.3.0\"}}"), appVersion: "0.2.0"), "app-old")
        XCTAssertNil(WittyClient.judge(try caps("{\(ok),\"minClientVersions\":{\"apple\":\"0.2.0\"}}"), appVersion: "0.2.0"))
        XCTAssertNil(WittyClient.judge(try caps("{\(ok),\"minClientVersions\":{\"android\":\"9.0.0\",\"desktop\":\"9.0.0\"}}"), appVersion: "0.2.0"))
        XCTAssertNil(WittyClient.judge(try caps("{\(ok),\"minClientVersions\":{\"apple\":\"who knows\"}}"), appVersion: "0.2.0"), "unknown means fine")
        XCTAssertNil(WittyClient.judge(try caps("{\(ok),\"minClientVersions\":\"not a map\"}"), appVersion: "0.2.0"), "an unreadable field counts as absent")
    }

    func testFeaturesGoByName() throws {
        let capabilities = try caps("{\(ok),\"features\":[\"pairing\",\"something-new\"]}")
        XCTAssertTrue(capabilities.has("pairing"))
        XCTAssertFalse(capabilities.has("pair"))
        XCTAssertFalse(try caps("{\(ok)}").has("pairing"))
    }

    // MARK: Addresses

    func testAddressesInAnswersStayOnTheServer() {
        let base = "http://192.168.1.5:9797"
        XCTAssertEqual(Origin.join(base: base, path: "/api/hls/x/master.m3u8?st=abc")?.absoluteString, base + "/api/hls/x/master.m3u8?st=abc")
        XCTAssertNil(Origin.join(base: base, path: "@evil.example/x"), "after a host, that makes evil.example the host")
        XCTAssertNil(Origin.join(base: base, path: "//evil.example/x"))
        XCTAssertNil(Origin.join(base: base, path: "https://evil.example/x"))
        XCTAssertNil(Origin.join(base: base, path: ".evil.example/x"))
        XCTAssertNil(Origin.join(base: base, path: ""))
        XCTAssertNil(Origin.join(base: "", path: "/x"))
    }

    func testTheSameServerByOrigin() throws {
        func url(_ text: String) throws -> URL { try XCTUnwrap(URL(string: text)) }
        XCTAssertTrue(Origin.same(try url("http://Home.Local:80/a"), try url("http://home.local")))
        XCTAssertTrue(Origin.same(try url("https://h/a"), try url("https://h:443/b")))
        XCTAssertFalse(Origin.same(try url("https://h/a"), try url("http://h/a")))
        XCTAssertFalse(Origin.same(try url("http://h:1/a"), try url("http://h:2/a")))
        XCTAssertFalse(Origin.same(try url("http://user:pw@h/a"), try url("http://h/a")))
        XCTAssertFalse(Origin.same(try url("file:///a"), try url("file:///a")))
    }

    func testOnlyAnUpgradeOnTheSameHostIsWorthTrying() {
        XCTAssertEqual(Address.upgrade(from: "http://192.168.1.5:9797", location: "https://192.168.1.5:9443/api/v1/capabilities"), "https://192.168.1.5:9443")
        XCTAssertEqual(Address.upgrade(from: "http://mediabox.local", location: "https://MediaBox.local/"), "https://mediabox.local")
        XCTAssertNil(Address.upgrade(from: "http://192.168.1.5:9797", location: "https://elsewhere.example/"))
        XCTAssertNil(Address.upgrade(from: "http://192.168.1.5:9797", location: "http://192.168.1.5:80/"))
        XCTAssertNil(Address.upgrade(from: "https://192.168.1.5:9797", location: "https://192.168.1.5:80/"))
        XCTAssertNil(Address.upgrade(from: "http://192.168.1.5", location: "/somewhere"))
        XCTAssertNil(Address.upgrade(from: "http://192.168.1.5", location: "https://user:pw@192.168.1.5/"))
        XCTAssertNil(Address.upgrade(from: "http://192.168.1.5", location: nil))
    }

    func testANumberIsNotALocalName() {
        XCTAssertFalse(Address.isPrivateHost("134744072"), "this is 8.8.8.8")
        XCTAssertFalse(Address.isPrivateHost("0x08080808"))
        XCTAssertEqual(Address.normalize("134744072"), .bad("public-http"))
        XCTAssertTrue(Address.isPrivateHost("mediabox"))
    }

    func testNamesThatResolveToTheInternetDoNotCountAsLocal() async {
        XCTAssertTrue(Address.staysLocal(resolved: ["127.0.0.1", "::1", "192.168.1.5", "fe80::1%en0", "fd00::2", "::ffff:10.0.0.3"]))
        XCTAssertFalse(Address.staysLocal(resolved: ["192.168.1.5", "8.8.8.8"]), "one public answer is enough")
        XCTAssertFalse(Address.staysLocal(resolved: ["2001:4860:4860::8888"]))
        XCTAssertFalse(Address.staysLocal(resolved: ["::ffff:8.8.8.8"]))
        let localhost = await Address.plainHTTPStaysLocal("http://localhost:9797")
        XCTAssertTrue(localhost)
        let https = await Address.plainHTTPStaysLocal("https://media.example.com")
        XCTAssertTrue(https, "https needs no looking up")
        let written = await Address.plainHTTPStaysLocal("http://192.168.1.5:9797")
        XCTAssertTrue(written)
    }

    func testOnlyWebLinksLeaveTheApp() throws {
        func link(_ text: String) throws -> Bool { WebPlayer.isWebLink(try XCTUnwrap(URL(string: text))) }
        XCTAssertTrue(try link("https://example.com/x"))
        XCTAssertTrue(try link("http://192.168.1.9/x"))
        XCTAssertFalse(try link("http://example.com/x"), "plain http to the internet stays refused here too")
        XCTAssertFalse(try link("https://user:pw@example.com/x"))
        XCTAssertFalse(try link("file:///etc/passwd"))
        XCTAssertFalse(try link("javascript:alert(1)"))
        XCTAssertFalse(try link("wittymedia://item/1"))
    }

    func testAnAnnouncementCanNotPointAtThisDevice() {
        let id = "0123456789abcdef0123456789abcdef"
        XCTAssertNil(Discovery.makeServer(id: id, name: "x", host: "127.0.0.1", port: 9797, tls: false))
        XCTAssertNil(Discovery.makeServer(id: id + "\n", name: "x", host: "192.168.1.2", port: 9797, tls: false), "a line ending is not part of an ID")
        XCTAssertNotNil(Discovery.makeServer(id: id, name: "x", host: "192.168.1.2", port: 9797, tls: false))
    }

    // MARK: Pairing

    private func pair(_ fields: String) throws -> PairStart {
        try JSONDecoder().decode(PairStart.self, from: Data(#"{"code":"BCDF-GHJK","deviceSecret":"s"\#(fields)}"#.utf8))
    }

    func testTheApproveAddressPrefersTheOneWithTheCode() throws {
        let base = "http://192.168.1.5:9797"
        XCTAssertEqual(try pair(#","approvePath":"/pair","approveUrl":"/pair?code=BCDF-GHJK""#).approveAddress(base: base), base + "/pair?code=BCDF-GHJK")
        XCTAssertEqual(try pair(#","approvePath":"/pair2""#).approveAddress(base: base), base + "/pair2")
        XCTAssertEqual(try pair("").approveAddress(base: base), base + "/pair")
    }

    func testAnApproveAddressElsewhereIsIgnored() throws {
        let base = "http://192.168.1.5:9797"
        XCTAssertEqual(try pair(#","approveUrl":"//evil.example/pair","approvePath":"@evil.example/""#).approveAddress(base: base), base + "/pair")
    }

    // MARK: The key that was shown

    private func proof(_ state: IdentityState, key: String) -> ServerProof { ServerProof(state: state, publicKey: key) }

    func testOnlyTheKeyThatWasShownGetsSentAnything() {
        XCTAssertEqual(Identity.beforeSending(shownKey: "A", proof: proof(.same, key: "A")), .send)
        XCTAssertEqual(Identity.beforeSending(shownKey: "A", proof: proof(.same, key: "B")), .changed, "a key remembered from elsewhere is still another key")
        XCTAssertEqual(Identity.beforeSending(shownKey: "A", proof: proof(.different, key: "B")), .changed)
        XCTAssertEqual(Identity.beforeSending(shownKey: "A", proof: proof(.new, key: "B")), .changed)
        XCTAssertEqual(Identity.beforeSending(shownKey: "A", proof: proof(.older, key: "")), .refuse, "a key that goes away is what a look-alike would do")
        XCTAssertEqual(Identity.beforeSending(shownKey: "A", proof: proof(.bad, key: "")), .refuse)
        XCTAssertEqual(Identity.beforeSending(shownKey: "A", proof: proof(.unreachable, key: "")), .unreachable)
        XCTAssertEqual(Identity.beforeSending(shownKey: "", proof: proof(.older, key: "")), .send, "a server older than this check")
        XCTAssertEqual(Identity.beforeSending(shownKey: "", proof: proof(.new, key: "B")), .send)
    }

    // MARK: Problems

    func testProblemsInPlainTerms() {
        XCTAssertEqual(Problem.of(CancellationError()), .cancelled)
        XCTAssertEqual(Problem.of(URLError(.cancelled)), .cancelled)
        XCTAssertEqual(Problem.of(URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(Problem.of(URLError(.timedOut)), .lost)
        XCTAssertEqual(Problem.of(URLError(.cannotConnectToHost)), .lost)
        XCTAssertEqual(Problem.of(URLError(.serverCertificateUntrusted)), .certificate)
        XCTAssertEqual(Problem.of(APIError(status: 401, message: "no")), .expiredSignIn)
        XCTAssertEqual(Problem.of(APIError(status: 500, message: "Busy.")), .server("Busy."))
        struct Other: Error {}
        XCTAssertEqual(Problem.of(Other()), .unreadable)
    }

    func testRepeatsAreDropped() {
        struct Thing: Identifiable, Equatable { let id: Int; let name: String }
        let list = [Thing(id: 1, name: "a"), Thing(id: 2, name: "b"), Thing(id: 1, name: "c")]
        XCTAssertEqual(uniqued(list).map(\.name), ["a", "b"])
    }

    // MARK: Search

    func testSearchWordsCanNotAddParameters() {
        XCTAssertEqual(WittyClient.searchQuery("a&library=9"), "a%26library%3D9")
        XCTAssertEqual(WittyClient.searchQuery("  two words "), "two%20words")
        XCTAssertNil(WittyClient.searchQuery(" a "), "one letter isn't worth asking about")
        XCTAssertEqual(WittyClient.searchQuery(String(repeating: "x", count: 500))?.count, 200)
    }

    func testSearchAsksForShowsAndItems() async throws {
        let stand = try StandInServer { request in
            if request.path.hasPrefix("/api/v1/shows") { return StandInServer.answer(body: #"{"shows":[{"id":3,"title":"A Sample Show"}],"total":1}"#) }
            return StandInServer.answer(body: #"{"items":[{"id":1,"title":"A Sample Film","kind":"video"},{"id":1,"title":"A Sample Film","kind":"video"}],"total":2}"#)
        }
        addTeardownBlock { stand.stop() }
        let results = try await WittyClient(base: stand.address, token: "t").search("sample")
        XCTAssertEqual(results.items.count, 1, "a repeat is dropped")
        XCTAssertEqual(results.shows.first?.title, "A Sample Show")
        XCTAssertEqual(Set(stand.requests.map(\.path)), ["/api/v1/items?search=sample&noEpisodes=1&limit=40", "/api/v1/shows?search=sample&limit=40"])
    }

    // MARK: Playing

    func testTheClockOnlyBelievesAStreamThatIsReady() {
        var clock = PlaybackClock()
        XCTAssertFalse(clock.tick(playerSeconds: 100, offset: 0, playing: true), "nothing is ready yet")
        XCTAssertEqual(clock.filmSeconds, 0)
        XCTAssertNil(clock.saveable)
        clock.ready()
        XCTAssertTrue(clock.tick(playerSeconds: 100, offset: 600, playing: true))
        XCTAssertEqual(clock.filmSeconds, 700)
        clock.switching()
        XCTAssertFalse(clock.tick(playerSeconds: 3, offset: 900, playing: true), "the old player time with a new offset would be nonsense")
        XCTAssertEqual(clock.filmSeconds, 700, "leaving now saves the last good place")
        XCTAssertEqual(clock.saveable, 700)
    }

    func testProgressIsSavedEveryTenSecondsAndNotInTheFirstFive() {
        var clock = PlaybackClock()
        clock.ready()
        XCTAssertFalse(clock.tick(playerSeconds: 4, offset: 0, playing: true))
        XCTAssertNil(clock.saveable)
        XCTAssertTrue(clock.tick(playerSeconds: 5, offset: 0, playing: true))
        XCTAssertFalse(clock.tick(playerSeconds: 14, offset: 0, playing: true))
        XCTAssertTrue(clock.tick(playerSeconds: 15, offset: 0, playing: true))
        XCTAssertFalse(clock.tick(playerSeconds: 40, offset: 0, playing: false), "paused saves nothing by itself")
        XCTAssertTrue(clock.tick(playerSeconds: 40, offset: 0, playing: true))
        XCTAssertFalse(clock.tick(playerSeconds: .nan, offset: 0, playing: true))
        XCTAssertEqual(clock.filmSeconds, 40)
    }

    func testWatchNextComesInTheLastThirtySeconds() {
        var clock = PlaybackClock()
        XCTAssertFalse(clock.nearEnd(duration: 100))
        clock.ready()
        clock.tick(playerSeconds: 69, offset: 0, playing: true)
        XCTAssertFalse(clock.nearEnd(duration: 100))
        clock.tick(playerSeconds: 71, offset: 0, playing: true)
        XCTAssertTrue(clock.nearEnd(duration: 100))
        XCTAssertFalse(clock.nearEnd(duration: nil))
    }

    func testAFailingStreamGivesUpAndAGoodRunStartsAgain() {
        var budget = RetryBudget()
        XCTAssertEqual(budget.next(), 1)
        XCTAssertEqual(budget.next(), 4)
        XCTAssertEqual(budget.next(), 6)
        XCTAssertNil(budget.next(), "it stops")
        budget.played(seconds: 5)
        XCTAssertNil(budget.next(), "a moment of playing isn't enough: that's how it would loop for ever")
        budget.played(seconds: 30)
        XCTAssertEqual(budget.next(), 1)
    }

    private func stream(seek: String, offset: Double) throws -> Playback {
        let json = #"{"url":"/x","seek":"\#(seek)","timeOffsetSec":\#(offset)}"#
        return try JSONDecoder().decode(Playback.self, from: Data(json.utf8))
    }

    func testSeekingAGrowingStream() throws {
        let growing = try stream(seek: "restart", offset: 600)
        XCTAssertEqual(growing.seekPlan(toFilm: 650, seekableEnd: 100), .inPlayer(50))
        XCTAssertEqual(growing.seekPlan(toFilm: 800, seekableEnd: 100), .reopen(atFilm: 800), "past what exists so far")
        XCTAssertEqual(growing.seekPlan(toFilm: 500, seekableEnd: 100), .reopen(atFilm: 500), "before where this stream starts")
        XCTAssertEqual(growing.seekPlan(toFilm: 650, seekableEnd: nil), .reopen(atFilm: 650), "not ready to say")
        let whole = try stream(seek: "native", offset: 0)
        XCTAssertEqual(whole.seekPlan(toFilm: 9000, seekableEnd: 10), .inPlayer(9000))
        XCTAssertEqual(whole.seekPlan(toFilm: -5, seekableEnd: 10), .inPlayer(0))
    }

    private func track(_ index: Int, _ language: String?) -> Track {
        Track(index: index, language: language, languageName: nil, title: nil, codec: nil, channels: nil, delivery: nil, url: nil)
    }

    func testChoosingTheRightLanguage() {
        XCTAssertEqual(TrackMatch.base("eng"), "en")
        XCTAssertEqual(TrackMatch.base("en-US"), "en")
        XCTAssertEqual(TrackMatch.base("ger"), "de")
        XCTAssertEqual(TrackMatch.base("deu"), "de")
        XCTAssertEqual(TrackMatch.base("und"), "")
        let tracks = [track(0, "eng"), track(1, "fre"), track(2, "eng")]
        let options = [TrackOption(language: "fr", name: "Français"), TrackOption(language: "en", name: "English"), TrackOption(language: "en-GB", name: "English SDH")]
        XCTAssertEqual(TrackMatch.pick(wanted: tracks[1], among: tracks, options: options), 0)
        XCTAssertEqual(TrackMatch.pick(wanted: tracks[0], among: tracks, options: options), 1)
        XCTAssertEqual(TrackMatch.pick(wanted: tracks[2], among: tracks, options: options), 2, "the second English track is the second English option")
    }

    func testAnUnmatchedTrackPicksNothing() {
        let tracks = [track(0, "kor"), track(1, nil)]
        let options = [TrackOption(language: "en", name: "English"), TrackOption(language: nil, name: "Unknown")]
        XCTAssertNil(TrackMatch.pick(wanted: tracks[0], among: tracks, options: options), "better none than another language")
        XCTAssertEqual(TrackMatch.pick(wanted: tracks[1], among: tracks, options: options), 1, "the same list counts along")
        XCTAssertNil(TrackMatch.pick(wanted: tracks[1], among: tracks, options: Array(options.prefix(1))))
    }

    // MARK: What the device can do

    func testAPhoneSaysWhatItFound() throws {
        let phone = DeviceFacts(kind: .phone, hevc: true, av1: false, hdr: ["hdr10", "hlg"], audioChannels: 2)
        XCTAssertEqual(phone.profile, "appletv")
        let caps = phone.capabilities
        XCTAssertEqual(caps.videoCodecs, ["h264", "hevc"])
        XCTAssertEqual(caps.hdr, ["hdr10", "hlg"])
        XCTAssertEqual(caps.maxAudioChannels, 2, "not a TV's")
        XCTAssertNil(caps.maxBitrateKbps)
        XCTAssertEqual(DeviceFacts(kind: .phone, hevc: true, av1: false, hdr: [], audioChannels: 2, costlyNetwork: true).capabilities.maxBitrateKbps, 8000)
    }

    func testAnOldDeviceGetsTheSaferProfile() {
        let old = DeviceFacts(kind: .tv, hevc: false, av1: false, hdr: ["hdr10"], audioChannels: 6)
        XCTAssertEqual(old.profile, "appletv-hd")
        XCTAssertEqual(old.capabilities.videoCodecs, ["h264"])
        XCTAssertEqual(old.capabilities.hdr, [], "HDR needs 10-bit HEVC")
        XCTAssertEqual(old.capabilities.maxHeight, 1080)
        XCTAssertEqual(old.capabilities.maxAudioChannels, 6)
        XCTAssertNil(DeviceFacts(kind: .tv, hevc: false, av1: false, hdr: [], audioChannels: 6, costlyNetwork: true).capabilities.maxBitrateKbps, "a TV isn't on a metered phone plan")
    }

    func testAV1IsOnlyForFilesNotForHLS() {
        let new = DeviceFacts(kind: .tablet, hevc: true, av1: true, hdr: [], audioChannels: nil)
        XCTAssertEqual(new.capabilities.videoCodecs, ["h264", "hevc", "av1"])
        XCTAssertEqual(new.capabilities.hlsVideo, ["h264", "hevc"])
        XCTAssertNil(new.capabilities.maxAudioChannels)
    }

    func testCapabilitiesGoInTheRequestWithTheServersNames() throws {
        let facts = DeviceFacts(kind: .tv, hevc: true, av1: false, hdr: ["dv5"], audioChannels: 8)
        let request = PlaybackRequest(profile: facts.profile, capabilities: facts.capabilities, startSec: 12)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertEqual(object["profile"] as? String, "appletv")
        XCTAssertEqual(object["startSec"] as? Double, 12)
        let caps = try XCTUnwrap(object["capabilities"] as? [String: Any])
        XCTAssertEqual(Set(caps.keys), ["videoCodecs", "hdr", "tenBit", "maxHeight", "maxAudioChannels", "hlsVideo"])
        XCTAssertEqual(caps["maxAudioChannels"] as? Int, 8)
    }

    // MARK: Deep links

    func testDeepLinksHoldANumberAndNothingElse() throws {
        func parse(_ text: String) throws -> DeepLink? { DeepLink.parse(try XCTUnwrap(URL(string: text))) }
        XCTAssertEqual(try parse("wittymedia://item/123"), .item(123))
        XCTAssertEqual(try parse("wittymedia://show/9"), .show(9))
        XCTAssertEqual(try parse("WITTYMEDIA://item/5"), .item(5))
        for bad in ["wittymedia://item/", "wittymedia://item/12a", "wittymedia://item/-1", "wittymedia://item/0", "wittymedia://item/123/",
                    "wittymedia://item/123?token=abc", "wittymedia://item/123#x", "wittymedia://item/1/2", "wittymedia://user@item/1",
                    "wittymedia://other/1", "wittymedia://item/9999999999999999999", "https://item/1", "wittymedia:item/1",
                    "wittymedia://item/%31", "wittymedia://item/١"] {
            if let url = URL(string: bad) { XCTAssertNil(DeepLink.parse(url), bad) }
        }
    }

    func testADeepLinkReadsBackAsItself() throws {
        for link in [DeepLink.item(42), DeepLink.show(7)] {
            XCTAssertEqual(DeepLink.parse(try XCTUnwrap(URL(string: link.address))), link)
        }
    }

    // MARK: Top Shelf

    private func tempFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    private let homeJSON = #"""
    {"featured":[{"id":1,"title":"A Sample Picture Book","kind":"book"},{"id":2,"title":"A Sample Film","kind":"video"}],
     "hubs":[{"key":"continue","title":"Continue watching","items":[{"id":11,"title":"Pilot","kind":"video","showTitle":"A Sample Show","season":1,"episode":1},{"id":11,"title":"Pilot","kind":"video"}]},
             {"key":"recent-2","title":"Recently added in TV","items":null,"shows":[{"id":3,"title":"Another Sample Show"}]},
             {"key":"continue-reading","title":"Continue reading","items":[{"id":20,"title":"A Sample Novel","kind":"book"}]}],
     "libraries":[]}
    """#

    func testTheShelfComesFromTheHomePage() throws {
        let home = try JSONDecoder().decode(Home.self, from: Data(homeJSON.utf8))
        let shelf = Shelf.from(home: home)
        XCTAssertEqual(shelf.sections.map(\.title), ["Continue watching", "Recently added"])
        XCTAssertEqual(shelf.sections[0].entries.map(\.link), ["wittymedia://item/11"], "once each, and no books")
        XCTAssertEqual(shelf.sections[0].entries[0].title, "A Sample Show")
        XCTAssertEqual(shelf.sections[0].entries[0].subtitle, "S1 · E1")
        XCTAssertEqual(shelf.sections[1].entries[0].link, "wittymedia://show/3")
        XCTAssertEqual(shelf.sections[1].entries[0].poster, "s3.jpg")
    }

    func testTheShelfSurvivesTheFolderAndNoTokenIsInIt() throws {
        let folder = try tempFolder()
        let home = try JSONDecoder().decode(Home.self, from: Data(homeJSON.utf8))
        let shelf = Shelf.from(home: home)
        try shelf.write(to: folder)
        XCTAssertEqual(Shelf.read(from: folder), shelf)
        let written = try String(contentsOf: folder.appendingPathComponent(Shelf.fileName), encoding: .utf8)
        XCTAssertFalse(written.contains("token"))
        XCTAssertFalse(written.contains("http"), "no server address in the shared folder")
        Shelf.clear(in: folder)
        XCTAssertEqual(Shelf.read(from: folder), Shelf())
    }

    func testAShelfFromAnywhereElseIsCheckedBeforeUse() throws {
        let folder = try tempFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let bad = #"""
        {"sections":[{"title":"T","entries":[
          {"id":"a","title":"Good","subtitle":"","poster":"i1.jpg","link":"wittymedia://item/1"},
          {"id":"b","title":"Bad link","subtitle":"","poster":"i2.jpg","link":"https://evil.example/"},
          {"id":"c","title":"Bad poster","subtitle":"","poster":"../../etc/passwd","link":"wittymedia://item/3"}
        ]}]}
        """#
        try Data(bad.utf8).write(to: folder.appendingPathComponent(Shelf.fileName))
        let entries = Shelf.read(from: folder).entries
        XCTAssertEqual(entries.map(\.title), ["Good", "Bad poster"])
        XCTAssertEqual(entries[1].poster, nil)
        try Data("not json".utf8).write(to: folder.appendingPathComponent(Shelf.fileName))
        XCTAssertEqual(Shelf.read(from: folder), Shelf())
        try Data(repeating: 32, count: 300 * 1024).write(to: folder.appendingPathComponent(Shelf.fileName))
        XCTAssertEqual(Shelf.read(from: folder), Shelf(), "too big to be real")
    }

    func testPosterNamesCanNotBePaths() {
        XCTAssertTrue(Shelf.isPosterName("i12.jpg"))
        XCTAssertTrue(Shelf.isPosterName("s3.jpg"))
        for bad in ["../x.jpg", "i1.jpg/..", "x1.jpg", "i.jpg", "i1.png", "i1.jpg\n"] { XCTAssertFalse(Shelf.isPosterName(bad), bad) }
    }

    // MARK: Models

    func testTheHeroIsSomethingThisAppCanPlay() throws {
        let home = try JSONDecoder().decode(Home.self, from: Data(homeJSON.utf8))
        XCTAssertEqual(home.hero?.id, 2)
        let none = try JSONDecoder().decode(Home.self, from: Data(#"{"featured":[],"hubs":[{"key":"continue","title":"x","items":[{"id":7,"title":"t","kind":"video"}]}]}"#.utf8))
        XCTAssertEqual(none.hero?.id, 7)
    }

    func testProgressForTheBarOnACard() throws {
        func item(_ json: String) throws -> Item { try JSONDecoder().decode(Item.self, from: Data(json.utf8)) }
        XCTAssertEqual(try item(#"{"id":1,"title":"t","progress":{"positionSec":30,"durationSec":120}}"#).progressFraction, 0.25)
        XCTAssertNil(try item(#"{"id":1,"title":"t"}"#).progressFraction)
        XCTAssertNil(try item(#"{"id":1,"title":"t","progress":{"positionSec":30,"durationSec":120,"watched":true}}"#).progressFraction)
        XCTAssertEqual(try item(#"{"id":1,"title":"t","runtimeSec":60,"progress":{"positionSec":90}}"#).progressFraction, 1, "never past the end")
    }

    func testWhichLibrariesOpenHere() throws {
        func library(_ type: String) throws -> Library { try JSONDecoder().decode(Library.self, from: Data(#"{"id":1,"name":"x","type":"\#(type)"}"#.utf8)) }
        for type in ["movies", "shows", "anime", "videos", "discs"] { XCTAssertTrue(try library(type).opensHere, type) }
        for type in ["music", "books", "photos", "games", "something-new"] { XCTAssertFalse(try library(type).opensHere, type) }
        XCTAssertTrue(try library("audiobooks").isListening)
        XCTAssertFalse(try library("movies").isListening)
    }

    func testANameFromAServerIsCleaned() throws {
        let status = try JSONDecoder().decode(ServerStatus.self, from: Data(#"{"name":"WittyMediaServer","brandName":"Home\u0007‮ Box"}"#.utf8))
        XCTAssertEqual(status.displayName, "Home Box")
    }

    func testPlainWordsAreKeptShort() {
        XCTAssertEqual(PlainWords.clean(String(repeating: "x", count: 500)).count, 300)
        XCTAssertEqual(PlainWords.clean("  a\tb\n"), "ab")
    }
}
