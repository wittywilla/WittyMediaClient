// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wittywilla.wittymediaclient.net.SduiNavItem

// The frames an experience draws the app's menu in (docs/plans/DESIGN-2.md section 7). The server says which in the
// page's `layout.shell`: the menu's style (a `navStyles` entry) and its breadth, open width and drawer. The frame is
// drawn from those, never from the experience's id. A phone's tab bar and a TV's top menu are the app's existing ones
// (PhoneShell.kt, TvTabs.kt); these are the others.

// The menu's style from the server, or the app's usual one for this device when the server has no layout options.
fun menuStyle(nav: Nav, tv: Boolean): String = nav.sduiNav?.shell?.nav?.takeIf { it in MENU_STYLES } ?: if (tv) "tvTopMenu" else "bottomTabs"

// How each style is drawn: a column down the side, a bar across the top, or the app's own bar. Styles that differ only in
// finish (a cable bar, a bevelled bar, glass, the tele keys, a headset's ornament tabs) are the top bar in the theme's own
// colours; the finish tokens (docs/plans/DESIGN-2-SDUI-GAPS.md) restyle it when the server sends them.
fun isSideStyle(style: String) = style == "sidebar" || style == "rail" || style == "railDrawer"
fun isTopStyle(style: String) = style in TOP_STYLES

// The menu's breadth in points, from the server, else the specification's for that style.
fun menuSize(nav: Nav, style: String, tablet: Boolean): Int = nav.sduiNav?.shell?.size?.takeIf { it > 0 } ?: when (style) {
    "sidebar" -> if (tablet) 220 else 240
    "rail", "railDrawer" -> if (tablet) 72 else 76
    "topTabs" -> if (tablet) 56 else 48
    "tvSideMenu" -> 120
    else -> 56
}

private val TOP_STYLES = setOf("topTabs", "floatingGlass", "cableBar", "bevelBar", "teleKeys", "ornamentTabs", "crossbar")
private val MENU_STYLES = setOf("sidebar", "rail", "railDrawer", "bottomTabs", "tvTopMenu", "tvSideMenu") + TOP_STYLES

private fun chosen(nav: Nav, route: Route): Boolean =
    nav.current.key == route.key || (route is Route.Page && (nav.current as? Route.Page)?.path?.startsWith(route.path) == true)

// One entry's picture: its icon, or the profile's avatar for You.
@Composable
private fun EntryMark(nav: Nav, entry: SduiNavItem, route: Route, tint: Color, size: Dp) {
    if (route == Route.Profile) {
        val me = nav.me
        Avatar((if (me == null) "" else avatarName(me.displayName, me.name)).ifEmpty { "?" }, size + 6.dp)
    } else {
        Icon(sduiIcon(entry.icon), null, tint = tint, modifier = Modifier.size(size))
    }
}

