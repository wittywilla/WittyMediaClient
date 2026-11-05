import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct APIError: LocalizedError {
    public let status: Int
    public let message: String
    /// Where a redirect that wasn't followed pointed.
    public let location: String?
    /// Signing in needs the code from an authenticator app, or the one given was wrong.
    public let twoFactor: Bool
    public var errorDescription: String? { message }
    public var isExpiredSignIn: Bool { status == 401 }

    public init(status: Int, message: String, location: String? = nil, twoFactor: Bool = false) {
        self.status = status
        self.message = message
        self.location = location
        self.twoFactor = twoFactor
    }
}

/// How much of an answer this app will read. A server that hasn't proved itself gets very little,
/// since it can only have small things to say: asking it costs no more than that.
enum AnswerLimit {
    static let unproved = 256 * 1024
    static let signedIn = 32 * 1024 * 1024
    static let picture = 16 * 1024 * 1024
    static let report = 64 * 1024
}

/// One answer being read, with a limit. Only touched on the session's own queue, or under the lock.
private final class Transfer {
    let limit: Int
    var data = Data()
    var response: URLResponse?
    var tooBig = false
    var waiting: CheckedContinuation<(Data, URLResponse), Error>?

    init(limit: Int, waiting: CheckedContinuation<(Data, URLResponse), Error>) {
        self.limit = limit
        self.waiting = waiting
    }
}

/// The session's delegate. It reads answers up to their limit, and follows a redirect only
/// within the same server: same scheme, host and port, where the sign-in has already gone.
/// Anything else comes back as the redirect it was, with its `Location`, and is never
/// followed: a move from http to https has to be proved all over again at the new address.
private final class SessionGuard: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var transfers: [Int: Transfer] = [:]

    func add(_ task: URLSessionTask, limit: Int, waiting: CheckedContinuation<(Data, URLResponse), Error>) {
        lock.lock()
        transfers[task.taskIdentifier] = Transfer(limit: limit, waiting: waiting)
        lock.unlock()
    }

    private func transfer(_ task: URLSessionTask) -> Transfer? {
        lock.lock()
        defer { lock.unlock() }
        return transfers[task.taskIdentifier]
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let from = task.originalRequest?.url, let to = request.url, Origin.same(from, to) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let transfer = transfer(dataTask) else {
            completionHandler(.cancel)
            return
        }
        transfer.response = response
        if response.expectedContentLength > Int64(transfer.limit) {
            transfer.tooBig = true
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let transfer = transfer(dataTask), !transfer.tooBig else { return }
        if transfer.data.count + data.count > transfer.limit {
            transfer.tooBig = true
            transfer.data = Data()
            dataTask.cancel()
            return
        }
        transfer.data.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let finished = transfers.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        guard let finished, let waiting = finished.waiting else { return }
        finished.waiting = nil
        if finished.tooBig {
            waiting.resume(throwing: APIError(status: 0, message: "The server sent more than this app will read."))
        } else if let error {
            waiting.resume(throwing: error)
        } else if let response = finished.response {
            waiting.resume(returning: (finished.data, response))
        } else {
            waiting.resume(throwing: URLError(.badServerResponse))
        }
    }
}

/// One connection to one server. The token goes in a header, so it stays out
/// of URLs and logs.
public final class WittyClient: @unchecked Sendable {
    /// The oldest API revision this app was written for. A server below it is told to update.
    public static let minimumAPIRevision = 5
    /// This family's name in `minClientVersions`.
    public static let platform = "apple"

    public let base: String
    public let token: String
    private let apiPath = "/api/v1" // the contract: docs/CLIENT-API.md
    private let session: URLSession
    private let sessionGuard = SessionGuard()
    private let answerLimit: Int
    private let decoder = JSONDecoder()

    /// Quick is for questions to an address not yet trusted, which get short waits and small answers.
    public init(base: String, token: String = "", quick: Bool = false) {
        self.base = base
        self.token = token
        answerLimit = quick ? AnswerLimit.unproved : AnswerLimit.signedIn
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = quick ? 5 : 60 // the first play request probes the file
        config.timeoutIntervalForResource = quick ? 5 : 180
        // Only ever the bearer token: no cookies, no remembered passwords, nothing kept on disk.
        config.httpCookieStorage = nil
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        #if !canImport(FoundationNetworking)
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        #endif
        session = URLSession(configuration: config, delegate: sessionGuard, delegateQueue: nil)
    }

