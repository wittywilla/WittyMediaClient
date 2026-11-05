package com.wittywilla.wittymediaclient.ui

import android.graphics.BlurMaskFilter
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

// docs/APP-DESIGN.md, "One mobile design with the website": the pieces the phone app shares with the server's
// website at phone size. Icons are the website's own (web/src/icons.tsx), filled paths on a 24 grid, so the
// app and the website draw the same shapes.
private fun webIcon(name: String, path: String): ImageVector =
    ImageVector.Builder(name, 24.dp, 24.dp, 24f, 24f)
        .addPath(addPathNodes(spacedArcs(path)), fill = SolidColor(Color.Black))
        .build()

// SVG lets an arc's two flags run into the next number ("a10 10 0 100 20" is flags 1 and 0, then 0 20), which
// browsers read and Android's parser doesn't. This writes every arc out in full.
internal fun spacedArcs(path: String): String {
    val out = StringBuilder()
    var i = 0
    var command = ' '
    var field = 0
    fun number(): String {
        val start = i
        if (i < path.length && (path[i] == '-' || path[i] == '+')) i++
        var dot = false
        while (i < path.length && (path[i].isDigit() || (path[i] == '.' && !dot))) { if (path[i] == '.') dot = true; i++ }
        if (i < path.length && (path[i] == 'e' || path[i] == 'E')) { i++; if (path[i] == '-' || path[i] == '+') i++; while (i < path.length && path[i].isDigit()) i++ }
        return path.substring(start, i)
    }
    while (i < path.length) {
        val c = path[i]
        when {
            c.isLetter() && c != 'e' && c != 'E' -> { command = c; field = 0; out.append(c); i++ }
            c == ' ' || c == ',' -> i++
            else -> {
                val arc = command == 'a' || command == 'A'
                val text = if (arc && (field % 7 == 3 || field % 7 == 4)) path[i++].toString() else number()
                if (out.isNotEmpty() && !out.last().isLetter()) out.append(' ')
                out.append(text)
                field++
            }
        }
    }
    return out.toString()
}

