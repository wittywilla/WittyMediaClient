package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.Address
import com.wittywilla.wittymediaclient.net.Api
import com.wittywilla.wittymediaclient.net.ApiError
import com.wittywilla.wittymediaclient.net.Capabilities
import com.wittywilla.wittymediaclient.net.Compat
import com.wittywilla.wittymediaclient.net.Identity
import com.wittywilla.wittymediaclient.net.IdentityState
import com.wittywilla.wittymediaclient.net.SendStep
import com.wittywilla.wittymediaclient.net.ServerProof
import com.wittywilla.wittymediaclient.net.has
import com.wittywilla.wittymediaclient.net.httpsUpgrade
import com.wittywilla.wittymediaclient.net.json
import com.wittywilla.wittymediaclient.net.problemWords
import com.wittywilla.wittymediaclient.ui.ThemeFile
import com.wittywilla.wittymediaclient.ui.qrCells
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.SerializationException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.io.IOException
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

class AuditFixesTest {
    private val repo = generateSequence(File("").absoluteFile) { it.parentFile }.first { File(it, "shared/data").isDirectory }

    @Test
    fun bareNumbersAreNotLocalNames() {
        // Systems read each of these as 8.8.8.8.
        for (host in listOf("134744072", "0x08080808", "0X8080808")) assertFalse(host, Address.isPrivateHost(host))
        assertEquals(Address.Result.Bad("public-http"), Address.normalize("134744072"))
        assertEquals(Address.Result.Bad("public-http"), Address.normalize("http://0x08080808"))
    }

    @Test
    fun aLocalNameMustStayLocalWhenResolved() {
        assertTrue(Address.staysLocal(listOf("192.168.1.5", "fe80::1%wlan0", "::ffff:10.0.0.2", "fd00::1")))
        assertFalse(Address.staysLocal(listOf("192.168.1.5", "8.8.8.8")))
        assertFalse(Address.staysLocal(listOf("::ffff:8.8.8.8")))
        assertFalse(Address.staysLocal(listOf("2606:4700::1")))
        assertTrue(Address.isLiteral("192.168.1.5"))
        assertTrue(Address.isLiteral("[::1]"))
        assertFalse(Address.isLiteral("mediabox"))
    }

    @Test
    fun theServerCantPointThePlayerElsewhere() {
        val api = Api("http://192.168.1.5:9797", "secret")
        assertEquals("http://192.168.1.5:9797/api/hls/x.m3u8?st=1", api.mediaUrl("/api/hls/x.m3u8?st=1"))
        for (bad in listOf("@evil.example/x", "//evil.example/x", ".evil.example/x", "evil", "https://evil.example/x")) {
            assertThrows(bad, ApiError::class.java) { api.mediaUrl(bad) }
        }
    }

    @Test
    fun anEmptyConnectionDoesntThrowOutsideARequest() {
        // Images may still ask just after the app has left a server.
        assertNotNull(Api("", "").http)
    }

    @Test
    fun aKeyChangingJustBeforeACodeGoesOutIsNoticed() {
        val shown = "KEY"
        fun step(state: IdentityState, key: String = shown) = Identity.beforeSending(shown, ServerProof(state, publicKey = key))
        assertEquals(SendStep.Send, step(IdentityState.Same))
        assertEquals(SendStep.Changed, step(IdentityState.Same, "OTHER"))
        assertEquals(SendStep.Changed, step(IdentityState.Different))
        assertEquals(SendStep.Changed, step(IdentityState.New, "OTHER"))
        assertEquals(SendStep.Refuse, step(IdentityState.Bad))
        assertEquals(SendStep.Refuse, step(IdentityState.None))
        assertEquals(SendStep.Unreachable, step(IdentityState.Unreachable))
        // A server older than keys, when no key was shown.
        assertEquals(SendStep.Send, Identity.beforeSending("", ServerProof(IdentityState.None)))
    }

    @Test
    fun httpMayOnlyMoveToHttpsOnTheSameHost() {
        assertEquals("https://media.local", httpsUpgrade("http://media.local:9797", "https://media.local/api/v1/capabilities"))
        assertEquals("https://media.local:8443", httpsUpgrade("http://media.local", "https://media.local:8443/x"))
        assertNull(httpsUpgrade("http://media.local", "https://evil.example/"))
        assertNull(httpsUpgrade("http://media.local", "http://media.local:81/"))
        assertNull(httpsUpgrade("https://media.local", "https://media.local:8443/"))
        assertNull(httpsUpgrade("http://media.local", "/relative"))
    }

