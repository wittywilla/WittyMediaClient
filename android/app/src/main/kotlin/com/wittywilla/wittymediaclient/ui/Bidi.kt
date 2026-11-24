// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import android.os.Build

// Text that isn't the app's own (a title, an artist, a file name, "2 hr 10 min") joined into one line with others.
// On a phone set to Arabic or Hebrew the app is laid out right to left, and the bidi rules would move the digits and
// dashes of a Latin part to the other end ("00-aurora-…-2019" as "…-2019-00", "2018 · 2 hr 10 min" as
// "hr 10 min 2 · 2018"); a Hebrew title among Latin ones has the same problem the other way. Each part is isolated
// (U+2068 … U+2069, the plain-text <bdi>), so it keeps its own order and the line keeps its parts in place.
// The server's web app does the same (web/src/bidi.css, i18n/core.ts).

private const val FSI = '⁨'
private const val PDI = '⁩'

// Android 7 is where isolates are laid out everywhere; before that they're left out rather than risk a box.
private val isolates = Build.VERSION.SDK_INT >= 24

/** [s] isolated from the text around it, keeping its own direction. */
fun isolate(s: String): String = if (!isolates || s.isEmpty() || s[0] == FSI) s else "$FSI$s$PDI"

/** Parts joined into one line (" · " between them), each isolated: see [isolate]. */
fun Iterable<String>.factsLine(separator: String = " · "): String = joinToString(separator) { isolate(it) }

/** As [factsLine], for parts made from something else. */
fun <T> Iterable<T>.factsLine(separator: String = " · ", transform: (T) -> CharSequence): String =
    joinToString(separator) { isolate(transform(it).toString()) }
