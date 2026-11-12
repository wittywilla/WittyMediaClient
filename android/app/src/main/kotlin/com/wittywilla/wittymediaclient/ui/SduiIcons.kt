// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import android.app.ActivityManager
import android.content.Context
import android.content.res.Configuration
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.unit.dp
import com.wittywilla.wittymediaclient.WittyApp
import com.wittywilla.wittymediaclient.net.SduiDevice

// The few of the catalogue's icons the app had no drawing of: Material Icons, on their 24 grid, from
// github.com/google/material-design-icons (Apache-2.0), as Symbols.kt's are.
private fun icon24(name: String, path: String): ImageVector =
    ImageVector.Builder(name, 24.dp, 24.dp, 24f, 24f).addPath(addPathNodes(path), fill = SolidColor(Color.Black)).build()

object SduiSymbols {
    val Clock: ImageVector by lazy { icon24("schedule", "M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm0 18a8 8 0 1 1 0-16 8 8 0 0 1 0 16zm.5-13H11v6l5.2 3.2.8-1.3-4.5-2.7z") }
    val History: ImageVector by lazy { icon24("history", "M13 3a9 9 0 0 0-9 9H1l3.89 3.89.07.14L9 12H6c0-3.87 3.13-7 7-7s7 3.13 7 7-3.13 7-7 7c-1.93 0-3.68-.79-4.94-2.06l-1.42 1.42A8.954 8.954 0 0 0 13 21a9 9 0 0 0 0-18zm-1 5v5l4.28 2.54.72-1.21-3.5-2.08V8H12z") }
    val Calendar: ImageVector by lazy { icon24("event", "M17 12h-5v5h5v-5zM16 1v2H8V1H6v2H5c-1.11 0-1.99.9-1.99 2L3 19c0 1.1.89 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2h-1V1h-2zm3 18H5V8h14v11z") }
    val Share: ImageVector by lazy { icon24("share", "M18 16.08c-.76 0-1.44.3-1.96.77L8.91 12.7c.05-.23.09-.46.09-.7s-.04-.47-.09-.7l7.05-4.11c.54.5 1.25.81 2.04.81 1.66 0 3-1.34 3-3s-1.34-3-3-3-3 1.34-3 3c0 .24.04.47.09.7L8.04 9.81C7.5 9.31 6.79 9 6 9c-1.66 0-3 1.34-3 3s1.34 3 3 3c.79 0 1.5-.31 2.04-.81l7.12 4.16c-.05.21-.08.43-.08.65 0 1.61 1.31 2.92 2.92 2.92 1.61 0 2.92-1.31 2.92-2.92s-1.31-2.92-2.92-2.92z") }
    val Shuffle: ImageVector by lazy { icon24("shuffle", "M10.59 9.17L5.41 4 4 5.41l5.17 5.17 1.42-1.41zM14.5 4l2.04 2.04L4 18.59 5.41 20 17.96 7.46 20 9.5V4h-5.5zm.33 9.41l-1.41 1.41 3.13 3.13L14.5 20H20v-5.5l-2.04 2.04-3.13-3.13z") }
    val Download: ImageVector by lazy { icon24("file_download", "M19 9h-4V3H9v6H5l7 7 7-7zM5 18v2h14v-2H5z") }
    val Grid: ImageVector by lazy { icon24("grid_view", "M3 3v8h8V3H3zm6 6H5V5h4v4zm-6 4v8h8v-8H3zm6 6H5v-4h4v4zm4-16v8h8V3h-8zm6 6h-4V5h4v4zm-6 4v8h8v-8h-8zm6 6h-4v-4h4v4z") }
    val Fire: ImageVector by lazy { icon24("whatshot", "M13.5.67s.74 2.65.74 4.8c0 2.06-1.35 3.73-3.41 3.73-2.07 0-3.63-1.67-3.63-3.73l.03-.36C5.21 7.51 4 10.62 4 14c0 4.42 3.58 8 8 8s8-3.58 8-8C20 8.61 17.41 3.8 13.5.67zM11.71 19c-1.78 0-3.22-1.4-3.22-3.14 0-1.62 1.05-2.76 2.81-3.12 1.77-.36 3.6-1.21 4.62-2.58.39 1.29.59 2.65.59 4.04 0 2.65-2.15 4.8-4.8 4.8z") }
    val Pin: ImageVector by lazy { icon24("push_pin", "M16 9V4h1c.55 0 1-.45 1-1s-.45-1-1-1H7c-.55 0-1 .45-1 1s.45 1 1 1h1v5c0 1.66-1.34 3-3 3v2h5.97v7l1 1 1-1v-7H19v-2c-1.66 0-3-1.34-3-3z") }
}

