// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

final class MediaExtrasTests: XCTestCase {
    private func watch(_ json: String) throws -> WhereToWatch { try JSONDecoder().decode(WhereToWatch.self, from: Data(json.utf8)) }

    private let full = #"""
    {"inLibrary":true,"itemId":2,"local":{"itemId":2,"title":"The Matrix","quality":"4K","versions":[
        {"itemId":2,"kind":"video","quality":"4K","width":3840,"height":2160,"container":"mkv","videoCodec":"hevc","sizeBytes":4509715660},
        {"itemId":7,"label":"Director's cut","kind":"video","quality":"1080p","container":"mp4","sizeBytes":2147483648}]},
     "region":"NL","tmdb":{"type":"movie","tmdbId":"603"},"source":"tmdb","link":"https://www.themoviedb.org/movie/603-the-matrix/watch?locale=NL",
     "groups":[{"type":"rent","providers":[{"providerId":2,"key":"apple-tv","name":"Apple TV","type":"rent","logo":"https://image.tmdb.org/t/p/w92/9gh.jpg","priority":4}]},
               {"type":"stream","providers":[{"providerId":1899,"key":"hbo-max","name":"HBO Max","type":"stream","priority":27},
                                             {"providerId":8,"key":"netflix","name":"Netflix","type":"stream","logo":"https://image.tmdb.org/t/p/w92/pbp.jpg","priority":0},
                                             {"providerId":8,"key":"netflix","name":"netflix","type":"stream","priority":1}]},
               {"type":"buy","providers":[]}],
     "providers":[],"attribution":"This product uses the TMDB API but is not endorsed or certified by TMDB.","fetchedAt":1794000000,"cached":true}
    """#

    func testProvidersAreGroupedInTheOrderThatMattersToSomeoneChoosing() throws {
        let rows = WhereToWatchLook.rows(try watch(full))
        XCTAssertEqual(rows.map(\.heading), ["Included with a subscription", "Rent"], "what's already paid for first; an empty group isn't shown")
        XCTAssertEqual(rows[0].providers.map(\.name), ["Netflix", "HBO Max"], "by the server's priority, each service once")
        XCTAssertTrue(WhereToWatchLook.shown(try watch(full)))
    }

    func testWhatTheLibraryHasIsSaidFirst() throws {
        let answer = try watch(full)
        XCTAssertEqual(WhereToWatchLook.libraryLine(answer), "In your library · 4K")
        XCTAssertEqual(WhereToWatchLook.versionLines(answer), ["This copy · 4K · MKV · 4.2 GB", "Director's cut · 1080p · MP4 · 2.0 GB"])
        XCTAssertEqual(WhereToWatchLook.regionWords(answer), "Offers in Netherlands")
        XCTAssertEqual(answer.attribution, "This product uses the TMDB API but is not endorsed or certified by TMDB.")
    }

    func testAServerWithoutAKeyOrATitleNobodyOffersSaysNothing() throws {
        let quiet = try watch(#"{"inLibrary":true,"local":{"quality":"720p","versions":[{"itemId":2,"kind":"video","quality":"720p"}]},"region":"US","groups":[],"providers":[],"reason":"no-api-key","fetchedAt":0,"cached":false}"#)
        XCTAssertFalse(WhereToWatchLook.shown(quiet))
        XCTAssertEqual(WhereToWatchLook.rows(quiet), [])
        XCTAssertEqual(WhereToWatchLook.versionLines(quiet), [], "one copy needs no list")
        XCTAssertEqual(WhereToWatchLook.libraryLine(quiet), "In your library · 720p")
        XCTAssertFalse(WhereToWatchLook.shown(nil))
        XCTAssertEqual(WhereToWatchLook.libraryLine(try watch(#"{"inLibrary":false,"region":"US","groups":[],"providers":[]}"#)), "")
    }

    func testOnlyTheSourcesOwnAddressesAreOpenedOrLoaded() throws {
        XCTAssertEqual(WhereToWatchLook.link(try watch(full))?.host, "www.themoviedb.org")
        XCTAssertNil(WhereToWatchLook.link(try watch(#"{"link":"https://evil.example/phish","groups":[]}"#)))
        XCTAssertNil(WhereToWatchLook.link(try watch(#"{"link":"http://www.themoviedb.org/movie/1/watch","groups":[]}"#)), "never over plain HTTP")
        XCTAssertNil(WhereToWatchLook.link(try watch(#"{"groups":[]}"#)))
        func provider(_ logo: String?) -> WhereToWatch.Provider { WhereToWatch.Provider(providerId: 1, name: "X", logo: logo, priority: 0) }
        XCTAssertNotNil(WhereToWatchLook.logo(provider("https://image.tmdb.org/t/p/w92/a.jpg")))
        XCTAssertNil(WhereToWatchLook.logo(provider("https://tracker.example/a.jpg")))
        XCTAssertNil(WhereToWatchLook.logo(provider("http://image.tmdb.org/t/p/w92/a.jpg")))
        XCTAssertNil(WhereToWatchLook.logo(provider(nil)))
    }

    func testATaskIsFollowedToItsEnd() throws {
        let tasks = try JSONDecoder().decode(ActivityTasks.self, from: Data(#"""
        {"access":{"enabled":true,"visible":true,"readOnly":false},
         "tasks":[{"id":"a-1","type":"other","title":"Making a canvas","state":"queued","done":0,"total":0,"percent":-1},
                  {"id":"a-2","type":"intros","title":"Finding intros and credits","state":"running","phase":"Listening","done":2,"total":3,"unit":"episodes","percent":66.7}],
         "recent":[{"id":"a-3","type":"other","title":"Making an approximate instrumental","state":"failed","error":"this song is mono, so there are no two channels to take from each other"},
                   {"id":"a-4","type":"intros","title":"Finding intros and credits","state":"done","result":"Found an intro in 3 of 3 episodes, and credits in 3."},
                   {"id":"a-5","type":"other","title":"Making a canvas","state":"cancelled"}],
         "summary":{"active":1,"queued":1,"paused":0,"percent":66.7}}
        """#.utf8))
        XCTAssertEqual(MediaJobState.of(task: "a-1", in: tasks), .waiting)
        XCTAssertEqual(MediaJobState.of(task: "a-2", in: tasks), .running(percent: 66.7, phase: "Listening"))
        XCTAssertEqual(MediaJobState.of(task: "a-3", in: tasks), .failed(words: "this song is mono, so there are no two channels to take from each other"))
        XCTAssertEqual(MediaJobState.of(task: "a-4", in: tasks), .done(result: "Found an intro in 3 of 3 episodes, and credits in 3."))
        XCTAssertEqual(MediaJobState.of(task: "a-5", in: tasks), .stopped)
        XCTAssertEqual(MediaJobState.of(task: "gone", in: tasks), .unknown)
        XCTAssertEqual(MediaJobState.of(task: "a-1", in: nil), .unknown, "an account that can't see tasks")
        XCTAssertTrue(MediaJobState.of(task: "a-3", in: tasks).finished)
        XCTAssertFalse(MediaJobState.of(task: "a-2", in: tasks).finished)
        XCTAssertEqual(MediaJobState.of(task: "a-1", in: tasks).progressWords("Making a canvas"), "Making a canvas: waiting its turn…")
        XCTAssertEqual(MediaJobState.of(task: "a-2", in: tasks).progressWords("Finding intros"), "Finding intros… Listening · 67%")
        XCTAssertEqual(MediaJobState.unknown.progressWords("Making it"), "Making it…")
    }

    func testStartingSomethingAnswersItsTask() throws {
        let started = try JSONDecoder().decode(MediaJobStart.self, from: Data(#"{"ok":true,"task":"t6-9","episodes":3,"seasons":1}"#.utf8))
        XCTAssertEqual(started.task, "t6-9")
        XCTAssertEqual(started.episodes, 3)
        let exists = try JSONDecoder().decode(MediaJobStart.self, from: Data(#"{"ok":true,"exists":true,"approximate":true,"source":"approximate"}"#.utf8))
        XCTAssertNil(exists.task)
        XCTAssertEqual(exists.exists, true)
    }

    /// The routes, against a real connection: the method, the path and the body each one sends.
    func testTheRoutesAskForWhatTheServerDocuments() async throws {
        let server = try StandInServer { request in
            let body: String
            switch request.path {
            case "/api/v1/items/9/stream-token": body = #"{"token":"st_abc","param":"st","expiresInSec":1799}"#
            case "/api/v1/media/9/canvas": body = #"{"available":true,"url":"/api/media/9/canvas/file?v=x1","mime":"video/mp4","loop":true,"canGenerate":false}"#
            case "/api/v1/media/9/stems": body = #"{"stems":[],"names":[],"separation":{"approximate":{"available":true},"external":{"available":false}}}"#
            case "/api/v1/media/9/markers": body = #"{"intro":{"startSec":5,"endSec":20},"recap":null,"credits":null,"commercials":[],"source":"skip.json","sources":{"intro":"skip.json"}}"#
            case "/api/v1/media/9/where-to-watch": body = #"{"inLibrary":true,"region":"US","groups":[],"providers":[],"reason":"no-api-key"}"#
            default: body = #"{"ok":true,"task":"t1-1"}"#
            }
            return Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)".utf8)
        }
        let client = WittyClient(base: server.address, token: "session")
        let canvas = try await client.canvas(item: 9)
        let address = try await client.canvasURL(canvas, item: 9)
        XCTAssertEqual(address?.absoluteString, "\(server.address)/api/media/9/canvas/file?v=x1&st=st_abc")
        let markers = try await client.markers(item: 9)
        XCTAssertEqual(markers.intro?.endSec, 20)
        let watch = try await client.whereToWatch(item: 9)
        XCTAssertEqual(watch.reason, "no-api-key")
        var started = try await client.generateCanvas(item: 9)
        XCTAssertEqual(started.task, "t1-1")
        started = try await client.detectIntros(show: 4)
        try await client.removeCanvas(item: 9)
        let lines = server.requests.map(\.line).map { $0.replacingOccurrences(of: " HTTP/1.1", with: "") }
        XCTAssertEqual(Array(lines.suffix(3)), ["POST /api/v1/media/9/canvas/generate", "POST /api/v1/shows/4/detect-intros", "DELETE /api/v1/media/9/canvas"])
        XCTAssertTrue(server.requests.allSatisfy(\.hasToken))
        XCTAssertEqual(client.tokenURL(path: "/api/media/9/stems/vocals", token: "st_abc")?.absoluteString, "\(server.address)/api/media/9/stems/vocals?st=st_abc")
    }
}
