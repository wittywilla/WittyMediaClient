import AVFoundation
import MediaPlayer
import Network
import SwiftUI
import WittyKit

// Music, audiobooks and podcasts, as Android's player/Listening.kt and ListeningService.kt: one queue
// for the whole app, carrying on with the screen off and after leaving the app, on the lock screen
// and in Control Center, with headphone and media keys. Everything here is on the main thread.
//
// A queue can be long and a stream token runs out, so nothing is asked of the server until a track
// is about to play. A song the server converts is a pipe with no length and nothing to seek in: its
// length comes from the server, and a seek asks for a new stream from that time, which the player's
// clock then counts on from (`timeOffsetSec`).

/// One track in the queue.
struct QueuedTrack: Identifiable, Equatable {
    /// Unique within the app's queue, so the same song twice is still two rows.
    let id: Int
    let item: Item
    /// A book or a podcast: it keeps its place, and gets Back 15 and Forward 30 rather than Next.
    let keepsPlace: Bool

    var title: String { item.title }
    var artist: String { [item.artist, item.albumArtist].compactMap { $0 }.first { !$0.isEmpty } ?? "" }
    var album: String { item.album ?? "" }
    var durationSec: Double { item.runtimeSec ?? 0 }
}

/// A row of the queue as the screens show it, in the order it will play.
struct QueueRow: Identifiable, Equatable {
    /// Its place in the queue's list, which is what moving and removing go by.
    let index: Int
    let track: QueuedTrack
    var id: Int { track.id }
}

@MainActor
final class Listening: ObservableObject {
    static let backSeconds = 15.0
    static let forwardSeconds = 30.0
    /// The profile every Apple device shares for sound: they all play the same formats.
    private static let profile = "appletv"
    private static let bookSpeedKey = "listening.bookSpeed"

    @Published private(set) var now: QueuedTrack?
    /// Playing, or on its way to.
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var rows: [QueueRow] = []
    @Published private(set) var nowIndex = 0
    @Published private(set) var shuffle = false
    @Published private(set) var repeatMode: RepeatMode = .off
    @Published private(set) var speed: Float = 1
    @Published private(set) var canGoNext = false
    /// Said once it has given up. Empty means all is well.
    @Published private(set) var problem = ""
    /// Goes up when the place changes by other than playing, so a clock on screen looks again.
    @Published private(set) var jumps = 0
    /// The whole-screen player is showing.
    @Published var screenShown = false
    /// Opens it with the queue showing: the tablet bar's Queue button, as the website's.
    var screenWithQueue = false

    /// The website's sleep timer: stop at a time, or at the end of what's playing.
    enum Sleep: Equatable {
        case at(Date)
        case afterThis
    }
    @Published var sleep: Sleep? {
        didSet { scheduleSleep() }
    }
    private var sleepTask: Task<Void, Never>?

    var keepsPlace: Bool { now?.keepsPlace == true }
    /// Which kind each library is, for what lists of tracks don't say. Asked for once.
    var libraryTypes: [Int64: String] = [:]

    /// The deck that's playing. The website has two that take turns, so the next song can start right as this one
    /// ends, or cross into it: `standby` is the other.
    private var player = AVPlayer()
    private struct Standby {
        let entry: Int
        let trackId: Int
        let player: AVPlayer
        let item: AVPlayerItem
        let answer: Playback
        let tap: SoundTap?
    }
    private var standby: Standby?
    private var preparing: Int?
    private var handoffTask: Task<Void, Never>?
    private var fadeTask: Task<Void, Never>?
    private var fadingOut: AVPlayer?
    private var deckFade: [ObjectIdentifier: Float] = [:]
    /// How it sounds on this device: the website's Sound panel.
    @Published private(set) var sound = SoundStore().load()
    private var loudnessKnown: [Int64: Loudness] = [:]
    private var tap: SoundTap?
    private var queue = ListeningQueue<QueuedTrack>()
    private var serial = 0
    /// The connection this queue started on. Reports go with it, as the app may have moved on.
    private var client: WittyClient?
    private var stream: Playback?
    /// Goes up every time a new stream is asked for, so an answer that arrives late is ignored.
    private var generation = 0
    /// The place while a stream for it is on its way, so the clock doesn't jump back meanwhile.
    private var placeWhileOpening: Double?
    /// Where a file is to start once it's ready. A conversion already starts there.
    private var pendingSeek: Double?
    private var lastPlace = 0.0
    private var wantsToPlay = false
    private var ended = false
    private var suspendedForVideo = false
    private var resumeAfterInterruption = false
    /// Tracks this device couldn't decode, which the server converts from then on.
    private var converting = Set<Int64>()
    private var budget = RetryBudget()
    private var retryTask: Task<Void, Never>?
    private var savingTask: Task<Void, Never>?
    private var stallTask: Task<Void, Never>?
    private var pauseCheck: Task<Void, Never>?
    private var playingSince: Date?
    private var heardSeconds = 0.0
    private var monitor: NWPathMonitor?
    private var networkSeen: NWPath.Status?
    private var itemObservers: [NSObjectProtocol] = []
    private var statusObserver: NSKeyValueObservation?
    private var controlObserver: NSKeyValueObservation?
    private var timeObserver: Any?
    private var commandsAttached = false
    private var artwork: (id: Int64, art: MPMediaItemArtwork)?
    private var artworkLoading: Int64?
    private let defaults = UserDefaults.standard

