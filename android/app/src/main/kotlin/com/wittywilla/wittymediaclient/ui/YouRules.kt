// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

// docs/APP-DESIGN.md, "You and settings": which rows the You tab has, for whom, and what each opens.
// Apart from the screen, so it can be tested without one. Rows the server would refuse are left out,
// not greyed.

enum class YouNative { Names, Password, TwoStep, Devices, SignInTv, Theme, TopMenu, Licences, Log, Servers, Away, Profiles, PlayingHere, Look, Modules, RemoteControl, WatchParty, EditLayout, NameAndLogo }

sealed interface YouOpens {
    data class Native(val screen: YouNative) : YouOpens
    // The server's own page for it, inside the app; a QR card for it on a TV.
    data class Page(val path: String) : YouOpens
    // One of the server's SDUI pages (its catalogue's routes), drawn by the app the same on a phone, tablet and TV.
    data class Sdui(val path: String) : YouOpens
    // A desktop Settings page a TV draws itself, from shared/data/tv-settings.json (net/TvSettings.kt).
    data class Tv(val page: String) : YouOpens
    // An editor kept for a computer: its QR card on a TV, even where the server's table doesn't list it yet.
    data class Card(val path: String) : YouOpens
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
    // The app can reach a server from away (the connector library is in it).
    val fromAway: Boolean = false,
    // The server's modules have settings to show (`module-settings`).
    val moduleSettings: Boolean = false,
    // The server has experiences (looks) to choose from.
    val looks: Boolean = false,
    // The server has parental controls this app can show itself: Profiles is then the app's own screen.
    val nativeProfiles: Boolean = false,
    // What this profile's limits turn off (GET /me/limits): rows for those aren't offered.
    val off: Set<String> = emptySet(),
    // The server and this profile have remote control of other devices (`remote-protocol`, canControl).
    val remote: Boolean = false,
    // The server has watch parties (`syncplay`), and this profile may join them.
    val parties: Boolean = false,
    // The server has placements (`sdui-experiences`): Edit layout is offered.
    val layoutEditor: Boolean = false,
)

private const val QUIET = "#5d6474"

private fun native(key: String, icon: String, tint: String?, screen: YouNative) = YouRow(key, icon, tint, YouOpens.Native(screen))
private fun page(key: String, icon: String, tint: String?, path: String) = YouRow(key, icon, tint, YouOpens.Page(path))

// The server's page on a phone or tablet; on a TV, the TV's own drawing of it (docs/TV-SETTINGS-PARITY.md).
private fun tvPage(who: YouWho, key: String, icon: String, tint: String?, page: String, path: String) =
    YouRow(key, icon, tint, if (who.onTv) YouOpens.Tv(page) else YouOpens.Page(path))

