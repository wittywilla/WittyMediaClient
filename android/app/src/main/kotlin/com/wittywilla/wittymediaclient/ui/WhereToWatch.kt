// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
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
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
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
    val metrics = LocalMetrics.current
    Box(
        Modifier.size(metrics.u(120), metrics.u(56)).clip(metrics.corner(10)).background(scheme.surface).clearAndSetSemantics { contentDescription = name },
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.fillMaxSize().padding(horizontal = metrics.u(12), vertical = metrics.u(8)), contentAlignment = Alignment.Center) {
            BrandLogo(nav.app.api, name, logo, metrics.u(96), metrics.u(40), 12, scheme.onSurface)
        }
    }
}

// `itemId` is the film or the episode asked about; a show's page gives one of its episodes. Nothing at all on a
// server without the feature, while it's being asked, or when there's nothing to say. A section of the title's page
// in Design 2's parts (DesignPage.kt): its heading, the notes, the versions as chips and the services as tiles.
@Composable
fun WhereToWatchSection(nav: Nav, itemId: Long, modifier: Modifier = Modifier) {
    if (itemId <= 0 || !nav.has(ExtrasFeature.WHERE_TO_WATCH)) return
    var attempt by remember(itemId) { mutableIntStateOf(0) }
    val state = rememberWatch(nav, itemId, attempt)
    val admin = nav.me?.isAdmin == true
    when (state) {
        WatchAnswer.Asking -> return
        WatchAnswer.Failed -> {
            DesignSized {
                DesignSection("Where to watch", modifier) {
                    DesignNote("Where else this can be watched couldn't be read from your server.")
                    DesignChips { DesignChip("Try again", { attempt++ }, focusKey = "watch-retry") }
                }
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
    DesignSized {
        val s = LocalDesignSizes.current
        val scheme = MaterialTheme.colorScheme
        val extra = LocalExtraColours.current
        val tv = LocalMetrics.current.tv
        DesignSection("Where to watch", modifier) {
            DesignNote(WatchLook.hereWords(answer))
            if (others.isNotEmpty()) {
                DesignChips {
                    others.forEach { v ->
                        DesignChip(WatchLook.versionWords(v), { nav.push(Route.Item(v.itemId)) }, focusKey = "watch-version-${v.itemId}")
                    }
                }
            }
            sections.forEach { section ->
                Text(section.title, color = scheme.onSurfaceVariant, fontSize = s.small, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = s.gap * 0.6f))
                FlowRow(
                    Modifier.semantics { contentDescription = "${section.title}: ${section.providers.joinToString { it.name }}" },
                    horizontalArrangement = Arrangement.spacedBy(s.gap * 0.8f), verticalArrangement = Arrangement.spacedBy(s.gap * 0.8f),
                ) {
                    section.providers.forEach { p -> ServiceTile(nav, p.name, logos[BrandLogoAnswer.key("platform", p.name)]) }
                }
            }
            DesignNote(reason)
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
                Text(note, color = scheme.onSurfaceVariant, fontSize = s.small, lineHeight = s.small * 1.5f, modifier = Modifier.padding(top = s.gap * 0.6f).widthIn(max = s.leadWidth))
                if (link != null && tv) {
                    DesignChips { DesignChip(if (code) "Hide the code" else "See every offer on a phone", { code = !code }, on = code, focusKey = "watch-offers") }
                    if (code) QrCard(link, "Scan with a phone's camera to open the list of offers.")
                }
                if (!tv) LegalLine(nav, "listings")
                if (!tv && sections.any { sec -> sec.providers.any { logos[BrandLogoAnswer.key("platform", it.name)]?.has == true } }) LegalLine(nav, "logos")
            }
        }
    }
}