    @Test
    fun versionsCompareAsNumbers() {
        assertTrue(Compat.isOlder("0.2.0", "0.10.0"))
        assertFalse(Compat.isOlder("0.10.0", "0.2.0"))
        assertFalse(Compat.isOlder("1.0", "1.0.0"))
        assertTrue(Compat.isOlder("1.0", "1.0.1"))
        assertFalse(Compat.isOlder("0.6.0-alpha", "0.6.0"))
        // Unreadable is never a reason to lock someone out.
        assertFalse(Compat.isOlder("", "9.9.9"))
        assertFalse(Compat.isOlder("0.2.0", ""))
        assertFalse(Compat.isOlder("beta", "1.0"))
    }

    @Test
    fun whichServerThisAppWorksWith() {
        val good = Capabilities(apiVersions = listOf(1), apiRevision = Compat.MINIMUM_API_REVISION, features = listOf("live-tv"))
        assertNull(Compat.problem(good, "0.2.0"))
        assertTrue(good.has("live-tv"))
        assertFalse(good.has("something-new"))
        assertEquals("app-old", Compat.problem(good.copy(apiVersions = listOf(2)), "0.2.0"))
        assertEquals("server-old", Compat.problem(good.copy(apiRevision = Compat.MINIMUM_API_REVISION - 1), "0.2.0"))
        assertEquals("not-set-up", Compat.problem(good.copy(setupRequired = true), "0.2.0"))
        assertEquals("app-old", Compat.problem(good.copy(minClientVersions = mapOf("android" to "0.3.0")), "0.2.0"))
        // Another kind of app's number isn't this one's business.
        assertNull(Compat.problem(good.copy(minClientVersions = mapOf("apple" to "9.0.0")), "0.2.0"))
    }

    @Test
    fun peopleNeverSeeAnExceptionsOwnWords() {
        assertEquals("lost", problemWords(IOException("failed to connect to /192.168.1.5"), "lost"))
        assertEquals("The server's words", problemWords(ApiError(400, "The server's words"), "lost"))
        assertFalse(problemWords(SerializationException("Unexpected JSON token at offset 3"), "lost").contains("JSON"))
    }

    @Test
    fun beingCancelledIsNotAProblemToShow() {
        // What used to put "StandaloneCoroutine was cancelled" on the screen.
        assertThrows(CancellationException::class.java) { problemWords(CancellationException("gone"), "lost") }
    }

    @Test
    fun theQrCodeHoldsAnAddress() {
        val cells = qrCells("http://192.168.1.5:9797/pair?code=BCDF-GHJK")
        assertNotNull(cells)
        // A square, with the three finder squares in their corners.
        assertEquals(cells!!.size, cells[0].size)
        assertTrue(cells.any { row -> row.any { it } })
    }

    @Test
    fun theLicencesTheAppShowsAreTheRepositorysOwn() {
        assertEquals(File(repo, "NOTICE").readText(), File(repo, "shared/data/NOTICE.txt").readText())
    }

    private fun luminance(hex: String): Double {
        val channel = { at: Int ->
            val v = hex.substring(at, at + 2).toInt(16) / 255.0
            if (v <= 0.03928) v / 12.92 else ((v + 0.055) / 1.055).pow(2.4)
        }
        return 0.2126 * channel(1) + 0.7152 * channel(3) + 0.0722 * channel(5)
    }

    private fun contrast(a: String, b: String): Double {
        val x = luminance(a)
        val y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    @Test
    fun everyThemeIsReadable() {
        val file = json.decodeFromString<ThemeFile>(File(repo, "shared/data/themes.json").readText())
        assertTrue(file.themes.isNotEmpty())
        val failures = ArrayList<String>()
        for (t in file.themes) {
            val c = t.colours
            val pairs = listOf(
                "text on background" to (c.text to c.background),
                "text on panel" to (c.text to c.panel),
                "text on card" to (c.text to c.card),
                "secondary on background" to (c.textSecondary to c.background),
                "secondary on card" to (c.textSecondary to c.card),
                "on accent" to (c.onAccent to c.accent),
            )
            for ((what, pair) in pairs) {
                val got = contrast(pair.first, pair.second)
                if (got < AA) failures += "${t.id}: $what is ${"%.2f".format(got)}"
            }
        }
        assertTrue(failures.joinToString("\n"), failures.isEmpty())
    }

    private companion object {
        const val AA = 4.5
    }
}