// The catalogue's icons by name (the server's docs/SDUI.md, Icons), as the icons the app already draws with: the
// website's on a phone or tablet and in the menus, so a server-driven page looks like the pages beside it. A name
// this app doesn't know gets a plain dot of a list, never nothing.
fun sduiIcon(name: String): ImageVector = when (name) {
    "home" -> WebIcons.Home
    "library", "collection", "folder" -> WebIcons.Library
    "movie", "video" -> WebIcons.Film
    "show", "tv" -> WebIcons.Tv
    "live", "guide" -> Symbols.LiveTv
    "record" -> WebIcons.Station
    "music", "album" -> WebIcons.Audio
    "artist", "user" -> Symbols.Person
    "users" -> Symbols.Group
    "kids" -> Symbols.Family
    "mic", "podcast" -> WebIcons.Mic
    "radio" -> WebIcons.Radio
    "book", "comic" -> WebIcons.Book
    "audiobook" -> WebIcons.Headphones
    "photo" -> WebIcons.Image
    "disc" -> WebIcons.Disc
    "game" -> WebIcons.Gamepad
    "list" -> WebIcons.AddList
    "search" -> WebIcons.Search
    "settings" -> WebIcons.Settings
    "star" -> WebIcons.Star
    "heart" -> WebIcons.Heart
    "clock" -> SduiSymbols.Clock
    "history" -> SduiSymbols.History
    "calendar" -> SduiSymbols.Calendar
    "sparkles" -> Symbols.Sparkles
    "fire" -> SduiSymbols.Fire
    "shuffle" -> SduiSymbols.Shuffle
    "play" -> WebIcons.Play
    "download" -> SduiSymbols.Download
    "share" -> SduiSymbols.Share
    "globe" -> Symbols.Globe
    "info" -> WebIcons.Info
    "warning" -> Symbols.Warning
    "check" -> WebIcons.Check
    "plus" -> WebIcons.Plus
    "grid" -> SduiSymbols.Grid
    "filter" -> WebIcons.Tune
    "sort" -> WebIcons.SortDown
    "plug" -> WebIcons.Plug
    "chart" -> WebIcons.Chart
    "devices" -> Symbols.Devices
    "more" -> WebIcons.More
    else -> WebIcons.More
}

// What stands in for a picture that isn't there, by the kind of thing it is.
fun sduiKindIcon(kind: String): ImageVector = when (kind) {
    "movie", "video", "episode", "recording" -> WebIcons.Film
    "show" -> WebIcons.Tv
    "album", "track" -> WebIcons.Audio
    "artist" -> Symbols.Person
    "book" -> WebIcons.Book
    "audiobook" -> WebIcons.Headphones
    "podcast" -> WebIcons.Mic
    "game" -> WebIcons.Gamepad
    "photo" -> WebIcons.Image
    "channel" -> Symbols.LiveTv
    "library", "collection" -> WebIcons.Library
    "disc" -> WebIcons.Disc
    else -> WebIcons.Film
}

// What this device says it is with every request for a page (net/SduiClient.kt): a phone, a tablet or a TV, the
// window in dp, the language, and the app's own rich views a page may ask for.
fun sduiDeviceFor(app: WittyApp, config: Configuration, reduceMotion: Boolean): SduiDevice {
    val tv = app.isTv
    val memory = app.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
    // A TV stick with 1 or 2 GB reports itself low on memory, or gives each app a small heap.
    val lowMemory = memory?.isLowRamDevice == true || (memory?.memoryClass ?: LOW_HEAP_MB) < LOW_HEAP_MB
    return SduiDevice(
        platform = if (tv) "androidtv" else "android",
        formFactor = SduiDevice.formFactor(tv, config.smallestScreenWidthDp),
        // A TV's canvas is the server's own 1920 by 1080; what differs is how many pixels the app really draws.
        deviceClass = if (tv) SduiDevice.tvClass(app.resources.displayMetrics.heightPixels, lowMemory) else "",
        viewport = if (tv) "" else "${config.screenWidthDp}x${config.screenHeightDp}",
        locale = androidx.core.os.ConfigurationCompat.getLocales(config)[0]?.toLanguageTag().orEmpty(),
        capabilities = buildList {
            if (!tv) add("touch")
            if (reduceMotion) add("reducedMotion")
        },
        // The guide's grid is the app's own on a TV, and the server's own page inside the app elsewhere. The photo
        // timeline, the map and cover flow aren't here, so the server sends what stands in for them.
        views = listOf("guide"),
        device = app.layoutDeviceName,
    )
}

private const val LOW_HEAP_MB = 192
