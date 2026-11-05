package com.wittywilla.wittymediaclient.net

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// What the server sends, keeping only the fields this app uses. Times are in
// seconds and may be fractional. Lists may arrive as null.

@Serializable
data class ServerStatus(
    val name: String = "",
    val version: String = "",
    val setupRequired: Boolean = false,
    val brandName: String = "",
    // The version of the server's own logo, or empty for the app's mark.
    val brandLogo: String = "",
    val theme: String = "default",
    val user: User? = null,
)

@Serializable
data class User(
    val id: Long = 0,
    val name: String = "",
    // The profile name, which anyone may choose. Empty means the username.
    val displayName: String = "",
    // The corner of the server's pages shows the username instead of the profile name.
    val showUsername: Boolean = false,
    val twoFactor: Boolean = false,
    val isAdmin: Boolean = false,
    val kind: String = "adult",
)

@Serializable
data class Profile(
    val id: Long = 0,
    // The username, which signing in needs.
    val name: String = "",
    val displayName: String = "",
    val kind: String = "adult",
    val hasPassword: Boolean = true,
)

@Serializable
data class Profiles(val style: String = "classic", val profiles: List<Profile> = emptyList())

@Serializable
data class LoginResult(val token: String = "", val user: User? = null)

@Serializable
data class Library(
    val id: Long = 0,
    val name: String = "",
    val type: String = "",
    val console: String = "",
    val itemCount: Int = 0,
)

@Serializable
data class Progress(
    val positionSec: Double = 0.0,
    val durationSec: Double = 0.0,
    val watched: Boolean = false,
    val resumeSec: Double = 0.0, // where Resume goes; 0 means start over
    val updatedAt: Long = 0,
)

@Serializable
data class Item(
    val id: Long = 0,
    val libraryId: Long = 0,
    val kind: String = "video",
    val title: String = "",
    val year: Int? = null,
    val overview: String = "",
    val genres: List<String> = emptyList(),
    val contentRating: String = "",
    val runtimeSec: Double = 0.0,
    val updatedAt: Long = 0,
    val progress: Progress? = null,
    val showId: Long? = null,
    val showTitle: String? = null,
    val season: Int? = null,
    val episode: Int? = null,
    val episodeEnd: Int? = null,
    val nextId: Long? = null,
    val introStart: Double? = null,
    val introEnd: Double? = null,
    val console: String = "",
    val tagline: String = "",
    // Worked out by the server from its list of formats, so no client keeps a list of its own.
    val audioDirect: Boolean = false,
    val reader: String = "",
    val album: String = "",
    val albumArtist: String = "",
    val artist: String = "",
    val track: Int? = null,
)

// An album, a book or a podcast: the server groups them from their tracks, so these have no ID of
// their own. `coverItem` is a track whose poster is the cover.
@Serializable
data class Album(
    val artist: String = "",
    val title: String = "",
    val year: Int? = null,
    val tracks: Int = 0,
    val durationSec: Double = 0.0,
    val coverItem: Long = 0,
)

@Serializable
data class Artist(
    val name: String = "",
    val albums: Int = 0,
    val tracks: Int = 0,
    val coverItem: Long = 0,
)

@Serializable
data class Show(
    val id: Long = 0,
    val title: String = "",
    val year: Int? = null,
    val overview: String = "",
    val updatedAt: Long = 0,
    val episodeCount: Int = 0,
    val seasonCount: Int = 0,
    val unwatched: Int = 0,
)

@Serializable
data class Season(
    val number: Int = 0,
    val title: String = "",
    val episodeCount: Int = 0,
    val unwatched: Int = 0,
)

@Serializable
data class ShowDetail(
    val show: Show = Show(),
    val seasons: List<Season> = emptyList(),
    val episodes: List<Item> = emptyList(),
    val nextUpId: Long? = null,
)

@Serializable
data class Hub(
    val key: String = "",
    val title: String = "",
    val libraryId: Long? = null,
    val items: List<Item> = emptyList(),
    val shows: List<Show> = emptyList(),
)

@Serializable
data class Home(
    val hubs: List<Hub> = emptyList(),
    val featured: List<Item> = emptyList(),
    val libraries: List<Library> = emptyList(),
)

// One programme in the guide. Times are seconds since 1970, as the server sends them.
@Serializable
data class GuideProgramme(
    val start: Long = 0,
    val end: Long = 0,
    // `show`, `filler`, `slate`, `broadcast` or `none`. A slate is the channel's own "back soon".
    val kind: String? = null,
    val title: String = "",
    val sub: String? = null,
    val desc: String? = null,
    val genre: String? = null,
    val rating: String? = null,
    val year: Int? = null,
    // What in the library it plays, for a library channel.
    val itemId: Long? = null,
    val showId: Long? = null,
    val season: Int? = null,
    val episode: Int? = null,
) {
    fun isOn(now: Long) = start <= now && now < end
}

