package com.wittywilla.wittymediaclient.games

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// WittyPlay, the server's games, as data (the server's docs/GAMING-API.md). The server runs every game and
// streams it: this device shows the picture, plays the sound and sends the controls. Nothing here emulates
// anything, and no game file ever comes to the device.

@Serializable
data class GameProgress(val positionSec: Double = 0.0)

// One game: what its card and its page need. The same answer as any item, with what only games have.
@Serializable
data class GameItem(
    val id: Long = 0,
    val libraryId: Long = 0,
    val kind: String = "game",
    val title: String = "",
    val year: Int? = null,
    val overview: String = "",
    val tagline: String = "",
    val genres: List<String> = emptyList(),
    val rating: Double? = null,
    val contentRating: String = "",
    val studio: String = "",
    val console: String = "",
    val updatedAt: Long = 0,
    val progress: GameProgress? = null,
    val sizeBytes: Long = 0,
    val container: String = "",
    // Where the server keeps its pictures. Only whether there is one matters here.
    val poster: String = "",
    val backdrop: String = "",
) {
    val hasPoster: Boolean get() = poster.isNotEmpty()
    val hasBackdrop: Boolean get() = backdrop.isNotEmpty()

    // A game on someone's own PC plays through Moonlight, not here.
    val isRigGame: Boolean get() = console == "rig"
    val playedSeconds: Double get() = progress?.positionSec ?: 0.0
}

@Serializable
data class GameItemPage(val items: List<GameItem> = emptyList(), val total: Int = 0)

@Serializable
data class GameButton(val id: Int = 0, val label: String = "")

// A console's controller: its names for its buttons, and whether it has sticks or a touch screen.
@Serializable
data class GamePadShape(
    val face: List<GameButton> = emptyList(),
    val shoulder: List<GameButton> = emptyList(),
    val meta: List<GameButton> = emptyList(),
    val sticks: Boolean = false,
    val pointer: Boolean = false,
    // The Nintendo 64: games steer with the stick, so arrows push it.
    val stickFirst: Boolean = false,
    val art: String = "",
) {
    val buttons: List<GameButton> get() = face + shoulder + meta
}

@Serializable
data class GameCore(val id: String = "", val name: String = "", val license: String = "")

@Serializable
data class GameBios(val file: String = "", val `for`: String = "", val required: Boolean = false, val found: Boolean = false)

@Serializable
data class GameConsole(
    val id: String = "",
    val name: String = "",
    val short: String = "",
    val ready: Boolean = false,
    // Why it can't be played here at all, in the server's words.
    val unavailable: String = "",
    val installed: List<GameCore> = emptyList(),
    val pad: GamePadShape? = null,
    // That library's games for it, when asked with ?library=.
    val count: Int = 0,
) {
    val shortName: String get() = short.ifEmpty { name }
}

@Serializable
data class GameSaveRef(val slot: Int = 0, val updatedAt: Long = 0, val hasThumb: Boolean = false)

@Serializable
data class GameContinue(val item: GameItem = GameItem(), val plays: Int = 0, val lastPlayed: Long = 0, val save: GameSaveRef? = null)

@Serializable
data class GameShelf(val kind: String = "", val name: String = "", val count: Int = 0, val items: List<GameItem> = emptyList())

// The games home screen in one answer.
@Serializable
data class GamesHome(
    val hero: List<GameItem> = emptyList(),
    val `continue`: List<GameContinue> = emptyList(),
    val recent: List<GameItem> = emptyList(),
    val favourites: List<GameItem> = emptyList(),
    val favouriteIds: List<Long> = emptyList(),
    val mostPlayed: List<GameItem> = emptyList(),
    val shelves: List<GameShelf> = emptyList(),
)

// What a game needs in order to play, and whether this server has it: the server's readiness check. Its
// `message` is the server's own reason, shown as it is; a `reason` this app doesn't know still shows it.
@Serializable
data class GameCheck(
    val ready: Boolean = false,
    // core, bios, unavailable, or something newer.
    val reason: String = "",
    val message: String = "",
    val console: String = "",
    val consoleName: String = "",
    val core: GameCore? = null,
    val needsGpu: Boolean = false,
    val bios: List<GameBios> = emptyList(),
    val biosFolder: String = "",
)

