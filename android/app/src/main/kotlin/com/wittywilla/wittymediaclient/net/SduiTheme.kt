// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

// Colour in a page (docs/SDUI.md, "Colour and theme", "Theme scopes"): a page never holds a colour, only the names of
// the theme's tokens. `document.theme.tokens` overrides some for the whole page, and a node's `tokens` for itself and
// everything in it. This puts those overrides on top of the theme the app is already drawing with.
object SduiTokens {
    // The theme with these tokens set. A name this app doesn't know, or a value that isn't a colour, changes nothing.
    // The accent's companions follow it unless they are set themselves, as a theme's own are worked out.
    fun over(theme: AppTheme, tokens: Map<String, String>): AppTheme {
        if (tokens.isEmpty()) return theme
        fun colour(name: String): ThemeColour? = ThemeColour.parse(tokens[name])
        val background = colour("bg") ?: theme.background
        val text = colour("fg") ?: theme.text
        val accent = colour("accent")
        var out = theme.copy(
            background = background,
            panel = colour("bg2") ?: theme.panel,
            card = colour("bg3") ?: theme.card,
            raised = colour("bg4") ?: theme.raised,
            text = text,
            textSecondary = colour("fg2") ?: theme.textSecondary,
            textHint = colour("fg3") ?: theme.textHint,
            border = colour("border") ?: theme.border,
            control = colour("controlLine") ?: colour("borderStrong") ?: theme.control,
            danger = colour("danger") ?: theme.danger,
            ok = colour("ok") ?: theme.ok,
            warn = colour("warn") ?: theme.warn,
            scrim = colour("scrim") ?: colour("overlay") ?: theme.scrim,
        )
        if (accent != null) {
            out = out.copy(
                accent = accent,
                accentPressed = accent.mixed(ThemeColour.BLACK, 0.10),
                onAccent = if (ThemeColour.WHITE.contrast(accent) >= ThemeColour.INK.contrast(accent)) ThemeColour.WHITE else ThemeColour.INK,
                // Words in the accent's colour must still read on the page: the accent itself when it does, else it
                // is moved towards the text until it does.
                accentText = readable(accent, background, text),
            )
        }
        colour("accentHover")?.let { out = out.copy(accentPressed = it) }
        colour("accentFg")?.let { out = out.copy(onAccent = it) }
        colour("accentText")?.let { out = out.copy(accentText = it) }
        return out
    }

    // A page's tokens, then each scope's on the way down to a node, the innermost last.
    fun resolve(theme: AppTheme, vararg layers: Map<String, String>?): AppTheme =
        layers.fold(theme) { acc, layer -> if (layer.isNullOrEmpty()) acc else over(acc, layer) }

    private const val AA = 4.5

    private fun readable(accent: ThemeColour, background: ThemeColour, text: ThemeColour): ThemeColour {
        if (accent.alpha < 1 || accent.contrast(background) >= AA) return accent
        for (step in 1..10) {
            val moved = accent.mixed(text, step / 10.0)
            if (moved.contrast(background) >= AA) return moved
        }
        return text
    }
}