    // A session keeps itself and its delegate alive until it's told it can go.
    deinit { session.finishTasksAndInvalidate() }

    /// The headers an API or artwork request to this server needs. Video doesn't
    /// use these: its addresses carry a short-lived stream token instead.
    public var authHeaders: [String: String] {
        token.isEmpty ? [:] : ["Authorization": "Bearer \(token)"]
    }

    /// Reads one answer, no further than its limit. Leaving the screen cancels it.
    private func fetch(_ request: URLRequest, limit: Int) async throws -> (Data, URLResponse) {
        let task = session.dataTask(with: request)
        let keeper = sessionGuard
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (waiting: CheckedContinuation<(Data, URLResponse), Error>) in
                keeper.add(task, limit: limit, waiting: waiting)
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    private func call(_ method: String, _ path: String, body: Data? = nil) async throws -> Data {
        guard let url = URL(string: base + apiPath + path) else {
            throw APIError(status: 0, message: "That server address can't be used.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        for (name, value) in authHeaders { request.setValue(value, forHTTPHeaderField: name) }
        let place = "\(method) \(path.split(separator: "?").first.map(String.init) ?? path)"
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await fetch(request, limit: answerLimit)
        } catch {
            // Leaving a screen cancels what it asked for, which is nothing to report.
            if !token.isEmpty, !(error is CancellationError), (error as? URLError)?.code != .cancelled {
                ClientLog.shared.warn("network", "\(place) failed: \((error as? URLError)?.code.rawValue ?? 0)")
            }
            throw error
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError(status: 0, message: "The server sent an answer that can't be read.")
        }
        guard (200..<300).contains(http.statusCode) else {
            struct Failure: Decodable {
                let error: String?
                let twoFactor: Bool?
            }
            let failure = try? decoder.decode(Failure.self, from: data)
            let said = failure?.error.map { PlainWords.clean($0) } ?? ""
            let message = said.isEmpty ? "The server answered with an error (\(http.statusCode))." : said
            reportFailure(place, method: method, status: http.statusCode, message: message, request: http.value(forHTTPHeaderField: "X-Request-Id") ?? "")
            throw APIError(status: http.statusCode, message: message, location: http.value(forHTTPHeaderField: "Location"),
                           twoFactor: failure?.twoFactor == true)
        }
        return data
    }

    /// Only for a signed-in connection: an address being tried has its own words on
    /// screen. A sign-in that has run out and a stream already gone are normal.
    private func reportFailure(_ place: String, method: String, status: Int, message: String, request: String) {
        guard !token.isEmpty, status != 401, !(method == "DELETE" && status == 404) else { return }
        ClientLog.shared.report(status >= 500 ? "error" : "warn", "request", "\(place) answered \(status): \(message)", request: request)
    }

    /// This app's own errors, for the server's log. The answer is all that comes back:
    /// it skips `call`, so a report that fails can't become a report of its own.
    func sendClientLog(_ body: Data) async throws -> Int {
        guard let url = URL(string: base + apiPath + "/logs/client") else { return 0 }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in authHeaders { request.setValue(value, forHTTPHeaderField: name) }
        let (_, response) = try await fetch(request, limit: AnswerLimit.report)
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try decoder.decode(T.self, from: try await call("GET", path))
    }

    public func capabilities() async throws -> Capabilities { try await get("/capabilities") }
    public func status() async throws -> ServerStatus { try await get("/status") }
    public func profiles() async throws -> Profiles { try await get("/profiles") }
    public func home() async throws -> Home { try await get("/home") }
    public func item(_ id: Int64) async throws -> Item { try await get("/items/\(id)") }
    public func show(_ id: Int64) async throws -> ShowDetail { try await get("/shows/\(id)") }
    public func shows(library: Int64) async throws -> ShowPage { try await get("/shows?library=\(library)&sort=title") }
    public func items(library: Int64, offset: Int, limit: Int) async throws -> ItemPage {
        try await get("/items?library=\(library)&offset=\(offset)&limit=\(limit)&sort=title")
    }

    /// Words go to the server as they are, in one query value. Shows and films are searched:
    /// a show's episodes are behind the show.
    public func search(_ words: String, limit: Int = 40) async throws -> SearchResults {
        guard let query = Self.searchQuery(words) else { return SearchResults(items: [], shows: []) }
        async let items: ItemPage = get("/items?search=\(query)&noEpisodes=1&limit=\(limit)")
        async let shows: ShowPage = get("/shows?search=\(query)&limit=\(limit)")
        return SearchResults(items: uniqued(try await items.items ?? []), shows: uniqued(try await shows.shows ?? []))
    }

    /// Percent-encoded so nothing typed can add a parameter. Nil when there's nothing worth asking.
    public static func searchQuery(_ words: String) -> String? {
        let trimmed = String(words.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard trimmed.count >= 2 else { return nil }
        var safe = CharacterSet.alphanumerics
        safe.insert(charactersIn: "-._~")
        return trimmed.addingPercentEncoding(withAllowedCharacters: safe)
    }

    /// A plain list, which a Go nil sends as null.
    private func list<T: Decodable>(_ path: String) async throws -> [T] {
        try decoder.decode([T]?.self, from: try await call("GET", path)) ?? []
    }

    /// One value in a query, as it is: nothing in a name can add a parameter or end the address.
    public static func queryValue(_ text: String) -> String {
        var safe = CharacterSet.alphanumerics
        safe.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: safe) ?? ""
    }

    public func libraries() async throws -> [Library] { try await list("/libraries") }

    /// Albums, books or podcasts: by `title`, `artist`, `added` or `year`. With an artist, only theirs.
    public func albums(library: Int64, sort: String, artist: String? = nil) async throws -> [Album] {
        try await list("/music/albums?library=\(library)&sort=\(Self.queryValue(sort))" + (artist.map { "&artist=\(Self.queryValue($0))" } ?? ""))
    }

    public func artists(library: Int64) async throws -> [Artist] { try await list("/music/artists?library=\(library)") }

    /// The tracks of one album, in order. An empty album or artist means none or unknown: it is still asked for by name.
    public func tracks(library: Int64, album: String, artist: String) async throws -> [Item] {
        try await list("/music/tracks?library=\(library)&album=\(Self.queryValue(album))&artist=\(Self.queryValue(artist))")
    }

    /// Every song in a music library, a page at a time, by title.
    public func songs(library: Int64, offset: Int, limit: Int) async throws -> [Item] {
        try await list("/music/songs?library=\(library)&offset=\(offset)&limit=\(limit)&sort=title")
    }

    /// Music has no place to save, but what was heard counts towards the server's yearly summary.
    public func recordListen(_ id: Int64, seconds: Double) async throws {
        let body = try JSONEncoder().encode(["seconds": seconds])
        _ = try await call("POST", "/items/\(id)/view", body: body)
    }

    public func playback(_ id: Int64, _ request: PlaybackRequest) async throws -> Playback {
        let body = try JSONEncoder().encode(request)
        return try decoder.decode(Playback.self, from: try await call("POST", "/items/\(id)/playback", body: body))
    }

    /// Stops the conversion at once when the viewer leaves.
    public func stopStream(_ streamId: String) async throws {
        _ = try await call("DELETE", "/hls/\(streamId)")
    }

    public func pairStart(device: String, platform: String) async throws -> PairStart {
        let body = try JSONEncoder().encode(["device": device, "platform": platform])
        return try decoder.decode(PairStart.self, from: try await call("POST", "/pair/start", body: body))
    }

    /// Denied, expired and slow-down are normal answers here, not errors.
    public func pairPoll(deviceSecret: String) async throws -> PairPoll {
        let body = try JSONEncoder().encode(["deviceSecret": deviceSecret])
        do {
            return try decoder.decode(PairPoll.self, from: try await call("POST", "/pair/poll", body: body))
        } catch let error as APIError where [403, 410, 429].contains(error.status) {
            switch error.status {
            case 403: return PairPoll(status: "denied", token: nil, intervalSec: nil)
            case 410: return PairPoll(status: "expired", token: nil, intervalSec: nil)
            default: return PairPoll(status: "slow-down", token: nil, intervalSec: nil)
            }
        }
    }

    /// A refusal that wants the code from an authenticator app is an `APIError` with `twoFactor` set:
    /// ask for it, then sign in again with the same name and password and the `code`.
    public func login(name: String, password: String, device: String, code: String = "") async throws -> LoginResult {
        var fields = ["name": name, "password": password, "device": device]
        if !code.isEmpty { fields["code"] = code }
        let body = try JSONEncoder().encode(fields)
        return try decoder.decode(LoginResult.self, from: try await call("POST", "/login", body: body))
    }

    /// Errors carry the server's own plain words: a wrong, expired or used code, or too many tries.
    public func pairRedeem(code: String, device: String, platform: String) async throws -> LoginResult {
        let body = try JSONEncoder().encode(["code": code, "device": device, "platform": platform])
        return try decoder.decode(LoginResult.self, from: try await call("POST", "/pair/redeem", body: body))
    }

    public func identity(nonce: String) async throws -> IdentityAnswer {
        let body = try JSONEncoder().encode(["nonce": nonce])
        return try decoder.decode(IdentityAnswer.self, from: try await call("POST", "/identity", body: body))
    }

    public func saveProgress(_ id: Int64, positionSec: Double, durationSec: Double) async throws {
        let body = try JSONEncoder().encode(["positionSec": positionSec, "durationSec": durationSec])
        _ = try await call("POST", "/items/\(id)/progress", body: body)
    }

    public func couchStatus() async throws -> CouchStatus { try await get("/couch") }
    public func guide() async throws -> Guide { try await get("/guide?hours=3") }

    /// How this account's guide looks, as chosen on any device.
    public func tvSaved() async throws -> TvSaved? {
        let choices: AccountChoices = try await get("/me/ui")
        return choices.tvLook
    }

    /// Starts a channel's shared stream. A 503 means it's still starting: wait and ask again.
    public func tune(_ key: String, viewer: String) async throws -> Tuned {
        try await get("/tv/\(WittyClient.pathPart(key))/tune?streamToken=1&viewer=\(WittyClient.pathPart(viewer))")
    }

    public func leaveChannel(_ key: String, viewer: String) async throws {
        _ = try await call("POST", "/tv/\(WittyClient.pathPart(key))/leave?viewer=\(WittyClient.pathPart(viewer))", body: Data("{}".utf8))
    }

    /// A channel's key goes in the address as it is, and only ever as one piece of it.
    public static func pathPart(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_"))) ?? ""
    }

    /// What this device can do to play a game on someone's own PC. It starts nothing there.
    public func rigPlay(_ gameId: Int64, client: String, os: String) async throws -> RigPlay {
        let body = try JSONEncoder().encode(["client": client, "os": os])
        return try decoder.decode(RigPlay.self, from: try await call("POST", "/rigs/games/\(gameId)/play", body: body))
    }

    /// Starts the game on the PC, so Moonlight can pick it up with Resume.
    public func rigStart(_ gameId: Int64) async throws -> RigStarted {
        try decoder.decode(RigStarted.self, from: try await call("POST", "/rigs/games/\(gameId)/start", body: Data("{}".utf8)))
    }

    public func rigWake(_ rigId: Int64) async throws -> RigWake {
        try decoder.decode(RigWake.self, from: try await call("POST", "/rigs/\(rigId)/wake", body: Data("{}".utf8)))
    }

    public func logout() async throws {
        _ = try await call("POST", "/logout", body: Data("{}".utf8))
    }

    /// Goes with the sign-in, so only ever to this server.
    public func imageData(_ url: URL) async throws -> Data {
        guard let server = URL(string: base), Origin.same(url, server) else {
            throw APIError(status: 0, message: "No picture.")
        }
        var request = URLRequest(url: url)
        for (name, value) in authHeaders { request.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await fetch(request, limit: AnswerLimit.picture)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, message: "No picture.")
        }
        return data
    }

    public func posterURL(_ item: Item) -> URL? { URL(string: "\(base)\(apiPath)/items/\(item.id)/poster?v=\(item.updatedAt ?? 0)") }
    /// An album's or an artist's cover: the poster of the track the server chose for it.
    public func coverURL(_ item: Int64) -> URL? { URL(string: "\(base)\(apiPath)/items/\(item)/poster") }
    public func posterURL(_ show: Show) -> URL? { URL(string: "\(base)\(apiPath)/shows/\(show.id)/art/poster?v=\(show.updatedAt ?? 0)") }
    public func backdropURL(_ item: Item) -> URL? { URL(string: "\(base)\(apiPath)/items/\(item.id)/backdrop?v=\(item.updatedAt ?? 0)") }
    public func backdropURL(_ show: Show) -> URL? { URL(string: "\(base)\(apiPath)/shows/\(show.id)/art/backdrop?v=\(show.updatedAt ?? 0)") }

    /// Addresses in answers start with /api/: the server's address goes in front, nothing else changes.
    /// One that would end up anywhere but this server comes back nil.
    public func mediaURL(_ path: String) -> URL? { Origin.join(base: base, path: path) }

    /// The owner's own logo, when `/status` names one; shown before anyone signs in, as on the web.
    public func brandLogoURL(version: String?) -> URL? {
        guard let version, !version.isEmpty else { return nil }
        let escaped = version.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        return Origin.join(base: base, path: "/api/branding/logo?v=\(escaped)")
    }
    /// A photo as it was taken, as big as the file is.
    public func originalURL(_ item: Int64) -> URL? { URL(string: "\(base)\(apiPath)/items/\(item)/original") }

    public enum Probe: Equatable {
        case found(ServerStatus)
        case failed(String)
        /// The address answered by moving to https on the same host: try that one instead.
        case moved(String)
    }

    /// What's wrong with this server for this app, in the words of `Probe.failed`, or nil if it's fine.
    /// Optional abilities don't come into it: those go by `Capabilities.has`.
    public static func judge(_ caps: Capabilities, appVersion: String) -> String? {
        guard caps.server == "WittyMediaServer" else { return "not-server" }
        guard caps.apiVersions?.contains(1) == true else { return "app-old" }
        guard (caps.apiRevision ?? 0) >= minimumAPIRevision else { return "server-old" }
        if let lowest = caps.minClientVersions?[platform], Version.isOlder(appVersion, than: lowest) { return "app-old" }
        if caps.setupRequired == true { return "not-set-up" }
        return nil
    }

    /// The version this app was built as.
    public static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// Asks an address whether it is a WittyMediaServer this app can use.
    public static func probe(_ url: String, appVersion: String = WittyClient.appVersion) async -> Probe {
        guard await Address.plainHTTPStaysLocal(url) else { return .failed("public-http") }
        let client = WittyClient(base: url, quick: true)
        do {
            let caps = try await client.capabilities()
            if let reason = judge(caps, appVersion: appVersion) { return .failed(reason) }
            return .found(try await client.status())
        } catch let error as URLError {
            switch Problem.of(error) {
            case .certificate: return .failed("certificate")
            default: return .failed("unreachable")
            }
        } catch let error as APIError where (300..<400).contains(error.status) {
            // Never followed. It's only worth trying if it's the same host asking for https.
            if let safer = Address.upgrade(from: url, location: error.location) { return .moved(safer) }
            return .failed("not-server")
        } catch let error as APIError where error.status == 404 {
            // No /capabilities: an older server, if it says it is one at all.
            let old = (try? await client.status())?.name == "WittyMediaServer"
            return .failed(old ? "server-old" : "not-server")
        } catch {
            return .failed("not-server")
        }
    }

    /// Has the server at this address proved it holds its key, and is that a key we
    /// remember? A new nonce every time, and no token goes with the question. Every path
    /// to sending a token or a code comes through here first, so this is also where a local
    /// name that has started resolving to the internet is stopped.
    public static func identify(_ url: String, saved: [SavedServer]) async -> ServerProof {
        guard await Address.plainHTTPStaysLocal(url) else { return ServerProof(state: .bad) }
        let nonce = Identity.newNonce()
        let client = WittyClient(base: url, quick: true)
        do {
            let answer = try await client.identity(nonce: nonce)
            let state = Identity.judge(answer, nonce: nonce, url: url, saved: saved)
            if state == .bad { return ServerProof(state: .bad) }
            return ServerProof(state: state, serverId: answer.serverId, publicKey: answer.publicKey, fingerprint: Identity.fingerprint(answer.publicKey))
        } catch is URLError {
            return ServerProof(state: .unreachable)
        } catch let error as APIError where error.status == 404 {
            return ServerProof(state: Identity.unanswered(url: url, saved: saved))
        } catch {
            return ServerProof(state: .bad)
        }
    }
}