// Whether a channel is encrypted, in the server's words: every client shows the same.
@Serializable
data class GuideSecurity(val state: String = "", val label: String = "", val detail: String = "")

// The same station another way, for one that can't be watched as it is.
@Serializable
data class GuideAlternative(val key: String = "", val number: String = "", val name: String = "")

// The name a channel's logo goes by in the logo service.
@Serializable
data class GuideBrand(val kind: String = "", val name: String = "")

// One channel from GET /guide. Channels and tuners aren't items, so they don't go through /playback.
@Serializable
data class GuideChannel(
    val key: String = "",
    // `library` or `tuner`.
    val kind: String? = null,
    val number: String = "",
    val name: String = "",
    val group: String? = null,
    val radio: Boolean? = null,
    val hd: Boolean? = null,
    val atsc3: Boolean? = null,
    val encrypted: String = "", // why it can't be tuned: this server never decrypts a broadcast
    // Whether Record is offered: the server's word alone, and missing means no. Only tuner channels the profile may
    // record ever have it; no app works it out for itself (docs/APP-DESIGN.md, On a TV).
    val canRecord: Boolean? = null,
    val noRecord: String? = null,
    val security: GuideSecurity? = null,
    val alternative: GuideAlternative? = null,
    val notices: List<String>? = null,
    val description: String? = null,
    val categories: List<String>? = null,
    // The channel's own colour.
    val accent: String? = null,
    val favourite: Boolean = false,
    val brand: GuideBrand? = null,
    // The owner's picture for it, as an address on the server. Not every channel has one.
    val logo: String? = null,
    val programmes: List<GuideProgramme> = emptyList(),
) {
    val canTune: Boolean get() = encrypted.isEmpty()
}

// A page of the guide. The look the server's owner starts people on comes with it: `layout` and `skin` are from before
// there were themes. How many channels there are with what was asked, where this page starts, and the groups.
@Serializable
data class Guide(
    val channels: List<GuideChannel> = emptyList(),
    val theme: String? = null,
    val layout: String? = null,
    val skin: String? = null,
    val total: Int? = null,
    val offset: Int? = null,
    val groups: List<String>? = null,
)

// What GET /tv/{key}/tune answers: the stream, what's on and next, and what the server says about the channel.
@Serializable
data class Tuned(
    val url: String? = null,
    val streamUrl: String? = null,
    val key: String? = null,
    val number: String? = null,
    val name: String? = null,
    val logo: String? = null,
    val accent: String? = null,
    val now: GuideProgramme? = null,
    val next: GuideProgramme? = null,
    // What a library channel is really playing, when that isn't the programme (a bumper, say).
    val playing: GuideProgramme? = null,
    val notices: List<String>? = null,
    val alternative: GuideAlternative? = null,
    val security: GuideSecurity? = null,
)

@Serializable
data class ItemPage(val items: List<Item> = emptyList(), val total: Int = 0)

@Serializable
data class ShowPage(val shows: List<Show> = emptyList(), val total: Int = 0)

@Serializable
data class Track(
    val index: Int = 0,
    val language: String = "",
    val languageName: String = "",
    val title: String = "",
    val codec: String = "",
    val channels: Int = 0,
    val delivery: String = "",
    val url: String = "",
    val text: Boolean = false,
)

@Serializable
data class Intro(val startSec: Double = 0.0, val endSec: Double = 0.0)

// What POST /items/{id}/playback answers: see docs/CLIENT-API.md. The film's
// position is always the player's time plus timeOffsetSec.
@Serializable
data class Playback(
    val decision: String = "",
    val protocol: String = "",
    val url: String = "",
    val streamId: String = "",
    val tokenExpiresInSec: Int = 0,
    val durationSec: Double = 0.0,
    val seek: String = "native",
    val startAtSec: Double = 0.0,
    val timeOffsetSec: Double = 0.0,
    val audio: List<Track> = emptyList(),
    val subtitles: List<Track> = emptyList(),
    val audioIndex: Int = 0,
    val subtitleIndex: Int = -1,
    val subtitleDelivery: String = "none",
    val intro: Intro? = null,
    val nextId: Long? = null,
    // Why it plays this way, in plain words to show as they are.
    val explain: Explanation? = null,
    // A 3D picture stored in the frame: sbs or tab. Asking with `flatten3d` shows one eye.
    val stereo: String = "",
)

@Serializable
data class Explanation(
    val summary: String = "",
    val source: String = "",
    val picture: String = "",
    val sound: String = "",
    val subtitles: String = "",
    val reasons: List<String> = emptyList(),
) {
    val lines: List<String> get() = listOf(source, picture, sound, subtitles).filter { it.isNotEmpty() } + reasons
}