object WebIcons {
    val Home: ImageVector by lazy { webIcon("home", "M12 3l9 8h-3v9h-5v-6h-2v6H6v-9H3z") }
    val Tv: ImageVector by lazy { webIcon("tv", "M21 3H3a2 2 0 00-2 2v12a2 2 0 002 2h5v2h8v-2h5a2 2 0 002-2V5a2 2 0 00-2-2zm0 14H3V5h18z") }
    val Search: ImageVector by lazy { webIcon("search", "M15.5 14h-.8l-.3-.3a6.5 6.5 0 10-.7.7l.3.3v.8l5 5 1.5-1.5zm-6 0a4.5 4.5 0 110-9 4.5 4.5 0 010 9z") }
    val Menu: ImageVector by lazy { webIcon("menu", "M3 6h18v2H3zm0 5h18v2H3zm0 5h18v2H3z") }
    val Left: ImageVector by lazy { webIcon("left", "M15.4 7.4L10.8 12l4.6 4.6L14 18l-6-6 6-6z") }
    val Right: ImageVector by lazy { webIcon("right", "M8.6 7.4L13.2 12l-4.6 4.6L10 18l6-6-6-6z") }
    val Star: ImageVector by lazy { webIcon("star", "M12 3l2.7 5.8 6.3.8-4.6 4.4 1.2 6.3L12 17.2 6.4 20.3l1.2-6.3L3 9.6l6.3-.8z") }
    val Plus: ImageVector by lazy { webIcon("plus", "M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6z") }
    val More: ImageVector by lazy { webIcon("more", "M5 10a2 2 0 110 4 2 2 0 010-4zm7 0a2 2 0 110 4 2 2 0 010-4zm7 0a2 2 0 110 4 2 2 0 010-4z") }
    val Tune: ImageVector by lazy { webIcon("tune", "M3 17v2h6v-2zM3 5v2h10V5zm10 16v-2h8v-2h-8v-2h-2v6zM7 9v2H3v2h4v2h2V9zm14 4v-2H11v2zm-6-4h2V7h4V5h-4V3h-2z") }
    val SortUp: ImageVector by lazy { webIcon("sort-up", "M13 20h-2V7.8l-5.6 5.6L4 12l8-8 8 8-1.4 1.4L13 7.8z") }
    val SortDown: ImageVector by lazy { webIcon("sort-down", "M11 4h2v12.2l5.6-5.6L20 12l-8 8-8-8 1.4-1.4 5.6 5.6z") }
    val Check: ImageVector by lazy { webIcon("check", "M9 16.2l-3.5-3.5L4 14.2 9 19.2 20 8.2l-1.4-1.4z") }
    val Disc: ImageVector by lazy { webIcon("disc", "M12 2a10 10 0 100 20 10 10 0 000-20zm0 13a3 3 0 110-6 3 3 0 010 6zm0-4.5a1.5 1.5 0 100 3 1.5 1.5 0 000-3z") }
    val Image: ImageVector by lazy { webIcon("image", "M21 19V5a2 2 0 00-2-2H5a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2zM8.5 13.5l2.5 3 3.5-4.5 4.5 6H5z") }
    val Film: ImageVector by lazy { webIcon("film", "M4 4h16v16H4zM6 6v2h2V6zm0 4v2h2v-2zm0 4v2h2v-2zm10-8v2h2V6zm0 4v2h2v-2zm0 4v2h2v-2zM10 6v12h4V6z") }
    val Library: ImageVector by lazy { webIcon("library", "M4 6H2v14a2 2 0 002 2h14v-2H4zm16-4H8a2 2 0 00-2 2v12a2 2 0 002 2h12a2 2 0 002-2V4a2 2 0 00-2-2zm-1 9H9V9h10zm-4 4H9v-2h6zm4-8H9V5h10z") }
    val Gamepad: ImageVector by lazy { webIcon("gamepad", "M7 7h10a5 5 0 015 5v3.5a3.5 3.5 0 01-6.4 2L14 16h-4l-1.6 1.5A3.5 3.5 0 012 15.5V12a5 5 0 015-5zm0 2.5V11H5.5v1.5H7V14h1.5v-1.5H10V11H8.5V9.5zM16 10a1 1 0 100 2 1 1 0 000-2zm2.5 2.5a1 1 0 100 2 1 1 0 000-2z") }
    val Shorts: ImageVector by lazy { webIcon("shorts", "M17 2H7a3 3 0 00-3 3v14a3 3 0 003 3h10a3 3 0 003-3V5a3 3 0 00-3-3zm-7 14V8l6 4z") }
    val Channels: ImageVector by lazy { webIcon("channels", "M21 5H3a2 2 0 00-2 2v10a2 2 0 002 2h18a2 2 0 002-2V7a2 2 0 00-2-2zM10 15.5v-7l6 3.5z") }
    val Radio: ImageVector by lazy { webIcon("radio", "M3.2 6.8A2 2 0 002 8.6V20a2 2 0 002 2h16a2 2 0 002-2V8a2 2 0 00-2-2H8.3l8.3-3.4L16 1zM7 20a3 3 0 110-6 3 3 0 010 6zm13-8h-2v-2h-2v2H4V8h16z") }
    val Anime: ImageVector by lazy { webIcon("anime", "M12 2l2.4 5.6L20 9l-4.3 3.9L17 19l-5-3-5 3 1.3-6.1L4 9l5.6-1.4z") }
    val Mic: ImageVector by lazy { webIcon("mic", "M12 2a3.5 3.5 0 00-3.5 3.5v6a3.5 3.5 0 007 0v-6A3.5 3.5 0 0012 2zm6.5 9.5h-2a4.5 4.5 0 01-9 0h-2a6.5 6.5 0 005.5 6.4V21h2v-3.1a6.5 6.5 0 005.5-6.4z") }
    val Headphones: ImageVector by lazy { webIcon("headphones", "M12 3a9 9 0 00-9 9v7a2 2 0 002 2h2a2 2 0 002-2v-4a2 2 0 00-2-2H5v-1a7 7 0 0114 0v1h-2a2 2 0 00-2 2v4a2 2 0 002 2h2a2 2 0 002-2v-7a9 9 0 00-9-9z") }
    val Book: ImageVector by lazy { webIcon("book", "M18 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V4a2 2 0 00-2-2zM6 4h5v8l-2.5-1.5L6 12z") }
    val Camera: ImageVector by lazy { webIcon("camera", "M9 3L7.2 5H4a2 2 0 00-2 2v12a2 2 0 002 2h16a2 2 0 002-2V7a2 2 0 00-2-2h-3.2L15 3zm3 15a5 5 0 110-10 5 5 0 010 10zm0-2a3 3 0 100-6 3 3 0 000 6z") }
    val Chart: ImageVector by lazy { webIcon("chart", "M4 20V10h3v10H4zm6 0V4h3v16h-3zm6 0v-7h3v7h-3z") }
    val Refresh: ImageVector by lazy { webIcon("refresh", "M17.6 6.4A8 8 0 004.3 10h2.1a6 6 0 019.8-2.2L13 11h7V4zm-11.2 11.2A8 8 0 0019.7 14h-2.1a6 6 0 01-9.8 2.2L11 13H4v7z") }
    val Plug: ImageVector by lazy { webIcon("plug", "M16 7V3h-2v4h-4V3H8v4H6v6l4 4v4h4v-4l4-4V7z") }