// A saved state. Slot 0 is the automatic one, written when a game stops.
@Serializable
data class GameSave(val slot: Int = 0, val updatedAt: Long = 0, val size: Long = 0, val hasThumb: Boolean = false, val core: String = "")

// What a person keeps about a game.
@Serializable
data class GamePersonal(val favourite: Boolean = false, val note: String = "", val plays: Int = 0, val lastPlayed: Long = 0, val hasBattery: Boolean = false)

// The rest of a game's details, from GET /games/{id}/metadata.
@Serializable
data class GameDetails(
    val status: String = "",
    val players: Int = 0,
    val publisher: String = "",
    val developer: String = "",
    val released: String = "",
    val franchise: String = "",
    // Set when the file itself is a problem, such as an encrypted one.
    val problem: String = "",
)

@Serializable
data class GameVersion(val id: Long = 0, val label: String = "", val current: Boolean = false)

@Serializable
data class GameVersions(val versions: List<GameVersion> = emptyList())

@Serializable
data class GameDeviceType(val id: Int = 0, val name: String = "")

@Serializable
data class GamePortDevices(val port: Int = 0, val current: Int = 0, val types: List<GameDeviceType> = emptyList())

// A game being played, from POST /games/{id}/play. `modes` is kept raw: older servers send names, newer ones objects.
@Serializable
data class GameSession(
    val id: String = "",
    val itemId: Long = 0,
    val title: String = "",
    val console: String = "",
    val core: String = "",
    val width: Int = 0,
    val height: Int = 0,
    // Width over height: the picture is shown at this shape, whatever the video's.
    val aspect: Double = 0.0,
    val fps: Double = 0.0,
    val sampleRate: Double = 0.0,
    val resumed: Boolean = false,
    val encoder: String = "",
    // Quarter turns to draw the picture by.
    val turns: Int = 0,
    val disc: Int = 0,
    val discs: Int = 0,
    val modes: List<JsonElement> = emptyList(),
    val devices: List<GamePortDevices> = emptyList(),
    val safeMode: Boolean = false,
    val maxSpeed: Double = 0.0,
    val notices: List<String> = emptyList(),
) {
    val modeIds: List<String>
        get() = modes.mapNotNull { m ->
            when (m) {
                is JsonPrimitive -> m.content
                is JsonObject -> (m["id"] as? JsonPrimitive)?.content
                else -> null
            }
        }
}

// How far a game in an archive has got with being unpacked.
@Serializable
data class GamePrepare(val state: String = "ready", val done: Long = 0, val total: Long = 0) {
    val ready: Boolean get() = state == "ready"
    val fraction: Float? get() = if (total > 0) (done.toFloat() / total).coerceIn(0f, 1f) else null
}

// Something done to a running game: POST /play/{sid}/action.
@Serializable
data class GameAction(
    val type: String,
    val slot: Int? = null,
    val on: Boolean? = null,
    val value: Double? = null,
    val port: Int? = null,
    val device: Int? = null,
)

// A person's settings for a game, worked out by the server from every level.
@Serializable
data class GameSettingsResolved(val values: Map<String, JsonElement> = emptyMap())

@Serializable
data class GameSettings(val resolved: GameSettingsResolved = GameSettingsResolved()) {
    private fun value(key: String): JsonPrimitive? = resolved.values[key] as? JsonPrimitive

    fun text(key: String, fallback: String): String = value(key)?.let { if (it.isString) it.content else it.content.removeSuffix(".0") } ?: fallback
    fun number(key: String, fallback: Double): Double = value(key)?.let { it.doubleOrNull ?: it.content.toDoubleOrNull() } ?: fallback
    fun flag(key: String, fallback: Boolean): Boolean = value(key)?.let { it.booleanOrNull ?: (it.doubleOrNull?.let { n -> n != 0.0 }) } ?: fallback

    companion object {
        val NONE = GameSettings()

        fun of(values: Map<String, Any>): GameSettings = GameSettings(
            GameSettingsResolved(
                values.mapValues { (_, v) ->
                    when (v) {
                        is Boolean -> JsonPrimitive(v)
                        is Number -> JsonPrimitive(v)
                        else -> JsonPrimitive(v.toString())
                    }
                },
            ),
        )
    }
}

