// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.games

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wittywilla.wittymediaclient.net.ApiError
import kotlinx.coroutines.launch

// A game's page, as the website's (web/src/pages/games/Details.tsx): what it is, one big button to play it, where
// it was left off, and the rest below. Whatever stops a game from starting says so here in the server's own words
// from its readiness check, and Play doesn't appear for it (docs/APP-DESIGN.md, "Games everywhere").

// The heading of what stops a game, by the check's reason; the server's message says the rest.
fun blockedTitle(reason: String): String = when (reason) {
    "core" -> "This game needs a core first"
    "bios" -> "This game needs a BIOS file"
    "gpu" -> "This game needs a graphics card"
    else -> "This console can't play here yet"
}

// The server's own words for why a game can't play, or plain ones where it sends none.
fun blockedWords(check: GameCheck?, console: GameConsole?): String {
    val said = check?.message.orEmpty().ifEmpty { console?.unavailable.orEmpty() }
    if (said.isNotEmpty()) return said
    return when (check?.reason) {
        "core" -> "Ask whoever runs this server to install a core for this console."
        "bios" -> "Ask whoever runs this server to add the BIOS file it needs."
        else -> "This server can't play it yet."
    }
}

// Whether the main button shows: the check decides, and the console's own `ready` until it has answered.
fun canPlay(check: GameCheck?, console: GameConsole?, details: GameDetails?): Boolean =
    (check?.ready ?: console?.ready ?: false) && details?.problem.isNullOrEmpty()