    init() {
        watchPlayer()
        watchSession()
        applySound()
    }

    private func watchPlayer() {
        controlObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] observed, _ in
            let status = observed.timeControlStatus
            Task { @MainActor [weak self] in self?.controlChanged(status) }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 1), queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func unwatchPlayer() {
        controlObserver = nil
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
    }

    private var savedBookSpeed: Float {
        let saved = defaults.float(forKey: Self.bookSpeedKey)
        return saved > 0 ? saved : 1
    }

    private func made(_ item: Item, _ keepsPlace: Bool) -> QueuedTrack {
        serial += 1
        return QueuedTrack(id: serial, item: item, keepsPlace: keepsPlace)
    }

    // MARK: What the screens ask for

    /// A new queue, from this track and place.
    func play(_ tracks: [Item], start: ListeningStart, keepsPlace books: Bool, client: WittyClient) {
        guard !tracks.isEmpty else { return }
        _ = reportLeaving(reachedEnd: false)
        problem = ""
        self.client = client
        converting = []
        budget.reset()
        let mode = queue.repeatMode
        queue = ListeningQueue(tracks.map { made($0, books) }, start: start.index)
        queue.repeatMode = mode
        setSpeed(books ? savedBookSpeed : 1, save: false)
        ended = false
        publish()
        open(startSec: start.atSec, play: true)
    }

    /// At the end of the queue, or a queue of its own if there isn't one.
    func addToQueue(_ tracks: [Item], keepsPlace books: Bool, client: WittyClient) {
        guard !tracks.isEmpty else { return }
        if queue.isEmpty {
            play(tracks, start: ListeningStart(0), keepsPlace: books, client: client)
            return
        }
        queue.append(tracks.map { made($0, books) })
        publish()
        updateNowPlaying()
    }

    func positionSec() -> Double {
        if let placeWhileOpening { return placeWhileOpening }
        let at = player.currentTime().seconds
        guard at.isFinite, player.currentItem != nil else { return lastPlace }
        return max(0, at + (stream?.offset ?? 0))
    }

    /// The server's length first, so that a track says the same here as in the list it came from.
    func durationSec() -> Double {
        if let told = now?.durationSec, told > 0 { return told }
        if let told = stream?.durationSec, told > 0 { return told }
        let seen = player.currentItem?.duration.seconds ?? 0
        return seen.isFinite && seen > 0 ? seen : 0
    }

    /// Also Play on a finished queue, which starts it again, and Try again after it gave up.
    func toggle() {
        if !problem.isEmpty || player.currentItem?.status == .failed {
            tryAgain()
        } else if wantsToPlay {
            pause()
        } else {
            resume()
        }
    }

    func resume() {
        guard now != nil else { return }
        if !problem.isEmpty { tryAgain(); return }
        if ended, let first = queue.first {
            moveTo(first, play: true)
            return
        }
        wantsToPlay = true
        suspendedForVideo = false
        activateSession()
        attachCommands()
        if player.currentItem == nil {
            open(startSec: lastPlace, play: true)
        } else if pendingSeek == nil {
            player.play()
        }
        publish()
        updateNowPlaying()
    }

    func pause() {
        wantsToPlay = false
        resumeAfterInterruption = false
        handoffTask?.cancel()
        handoffTask = nil
        finishFade()
        player.pause()
        publish()
        updateNowPlaying()
    }

    /// A film has started: the sound stops, and the film's own player has the lock screen.
    func pauseForVideo() {
        guard now != nil else { return }
        pause()
        suspendedForVideo = true
        detachCommands()
    }

    func next() {
        if let next = queue.next { moveTo(next, play: wantsToPlay) }
    }

    /// The start of this one, unless it has only just begun and there's one before it.
    func previous() {
        if positionSec() > ListeningRules.previousRestartsAfterSeconds || queue.previous == nil {
            seek(to: 0)
        } else if let previous = queue.previous {
            moveTo(previous, play: wantsToPlay)
        }
    }

    /// Choosing one in the queue plays it.
    func jump(to index: Int) {
        moveTo(index, play: true)
    }

    func seek(to seconds: Double) {
        guard now != nil else { return }
        let duration = durationSec()
        let target = max(0, duration > 0 ? min(seconds, duration) : seconds)
        ended = false
        jumps += 1
        handoffTask?.cancel()
        handoffTask = nil
        guard let stream, placeWhileOpening == nil, player.currentItem?.status == .readyToPlay else {
            open(startSec: target, play: wantsToPlay)
            return
        }
        let seekable = player.currentItem?.seekableTimeRanges.last?.timeRangeValue.end.seconds
        switch stream.seekPlan(toFilm: target, seekableEnd: seekable) {
        case .inPlayer(let at):
            lastPlace = target
            player.seek(to: CMTime(seconds: at, preferredTimescale: 600)) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.jumps += 1
                    self?.updateNowPlaying()
                }
            }
        case .reopen(let at):
            open(startSec: at, play: wantsToPlay)
        }
        updateNowPlaying()
    }

    func seek(by seconds: Double) { seek(to: positionSec() + seconds) }

    func remove(_ index: Int) {
        if index == queue.current { _ = reportLeaving(reachedEnd: false) }
        let wasNow = queue.remove(at: index)
        if queue.isEmpty {
            stop()
            return
        }
        publish()
        if wasNow { open(startSec: 0, play: wantsToPlay) } else { updateNowPlaying() }
    }

    func move(from: Int, to: Int) {
        queue.move(from: from, to: to)
        publish()
        updateNowPlaying()
    }

    func toggleShuffle() {
        queue.setShuffled(!queue.shuffled)
        publish()
        updateNowPlaying()
    }

    func cycleRepeat() {
        queue.repeatMode = queue.repeatMode.next
        publish()
    }

    /// A speed chosen from the list in Now Playing.
    func choose(speed: Float) {
        setSpeed(speed, save: keepsPlace)
    }

    /// Takes away everything after the one playing, which carries on.
    func clearUpNext() {
        guard let at = rows.firstIndex(where: { $0.index == queue.current }) else { return }
        for index in rows.suffix(from: at + 1).map(\.index).sorted(by: >) {
            _ = queue.remove(at: index)
        }
        publish()
        updateNowPlaying()
    }

    private func scheduleSleep() {
        sleepTask?.cancel()
        sleepTask = nil
        guard case .at(let when) = sleep else { return }
        sleepTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, when.timeIntervalSinceNow) * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.pause()
            self.sleep = nil
        }
    }

    func cycleSpeed() {
        setSpeed(ListeningRules.nextSpeed(after: speed), save: keepsPlace)
    }

    private func setSpeed(_ chosen: Float, save: Bool) {
        speed = chosen
        player.defaultRate = chosen
        if player.rate > 0 { player.rate = chosen }
        if save { defaults.set(chosen, forKey: Self.bookSpeedKey) }
        updateNowPlaying()
    }

    // MARK: The sound

    /// A change from the Sound panel or karaoke. The voice and the key aren't kept for another day.
    func setSound(_ change: (inout SoundSettings) -> Void) {
        var next = sound
        change(&next)
        guard next != sound else { return }
        let leveling = next.replayGain != sound.replayGain
        sound = next
        SoundStore().save(next)
        applySound()
        if leveling { loadLoudness() }
    }

    private func applySound() {
        let now = sound
        SoundEngine.shared.set {
            $0.eqOn = now.eqOn
            $0.gains = now.eqGains
            $0.preampDb = now.preamp
            $0.vocalCut = now.vocalCut
            $0.keyShift = now.keyShift
        }
        level(player)
        if let fadingOut { level(fadingOut) }
    }

    /// How loud a deck is: the volume, times where it is in a crossfade.
    private func level(_ deck: AVPlayer) {
        deck.volume = Float(sound.muted ? 0 : sound.volume) * (deckFade[ObjectIdentifier(deck)] ?? 1)
    }

    /// A song tagged with how loud it is, brought to one level: music only.
    private func loadLoudness() {
        guard let track = queue.now, !track.keepsPlace, sound.replayGain != .off, let client else {
            SoundEngine.shared.set { $0.loudnessDb = 0 }
            return
        }
        let id = track.item.id
        let choice = sound.replayGain
        if let known = loudnessKnown[id] {
            SoundEngine.shared.set { $0.loudnessDb = known.gain(choice) }
            return
        }
        Task { [weak self] in
            guard let found = try? await client.loudness(item: id), let self else { return }
            self.loudnessKnown[id] = found
            guard self.queue.now?.item.id == id else { return }
            SoundEngine.shared.set { $0.loudnessDb = found.gain(self.sound.replayGain) }
        }
    }

    // MARK: Between songs

    /// As a song plays: the next one made ready on the other deck, then started at the right moment, right as this
    /// one ends or crossing into it (the website's watchEnd). Only songs sent as they are.
    private func watchEnd() {
        #if os(iOS) || os(visionOS)
        guard let track = queue.now, !track.keepsPlace, wantsToPlay, placeWhileOpening == nil, queue.repeatMode != .one,
              sleep != .afterThis, sound.gapless || sound.crossfade > 0, player.timeControlStatus == .playing else { return }
        let duration = durationSec()
        guard duration > 0, let entry = queue.afterEnd, entry != queue.current else { return }
        let next = queue.entries[entry]
        let left = (duration - positionSec()) / Double(max(speed, 0.1))
        let crossing = sound.fade(from: track.album, to: next.album)
        guard left <= crossing + 20 else { return }
        guard let ready = standby, ready.trackId == next.id else {
            if preparing != next.id { prepare(entry, next) }
            return
        }
        if handoffTask == nil, left <= crossing + 1.5, ready.item.status == .readyToPlay {
            let wait = max(0, left - crossing - 0.025)
            handoffTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                self.handoffTask = nil
                self.handOff(crossing)
            }
        }
        #endif
    }

    private func prepare(_ entry: Int, _ next: QueuedTrack) {
        dropStandby()
        guard let client else { return }
        preparing = next.id
        let run = generation
        let request = PlaybackRequest(profile: Self.profile, startSec: 0, forceTranscode: nil)
        Task { [weak self] in
            guard let answer = try? await client.playback(next.item.id, request), answer.decision == "audio-direct",
                  let url = client.mediaURL(answer.url) else { return }
            let item = AVPlayerItem(url: url)
            item.audioTimePitchAlgorithm = .timeDomain
            let found = await SoundEngine.shared.attach(to: item)
            guard let self, run == self.generation, self.preparing == next.id else { return }
            let deck = AVPlayer(playerItem: item)
            deck.defaultRate = self.speed
            self.deckFade[ObjectIdentifier(deck)] = 0
            self.level(deck)
            self.standby = Standby(entry: entry, trackId: next.id, player: deck, item: item, answer: answer, tap: found)
        }
    }

    /// The next song starts on the other deck, which becomes the one playing; the old one fades out, or stops.
    private func handOff(_ seconds: Double) {
        guard let ready = standby, wantsToPlay, ready.item.status == .readyToPlay, queue.entries.indices.contains(ready.entry),
              queue.entries[ready.entry].id == ready.trackId else { return }
        let left = (durationSec() - positionSec()) / Double(max(speed, 0.1))
        guard left <= seconds + 2 else { return }
        standby = nil
        preparing = nil
        // What was playing counts as heard to its end.
        if let track = queue.now {
            foldHeard()
            _ = report(track, positionSec: durationSec(), reachedEnd: true)
            heardSeconds = 0
        }
        generation += 1
        let old = player
        removeItemObservers()
        unwatchPlayer()
        player = ready.player
        watchPlayer()
        queue.jump(to: ready.entry)
        stream = ready.answer
        tap = ready.tap
        SoundEngine.shared.listen(to: ready.tap)
        observe(ready.item, run: generation)
        deckFade[ObjectIdentifier(player)] = seconds > 0 ? 0 : 1
        level(player)
        player.playImmediately(atRate: speed)
        placeWhileOpening = nil
        pendingSeek = nil
        lastPlace = 0
        ended = false
        jumps += 1
        publish()
        updateNowPlaying()
        loadLoudness()
        fadingOut = old
        let oldId = ObjectIdentifier(old)
        fadeTask?.cancel()
        fadeTask = Task { [weak self] in
            if seconds <= 0 {
                try? await Task.sleep(nanoseconds: 400_000_000)
            } else {
                // Equal power, so the middle of the fade isn't a dip.
                let began = Date()
                while !Task.isCancelled {
                    let part = min(1, Date().timeIntervalSince(began) / seconds)
                    guard let self else { return }
                    self.deckFade[ObjectIdentifier(self.player)] = Float(sin(part * .pi / 2))
                    self.deckFade[oldId] = Float(cos(part * .pi / 2))
                    self.level(self.player)
                    self.level(old)
                    if part >= 1 { break }
                    try? await Task.sleep(nanoseconds: 60_000_000)
                }
            }
            guard !Task.isCancelled, let self else { return }
            self.finishFade()
        }
    }

    /// The deck going out stops now.
    private func finishFade() {
        fadeTask?.cancel()
        fadeTask = nil
        if let old = fadingOut {
            old.pause()
            old.replaceCurrentItem(with: nil)
            deckFade[ObjectIdentifier(old)] = nil
        }
        fadingOut = nil
        if deckFade[ObjectIdentifier(player)] != 1 {
            deckFade[ObjectIdentifier(player)] = 1
            level(player)
        }
    }

    private func dropStandby() {
        handoffTask?.cancel()
        handoffTask = nil
        preparing = nil
        if let ready = standby {
            ready.player.replaceCurrentItem(with: nil)
            deckFade[ObjectIdentifier(ready.player)] = nil
        }
        standby = nil
    }

    /// Clears the queue. Where it got to is saved first.
    func stop() {
        problem = ""
        sleep = nil
        _ = reportLeaving(reachedEnd: false)
        clearAll()
    }

    /// Leaving a server or an account. The last place is on its way before the sign-in ends, so the
    /// caller can wait for it, and nothing keeps playing for the next person.
    @discardableResult
    func forget() -> Task<Void, Never>? {
        let sent = reportLeaving(reachedEnd: false)
        clearAll()
        problem = ""
        sleep = nil
        client = nil
        libraryTypes = [:]
        return sent
    }

    /// A person pressing Try again, or Play, after it gave up.
    func tryAgain() {
        budget.reset()
        retryTask?.cancel()
        stopWaitingForNetwork()
        problem = ""
        open(startSec: placeWhileOpening ?? lastPlace, play: true)
    }

    // MARK: Opening a track

    private func moveTo(_ index: Int, play: Bool) {
        _ = reportLeaving(reachedEnd: false)
        budget.reset()
        problem = ""
        queue.jump(to: index)
        ended = false
        publish()
        open(startSec: 0, play: play)
    }

    private func open(startSec: Double, play: Bool) {
        guard let track = queue.now, let client else { return }
        generation += 1
        let run = generation
        retryTask?.cancel()
        stallTask?.cancel()
        dropStandby()
        finishFade()
        wantsToPlay = play
        ended = false
        placeWhileOpening = startSec
        lastPlace = startSec
        pendingSeek = nil
        jumps += 1
        if play {
            suspendedForVideo = false
            activateSession()
        }
        attachCommands()
        player.pause()
        publish()
        updateNowPlaying()
        let request = PlaybackRequest(profile: Self.profile, startSec: startSec, forceTranscode: converting.contains(track.item.id) ? true : nil)
        Task { [weak self] in
            do {
                let answer = try await client.playback(track.item.id, request)
                guard let self, run == self.generation else { return }
                guard let url = client.mediaURL(answer.url) else {
                    self.failed(APIError(status: 0, message: "The server sent an address that can't be used."), giveUp: true)
                    return
                }
                await self.load(url, answer: answer, startSec: startSec, run: run)
            } catch {
                guard let self, run == self.generation, !(error is CancellationError) else { return }
                self.failed(error)
            }
        }
    }

    private func load(_ url: URL, answer: Playback, startSec: Double, run: Int) async {
        let next = AVPlayerItem(url: url)
        // Speech at a faster speed stays clear with this, and it costs nothing for music.
        next.audioTimePitchAlgorithm = .timeDomain
        #if os(iOS) || os(visionOS)
        // The Sound panel's tap goes on first: the player would read the same tracks before playing anyway.
        let found = await SoundEngine.shared.attach(to: next)
        guard run == generation else { return }
        tap = found
        SoundEngine.shared.listen(to: found)
        #endif
        stream = answer
        observe(next, run: run)
        // A file is told where to start once it's ready. A conversion starts there already.
        if !answer.mustReopenToSeekFar {
            let at = answer.startAtSec ?? startSec
            pendingSeek = at > 0.5 ? at : nil
        }
        deckFade[ObjectIdentifier(player)] = 1
        level(player)
        player.replaceCurrentItem(with: next)
        if wantsToPlay, pendingSeek == nil { player.play() }
        loadLoudness()
    }

    private func observe(_ next: AVPlayerItem, run: Int) {
        removeItemObservers()
        let itemId = ObjectIdentifier(next)
        itemObservers.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: next, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reachedEnd(itemId) }
        })
        itemObservers.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: next, queue: .main) { [weak self] note in
            let problem = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor [weak self] in self?.itemFailed(itemId, problem) }
        })
        statusObserver = next.observe(\.status, options: [.new]) { [weak self] observed, _ in
            let status = observed.status
            let problem = observed.error
            Task { @MainActor [weak self] in
                switch status {
                case .readyToPlay: await self?.becameReady(itemId, run: run)
                case .failed: self?.itemFailed(itemId, problem)
                default: break
                }
            }
        }
    }

    private func isCurrent(_ itemId: ObjectIdentifier) -> Bool {
        player.currentItem.map { ObjectIdentifier($0) == itemId } ?? false
    }

    private func becameReady(_ itemId: ObjectIdentifier, run: Int) async {
        guard run == generation, isCurrent(itemId), placeWhileOpening != nil else { return }
        if let at = pendingSeek {
            let near = CMTime(seconds: 0.5, preferredTimescale: 600)
            _ = await player.seek(to: CMTime(seconds: at, preferredTimescale: 600), toleranceBefore: near, toleranceAfter: near)
            guard run == generation, isCurrent(itemId) else { return }
        }
        pendingSeek = nil
        placeWhileOpening = nil
        stopWaitingForNetwork()
        if wantsToPlay { player.play() }
        jumps += 1
        publish()
        updateNowPlaying()
    }

    // MARK: Ends and failures

    private func reachedEnd(_ itemId: ObjectIdentifier) {
        guard isCurrent(itemId), let track = queue.now else { return }
        // A conversion that stops well short of the length dropped, rather than ended.
        let duration = durationSec()
        if stream?.mustReopenToSeekFar == true, duration > 0, positionSec() < duration - 3 {
            failed(URLError(.networkConnectionLost))
            return
        }
        foldHeard()
        _ = report(track, positionSec: duration, reachedEnd: true)
        heardSeconds = 0
        if let next = queue.afterEnd {
            // The sleep timer's "after this one": the next is ready, and waits for Play.
            let goOn = sleep != .afterThis
            if !goOn {
                sleep = nil
                wantsToPlay = false
            }
            queue.jump(to: next)
            publish()
            open(startSec: 0, play: goOn)
        } else {
            if sleep == .afterThis { sleep = nil }
            // The end of the queue. It stays, and Play starts it again.
            ended = true
            wantsToPlay = false
            lastPlace = duration
            publish()
            updateNowPlaying()
        }
    }

    private func itemFailed(_ itemId: ObjectIdentifier, _ problem: Error?) {
        guard isCurrent(itemId) else { return }
        removeItemObservers()
        failed(problem)
    }

    /// The same rules as a film: docs/CLIENT-API.md, "What a TV app must build itself".
    private func failed(_ error: Error?, giveUp: Bool = false) {
        guard let track = queue.now else { return }
        let recovery = giveUp ? ListeningRecovery.giveUp : ListeningRules.recovery(for: error)
        let id = track.item.id
        let place = placeWhileOpening ?? lastPlace
        let status = (error as? APIError)?.status
        let wait = recovery == .giveUp || (recovery == .convert && converting.contains(id)) ? nil : budget.next()
        let detail = error.map { found -> String in
            let ns = found as NSError
            return "\(ns.domain) \(ns.code)"
        } ?? "no details"
        stallTask?.cancel()
        // The sign-in has gone: every other track would fail the same way, so nothing moves on.
        if (error as? APIError)?.isExpiredSignIn == true {
            stopWith("The server no longer accepts this sign-in. Sign in again to carry on.", at: place)
            return
        }
        ClientLog.shared.report(wait != nil ? "warn" : "error", "player", "Listening failed: \(detail)\(wait != nil ? ", trying again" : "")")
        if let wait {
            if recovery == .convert { converting.insert(id) }
            placeWhileOpening = place
            let run = generation
            let play = wantsToPlay
            retryTask?.cancel()
            retryTask = Task { [weak self] in
                if recovery == .waitThenNewStream { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
                guard !Task.isCancelled, let self, run == self.generation else { return }
                self.open(startSec: place, play: play)
            }
            publish()
            return
        }
        let words = ListeningRules.failureWords(recovery, status: status)
        if recovery == .waitThenNewStream {
            // With the network down the next track won't play either, so wait for it to come back.
            stopWith(words, at: place)
            waitForNetwork()
        } else if let next = queue.next {
            // One bad file shouldn't end an album.
            moveTo(next, play: wantsToPlay)
        } else {
            stopWith(words, at: place)
        }
    }

    private func stopWith(_ words: String, at place: Double) {
        problem = words
        wantsToPlay = false
        placeWhileOpening = nil
        lastPlace = place
        player.pause()
        publish()
        updateNowPlaying()
    }

    // MARK: What the player says

    private func controlChanged(_ status: AVPlayer.TimeControlStatus) {
        let playing = status == .playing
        if playing, playingSince == nil {
            startedPlaying()
        } else if !playing, playingSince != nil {
            stoppedPlaying()
        }
        // Stuck waiting for far longer than a slow network explains. The player would wait for ever.
        stallTask?.cancel()
        if status == .waitingToPlayAtSpecifiedRate, player.reasonForWaitingToPlay != .noItemToPlay, let current = player.currentItem {
            let itemId = ObjectIdentifier(current)
            stallTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled, let self, self.isCurrent(itemId), self.wantsToPlay else { return }
                self.failed(URLError(.timedOut))
            }
        }
        // Paused by the system rather than by a person here: a call, or headphones unplugged.
        pauseCheck?.cancel()
        if status == .paused, wantsToPlay, placeWhileOpening == nil {
            pauseCheck = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard !Task.isCancelled, let self, self.player.timeControlStatus == .paused, self.wantsToPlay,
                      self.placeWhileOpening == nil, !self.ended else { return }
                self.wantsToPlay = false
                self.publish()
                self.updateNowPlaying()
            }
        }
        publish()
        updateNowPlaying()
    }

    private func tick() {
        guard placeWhileOpening == nil, player.currentItem != nil else { return }
        let at = positionSec()
        if at.isFinite { lastPlace = at }
        watchEnd()
    }

    // MARK: Telling the server

    private func heard() -> Double {
        heardSeconds + (playingSince.map { Date().timeIntervalSince($0) } ?? 0)
    }

    /// The time heard so far counts as heard, and the clock starts again from now.
    private func foldHeard() {
        if let since = playingSince {
            heardSeconds += Date().timeIntervalSince(since)
            playingSince = Date()
        }
    }

    private func startedPlaying() {
        playingSince = Date()
        problem = ""
        savingTask?.cancel()
        savingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(PlaybackClock.saveEverySeconds * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                self.budget.played(seconds: PlaybackClock.saveEverySeconds)
                if let track = self.queue.now, track.keepsPlace { _ = self.report(track, positionSec: self.positionSec(), reachedEnd: false) }
            }
        }
    }

    private func stoppedPlaying() {
        savingTask?.cancel()
        foldHeard()
        playingSince = nil
        // Saving on pause means a device that dies during a pause loses nothing.
        if let track = queue.now, track.keepsPlace, !ended, placeWhileOpening == nil {
            _ = report(track, positionSec: positionSec(), reachedEnd: false)
        }
    }

    /// Sent with the connection this queue started on.
    private func report(_ track: QueuedTrack, positionSec: Double, reachedEnd: Bool) -> Task<Void, Never>? {
        guard let client else { return nil }
        let duration = track.durationSec > 0 ? track.durationSec : (stream?.durationSec ?? 0)
        guard let what = ListeningRules.report(keepsPlace: track.keepsPlace, positionSec: positionSec, durationSec: duration,
                                               listenedSec: heard(), reachedEnd: reachedEnd) else { return nil }
        let id = track.item.id
        return Task.detached {
            switch what {
            case .place(let at, let length): try? await client.saveProgress(id, positionSec: at, durationSec: length)
            case .listened(let seconds): try? await client.recordListen(id, seconds: seconds)
            }
        }
    }

    /// Where the one playing got to, as the player moves on from it.
    private func reportLeaving(reachedEnd: Bool) -> Task<Void, Never>? {
        guard let track = queue.now else { return nil }
        let sent = report(track, positionSec: positionSec(), reachedEnd: reachedEnd)
        heardSeconds = 0
        if playingSince != nil { playingSince = Date() }
        return sent
    }

    // MARK: The network

    /// Nothing is polled. When the network comes back after it was the reason for stopping, carry on.
    private func waitForNetwork() {
        guard monitor == nil else { return }
        let watching = NWPathMonitor()
        watching.pathUpdateHandler = { [weak self] path in
            let status = path.status
            Task { @MainActor [weak self] in self?.networkChanged(status) }
        }
        networkSeen = nil
        watching.start(queue: DispatchQueue.global(qos: .utility))
        monitor = watching
    }

    private func networkChanged(_ status: NWPath.Status) {
        guard monitor != nil else { return }
        let before = networkSeen
        networkSeen = status
        // The first answer is how things are now, which is what just failed.
        guard let before, before != .satisfied, status == .satisfied else { return }
        tryAgain()
    }

    private func stopWaitingForNetwork() {
        monitor?.cancel()
        monitor = nil
        networkSeen = nil
    }

    // MARK: Keeping the screens up to date

    private func publish() {
        let current = queue.now
        if now != current { now = current }
        if nowIndex != queue.current { nowIndex = queue.current }
        if shuffle != queue.shuffled { shuffle = queue.shuffled }
        if repeatMode != queue.repeatMode { repeatMode = queue.repeatMode }
        let canNext = queue.next != nil
        if canGoNext != canNext { canGoNext = canNext }
        let order = queue.order.map { QueueRow(index: $0, track: queue.entries[$0]) }
        if rows != order { rows = order }
        let intends = wantsToPlay && current != nil
        if isPlaying != intends { isPlaying = intends }
        let loading = wantsToPlay && (placeWhileOpening != nil || player.timeControlStatus == .waitingToPlayAtSpecifiedRate)
        if isLoading != loading { isLoading = loading }
        if current == nil, screenShown { screenShown = false }
        enableCommands()
    }

    private func removeItemObservers() {
        for observer in itemObservers { NotificationCenter.default.removeObserver(observer) }
        itemObservers = []
        statusObserver = nil
    }

    private func clearAll() {
        generation += 1
        retryTask?.cancel()
        savingTask?.cancel()
        stallTask?.cancel()
        pauseCheck?.cancel()
        stopWaitingForNetwork()
        removeItemObservers()
        dropStandby()
        finishFade()
        player.pause()
        player.replaceCurrentItem(with: nil)
        let mode = queue.repeatMode
        queue = ListeningQueue()
        queue.repeatMode = mode
        stream = nil
        ended = false
        wantsToPlay = false
        placeWhileOpening = nil
        pendingSeek = nil
        lastPlace = 0
        heardSeconds = 0
        playingSince = nil
        converting = []
        artwork = nil
        detachCommands()
        deactivateSession()
        publish()
    }

    // MARK: The audio session

    /// Without `.playback` nothing is heard with the silent switch on, or once the app has gone.
    /// Speech ducks differently from music, and pauses instead when a notification sounds.
    private func activateSession() {
        #if !os(macOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: keepsPlace ? .spokenAudio : .default)
            try session.setActive(true)
        } catch {
            ClientLog.shared.warn("player", "The audio session couldn't start: \((error as NSError).code)")
        }
        #endif
    }

    private func deactivateSession() {
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    /// The player pauses itself for a call and for headphones coming out. Only the system knows if it
    /// should carry on after a call.
    private func watchSession() {
        #if !os(macOS)
        let centre = NotificationCenter.default
        _ = centre.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor [weak self] in self?.interrupted(raw.flatMap { AVAudioSession.InterruptionType(rawValue: $0) }, options: options) }
        }
        _ = centre.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor [weak self] in
                guard let self, raw.flatMap({ AVAudioSession.RouteChangeReason(rawValue: $0) }) == .oldDeviceUnavailable, self.wantsToPlay else { return }
                self.pause()
            }
        }
        #endif
    }

    #if !os(macOS)
    private func interrupted(_ type: AVAudioSession.InterruptionType?, options: UInt?) {
        guard now != nil, !suspendedForVideo else { return }
        switch type {
        case .began?:
            resumeAfterInterruption = wantsToPlay
            wantsToPlay = false
            publish()
            updateNowPlaying()
        case .ended?:
            let resume = options.map { AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume) } ?? false
            if resume, resumeAfterInterruption { self.resume() }
            resumeAfterInterruption = false
        default:
            break
        }
    }
    #endif

    // MARK: The lock screen, Control Center, headphones and media keys

    private func attachCommands() {
        guard !commandsAttached else { return }
        commandsAttached = true
        let centre = MPRemoteCommandCenter.shared()
        func on(_ command: MPRemoteCommand, _ act: @escaping @MainActor (Listening, MPRemoteCommandEvent) -> Void) {
            command.addTarget { [weak self] event in
                Task { @MainActor [weak self] in if let self { act(self, event) } }
                return .success
            }
        }
        on(centre.playCommand) { listening, _ in listening.resume() }
        on(centre.pauseCommand) { listening, _ in listening.pause() }
        on(centre.togglePlayPauseCommand) { listening, _ in listening.toggle() }
        on(centre.nextTrackCommand) { listening, _ in listening.next() }
        on(centre.previousTrackCommand) { listening, _ in listening.previous() }
        on(centre.skipBackwardCommand) { listening, _ in listening.seek(by: -Self.backSeconds) }
        on(centre.skipForwardCommand) { listening, _ in listening.seek(by: Self.forwardSeconds) }
        on(centre.changePlaybackPositionCommand) { listening, event in
            if let event = event as? MPChangePlaybackPositionCommandEvent { listening.seek(to: event.positionTime) }
        }
        on(centre.changePlaybackRateCommand) { listening, event in
            if let event = event as? MPChangePlaybackRateCommandEvent, listening.keepsPlace { listening.setSpeed(event.playbackRate, save: true) }
        }
        centre.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.backSeconds)]
        centre.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.forwardSeconds)]
        centre.changePlaybackRateCommand.supportedPlaybackRates = ListeningRules.speeds.map { NSNumber(value: $0) }
        enableCommands()
    }

    /// The same words for the system as for a person: books get Back and Forward on the lock screen,
    /// as Next would lose a place, and songs get Previous and Next.
    private func enableCommands() {
        guard commandsAttached else { return }
        let centre = MPRemoteCommandCenter.shared()
        let books = keepsPlace
        centre.nextTrackCommand.isEnabled = !books && canGoNext
        centre.previousTrackCommand.isEnabled = !books
        centre.skipBackwardCommand.isEnabled = books
        centre.skipForwardCommand.isEnabled = books
        centre.changePlaybackRateCommand.isEnabled = books
        centre.changePlaybackPositionCommand.isEnabled = true
    }

    private func detachCommands() {
        guard commandsAttached else { return }
        commandsAttached = false
        let centre = MPRemoteCommandCenter.shared()
        for command in [centre.playCommand, centre.pauseCommand, centre.togglePlayPauseCommand, centre.nextTrackCommand,
                        centre.previousTrackCommand, centre.skipBackwardCommand, centre.skipForwardCommand,
                        centre.changePlaybackPositionCommand, centre.changePlaybackRateCommand] {
            command.removeTarget(nil)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        #endif
    }

    private func updateNowPlaying() {
        guard commandsAttached, let track = queue.now else { return }
        let order = queue.order
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: durationSec(),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: positionSec(),
            MPNowPlayingInfoPropertyPlaybackRate: player.timeControlStatus == .playing ? Double(speed) : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(speed),
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: order.firstIndex(of: queue.current) ?? 0,
            MPNowPlayingInfoPropertyPlaybackQueueCount: order.count,
        ]
        if let artwork, artwork.id == track.item.id {
            info[MPMediaItemPropertyArtwork] = artwork.art
        } else {
            loadArtwork(track.item)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = wantsToPlay ? .playing : .paused
        #endif
    }

    /// The cover from the server, with the sign-in. A picture is a nice extra, and has to be small
    /// enough to hand around.
    private func loadArtwork(_ item: Item) {
        guard artworkLoading != item.id, let client, let url = client.posterURL(item) else { return }
        artworkLoading = item.id
        Task { [weak self] in
            defer { if self?.artworkLoading == item.id { self?.artworkLoading = nil } }
            guard let data = try? await client.imageData(url), data.count <= 4 * 1024 * 1024 else { return }
            let decoded = await Task.detached(priority: .utility) { decodeArt(data, maxPixels: 600) }.value
            guard let self, let decoded, self.queue.now?.item.id == item.id else { return }
            #if os(macOS)
            let image = NSImage(cgImage: decoded, size: NSSize(width: decoded.width, height: decoded.height))
            #else
            let image = UIImage(cgImage: decoded)
            #endif
            let art = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.artwork = (item.id, art)
            self.updateNowPlaying()
        }
    }
}