    // libIcon (web/src/icons.tsx): each kind of library's icon, the disc for anything else.
    fun forLibrary(type: String): ImageVector = when (type) {
        "games" -> Gamepad
        "photos" -> Image
        "shorts" -> Shorts
        "channels", "musicvideos" -> Channels
        "radio" -> Radio
        "movies" -> Film
        "shows" -> Tv
        "anime" -> Anime
        "music" -> Audio
        "podcasts" -> Mic
        "audiobooks" -> Headphones
        "books" -> Book
        "videos" -> Camera
        else -> Disc
    }

    // The player's (web/src/icons.tsx).
    val Play: ImageVector by lazy { webIcon("play", "M8 5v14l11-7z") }
    val Pause: ImageVector by lazy { webIcon("pause", "M6 19h4V5H6zm8-14v14h4V5z") }
    val Back: ImageVector by lazy { webIcon("back", "M20 11H7.8l5.6-5.6L12 4l-8 8 8 8 1.4-1.4L7.8 13H20z") }
    val Close: ImageVector by lazy { webIcon("close", "M19 6.4L17.6 5 12 10.6 6.4 5 5 6.4l5.6 5.6L5 17.6 6.4 19l5.6-5.6 5.6 5.6 1.4-1.4-5.6-5.6z") }
    val Full: ImageVector by lazy { webIcon("full", "M7 14H5v5h5v-2H7zm-2-4h2V7h3V5H5zm12 7h-3v2h5v-5h-2zm-3-12v2h3v3h2V5z") }
    val Volume: ImageVector by lazy { webIcon("volume", "M3 9v6h4l5 5V4L7 9zm13.5 3A4.5 4.5 0 0014 8v8a4.5 4.5 0 002.5-4zM14 3.2v2.1a7 7 0 010 13.4v2.1a9 9 0 000-17.6z") }
    val Mute: ImageVector by lazy { webIcon("mute", "M16.5 12A4.5 4.5 0 0014 8v2.2l2.5 2.5zM19 12a7 7 0 01-1.3 4l1.5 1.5A9 9 0 0021 12a9 9 0 00-7-8.8v2.1A7 7 0 0119 12zM4.3 3L3 4.3 7.7 9H3v6h4l5 5v-6.7l4.3 4.3a7 7 0 01-2.3 1.3v2.1a9 9 0 003.7-1.9L19.7 21l1.3-1.3zM12 4L9.9 6.1 12 8.2z") }
    val Next: ImageVector by lazy { webIcon("next", "M6 18l8.5-6L6 6zm10-12v12h2V6z") }
    val Prev: ImageVector by lazy { webIcon("prev", "M6 6h2v12H6zm3.5 6l8.5 6V6z") }
    val Subs: ImageVector by lazy { webIcon("subs", "M20 4H4a2 2 0 00-2 2v12a2 2 0 002 2h16a2 2 0 002-2V6a2 2 0 00-2-2zM4 12h4v2H4zm10 6H4v-2h10zm6 0h-4v-2h4zm0-4H10v-2h10z") }
    val Audio: ImageVector by lazy { webIcon("audio", "M12 3v10.6A4 4 0 1014 17V7h4V3z") }
    val Chapters: ImageVector by lazy { webIcon("chapters", "M3 5h2v14H3zm4 0h2v14H7zm4 0h10v14H11z") }
    val Settings: ImageVector by lazy { webIcon("settings", "M19.4 13a7.9 7.9 0 000-2l2.1-1.6-2-3.5-2.5 1a8 8 0 00-1.7-1L15 3H9l-.3 2.9a8 8 0 00-1.7 1l-2.5-1-2 3.5L4.6 11a7.9 7.9 0 000 2l-2.1 1.6 2 3.5 2.5-1a8 8 0 001.7 1L9 21h6l.3-2.9a8 8 0 001.7-1l2.5 1 2-3.5zM12 15.5a3.5 3.5 0 110-7 3.5 3.5 0 010 7z") }
    val Info: ImageVector by lazy { webIcon("info", "M11 7h2v2h-2zm0 4h2v6h-2zm1-9a10 10 0 100 20 10 10 0 000-20z") }
    val Remote: ImageVector by lazy { webIcon("remote", "M15 2H9a3 3 0 00-3 3v14a3 3 0 003 3h6a3 3 0 003-3V5a3 3 0 00-3-3zm-3 3a2.5 2.5 0 110 5 2.5 2.5 0 010-5zM9.5 13h1.5v1.5H9.5zm3.5 0h1.5v1.5H13zm-3.5 3h1.5v1.5H9.5zm3.5 0h1.5v1.5H13z") }
    val Mini: ImageVector by lazy { webIcon("mini", "M19 11h-8v6h8zm4 8V5a2 2 0 00-2-2H3a2 2 0 00-2 2v14a2 2 0 002 2h18a2 2 0 002-2zm-2 0H3V5h18z") }
    val Expand: ImageVector by lazy { webIcon("expand", "M4 4h7v2H7.4l4.3 4.3-1.4 1.4L6 7.4V11H4zm16 16h-7v-2h3.6l-4.3-4.3 1.4-1.4 4.3 4.3V13h2z") }
}

