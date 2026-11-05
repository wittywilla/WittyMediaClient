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
    // A newer version the server's update check found, for administrators only; empty for none.
    val update: String = "",
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
    // A commercials library is only in the menus when it asks to be.
    val showMain: Boolean = false,
    val scanning: Boolean = false,
) {
    val inMainMenus: Boolean get() = type != "commercials" || showMain
}

// GET /modules/web: the server's add-ons and the pages they put in the menus.
@Serializable
data class ModuleBundles(val bundles: List<ModuleBundle> = emptyList())

@Serializable
data class ModuleBundle(val id: String = "", val pages: List<ModulePage> = emptyList())

@Serializable
data class ModulePage(val id: String = "", val title: String = "", val icon: String = "", val where: String = "")

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
    // The website's facts: a rating out of ten, a disc's menus, whether there's artwork at all.
    val rating: Double? = null,
    val disc: DiscFacts? = null,
    val poster: String = "",
    val backdrop: String = "",
    // The facts table on the item page.
    val studio: String = "",
    val container: String = "",
    val videoCodec: String = "",
    val width: Int = 0,
    val height: Int = 0,
    val audioLangs: List<String>? = null,
    val subLangs: List<String>? = null,
    val sizeBytes: Long = 0,
    val aired: String = "",
) {
    val isDisc: Boolean get() = kind in setOf("dvd-iso", "dvd-folder", "bluray-iso", "bluray-folder")
}

@Serializable
data class DiscFacts(val hasMenus: Boolean? = null)

// GET /me/recommended: picks for this person, and the title they're picked because of.
@Serializable
data class ForYou(val items: List<Item> = emptyList(), val shows: List<Show> = emptyList(), val because: String = "")

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
    val genres: List<String> = emptyList(),
    val contentRating: String = "",
    val network: String = "",
    val status: String = "",
)

@Serializable
data class Season(
    val number: Int = 0,
    val title: String = "",
    val overview: String = "",
    val episodeCount: Int = 0,
    // Left out until something has been watched.
    val unwatched: Int? = null,
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
    // A saved view's choices, as the library page's address carries them: "genre=Drama&sort=added".
    val query: String = "",
    val items: List<Item> = emptyList(),
    val shows: List<Show> = emptyList(),
)

@Serializable
data class Home(
    val hubs: List<Hub> = emptyList(),
    val featured: List<Item> = emptyList(),
    val libraries: List<Library> = emptyList(),
)

@Serializable
data class GuideProgramme(
    val start: Long = 0,
    val end: Long = 0,
    val title: String = "",
    val itemId: Long? = null,
)

@Serializable
data class GuideChannel(
    val key: String = "",
    val number: String = "",
    val name: String = "",
    // "library" for a channel the server makes from a library, which is off air between its programmes.
    val kind: String = "",
    val encrypted: String = "", // why it can't be tuned: this server never decrypts a broadcast
    val favourite: Boolean = false,
    val programmes: List<GuideProgramme> = emptyList(),
)

@Serializable
data class Guide(val channels: List<GuideChannel> = emptyList())

// What GET /update says, for administrators: only what Home's notice of a newer server uses.
@Serializable
data class UpdateChange(val version: String = "", val notes: String = "")

@Serializable
data class UpdateLatest(val version: String = "", val changes: List<UpdateChange> = emptyList())

@Serializable
data class UpdateStatus(
    val current: String = "",
    val latest: UpdateLatest? = null,
    // apply, installer or docker: a server in Docker is updated by its owner, so the notice says how.
    val method: String = "",
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
    val flattened: Boolean = false,
    // Named points in the film, for the scenes panel and the marks on the seek bar.
    val chapters: List<Chapter> = emptyList(),
    // A file with several pictures lists them; videoIndex is the one playing.
    val videos: List<VideoStream> = emptyList(),
    val videoIndex: Int = 0,
)

@Serializable
data class Chapter(val start: Double = 0.0, val title: String = "")

@Serializable
data class VideoStream(val index: Int = 0, val title: String = "", val width: Int = 0, val height: Int = 0)

// GET /items/{id}/recommend: something to watch after this, and the show it belongs to.
@Serializable
data class Recommendation(val item: Item? = null, val show: Show? = null)

// GET /prefs: the server's limits for players, and how a show's episodes are laid out unless it says otherwise.
@Serializable
data class PlayerPrefs(val maxSpeed: Double = 4.0, val episodeView: String = "")

@Serializable
data class Explanation(
    val summary: String = "",
    val source: String = "",
    val picture: String = "",
    val sound: String = "",
    val subtitles: String = "",
    val reasons: List<String> = emptyList(),
    // What it costs the server: none, light or heavy.
    val load: String = "",
    val streaming: String = "",
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
    val burnSubtitle: Boolean? = null,
    val video: Int? = null,
    val streaming: String? = null,
    val measuredKbps: Int? = null,
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

// A collection, for Save to: its owner, and whether it's a system one such as Watch later.
@Serializable
data class Collection(val id: Long = 0, val ownerId: Long = 0, val name: String = "", val kind: String = "manual", val system: String = "")

@Serializable
data class CollectionItems(val items: List<Long> = emptyList(), val shows: List<Long> = emptyList())

@Serializable
data class WatchLater(val collectionId: Long = 0)

@Serializable
data class NewCollection(val name: String, val kind: String = "manual")

// GET /browse/shelves: a library's categories, collections, studios and networks.
@Serializable
data class ArtRef(val type: String = "item", val id: Long = 0, val v: Long = 0)

@Serializable
data class ShelfCard(val id: Long = 0, val key: String = "", val name: String = "", val genre: String = "", val kind: String = "", val count: Int = 0, val art: List<ArtRef> = emptyList())

@Serializable
data class Shelves(
    val categories: List<ShelfCard> = emptyList(),
    val collections: List<ShelfCard> = emptyList(),
    val studios: List<ShelfCard> = emptyList(),
    val networks: List<ShelfCard> = emptyList(),
)

// GET /browse: items and shows together, and how many there are in all.
@Serializable
data class BrowseHit(val type: String = "item", val item: Item? = null, val show: Show? = null)

@Serializable
data class BrowsePage(val results: List<BrowseHit> = emptyList(), val total: Int = 0)

@Serializable
data class Facet(val value: String = "", val label: String = "", val count: Int = 0)

// GET /legal/notices: the short notices every client shows at the foot of a page, and the words for the link.
@Serializable
data class LegalNotice(val text: String = "", val section: String = "")

@Serializable
data class LegalNotices(val linkText: String = "", val notices: Map<String, LegalNotice> = emptyMap())

// "0.6.2-alpha" as the website shows it (components/common.tsx VersionTag): the number, and the stage in capitals.
fun versionParts(version: String): Pair<String, String> {
    val match = Regex("""^v?(\d+\.\d+\.\d+)(?:-([a-zA-Z]+)[.\d]*)?""").find(version)
        ?: return (version.ifEmpty { "dev" }) to (if (version == "dev") "DEV" else "")
    return match.groupValues[1] to match.groupValues[2].uppercase()
}
