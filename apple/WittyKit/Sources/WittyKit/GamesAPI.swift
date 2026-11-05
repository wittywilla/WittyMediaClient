import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// The games routes this app uses: exactly the ones the website's player uses (the server's
// docs/GAMING-API.md), under /api/v1. Nothing here sends or receives a game's file.

extension WittyClient {
    private static let gamesDecoder = JSONDecoder()

    private func decode<T: Decodable>(_ method: String, _ path: String, body: Data? = nil) async throws -> T {
        try Self.gamesDecoder.decode(T.self, from: try await call(method, path, body: body))
    }

    private func decodeAs<T: Decodable>(_ type: T.Type, _ method: String, _ path: String, body: Data? = nil, wait: TimeInterval? = nil) async throws -> T {
        try Self.gamesDecoder.decode(T.self, from: try await call(method, path, body: body, wait: wait))
    }

    /// How long starting a game may take. A disc game is read and set up first, which took 83
    /// seconds for a PlayStation game on a Mac: the server's docs say to let it.
    public static let gameStartWait: TimeInterval = 300

    private func json<T: Encodable>(_ value: T) throws -> Data { try JSONEncoder().encode(value) }

    public func gamesHome(library: Int64) async throws -> GamesHome { try await decode("GET", "/games/home?library=\(library)") }

    /// Every console, with that library's count of games for each when one is given.
    public func gameConsoles(library: Int64? = nil) async throws -> [GameConsole] {
        try await decodeAs([GameConsole]?.self, "GET", "/games/consoles" + (library.map { "?library=\($0)" } ?? "")) ?? []
    }

    /// `sort` is `popular`, `title`, `newest`, `oldest`, `rating` or `added`, as the website's.
    public func games(library: Int64, console: String? = nil, sort: String = "popular", offset: Int = 0, limit: Int = 60) async throws -> GameItemPage {
        let descending = sort == "rating" || sort == "added"
        var path = "/items?library=\(library)&kind=game&sort=\(Self.queryValue(sort))&desc=\(descending ? 1 : 0)&offset=\(offset)&limit=\(limit)"
        if let console, !console.isEmpty { path += "&console=\(Self.queryValue(console))" }
        return try await decode("GET", path)
    }

    public func gameItem(_ id: Int64) async throws -> GameItem { try await decode("GET", "/items/\(id)") }
    public func gameCheck(_ id: Int64) async throws -> GameCheck { try await decode("GET", "/games/\(id)/check") }
    public func gameDetails(_ id: Int64) async throws -> GameDetails { try await decode("GET", "/games/\(id)/metadata") }
    public func gamePersonal(_ id: Int64) async throws -> GamePersonal { try await decode("GET", "/games/\(id)/meta") }

    @discardableResult
    public func setGameFavourite(_ id: Int64, _ on: Bool) async throws -> GamePersonal {
        try await decode("PUT", "/games/\(id)/meta", body: try json(["favourite": on]))
    }

    public func gameSaves(_ id: Int64) async throws -> [GameSave] {
        try await decodeAs([GameSave]?.self, "GET", "/games/\(id)/saves") ?? []
    }

    public func deleteGameSave(_ id: Int64, slot: Int) async throws {
        _ = try await call("DELETE", "/games/\(id)/saves/\(slot)")
    }

    /// A state's picture. `version` is its `updatedAt`, so a newer save is a new picture.
    public func gameSaveThumbURL(_ id: Int64, slot: Int, version: Int64) -> URL? {
        mediaURL("/api/v1/games/\(id)/saves/\(slot)/thumb?v=\(version)")
    }

    /// Covers come as smaller copies, as big as they'll be seen.
    public func gamePosterURL(_ game: GameItem, width: Int) -> URL? {
        mediaURL("/api/v1/items/\(game.id)/poster?v=\(game.updatedAt ?? 0)&w=\(min(640, max(64, width)))")
    }

