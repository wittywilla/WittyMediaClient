package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import com.google.zxing.BarcodeFormat
import com.google.zxing.WriterException
import com.google.zxing.qrcode.QRCodeWriter

// Which squares are dark, or null when the text can't be made into a code. Always black on white
// with its own quiet margin, whatever the theme: cameras read nothing else reliably.
fun qrCells(text: String): List<BooleanArray>? = try {
    val matrix = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, 0, 0)
    List(matrix.height) { y -> BooleanArray(matrix.width) { x -> matrix.get(x, y) } }
} catch (_: WriterException) {
    null
} catch (_: IllegalArgumentException) {
    null
}

// Drawn on white, for a QR card to put round it.
@Composable
fun QrCode(text: String, size: Dp, modifier: Modifier = Modifier) {
    val cells = remember(text) { qrCells(text) } ?: return
    Canvas(modifier.size(size).background(Color.White)) {
        val side = this.size.width / cells.size
        cells.forEachIndexed { y, row ->
            row.forEachIndexed { x, dark ->
                if (dark) drawRect(Color.Black, Offset(x * side, y * side), Size(side + 0.5f, side + 0.5f))
            }
        }
    }
}