// An editor kept for a computer: the server's page on a phone or tablet, the QR card on a TV.
private fun card(who: YouWho, key: String, icon: String, tint: String?, path: String) =
    YouRow(key, icon, tint, if (who.onTv) YouOpens.Card(path) else YouOpens.Page(path))

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
        if (who.adult && who.nativeProfiles) native("rowProfiles", "family_restroom", "#b8500d", YouNative.Profiles) else null,
        if (who.adult && !who.nativeProfiles) page("rowProfiles", "family_restroom", "#b8500d", "/settings/users") else null,
    )
    if (household.isNotEmpty()) groups += YouGroup("groupHousehold", household)
    groups += YouGroup(
        "groupYours",
        listOfNotNull(
            page("rowYourYear", "auto_awesome", "#c9302f", "/review"),
            page("rowCollections", "library_books", "#0e7c6f", "/collections"),
            if ("sharing" !in who.off) tvPage(who, "rowShareLinks", "link", "#0a6fb8", "sharing", "/settings/sharing") else null,
            tvPage(who, "rowActivity", "monitoring", "#99690a", "activity", "/settings/activity"),
            // The picture size and data videos play at, at home and away: the profile's own, on every device.
            tvPage(who, "rowVideoQuality", "hd", "#3e5bd0", "quality", "/settings/quality"),
            // What the player skips by itself: the profile's own, on the web under Playback or Appearance.
            if (who.onTv) YouRow("rowSkipping", "skip_next", "#2e7d3c", YouOpens.Tv("skipping")) else null,
            if (who.hasGames && "games" !in who.off) page("rowGameSettings", "sports_esports", "#7f46b8", "/settings/games") else null,
            if (who.hasGames && "games" !in who.off) page("rowControllers", "gamepad", "#3e5bd0", "/controllers") else null,
            // Playing on and steering other devices, and watching together: the app's own screens.
            if (who.remote && "remoteControl" !in who.off) native("rowRemoteControl", "cast", "#3e5bd0", YouNative.RemoteControl) else null,
            if (who.parties && "syncplay" !in who.off) native("rowWatchParty", "groups", "#bd2f85", YouNative.WatchParty) else null,
        ),
    )
    // What the server's modules let this profile set (Settings, Modules, in the app's own style).
    if (who.moduleSettings) groups += YouGroup("groupModules", listOf(native("rowModuleSettings", "extension", "#7f46b8", YouNative.Modules)))
    groups += YouGroup(
        "groupDevice",
        listOfNotNull(
            if (who.looks) native("rowLook", "toolbar", "#0e7c6f", YouNative.Look) else null,
            // Where the shell's parts and the page's sections are, for this device or for everyone (the layout editor).
            if (who.layoutEditor) native("rowEditLayout", "toolbar", "#7f46b8", YouNative.EditLayout) else null,
            native("rowTheme", "palette", "#0e7c6f", YouNative.Theme),
            // The web's Appearance, on a TV for everyone: motion, the language and what's made on a computer.
            if (who.onTv) YouRow("rowAppearance", "brush", "#0e7c6f", YouOpens.Tv("appearance")) else null,
            // Which libraries join the bar along the top: a TV's alone.
            if (who.onTv) native("rowTopMenu", "toolbar", "#bd2f85", YouNative.TopMenu) else null,
            // The servers this device remembers, to remove the ones no longer wanted.
            native("rowServers", "dns", QUIET, YouNative.Servers),
            // How this device reaches the server when it isn't at home: peer to peer.
            if (who.fromAway) native("rowAway", "settings_input_antenna", "#0a6fb8", YouNative.Away) else null,
            // Skipping intros and credits by itself, and artwork that moves: this device's own (YouPlaying.kt).
            native("rowPlayingHere", "smart_display", "#3e5bd0", YouNative.PlayingHere),
        ),
    )
    if (who.admin) {
        groups += YouGroup(
            "groupServer",
            listOfNotNull(
                YouRow("rowLibraries", "video_library", QUIET, YouOpens.Sdui("/manage/libraries")),
                page("rowMetadata", "image_search", QUIET, "/settings/metadata"),
                page("rowFixMatches", "auto_fix_high", QUIET, "/fix-matches"),
                tvPage(who, "rowPlayback", "smart_display", QUIET, "playback", "/settings/playback"),
                page("rowPagesMenu", "toolbar", QUIET, "/settings/pages"),
                page("rowLiveTv", "live_tv", QUIET, "/settings/channels"),
                page("rowGaming", "sports_esports", QUIET, "/settings/gaming"),
                page("rowGamePcs", "computer", QUIET, "/settings/couch"),
                page("rowTranscoding", "bolt", QUIET, "/settings/transcoding"),
                page("rowLibraryTranscoding", "autorenew", QUIET, "/settings/library-transcoding"),
                page("rowNetwork", "lan", QUIET, "/settings/network"),
                card(who, "rowDataFolder", "folder", QUIET, "/settings/data-folder"),
                page("rowRemote", "public", QUIET, "/settings/remote"),
                native("rowNameAndLogo", "badge", "#7f46b8", YouNative.NameAndLogo),
                // On a TV it is with this device's rows, for everyone.
                if (who.onTv) null else page("rowAppearance", "brush", QUIET, "/settings/appearance"),
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
            tvPage(who, "rowAboutServer", "info", QUIET, "about", "/settings/about"),
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