    public func gameBackdropURL(_ game: GameItem) -> URL? {
        mediaURL("/api/v1/items/\(game.id)/backdrop?v=\(game.updatedAt ?? 0)")
    }

    public func gameBezelURL(_ bezel: Int64) -> URL? { mediaURL("/api/v1/game-bezels/\(bezel)") }

    public func gameControls(console: String, device: String, game: Int64? = nil) async throws -> GameControls {
        var path = "/consoles/\(Self.pathPart(console))/controls?device=\(Self.queryValue(device))"
        if let game { path += "&game=\(game)" }
        return try await decode("GET", path)
    }

    /// `controller` is `vendor:product` in lowercase hex, or `id:<name>` for a pad without numbers.
    public func resolvePad(controller: String, console: String, game: Int64) async throws -> ResolvedPad {
        try await decode("GET", "/game-profiles/resolve?kind=gamepad&controller=\(Self.queryValue(controller))&console=\(Self.queryValue(console))&game=\(game)")
    }

    public func gameSettings(item: Int64) async throws -> GameSettings { try await decode("GET", "/games/settings?item=\(item)") }

    public func gameBackground() async throws -> GameBackground { try await decode("GET", "/game-background") }

    /// For a game in an archive: ask about once a second until it's ready, then play.
    public func prepareGame(_ id: Int64) async throws -> GamePrepare {
        try await decode("POST", "/games/\(id)/prepare", body: Data("{}".utf8))
    }

    /// Starts a game. Starting another saves and ends whatever this account was playing, anywhere.
    public func playGame(_ id: Int64, resume: Bool, safeMode: Bool = false) async throws -> GameSession {
        struct Start: Encodable { let resume: Bool; let client: String; let safeMode: Bool? }
        return try await decodeAs(GameSession.self, "POST", "/games/\(id)/play", body: try json(Start(resume: resume, client: "native", safeMode: safeMode ? true : nil)),
                                  wait: Self.gameStartWait)
    }

    public func gameSession(_ sid: String) async throws -> GameSession { try await decode("GET", "/play/\(Self.pathPart(sid))") }

    public func gameAction(_ sid: String, _ action: GameAction) async throws {
        _ = try await call("POST", "/play/\(Self.pathPart(sid))/action", body: try json(action))
    }

    /// Saves and stops. The answer comes once everything is written, battery save and all.
    public func stopGame(_ sid: String) async throws {
        _ = try await call("DELETE", "/play/\(Self.pathPart(sid))")
    }

    /// The WebSocket for a game: `video` is `h264` or `jpeg`. The sign-in goes in its header, as
    /// for every other request, and never in the address.
    /// The second stream's WebRTC offer, `POST /play/{sid}/stream`, signed in by header.
    public func gameStreamOfferRequest(_ sid: String) -> URLRequest? {
        guard let url = mediaURL("/api/v1/play/\(Self.pathPart(sid))/stream") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        for (name, value) in authHeaders { request.setValue(value, forHTTPHeaderField: name) }
        return request
    }

    /// The second stream's WebSocket: the hello goes first, as text.
    public func gameStreamRequest(_ sid: String) -> URLRequest? {
        socketRequest("/api/v1/play/\(Self.pathPart(sid))/stream")
    }

    public func gameSocketRequest(_ sid: String, video: String) -> URLRequest? {
        socketRequest("/api/v1/play/\(Self.pathPart(sid))/ws?video=\(Self.queryValue(video))")
    }

    /// A WebSocket's request, signed in by header: the token never goes in the address.
    private func socketRequest(_ path: String) -> URLRequest? {
        guard let http = mediaURL(path),
              var parts = URLComponents(url: http, resolvingAgainstBaseURL: false) else { return nil }
        parts.scheme = parts.scheme == "https" ? "wss" : "ws"
        guard let url = parts.url else { return nil }
        var request = URLRequest(url: url)
        for (name, value) in authHeaders { request.setValue(value, forHTTPHeaderField: name) }
        return request
    }
}