private const val REFRESH = "Refresh game details"

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun GamePageScreen(nav: GamesNav, gameId: Long, inShell: Boolean = false) {
    val look = gameLook()
    val api = remember(nav.api) { GamesApi(nav.api) }
    val scope = rememberCoroutineScope()
    var refreshWords by remember(gameId) { mutableStateOf(REFRESH) }
    var game by remember { mutableStateOf<GameItem?>(null) }
    var check by remember { mutableStateOf<GameCheck?>(null) }
    var console by remember { mutableStateOf<GameConsole?>(null) }
    var details by remember { mutableStateOf<GameDetails?>(null) }
    var mine by remember { mutableStateOf<GamePersonal?>(null) }
    var saves by remember { mutableStateOf<List<GameSave>>(emptyList()) }
    var versions by remember { mutableStateOf<List<GameVersion>>(emptyList()) }
    var resumeSetting by remember { mutableStateOf("ask") }
    var failed by remember { mutableStateOf("") }
    var attempt by remember { mutableIntStateOf(0) }
    var longRead by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf<Int?>(null) }
    var moreOpen by remember { mutableStateOf(false) }

    LaunchedEffect(gameId, attempt) {
        failed = ""
        try {
            val g = api.item(gameId)
            game = g
            launch { runCatching { api.check(gameId) }.onSuccess { check = it } }
            launch { runCatching { api.consoles() }.onSuccess { list -> console = list.firstOrNull { it.id == g.console } } }
            launch { runCatching { api.details(gameId) }.onSuccess { details = it } }
            launch { runCatching { api.personal(gameId) }.onSuccess { mine = it } }
            launch { runCatching { api.saves(gameId) }.onSuccess { saves = it } }
            launch { runCatching { api.versions(gameId) }.onSuccess { versions = it.versions } }
            launch { runCatching { api.settings(gameId) }.onSuccess { resumeSetting = it.text("states.resume", "ask") } }
        } catch (e: ApiError) {
            failed = e.message.orEmpty()
        } catch (e: Exception) {
            if (e is kotlinx.coroutines.CancellationException) throw e
            failed = "Check this device's connection, then try again."
        }
    }

    val g = game
    if (g == null) {
        Box(Modifier.fillMaxSize().background(GameColours.background), contentAlignment = Alignment.Center) {
            if (failed.isNotEmpty()) GameNote("This game didn't load", failed, action = "Try again", onAction = { attempt++ })
            else CircularProgressIndicator(color = GameColours.accent)
        }
        return
    }
    val words = com.wittywilla.wittymediaclient.ui.LocalWords.current
    val auto = saves.firstOrNull { it.slot == 0 }
    val ready = canPlay(check, console, details)
    val resumes = resumes(resumeSetting, auto != null)
    val playButton = remember { FocusRequester() }
    val favouriteButton = remember { FocusRequester() }
    // Focus lands on Play, or on a TV where there's no Play, on the first thing that can take it.
    LaunchedEffect(ready, resumes, mine != null) {
        if (ready) runCatching { playButton.requestFocus() } else if (look.tv && mine != null) runCatching { favouriteButton.requestFocus() }
    }

    Box(Modifier.fillMaxSize().background(GameColours.background)) {
        val pageScroll = rememberScrollState()
        if (inShell) com.wittywilla.wittymediaclient.ui.TracksScroll(pageScroll)
        Box(Modifier.fillMaxSize().verticalScroll(pageScroll)) {
            // The backdrop across the top, faint and fading into the page, scrolling away with it.
            // The backdrop, else where you left off, as Apple's game page: clear on a phone, faint on a TV.
            val heroUrl = if (g.hasBackdrop) api.backdropUrl(g) else auto?.takeIf { it.hasThumb }?.let { api.saveThumbUrl(g.id, 0, it.updatedAt) }
            // In the app's shell the top bar shades the picture under it, as over any page with one.
            if (inShell) com.wittywilla.wittymediaclient.ui.HeroPage(heroUrl != null)
            if (heroUrl != null) {
                val heroHeight = if (look.tv) 270.dp else 300.dp
                GamePicture(heroUrl, g.title, Modifier.fillMaxWidth().height(heroHeight).graphicsLayer { alpha = if (look.tv) 0.24f else 0.9f }, contentScale = ContentScale.Crop)
                Box(Modifier.fillMaxWidth().height(heroHeight).background(Brush.verticalGradient(0.55f to Color.Transparent, 1f to GameColours.background)))
            }
            Column(Modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.statusBars)) {
                if (!look.tv && !inShell) {
                    Pressable(nav.back, Modifier.padding(start = look.gutter, top = 8.dp).size(40.dp), radius = 20.dp, label = "Back", fill = GameColours.background.copy(alpha = 0.7f)) {
                        Icon(GameIcons.Back, null, Modifier.align(Alignment.Center).size(22.dp), tint = GameColours.text)
                    }
                }
                BoxWithConstraints(Modifier.fillMaxWidth().padding(horizontal = look.gutter, vertical = if (look.tv) 24.dp else 16.dp)) {
                    val wide = maxWidth > 720.dp
                    val narrowCover = 140.dp
                    val cover = @Composable { m: Modifier ->
                        Box(m.aspectRatio(0.75f), contentAlignment = Alignment.BottomCenter) {
                            if (g.hasPoster) GamePicture(api.posterUrl(g, 800), g.title, Modifier.fillMaxSize().clip(RoundedCornerShape(10.dp)))
                            else GamePlaceholder(g.title, console?.shortName.orEmpty(), Modifier.fillMaxSize().clip(RoundedCornerShape(10.dp)))
                            if (auto != null) GameRibbon(Modifier.align(Alignment.TopEnd).padding(end = 12.dp).offset(y = (-4).dp))
                        }
                    }
                    val info = @Composable { m: Modifier ->
                        Column(m, horizontalAlignment = Alignment.Start, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            // A phone has the console beside the cover, as Apple's.
                            if (wide) console?.let { Text(it.shortName, color = GameColours.secondary, fontSize = if (look.tv) look.small else 13.sp) }
                            Text(g.title, color = GameColours.text, fontSize = look.display, fontWeight = FontWeight.Bold, textAlign = TextAlign.Start)
                            if (g.tagline.isNotEmpty()) Text(g.tagline, color = GameColours.secondary, fontSize = if (look.tv) look.body else 17.sp, textAlign = TextAlign.Start)
                            val facts = listOfNotNull(
                                console?.name?.ifEmpty { null }?.takeIf { wide }, g.year?.toString(), details?.players?.takeIf { it > 0 }?.let { GameWords.players(it) },
                                g.contentRating.ifEmpty { null }, g.rating?.let { "★ %.1f".format(it) }, g.genres.take(3).joinToString(", ").ifEmpty { null },
                            )
                            if (facts.isNotEmpty()) Text(facts.joinToString("  ·  "), color = GameColours.secondary, fontSize = look.small, textAlign = TextAlign.Start)
                            val played = g.playedSeconds
                            val sessions = mine?.plays ?: 0
                            // A phone says time played under Where you left off instead.
                            if (wide && (played > 60 || sessions > 0)) {
                                Text(
                                    listOfNotNull(if (played > 60) "${GameWords.played(played)} played" else null, if (sessions > 0) "$sessions ${if (sessions == 1) "session" else "sessions"}" else null).joinToString("   "),
                                    color = GameColours.secondary, fontSize = look.small,
                                )
                            }
                            details?.problem?.takeIf { it.isNotEmpty() }?.let { Blocked(it) }
                            // Resume (or Play), Favourite and More in one row: on a phone Resume takes the width and Start over is
                            // under More, as Apple's.
                            val playIt = { nav.play(g.id, GameStart(resume = resumes)) }
                            val favourite: @Composable () -> Unit = {
                                mine?.let { m ->
                                    GameIconButton(GameIcons.Star, if (m.favourite) "Favourite" else "Add to favourites", {
                                        scope.launch { runCatching { api.setFavourite(g.id, !m.favourite) }.onSuccess { mine = it } }
                                    }, on = m.favourite, tint = if (m.favourite) Color(0xFFFFC94D) else null, focusRequester = favouriteButton)
                                }
                            }
                            if (wide) {
                                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                    if (ready) {
                                        GameButton(if (resumes) "Resume" else "Play", playIt, kind = ButtonKind.Primary, icon = GameIcons.Play, focusRequester = playButton)
                                        if (auto != null) GameButton("Start over", { nav.play(g.id, GameStart(resume = false)) })
                                    }
                                    favourite()
                                    if (ready) GameIconButton(GameIcons.More, "More for this game", { moreOpen = !moreOpen }, on = moreOpen)
                                }
                            } else {
                                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                                    if (ready) GameButton(if (resumes) "Resume" else "Play", playIt, Modifier.weight(1f), kind = ButtonKind.Primary, icon = GameIcons.Play, focusRequester = playButton, pill = true)
                                    mine?.let { m ->
                                        GameIconButton(GameIcons.Star, if (m.favourite) "Favourite" else "Add to favourites", {
                                            scope.launch { runCatching { api.setFavourite(g.id, !m.favourite) }.onSuccess { mine = it } }
                                        }, on = m.favourite, tint = if (m.favourite) Color(0xFFFFC94D) else null, focusRequester = favouriteButton, pill = true)
                                    }
                                    if (ready) GameIconButton(GameIcons.More, "More for this game", { moreOpen = !moreOpen }, on = moreOpen, pill = true)
                                }
                            }
                            if (moreOpen && ready) {
                                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                    // On a phone Start over (or Resume) is here, as under Apple's ⋯.
                                    if (!wide && auto != null) {
                                        if (resumes) GameButton(words["wpStartOver"] ?: "Start over", { nav.play(g.id, GameStart(resume = false)) }, icon = GameIcons.Refresh, big = false)
                                        else GameButton("Resume", { nav.play(g.id, GameStart(resume = true)) }, icon = GameIcons.Play, big = false)
                                    }
                                    GameButton("Start with default settings", { nav.play(g.id, GameStart(resume = auto != null, safeMode = true)) }, icon = GameIcons.Refresh, big = false)
                                    // An administrator looks the game up again from the start, as the website's game page.
                                    if (nav.admin) GameButton(refreshWords, {
                                        if (refreshWords != REFRESH) return@GameButton
                                        refreshWords = "Refreshing game details…"
                                        scope.launch {
                                            refreshWords = runCatching { api.refreshDetails(g.id) }.fold({ "Game details are being refreshed" }, { it.message ?: "The details couldn’t be refreshed. Try again." })
                                        }
                                    }, icon = GameIcons.Refresh, big = false)
                                }
                            }
                            if (auto != null && ready) ResumeCard(api, g, auto, words) { nav.play(g.id, GameStart(resume = true)) }
                            // What stops it: the server's own words, from its readiness check.
                            val c = check
                            if (c != null && !c.ready) Blocked(blockedWords(c, console), title = blockedTitle(c.reason))
                            else if (c == null && console?.ready == false) Blocked(blockedWords(null, console), title = blockedTitle(""))
                        }
                    }
                    if (wide) {
                        Row(horizontalArrangement = Arrangement.spacedBy(if (look.tv) 40.dp else 32.dp), verticalAlignment = Alignment.Bottom) {
                            cover(Modifier.width(if (look.tv) 180.dp else 220.dp))
                            info(Modifier.weight(1f))
                        }
                    } else {
                        // A phone, as Apple's: the cover small at the left over the picture, the console beside it, then the rest.
                        Column(Modifier.fillMaxWidth().padding(top = if (heroUrl != null) (if (inShell) 168.dp else 120.dp) else if (inShell) 48.dp else 0.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                                cover(Modifier.width(narrowCover))
                                console?.let { Text(it.shortName, color = GameColours.secondary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(bottom = 8.dp)) }
                            }
                            info(Modifier.fillMaxWidth())
                        }
                    }
                }

                Column(Modifier.padding(horizontal = look.gutter), verticalArrangement = Arrangement.spacedBy(look.sectionGap)) {
                    if (g.overview.isNotEmpty()) {
                        Section("About this game") {
                            Text(g.overview, color = GameColours.text, fontSize = look.body, maxLines = if (longRead) Int.MAX_VALUE else 6, overflow = TextOverflow.Ellipsis, lineHeight = look.body * 1.5f)
                            if (g.overview.length > 420) GameButton(if (longRead) "Show less" else "Read more", { longRead = !longRead }, kind = ButtonKind.Ghost, big = false)
                        }
                    }
                    val facts = listOfNotNull(
                        details?.released?.takeIf { it.isNotEmpty() }?.let { "Released" to it } ?: g.year?.let { "Year" to it.toString() },
                        g.studio.ifEmpty { null }?.let { "Developer" to it },
                        details?.publisher?.ifEmpty { null }?.let { "Publisher" to it },
                        details?.players?.takeIf { it > 0 }?.let { "Players" to if (it == 1) "1" else "Up to $it" },
                        details?.franchise?.ifEmpty { null }?.let { "Series" to it },
                        g.genres.joinToString(", ").ifEmpty { null }?.let { "Genres" to it },
                    )
                    if (facts.isNotEmpty()) {
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                            for ((name, value) in facts) Column(Modifier.widthIn(min = 140.dp, max = 320.dp)) {
                                Text(name.uppercase(), color = GameColours.hint, fontSize = if (look.tv) look.small else 11.sp, fontWeight = FontWeight.SemiBold)
                                Text(value, color = GameColours.text, fontSize = look.body)
                            }
                        }
                    }
                    val others = versions.filter { !it.current }
                    if (others.isNotEmpty()) {
                        Section("Other versions") {
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                for (v in others) GameChip(v.label.ifEmpty { "Version ${v.id}" }, false, { nav.openGame(v.id) })
                            }
                        }
                    }
                    // Moments, as Apple's: newest first, then the server's two for undoing; where you left off is above.
                    val moments = saves.filter { it.slot in 1..99 }.sortedByDescending { it.updatedAt } + saves.filter { it.slot == 100 } + saves.filter { it.slot == 101 }
                    fun momentName(slot: Int) = when (slot) {
                        100 -> words["wpBeforeYouLoaded"] ?: "Before you loaded"
                        101 -> words["wpBeforeStartingOver"] ?: "Before starting over"
                        else -> (words["wpMoment"] ?: "Moment") + " $slot"
                    }
                    if (moments.isNotEmpty()) {
                        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text(words["wpMoments"] ?: "Moments", color = GameColours.text, fontSize = look.title, fontWeight = FontWeight.Bold)
                                Text("${moments.size}", color = GameColours.hint, fontSize = look.small, modifier = Modifier.padding(bottom = 3.dp))
                            }
                            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(if (look.tv) 16.dp else 12.dp)) {
                                for (s in moments) {
                                    // 304 TV units (half a dp each), as Apple TV's.
                                    val w = if (look.tv) 152.dp else 200.dp
                                    Column(Modifier.width(w), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                        Pressable(
                                            { if (ready) nav.play(g.id, GameStart(resume = false, slot = s.slot)) },
                                            Modifier.width(w).aspectRatio(4f / 3f).clip(RoundedCornerShape(10.dp)),
                                            label = "${words["wpPlayFromHere"] ?: "Play from here"}: ${momentName(s.slot)}, saved ${GameWords.ago(s.updatedAt)}",
                                            fill = GameColours.card,
                                        ) {
                                            if (s.hasThumb) GamePicture(api.saveThumbUrl(g.id, s.slot, s.updatedAt), "", Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                                        }
                                        Row(verticalAlignment = Alignment.CenterVertically) {
                                            Column(Modifier.weight(1f)) {
                                                Text(momentName(s.slot), color = GameColours.text, fontSize = look.small, fontWeight = FontWeight.SemiBold, maxLines = 1)
                                                Text(GameWords.ago(s.updatedAt), color = GameColours.hint, fontSize = look.small, maxLines = 1)
                                            }
                                            val asking = deleting == s.slot
                                            Pressable({
                                                if (!asking) {
                                                    deleting = s.slot
                                                } else {
                                                    deleting = null
                                                    scope.launch { runCatching { api.deleteSave(g.id, s.slot) }.onSuccess { saves = saves.filter { it.slot != s.slot } } }
                                                }
                                            }, label = if (asking) "Delete for good" else "Delete ${momentName(s.slot)}", radius = 8.dp) {
                                                Row(Modifier.padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
                                                    Icon(GameIcons.Trash, null, Modifier.size(18.dp), tint = if (asking) GameColours.danger else GameColours.secondary)
                                                    if (asking) Text(" Delete?", color = GameColours.danger, fontSize = look.small)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Panel("How it plays") {
                        Check(true, "Runs on your server", "and streams to this device, so this device needs no emulator and nothing downloads. Saves stay on the server, and follow you to every device.")
                        check?.core?.takeIf { it.name.isNotEmpty() }?.let { Check(true, it.name, "The core that plays this game. Licence: ${it.license.ifEmpty { "not known" }}.") }
                        if (check?.reason == "core") Check(false, "No core installed", "Ask whoever runs this server.")
                        if (check?.needsGpu == true) Check(null, "Uses the server's graphics card", "This console is drawn with one, so it needs a server that has one.")
                        for (b in check?.bios.orEmpty().filter { it.required || it.found }) {
                            Check(b.found, "BIOS: ${b.file}", if (b.found) "Found. ${b.`for`}." else "Not found yet. ${b.`for`}. Put your own copy in a folder named ${check?.biosFolder?.ifEmpty { null } ?: "BIOS"} beside these games.")
                        }
                        console?.unavailable?.takeIf { it.isNotEmpty() }?.let { Check(false, "Not playable here yet", it) }
                    }
                    Panel("Controls") {
                        val pad = console?.pad
                        if (pad != null) {
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                for (name in listOf("D-pad") + (if (pad.sticks) listOf("Stick") else emptyList()) + pad.buttons.map { it.label }) Pill(name)
                            }
                        }
                        Text(
                            if (look.tv) "Play with a controller; the remote is for the menus. Back, or Start and Select together, opens the game menu."
                            else "Controllers, keyboards and the touch screen all work. Start and Select together, Escape or the button in the corner open the game menu.",
                            color = GameColours.secondary, fontSize = look.small,
                        )
                    }
                    // Room under the page for the app's floating bar when it is in the shell.
                    Spacer(Modifier.height(24.dp + if (inShell) com.wittywilla.wittymediaclient.ui.LocalBottomRoom.current else 0.dp).windowInsetsPadding(WindowInsets.navigationBars))
                }
            }
        }
        // What scrolls under the clock fades into the page.
        Box(Modifier.fillMaxWidth().windowInsetsTopHeight(WindowInsets.statusBars).background(Brush.verticalGradient(listOf(GameColours.background, GameColours.background.copy(alpha = 0.6f)))))
    }
}

// "Pick up where you left off": the automatic save's picture and when it was made.
@Composable
private fun ResumeCard(api: GamesApi, g: GameItem, auto: GameSave, words: Map<String, String>, onClick: () -> Unit) {
    val look = gameLook()
    Pressable(onClick, Modifier.fillMaxWidth().border(1.dp, GameColours.border, RoundedCornerShape(14.dp)), fill = GameColours.panel, radius = 14.dp, label = "Resume from ${GameWords.ago(auto.updatedAt)}") {
        Row(Modifier.padding(8.dp).padding(end = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(Modifier.width(if (look.tv) 64.dp else 96.dp).aspectRatio(4f / 3f).clip(RoundedCornerShape(4.dp)).background(GameColours.card)) {
                if (auto.hasThumb) GamePicture(api.saveThumbUrl(g.id, 0, auto.updatedAt), "", Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                GameRibbon(Modifier.align(Alignment.TopEnd).padding(end = 8.dp), height = 26.dp)
            }
            Column {
                Text(words["wpWhereYouLeftOff"] ?: "Where you left off", color = GameColours.text, fontSize = look.body, fontWeight = FontWeight.SemiBold)
                Text(GameWords.ago(auto.updatedAt), color = GameColours.secondary, fontSize = look.small)
                if (g.playedSeconds > 60) Text("${GameWords.played(g.playedSeconds)} played", color = GameColours.secondary, fontSize = look.small)
            }
        }
    }
}

@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    val look = gameLook()
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(title, color = GameColours.text, fontSize = look.title, fontWeight = FontWeight.SemiBold)
        content()
    }
}

@Composable
private fun Panel(title: String, content: @Composable () -> Unit) {
    val look = gameLook()
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(GameColours.panel).border(1.dp, GameColours.border, RoundedCornerShape(14.dp)).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(title, color = GameColours.text, fontSize = if (look.tv) look.title else 17.sp, fontWeight = FontWeight.SemiBold)
        content()
    }
}

// A line of "How it plays": ticked, missing, or just so.
@Composable
private fun Check(ok: Boolean?, title: String, words: String) {
    val look = gameLook()
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(
            if (ok == true) GameIcons.Check else GameIcons.Info, null, Modifier.padding(top = 2.dp).size(16.dp),
            tint = when (ok) {
                true -> GameColours.ok
                false -> GameColours.danger
                null -> GameColours.hint
            },
        )
        Column {
            Text(title, color = GameColours.text, fontSize = look.body, fontWeight = FontWeight.SemiBold)
            Text(words, color = GameColours.secondary, fontSize = look.small)
        }
    }
}

@Composable
private fun Pill(text: String) {
    val look = gameLook()
    Text(
        text,
        Modifier.clip(RoundedCornerShape(999.dp)).background(GameColours.card).padding(horizontal = 10.dp, vertical = 4.dp),
        color = GameColours.text, fontSize = if (look.tv) look.small else 12.sp, fontWeight = FontWeight.SemiBold,
    )
}
