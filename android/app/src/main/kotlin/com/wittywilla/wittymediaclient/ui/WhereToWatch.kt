// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.wittywilla.wittymediaclient.net.BrandLogoAnswer
import com.wittywilla.wittymediaclient.net.ExtrasFeature
import com.wittywilla.wittymediaclient.net.WatchLook
import com.wittywilla.wittymediaclient.net.WhereToWatch
import com.wittywilla.wittymediaclient.net.whereToWatch
import kotlinx.coroutines.CancellationException

// Where to watch, on a title's page: the copy here and its other versions, beside the streaming services that offer
// the title in the server's region (GET /media/{id}/where-to-watch). Nothing plays from those services and nothing is
// fetched from them: their logos come from the server's own logo service, as a studio's do. On a phone or tablet the
// source's page of offers opens in the browser; a TV never opens anything outside, and shows a code for a phone.

private sealed interface WatchAnswer {
    data object Asking : WatchAnswer
    data object Failed : WatchAnswer
    data class Here(val answer: WhereToWatch, val logos: Map<String, BrandLogoAnswer>) : WatchAnswer
}

@Composable
private fun rememberWatch(nav: Nav, itemId: Long, attempt: Int): WatchAnswer {
    var state by remember(itemId) { mutableStateOf<WatchAnswer>(WatchAnswer.Asking) }
    LaunchedEffect(itemId, attempt) {
        val api = nav.app.api
        state = try {
            val answer = api.whereToWatch(itemId)
            val names = WatchLook.sections(answer).flatMap { it.providers }.map { "platform" to it.name }.distinct()
            WatchAnswer.Here(answer, lookUpLogos(api, names))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (nav.handleExpired(e)) WatchAnswer.Asking else WatchAnswer.Failed
        }
    }
    return state
}

// A service as a tile, as a studio's is, but nothing to press: it's a fact, not a way in.
@Composable
private fun ServiceTile(nav: Nav, name: String, logo: BrandLogoAnswer?) {
    val scheme = MaterialTheme.colorScheme
    Box(
        Modifier.size(120.dp, 56.dp).clip(RoundedCornerShape(10.dp)).background(scheme.surfaceVariant).clearAndSetSemantics { contentDescription = name },
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.fillMaxSize().padding(horizontal = 12.dp, vertical = 8.dp), contentAlignment = Alignment.Center) {
            BrandLogo(nav.app.api, name, logo, 96.dp, 40.dp, 12, scheme.onBackground)
        }
    }
}

// `itemId` is the film or the episode asked about; a show's page gives one of its episodes. Nothing at all on a
// server without the feature, while it's being asked, or when there's nothing to say.
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun WhereToWatchSection(nav: Nav, itemId: Long, modifier: Modifier = Modifier) {
    if (itemId <= 0 || !nav.has(ExtrasFeature.WHERE_TO_WATCH)) return
    var attempt by remember(itemId) { mutableIntStateOf(0) }
    val state = rememberWatch(nav, itemId, attempt)
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val tv = LocalMetrics.current.tv
    val admin = nav.me?.isAdmin == true
    @Composable
    fun Head() {
        if (tv) SectionTitle("Where to watch")
        else Text(
            "Where to watch", color = scheme.onBackground, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, letterSpacing = (-0.012).em,
            modifier = Modifier.semantics { heading() },
        )
    }
    when (state) {
        WatchAnswer.Asking -> return
        WatchAnswer.Failed -> {
            Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Head()
                Text("Where else this can be watched couldn't be read from your server.", color = extra.hint, fontSize = if (tv) 16.sp else 13.sp)
                if (tv) ActionButton("Try again", { attempt++ }, focusKey = "watch-retry") else WebButton("Try again", { attempt++ }, small = true)
            }
            return
        }
        is WatchAnswer.Here -> {}
    }
    val (answer, logos) = state
    if (!WatchLook.hasAnything(answer, itemId, admin)) return
    val sections = WatchLook.sections(answer)
    val others = WatchLook.otherVersions(answer, itemId)
    val link = WatchLook.offersLink(answer)
    val reason = WatchLook.reasonWords(answer, admin)
    var code by remember(itemId) { mutableStateOf(false) }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(if (tv) Space.S3 else 12.dp)) {
        Head()
        val here = WatchLook.hereWords(answer)
        if (here.isNotEmpty()) {
            if (tv) Secondary(here) else Text(here, color = scheme.onBackground, fontSize = 14.sp)
        }
        if (others.isNotEmpty()) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                others.forEach { v ->
                    val words = WatchLook.versionWords(v)
                    if (tv) ActionButton(words, { nav.push(Route.Item(v.itemId)) }, pill = true, focusKey = "watch-version-${v.itemId}")
                    else WebButton(words, { nav.push(Route.Item(v.itemId)) })
                }
            }
        }
        sections.forEach { section ->
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (tv) Secondary(section.title) else Text(section.title, color = scheme.onSurfaceVariant, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                FlowRow(
                    Modifier.semantics { contentDescription = "${section.title}: ${section.providers.joinToString { it.name }}" },
                    horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    section.providers.forEach { p -> ServiceTile(nav, p.name, logos[BrandLogoAnswer.key("platform", p.name)]) }
                }
            }
        }
        if (reason.isNotEmpty()) Text(reason, color = extra.hint, fontSize = if (tv) 16.sp else 13.sp)
        if (sections.isNotEmpty()) {
            val note = buildAnnotatedString {
                withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append("Nothing plays from these services.") }
                append(" Listed for ${answer.region}. ${answer.attribution}".trimEnd())
                // A phone or a tablet has a browser for the source's own page. A TV doesn't open anything outside.
                if (link != null && !tv) {
                    append(" ")
                    withLink(LinkAnnotation.Url(link, TextLinkStyles(SpanStyle(color = extra.accentText, textDecoration = TextDecoration.Underline)))) { append("See every offer") }
                }
            }
            Text(note, color = extra.hint, fontSize = if (tv) 16.sp else 13.sp)
            if (link != null && tv) {
                ActionButton(if (code) "Hide the code" else "See every offer on a phone", { code = !code }, pill = true, focusKey = "watch-offers")
                if (code) QrCard(link, "Scan with a phone's camera to open the list of offers.")
            }
            if (!tv) LegalLine(nav, "listings")
            if (!tv && sections.any { s -> s.providers.any { logos[BrandLogoAnswer.key("platform", it.name)]?.has == true } }) LegalLine(nav, "logos")
        }
    }
}