// One input of a W3C standard gamepad: {"b": n} a button, {"a": n, "d": ±1} one direction of an axis (with `r`
// for a trigger that rests at one end), {"h": n, "d": 1..4} a D-pad as one axis.
@Serializable
data class PadSource(val b: Int? = null, val a: Int? = null, val d: Int? = null, val h: Int? = null, val r: Int? = null)

// How sticks and turbo behave. Applying these is the app's job: the server only keeps them.
@Serializable
data class PadOptions(
    val deadzone: Double? = null,
    val threshold: Double? = null,
    val stickDpad: Boolean? = null,
    val turbo: List<Int>? = null,
    val turboHz: Double? = null,
    val noRumble: Boolean? = null,
) {
    // What's set here, over what's set in `under`.
    fun over(under: PadOptions?): PadOptions = PadOptions(
        deadzone ?: under?.deadzone, threshold ?: under?.threshold, stickDpad ?: under?.stickDpad,
        turbo ?: under?.turbo, turboHz ?: under?.turboHz, noRumble ?: under?.noRumble,
    )
}

// A control drawn on a touch screen, by its key in a layout.
@Serializable
data class GameControl(val key: String = "", val id: Int = -1, val label: String = "", val kind: String = "face", val stick: Boolean = false) {
    // A control of kind stick, or a D-pad marked as one, is an analog stick.
    val isStick: Boolean get() = kind == "stick" || stick
}

// Where a touch control sits: its centre as fractions of the play area, its size as a fraction of the shorter side.
@Serializable
data class Placement(val x: Double = 0.5, val y: Double = 0.5, val size: Double = 0.15, val opacity: Double = 0.55, val hidden: Boolean = false)

@Serializable
data class ControlsDefaults(
    val gamepad: Map<String, PadSource?> = emptyMap(),
    // RetroPad target to a KeyboardEvent.key name, for a TV remote.
    val remote: Map<String, String> = emptyMap(),
    // RetroPad target to a KeyboardEvent.code name.
    val keyboard: Map<String, String> = emptyMap(),
    val touch: Map<String, Map<String, Placement>> = emptyMap(),
    val options: PadOptions? = null,
)

@Serializable
data class ControlsSaved(
    // Layouts by the pad's model name.
    val gamepad: Map<String, Map<String, PadSource?>> = emptyMap(),
    val keyboard: Map<String, String>? = null,
    val touch: Map<String, Map<String, Placement>> = emptyMap(),
)

@Serializable
data class GameBackground(val version: Long = 0, val fit: String = "cover", val x: Double = 50.0, val y: Double = 50.0, val dim: Double = 50.0)

// The controller as data, from GET /consoles/{console}/controls.
@Serializable
data class GameControls(
    val console: String = "",
    val pad: GamePadShape = GamePadShape(),
    val controls: List<GameControl> = emptyList(),
    val defaults: ControlsDefaults = ControlsDefaults(),
    val saved: ControlsSaved = ControlsSaved(),
    val background: GameBackground = GameBackground(),
) {
    // The touch layout for this way up: the console's, with this device's own saved one over it.
    fun touchLayout(orientation: String): Map<String, Placement> =
        defaults.touch[orientation].orEmpty() + saved.touch[orientation].orEmpty()
}

// What a controller should do here, from GET /game-profiles/resolve.
@Serializable
data class ResolvedProfile(val id: Long = 0, val name: String = "")

@Serializable
data class ResolvedPad(val map: Map<String, PadSource?>? = null, val options: PadOptions? = null, val profile: ResolvedProfile? = null)

// An event's fields that this app reads. Everything else in one is ignored.
fun JsonObject.text(key: String): String = (this[key] as? JsonPrimitive)?.content.orEmpty()
fun JsonObject.number(key: String): Double? = (this[key] as? JsonPrimitive)?.doubleOrNull
fun JsonElement.asObject(): JsonObject? = runCatching { jsonObject }.getOrNull()
fun JsonElement.asText(): String? = runCatching { jsonPrimitive.content }.getOrNull()