// A column down the side of a phone on its side or a tablet: the sidebar (icons and names) or the rail (icons, names
// read out). The page colour's panel with a hairline at its edge, as the drawer is.
@Composable
fun SideMenu(nav: Nav, closed: Dp, labels: Boolean, top: Dp, bottom: Dp, modifier: Modifier = Modifier) {
    val scheme = MaterialTheme.colorScheme
    val accentText = LocalExtraColours.current.accentText
    val line = scheme.outline
    val shell = nav.sduiNav?.shell
    // A rail is closed (icons) and opens to a full side menu while focus is in it, or when the person keeps it open
    // (docs/plans/DESIGN-2.md section 9). A sidebar is always open.
    val rail = !labels
    var inside by remember { mutableStateOf(false) }
    val pinned = RailPin.pinned
    val open = rail && (inside || pinned)
    val fullWidth = (shell?.open?.takeIf { it > 0 } ?: 240).dp
    val reduce = LocalReduceMotion.current
    val width by animateDpAsState(if (open) fullWidth else closed, if (reduce) tween(0) else tween(200), label = "rail")
    val showLabels = labels || open
    Column(
        modifier.width(width).fillMaxHeight().background(scheme.surface).onFocusChanged { inside = it.hasFocus }
            .drawWithContent { drawContent(); drawRect(line, Offset(size.width - 1.dp.toPx(), 0f), Size(1.dp.toPx(), size.height)) }
            .verticalScroll(rememberScrollState()).padding(top = top + 12.dp, bottom = bottom + 12.dp, start = 8.dp, end = 8.dp)
            .semantics { role = Role.Tab },
        verticalArrangement = Arrangement.spacedBy(4.dp),
        horizontalAlignment = if (showLabels) Alignment.Start else Alignment.CenterHorizontally,
    ) {
        // The rail's mark is a square badge with its letter centred; open, the name follows it in its colours. A sidebar
        // has the name alone. Both are drawn from `brandParts`.
        val brand = LocalExtraColours.current.brandAccent
        val name = com.wittywilla.wittymediaclient.net.BrandName.plain(nav.brandName, nav.brandParts)
        Row(Modifier.padding(start = if (showLabels) 8.dp else 0.dp, top = 6.dp, bottom = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            if (rail) Box(Modifier.size(40.dp).background(scheme.primary.copy(alpha = 0.16f), RoundedCornerShape(10.dp)), contentAlignment = Alignment.Center) {
                Text(name.firstOrNull()?.uppercase() ?: "W", color = brand, fontSize = 20.sp, fontWeight = FontWeight.Bold)
            }
            if (showLabels) Text(
                brandAnnotated(nav.brandName, nav.brandParts, scheme.onBackground, brand), fontSize = 17.sp, fontWeight = FontWeight.Bold,
                maxLines = 1, overflow = TextOverflow.Ellipsis,
            )
        }
        nav.sduiMenuAll.forEach { (entry, route) ->
            val on = chosen(nav, route)
            Pressable(
                { nav.openMenuEntry(route) }, Modifier.fillMaxWidth().heightIn(min = if (labels) 44.dp else 56.dp),
                shape = RoundedCornerShape(10.dp), fill = if (on) scheme.primary.copy(alpha = 0.14f) else Color.Transparent,
                label = entry.label, state = if (on) "Selected" else null, selected = on, pressScale = 1f, ring = false,
            ) {
                val tint = if (on) accentText else scheme.onSurfaceVariant
                if (showLabels) Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    EntryMark(nav, entry, route, tint, 22.dp)
                    Text(entry.label, color = if (on) scheme.onBackground else scheme.onSurfaceVariant, fontSize = 15.sp, fontWeight = if (on) FontWeight.SemiBold else FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                } else Column(Modifier.padding(vertical = 6.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    EntryMark(nav, entry, route, tint, 24.dp)
                    Text(entry.label, color = tint, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
        // Keep menu open: a switch, remembered on this device.
        if (open) {
            Spacer(Modifier.weight(1f))
            Pressable({ RailPin.toggle() }, Modifier.fillMaxWidth().heightIn(min = 44.dp), shape = RoundedCornerShape(10.dp), label = "Keep menu open", state = if (pinned) "On" else "Off", selected = pinned, pressScale = 1f) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("Keep menu open", color = scheme.onSurfaceVariant, fontSize = 14.sp)
                    Text(if (pinned) "On" else "Off", color = if (pinned) accentText else scheme.onSurfaceVariant, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}

// Whether the rail stays open, kept on this device.
object RailPin {
    var pinned by mutableStateOf(false)
        private set
    private var prefs: android.content.SharedPreferences? = null

    fun load(context: android.content.Context) {
        if (prefs != null) return
        prefs = context.getSharedPreferences("frames", android.content.Context.MODE_PRIVATE)
        pinned = prefs?.getBoolean("railPinned", false) == true
    }

    fun toggle() {
        pinned = !pinned
        prefs?.edit()?.putBoolean("railPinned", pinned)?.apply()
    }
}

// A row of tabs across the top, under the clock: every entry by name, You at the end. Over the page (`overlay`, the
// streaming style) it is see-through until the page scrolls under it, then the page colour as the top bar is.
@Composable
fun TopTabs(nav: Nav, height: Dp, status: Dp, solid: Boolean, modifier: Modifier = Modifier) {
    val scheme = MaterialTheme.colorScheme
    val accentText = LocalExtraColours.current.accentText
    val page = scheme.background
    val line = scheme.outline
    val entries = nav.sduiMenuAll
    Column(modifier.fillMaxWidth().background(if (solid) page.copy(alpha = 0.92f) else Color.Transparent)
        .drawWithContent { drawContent(); if (solid) drawRect(line, Offset(0f, size.height - 1.dp.toPx()), Size(size.width, 1.dp.toPx())) }) {
        Spacer(Modifier.height(status))
        Row(Modifier.fillMaxWidth().height(height), verticalAlignment = Alignment.CenterVertically) {
            Row(
                Modifier.weight(1f).horizontalScroll(rememberScrollState()).padding(horizontal = 12.dp).semantics { role = Role.Tab },
                horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically,
            ) {
                entries.filter { it.second != Route.Profile }.forEach { (entry, route) ->
                    val on = chosen(nav, route)
                    Pressable({ nav.openMenuEntry(route) }, Modifier.heightIn(min = 40.dp), shape = RoundedCornerShape(50), fill = if (on) scheme.primary.copy(alpha = 0.14f) else Color.Transparent,
                        label = entry.label, state = if (on) "Selected" else null, selected = on, pressScale = 1f, ring = false) {
                        Text(entry.label, color = if (on) accentText else scheme.onBackground.copy(alpha = 0.85f), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp))
                    }
                }
            }
            entries.firstOrNull { it.second == Route.Profile }?.let { (entry, route) ->
                Pressable({ nav.openMenuEntry(route) }, Modifier.padding(end = 12.dp).size(44.dp), shape = RoundedCornerShape(50), label = entry.label, pressScale = 1f, ring = false) {
                    Box(contentAlignment = Alignment.Center) { EntryMark(nav, entry, route, scheme.onBackground, 30.dp) }
                }
            }
        }
    }
}

// A television's menu down the side: icons in a narrow column, opening to show their names while focus is in it, as
// the server says (`size` closed, `open` open). Down and up move along it; right goes into the page.
@Composable
fun TvSideMenu(nav: Nav, closed: Dp, open: Dp, modifier: Modifier = Modifier) {
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    val accentText = LocalExtraColours.current.accentText
    var inside by remember { mutableStateOf(false) }
    val reduce = LocalReduceMotion.current
    val width by animateDpAsState(if (inside) open else closed, if (reduce) tween(0) else tween(200), label = "side")
    Column(
        modifier.width(width).fillMaxHeight().background(if (inside) scheme.surface else scheme.background)
            .onFocusChanged { inside = it.hasFocus }
            .padding(vertical = metrics.u(48), horizontal = metrics.u(16)).semantics { role = Role.Tab },
        verticalArrangement = Arrangement.spacedBy(metrics.u(12), Alignment.CenterVertically),
    ) {
        nav.sduiMenuAll.forEach { (entry, route) ->
            val on = chosen(nav, route)
            Pressable(
                { nav.openMenuEntry(route) }, Modifier.fillMaxWidth().heightIn(min = metrics.u(72)),
                shape = RoundedCornerShape(metrics.u(16)), fill = if (on) scheme.primary.copy(alpha = 0.14f) else Color.Transparent,
                label = entry.label, state = if (on) "Selected" else null, selected = on, focusKey = "side-" + route.key,
                requestFocus = on && nav.stack.size == 1,
            ) {
                Row(Modifier.fillMaxWidth().padding(horizontal = metrics.u(22)), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(metrics.u(20))) {
                    EntryMark(nav, entry, route, if (on) accentText else scheme.onSurfaceVariant, metrics.u(44))
                    if (inside) Text(entry.label, color = if (on) scheme.onBackground else scheme.onSurfaceVariant, fontSize = (metrics.u(29).value).sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}
