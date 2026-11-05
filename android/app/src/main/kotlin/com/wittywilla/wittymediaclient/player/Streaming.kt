package com.wittywilla.wittymediaclient.player

// How this device asks for video to be sent: docs/CLIENT-API.md in WittyMediaServer, "Robust streaming".
// Robust favours staying smooth on a poor connection over the sharpest picture. The device's own choice
// wins wherever it is; auto follows the server, whose setting is for viewers away from home.
object Streaming {
    const val AUTO = "auto"
    const val STANDARD = "standard"
    const val ROBUST = "robust"
    val choices = listOf(AUTO, STANDARD, ROBUST)

    // A measurement is kept this long, as the guide asks: a connection doesn't change by the minute.
    const val KEEP_MS = 5 * 60 * 1000L
    // About a second of the speed test, from its first bytes.
    const val MEASURE_MS = 1000L
    // Less than this tells nothing about a connection.
    private const val ENOUGH_BYTES = 32 * 1024L

    fun clean(choice: String?): String = if (choice != null && choice in choices) choice else AUTO

    // Measuring costs a second and up to 4 MB, so only when robust can apply: the device chose it,
    // or it follows a server that streams robustly to viewers away from home.
    fun measures(choice: String, serverRemote: String): Boolean = choice == ROBUST || (choice == AUTO && serverRemote == ROBUST)

    // Bytes after the first chunk, over the time since it arrived, in kilobits a second.
    fun kbps(bytes: Long, millis: Long): Int? = if (bytes < ENOUGH_BYTES || millis <= 0) null else (bytes * 8 / millis).toInt()

    fun words(choice: String): String = when (choice) {
        STANDARD -> "Standard"
        ROBUST -> "Robust"
        else -> "The server's choice"
    }
}
