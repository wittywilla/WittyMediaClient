package com.wittywilla.wittymediaclient.ui

// docs/APP-DESIGN.md, "You and settings": which rows the You tab has, for whom, and what each opens.
// Apart from the screen, so it can be tested without one. Rows the server would refuse are left out,
// not greyed.

enum class YouNative { Names, Password, TwoStep, Devices, SignInTv, Theme, TopMenu, Licences, Log }

sealed interface YouOpens {
    data class Native(val screen: YouNative) : YouOpens
    // The server's own page for it, inside the app; a QR card for it on a TV.
    data class Page(val path: String) : YouOpens
}

// `icon` is a Material Symbols name, `tint` the icon tile's colour (null: the quiet grey, danger: "danger").
data class YouRow(val key: String, val icon: String, val tint: String?, val opens: YouOpens)

data class YouGroup(val key: String, val rows: List<YouRow>)

// Who's looking, as far as the rows care.
data class YouWho(
    val admin: Boolean,
    // An adult profile (administrators are adults too); Kids and Guest aren't.
    val adult: Boolean,
    val hasGames: Boolean,
    // The server offers two-step sign-in to this profile.
    val twoStepAvailable: Boolean,
    val onTv: Boolean,
)

private const val QUIET = "#5d6474"

private fun native(key: String, icon: String, tint: String?, screen: YouNative) = YouRow(key, icon, tint, YouOpens.Native(screen))
private fun page(key: String, icon: String, tint: String?, path: String) = YouRow(key, icon, tint, YouOpens.Page(path))

fun youGroups(who: YouWho): List<YouGroup> {
    val groups = mutableListOf<YouGroup>()
    groups += YouGroup(
        "groupAccount",
        listOfNotNull(
            native("rowNames", "badge", "#0a6fb8", YouNative.Names),
            if (who.adult) native("rowPassword", "key", "#3e5bd0", YouNative.Password) else null,
            if (who.adult && who.twoStepAvailable) native("rowTwoStep", "shield_lock", "#2e7d3c", YouNative.TwoStep) else null,
            native("rowDevices", "devices", "#7f46b8", YouNative.Devices),
        ),
    )
    // A TV is what gets signed in, so it doesn't sign in TVs.
    val household = listOfNotNull(
        if (who.adult && !who.onTv) native("rowSignInTv", "tv", "#bd2f85", YouNative.SignInTv) else null,
        if (who.adult) page("rowProfiles", "family_restroom", "#b8500d", "/settings/users") else null,
    )
    if (household.isNotEmpty()) groups += YouGroup("groupHousehold", household)
    groups += YouGroup(
        "groupYours",
        listOfNotNull(
            page("rowYourYear", "auto_awesome", "#c9302f", "/review"),
            page("rowCollections", "library_books", "#0e7c6f", "/collections"),
            page("rowShareLinks", "link", "#0a6fb8", "/settings/sharing"),
            page("rowActivity", "monitoring", "#99690a", "/settings/activity"),
            if (who.hasGames) page("rowGameSettings", "sports_esports", "#7f46b8", "/settings/games") else null,
            if (who.hasGames) page("rowControllers", "gamepad", "#3e5bd0", "/controllers") else null,
        ),
    )
    groups += YouGroup(
        "groupDevice",
        listOfNotNull(
            native("rowTheme", "palette", "#0e7c6f", YouNative.Theme),
            // Which libraries join the bar along the top: a TV's alone.
            if (who.onTv) native("rowTopMenu", "toolbar", "#bd2f85", YouNative.TopMenu) else null,
        ),
    )
    if (who.admin) {
        groups += YouGroup(
            "groupServer",
            listOf(
                page("rowLibraries", "video_library", QUIET, "/settings/libraries"),
                page("rowMetadata", "image_search", QUIET, "/settings/metadata"),
                page("rowFixMatches", "auto_fix_high", QUIET, "/fix-matches"),
                page("rowPlayback", "smart_display", QUIET, "/settings/playback"),
                page("rowLiveTv", "live_tv", QUIET, "/settings/channels"),
                page("rowGaming", "sports_esports", QUIET, "/settings/gaming"),
                page("rowGamePcs", "computer", QUIET, "/settings/couch"),
                page("rowTranscoding", "bolt", QUIET, "/settings/transcoding"),
                page("rowLibraryTranscoding", "autorenew", QUIET, "/settings/library-transcoding"),
                page("rowRemote", "public", QUIET, "/settings/remote"),
                page("rowAppearance", "brush", QUIET, "/settings/appearance"),
                page("rowWittyRigs", "dns", QUIET, "/settings/wittyrigs"),
            ),
        )
        groups += YouGroup(
            "groupMaintenance",
            listOf(
                page("rowLogs", "article", QUIET, "/settings/logs"),
                page("rowDiagnoser", "stethoscope", QUIET, "/settings/diagnoser"),
                page("rowModules", "extension", QUIET, "/settings/modules"),
                page("rowBackup", "backup", QUIET, "/settings/backup"),
                page("rowRepair", "build", QUIET, "/settings/repair"),
                page("rowReset", "restart_alt", "danger", "/settings/reset"),
            ),
        )
    }
    groups += YouGroup(
        "groupHelp",
        listOf(
            page("rowHelp", "help", "#99690a", "/help"),
            page("rowAboutServer", "info", QUIET, "/settings/about"),
            page("rowLegal", "gavel", QUIET, "/legal"),
            native("rowLicences", "menu_book", QUIET, YouNative.Licences),
            native("rowAppLog", "receipt_long", QUIET, YouNative.Log),
        ),
    )
    return groups
}

// The role under the name in You's header.
fun roleKey(admin: Boolean, kind: String): String = when {
    admin -> "roleAdmin"
    kind == "kids" -> "roleKids"
    kind == "guest" -> "roleGuest"
    else -> "roleAdult"
}

// A TV's code from /pair/start: eight letters from the server's alphabet, shown as XXXX-XXXX.
// What's typed is kept to those letters, in capitals.
const val TV_CODE_LETTERS = "BCDFGHJKLMNPQRSTVWXZ"
const val TV_CODE_LENGTH = 8

fun tvCodeTyped(text: String): String =
    text.uppercase().filter { it in TV_CODE_LETTERS }.take(TV_CODE_LENGTH)

// What a device's name says it is, for its icon: phone, tablet, tv, computer or browser.
fun deviceKind(name: String): String {
    val n = name.lowercase()
    return when {
        listOf("tv", "shield", "fire stick", "chromecast", "bigscreen").any { it in n } -> "tv"
        listOf("ipad", "tablet", "tab ").any { it in n } -> "tablet"
        listOf("chrome", "safari", "firefox", "edge", "opera", "browser").any { it in n } -> "browser"
        listOf("iphone", "pixel", "galaxy", "android", "phone", "sdk_gphone").any { it in n } -> "phone"
        else -> "computer"
    }
}

// A secret for an authenticator app, in groups of four so it can be typed.
fun groupsOfFour(secret: String): String = secret.chunked(4).joinToString(" ")