// What this device really plays, found by asking it. Replaces the profile's lists.
@Serializable
data class DeviceCapabilities(
    val videoCodecs: List<String>? = null,
    val audioCodecs: List<String>? = null,
    val hdr: List<String>? = null,
    val tenBit: Boolean? = null,
    val maxHeight: Int? = null,
    val maxAudioChannels: Int? = null,
    val hlsAudio: List<String>? = null,
    val hlsVideo: List<String>? = null,
)

// Left out, a field lets the server decide: which tracks, and where to resume.
@Serializable
data class PlaybackRequest(
    val profile: String,
    val audio: Int? = null,
    val subtitle: Int? = null,
    val startSec: Double? = null,
    val capabilities: DeviceCapabilities? = null,
    val maxBitrateKbps: Int? = null,
    val forceTranscode: Boolean? = null,
    val flatten3d: Boolean? = null,
)

@Serializable
data class Capabilities(
    val server: String = "",
    val version: String = "",
    val apiVersion: Int = 0,
    val apiRevision: Int = 0,
    val apiVersions: List<Int> = emptyList(),
    val setupRequired: Boolean = false,
    val features: List<String> = emptyList(),
    val minClientVersions: Map<String, String> = emptyMap(),
)

@Serializable
data class PairStart(
    val code: String = "",
    val deviceSecret: String = "",
    val expiresInSec: Int = 600,
    val intervalSec: Int = 3,
    val approvePath: String = "/pair",
    val approveUrl: String = "",
)

@Serializable
data class PairPoll(val status: String = "", val token: String = "", val intervalSec: Int = 0)

@Serializable
data class PairStartRequest(val device: String, val platform: String)

@Serializable
data class PairPollRequest(val deviceSecret: String)

@Serializable
data class PairRedeemRequest(val code: String, val device: String, val platform: String)

@Serializable
data class ProgressReport(val positionSec: Double, val durationSec: Double)

@Serializable
data class ViewReport(val seconds: Double)

@Serializable
// The code is the authenticator app's, for an account with two-factor sign-in.
data class Credentials(val name: String, val password: String, val device: String, val code: String = "")

@Serializable
data class RigPlayRequest(val client: String, val os: String)

@Serializable
data class RigInfo(
    val id: Long = 0,
    val name: String = "",
    val canWake: Boolean = false,
)

// One way to play, best first. Which fields are filled depends on its kind.
@Serializable
data class RigMethod(
    val kind: String = "",
    val label: String = "",
    val note: String = "",
    @SerialName("package") val packageName: String = "",
    val activity: String = "",
    val extras: Map<String, String> = emptyMap(),
    val steps: List<String> = emptyList(),
)

@Serializable
data class RigInstall(
    val name: String = "",
    val url: String = "",
    val note: String = "",
    val license: String = "",
)

// What POST /rigs/games/{id}/play answers.
@Serializable
data class RigPlay(
    val rig: RigInfo = RigInfo(),
    val ready: Boolean = false,
    val message: String = "",
    val methods: List<RigMethod> = emptyList(),
    val install: RigInstall? = null,
    val setup: List<String> = emptyList(),
)

@Serializable
data class CouchStatus(val allowed: Boolean = false)

@Serializable
data class RigWake(val ok: Boolean = false, val note: String = "")

// You and settings: docs/APP-DESIGN.md. What the server's internal/server answers for an account.

// A signed-in device. `where` is machine, home, vpn or internet; times are Unix seconds.
@Serializable
data class DeviceSession(
    val id: String = "",
    val device: String = "",
    val createdAt: Long = 0,
    val lastSeen: Long = 0,
    val where: String = "",
    val current: Boolean = false,
)

@Serializable
data class TwoFactorStatus(val on: Boolean = false, val recoveryLeft: Int = 0, val available: Boolean = false)

@Serializable
data class TwoFactorSetup(val secret: String = "", val uri: String = "")

@Serializable
data class RecoveryCodes(val recovery: List<String> = emptyList())

// What a TV asking to be signed in is, and who it may be signed in as.
@Serializable
data class PairChoice(val id: Long = 0, val name: String = "", val kind: String = "adult")

@Serializable
data class PairInfo(
    val code: String = "",
    val device: String = "",
    val platform: String = "",
    val ip: String = "",
    val expiresAt: Long = 0,
    val profiles: List<PairChoice> = emptyList(),
)

@Serializable
data class PairInvite(val code: String = "", val expiresInSec: Int = 0)

// Only what changed is sent: a Kids profile may not touch its names, but may choose which shows.
@Serializable
data class ProfileUpdate(val displayName: String? = null, val username: String? = null, val showUsername: Boolean? = null)

@Serializable
data class PasswordChange(val password: String, val current: String)

@Serializable
data class PasswordOnly(val password: String)

@Serializable
data class CodeOnly(val code: String)

@Serializable
data class PasswordAndCode(val password: String, val code: String)

@Serializable
data class PairAnswer(val code: String, val userId: Long? = null)

@Serializable
data class UserIdOnly(val userId: Long)
