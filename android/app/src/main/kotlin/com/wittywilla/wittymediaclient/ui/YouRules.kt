// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import com.wittywilla.wittymediaclient.net.SettingsMenu
import com.wittywilla.wittymediaclient.net.SettingsMenuRow
import com.wittywilla.wittymediaclient.net.visible

// docs/APP-DESIGN.md, "You and settings": which rows the You tab has, for whom, and what each opens, from the
// server's settings menu (net/SettingsMenu.kt). Apart from the screen, so it can be tested without one.

enum class YouNative { Names, Password, TwoStep, Devices, SignInTv, Theme, TopMenu, Licences, Log, Servers, Away, Profiles, PlayingHere, Look, Modules, RemoteControl, WatchParty, EditLayout, NameAndLogo }

sealed interface YouOpens {
    data class Native(val screen: YouNative) : YouOpens
    // The server's own page for it, inside the app; a QR card for it on a TV.
    data class Page(val path: String) : YouOpens
    // One of the server's SDUI pages (its catalogue's routes), drawn by the app the same on a phone, tablet and TV.
    data class Sdui(val path: String) : YouOpens
}

// `icon` is a Material Symbols name, `tint` the icon tile's colour (QUIET for the owner's tools, "danger" for Reset).
// `path` is the server's page for it (the address a TV's card gives), `part` its editor in the TV table, `value` what
// it shows on its right and `summary` what a TV shows on a row it can't change (the server's settingsmenu.json).
data class YouRow(
    val key: String,
    val icon: String,
    val tint: String?,
    val opens: YouOpens,
    val path: String = "",
    val part: String = "",
    val value: String = "",
    val summary: String = "",
)

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
) {
    // The menu's conditions that hold (settingsmenu.json, `conditions`).
    val facts: Set<String>
        get() = buildSet {
            if (admin) add("admin")
            if (adult) add("adult")
            if (onTv) add("tv")
            if (twoStepAvailable) add("twoStep")
            if (hasGames) add("games")
            add("app")
            add("servers")
            if (fromAway) add("fromAway")
            if (looks) add("looks")
            if (layoutEditor) add("layoutEditor")
            if (moduleSettings) add("moduleSettings")
            if (remote) add("remote")
            if (parties) add("parties")
        }
}

private const val QUIET = "#5d6474"

// This app's own screens, by the menu's `native` names.
private val NATIVE = mapOf(
    "names" to YouNative.Names, "password" to YouNative.Password, "twoStep" to YouNative.TwoStep, "devices" to YouNative.Devices,
    "signInTv" to YouNative.SignInTv, "profiles" to YouNative.Profiles, "remoteControl" to YouNative.RemoteControl,
    "watchParty" to YouNative.WatchParty, "modules" to YouNative.Modules, "look" to YouNative.Look, "editLayout" to YouNative.EditLayout,
    "theme" to YouNative.Theme, "topMenu" to YouNative.TopMenu, "servers" to YouNative.Servers, "away" to YouNative.Away,
    "playingHere" to YouNative.PlayingHere, "nameAndLogo" to YouNative.NameAndLogo, "licences" to YouNative.Licences, "appLog" to YouNative.Log,
)

// How this app opens a row: its own screen, else the server's SDUI page, else the server's page. Profiles is the
// app's own screen only where the server has parental controls this app draws itself.
fun youOpens(row: SettingsMenuRow, who: YouWho): YouOpens? {
    val native = NATIVE[row.native]?.takeIf { it != YouNative.Profiles || who.nativeProfiles }
    return when {
        native != null -> YouOpens.Native(native)
        row.path.isEmpty() -> null
        row.sdui -> YouOpens.Sdui(row.path)
        else -> YouOpens.Page(row.path)
    }
}

// The You page's groups for this person, from the settings menu every client draws (docs/APP-DESIGN.md, "You and
// settings"; the server's settingsmenu.json). Rows the server would refuse are left out, not greyed.
fun youGroups(who: YouWho, menu: SettingsMenu): List<YouGroup> =
    menu.visible(who.facts, who.off) { youOpens(it, who) != null }.map { g ->
        YouGroup(g.key, g.rows.map { r ->
            YouRow(r.key, r.icon.android, r.tint.takeIf { it != QUIET }, youOpens(r, who)!!, r.path, r.part, r.value, r.summary)
        })
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