// CSS's box-shadow under a rounded shape: offset, blur and colour as the website writes them. Compose's own
// shadow is a light-source elevation, which looks different, so this draws the blur itself.
fun Modifier.cssShadow(y: Dp, blur: Dp, colour: Color, radius: Dp, x: Dp = 0.dp): Modifier = drawBehind {
    val r = radius.toPx()
    val paint = Paint()
    paint.asFrameworkPaint().apply {
        isAntiAlias = true
        color = colour.toArgb()
        // CSS's blur radius is twice the Gaussian's sigma, and a mask filter's radius is about the sigma.
        if (blur > 0.dp) maskFilter = BlurMaskFilter(blur.toPx() / 2f, BlurMaskFilter.Blur.NORMAL)
    }
    drawIntoCanvas { canvas ->
        canvas.save()
        canvas.translate(x.toPx(), y.toPx())
        canvas.drawRoundRect(0f, 0f, size.width, size.height, r.coerceAtMost(size.minDimension / 2), r.coerceAtMost(size.minDimension / 2), paint)
        canvas.restore()
    }
}

// CSS's dashed border: dashes of about three times the line, round the corner.
fun Modifier.dashedBorder(colour: Color, radius: Dp, width: Dp = 1.dp): Modifier = drawBehind {
    val w = width.toPx()
    drawRoundRect(
        colour, topLeft = androidx.compose.ui.geometry.Offset(w / 2, w / 2), size = androidx.compose.ui.geometry.Size(size.width - w, size.height - w),
        cornerRadius = androidx.compose.ui.geometry.CornerRadius(radius.toPx()),
        style = androidx.compose.ui.graphics.drawscope.Stroke(w, pathEffect = androidx.compose.ui.graphics.PathEffect.dashPathEffect(floatArrayOf(3 * w, 3 * w))),
    )
}
