// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.PairAsk
import com.wittywilla.wittymediaclient.net.PairPhase
import com.wittywilla.wittymediaclient.net.PairRefusal
import com.wittywilla.wittymediaclient.net.PairRules
import com.wittywilla.wittymediaclient.net.PairSession
import com.wittywilla.wittymediaclient.net.QrProblem
import com.wittywilla.wittymediaclient.net.ended
import com.wittywilla.wittymediaclient.net.json
import com.wittywilla.wittymediaclient.net.pairPhaseAfter
import com.wittywilla.wittymediaclient.ui.Scanned
import com.wittywilla.wittymediaclient.ui.decodeQr
import com.wittywilla.wittymediaclient.ui.packRows
import com.wittywilla.wittymediaclient.ui.pickSize
import com.wittywilla.wittymediaclient.ui.qrCells
import com.wittywilla.wittymediaclient.ui.readScanned
import com.wittywilla.wittymediaclient.ui.scanCrop
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// docs/CLIENT-API.md, "With a QR code and a PIN": what a device's code says, whose it is, the PIN's countdown, the
// answers to a poll, and why an approval is refused. The JSON here is what a 0.8.0-alpha server answers.
class PairV2Test {
    private val server = "bd5297677f2406f0e07eb05815c20a16"
    private val qr = "wms://pair?v=1&s=$server&u=http%3A%2F%2F192.168.1.20%3A9797&c=3f58f07580f4250eee37fb052a5b1441&k=p4DbHlrJfU2kgJYv"

    @Test
    fun theStartAnswerIsRead() {
        val start = json.decodeFromString<PairSession>(
            """{"approvePath":"/pair","approveUrl":"http://127.0.0.1:9922/pair?code=RGNF-QNGZ","code":"RGNF-QNGZ","deviceSecret":"7dda","digits":6,"expiresAt":1794415179,"expiresInSec":300,"intervalSec":3,"period":30,"pin":"478206","pinExpiresAt":1794414900,"qr":"wms://pair?v=1&s=bd52&u=http%3A%2F%2F127.0.0.1%3A9922&c=3f58f07580f4250eee37fb052a5b1441&k=p4DbHlrJfU2kgJYv","sessionId":"3f58f07580f4250eee37fb052a5b1441"}""",
        )
        assertEquals("478206", start.pin)
        assertEquals(300, start.expiresInSec)
        assertEquals("3f58f07580f4250eee37fb052a5b1441", PairRules.parseQr(start.qr)?.session)
    }

    @Test
    fun aCodeIsTakenApart() {
        val read = PairRules.parseQr(qr)!!
        assertEquals(server, read.serverId)
        assertEquals("http://192.168.1.20:9797", read.base)
        assertEquals("3f58f07580f4250eee37fb052a5b1441", read.session)
        assertEquals("p4DbHlrJfU2kgJYv", read.check)
    }

    @Test
    fun whatIsNotOneOfTheseCodesIsRefused() {
        assertNull(PairRules.parseQr("https://example.com/pair?v=1&c=3f58f07580f4250eee37fb052a5b1441&k=abc"))
        assertNull(PairRules.parseQr("wms://pair?v=2&s=x&u=y&c=3f58f07580f4250eee37fb052a5b1441&k=abc"))
        // A session the server would never make: too short, not hex, or a path in disguise.
        assertNull(PairRules.parseQr("wms://pair?v=1&s=x&u=y&c=abc&k=abc"))
        assertNull(PairRules.parseQr("wms://pair?v=1&s=x&u=y&c=..%2F..%2Fusers%2F1%2Fpassword%2F..%2F..%2Fxx&k=abc"))
        assertNull(PairRules.parseQr("wms://pair?v=1&s=x&u=y&c=3F58F07580F4250EEE37FB052A5B1441&k=abc"))
        assertNull(PairRules.parseQr("wms://pair?v=1&s=x&u=y&c=3f58f07580f4250eee37fb052a5b1441"))
        assertNull(PairRules.parseQr("wms://pair?v=1&s=x&u=y&c=3f58f07580f4250eee37fb052a5b1441&k=a b"))
        // A field twice is a code someone made by hand.
        assertNull(PairRules.parseQr("$qr&c=00000000000000000000000000000000"))
        assertNull(PairRules.parseQr("wms://pair?" + "a=b&".repeat(400)))
        assertNull(PairRules.parseQr(""))
    }

    @Test
    fun aCodeForAnotherServerIsRefusedBeforeAnythingIsAsked() {
        assertNull(PairRules.problem(qr, server, "https://media.example.com"))
        // The same server by its ID, though this phone reaches it at another address than the TV does.
        assertTrue(PairRules.fitsServer(PairRules.parseQr(qr)!!, server, "https://media.example.com"))
        assertEquals(QrProblem.OtherServer, PairRules.problem(qr, "ffffffffffffffffffffffffffffffff", "http://192.168.1.20:9797"))
        assertEquals(QrProblem.NotOurs, PairRules.problem("hello", server, "http://192.168.1.20:9797"))
        // An older server with no ID to go by: the address the code names has to be this server's.
        val plain = qr.replace("s=$server", "s=")
        assertNull(PairRules.problem(plain, "", "http://192.168.1.20:9797"))
        assertEquals(QrProblem.OtherServer, PairRules.problem(plain, "", "http://192.168.1.21:9797"))
        assertEquals(QrProblem.OtherServer, PairRules.problem(plain, "", "https://192.168.1.20:9797"))
    }

    @Test
    fun whatACameraReadsBecomesAQuestionForThisServerOnly() {
        assertTrue(readScanned(qr, server, "http://a") is Scanned.Session)
        assertEquals(Scanned.OtherServer, readScanned(qr, "another", "http://a"))
        // The web address a device shows for phones without the app: only its letters are used.
        assertEquals(Scanned.Letters("RGNFQNGZ"), readScanned("http://127.0.0.1:9922/pair?code=RGNF-QNGZ", server, "http://a"))
        assertEquals(Scanned.NotACode, readScanned("http://127.0.0.1:9922/pair?code=AEIOU", server, "http://a"))
        assertEquals(Scanned.NotACode, readScanned("http://127.0.0.1:9922/settings?code=RGNF-QNGZ", server, "http://a"))
        assertEquals(Scanned.NotACode, readScanned("WIFI:S:home;T:WPA;P:secret;;", server, "http://a"))
    }

    @Test
    fun thePinCountsDownByThisDevicesOwnWaiting() {
        // 20 seconds of this PIN were left when the server answered.
        assertEquals(20, PairRules.secondsLeftAtAnswer(1000, 980, 30))
        // A clock the server never gave, or an answer that makes no sense: a whole period, never more.
        assertEquals(30, PairRules.secondsLeftAtAnswer(1000, 0, 30))
        assertEquals(30, PairRules.secondsLeftAtAnswer(5000, 980, 30))
        assertEquals(0, PairRules.secondsLeftAtAnswer(900, 980, 30))
        assertEquals(20, PairRules.secondsLeft(20, 0))
        assertEquals(15, PairRules.secondsLeft(20, 5_400))
        assertEquals(0, PairRules.secondsLeft(20, 60_000))
        assertEquals(0.5f, PairRules.share(15, 0, 30), 0.001f)
        assertEquals(0f, PairRules.share(15, 20_000, 30), 0.001f)
        assertEquals(1f, PairRules.share(30, 0, 30), 0.001f)
    }

    @Test
    fun theNextPinIsAskedForAsThisOneEndsAndNeverInATightLoop() {
        assertEquals(20_400, PairRules.nextPinInMs(20))
        assertEquals(1000, PairRules.nextPinInMs(0))
        assertEquals(60_000, PairRules.nextPinInMs(10_000))
        assertEquals("478 206", PairRules.shownPin("478206"))
        assertEquals("1234", PairRules.shownPin("1234"))
        assertEquals("478206", PairRules.typedPin("478 206 9"))
    }

    @Test
    fun pollingSlowsDownWhenToldToAndStaysSlower() {
        assertEquals(3, PairRules.pollWaitSec(3, "pending", 3))
        assertEquals(4, PairRules.pollWaitSec(3, "slow-down", 3))
        assertEquals(4, PairRules.pollWaitSec(4, "pending", 3))
        assertEquals(6, PairRules.pollWaitSec(2, "slow-down", 5))
        assertEquals(1, PairRules.pollWaitSec(0, "pending", 0))
        assertEquals(30, PairRules.pollWaitSec(40, "slow-down", 3))
        assertEquals(2, PairRules.retryWaitSec(0))
        assertEquals(6, PairRules.retryWaitSec(2))
        assertEquals(10, PairRules.retryWaitSec(50))
    }

    @Test
    fun eachAnswerToAPollLeadsSomewhere() {
        assertEquals(PairPhase.Waiting, pairPhaseAfter("pending", 200, false))
        assertEquals(PairPhase.Waiting, pairPhaseAfter("slow-down", 429, false))
        assertEquals(PairPhase.Approved, pairPhaseAfter("approved", 200, true))
        // Approved with nothing to sign in with is a failure, not a sign-in.
        assertEquals(PairPhase.Failed, pairPhaseAfter("approved", 200, false))
        assertEquals(PairPhase.Denied, pairPhaseAfter("denied", 403, false))
        assertEquals(PairPhase.Expired, pairPhaseAfter("expired", 410, false))
        assertEquals(PairPhase.Locked, pairPhaseAfter("locked", 410, false))
        // An answer with no word for it goes by its number.
        assertEquals(PairPhase.Expired, pairPhaseAfter("", 404, false))
        assertEquals(PairPhase.Failed, pairPhaseAfter("", 500, false))
        assertFalse(PairPhase.Waiting.ended)
        assertTrue(PairPhase.Denied.ended)
    }

    @Test
    fun aRefusedApprovalSaysWhy() {
        val wrong = PairRefusal.read("""{"error":"That PIN isn't right. Type the PIN the device shows now.","reason":"wrong-pin","triesLeft":4}""")
        assertTrue(wrong.wrongPin)
        assertEquals(4, wrong.triesLeft)
        assertFalse(wrong.over)
        val password = PairRefusal.read("""{"error":"Signing a device in as an administrator needs your password.","reason":"password-required","twoFactor":true}""")
        assertTrue(password.needsPassword)
        assertTrue(password.twoFactor)
        assertTrue(PairRefusal.read("""{"error":"x","reason":"locked"}""").over)
        assertTrue(PairRefusal.read("""{"error":"x","reason":"used"}""").over)
        assertEquals(PairRefusal(), PairRefusal.read("<html>"))
    }

    @Test
    fun whatIsAskingIsRead() {
        val ask = json.decodeFromString<PairAsk>(
            """{"code":"RGNF-QNGZ","createdAt":1794414879,"device":"Test TV","expiresAt":1794415179,"ip":"127.0.0.1","needsPin":true,"platform":"Android TV","profiles":[{"id":1,"name":"admin","kind":"adult","needsPassword":true},{"id":3,"name":"kiddo","kind":"kids"}],"sessionId":"3f58f07580f4250eee37fb052a5b1441","twoFactor":false}""",
        )
        assertTrue(ask.needsPin)
        assertTrue(ask.profiles[0].needsPassword)
        assertFalse(ask.profiles[1].needsPassword)
        assertEquals("Test TV", ask.device)
    }

    // The scanner's own decoder reads the code the device's screen draws: one drawn here, as a camera's luminance.
    @Test
    fun aDrawnCodeIsReadBack() {
        val cells = qrCells(qr)!!
        val scale = 6
        val margin = 40
        val side = cells.size * scale + margin * 2
        val width = side + 120 // wider than tall, as a camera's picture is
        val luminance = ByteArray(width * side) { 0xF0.toByte() }
        cells.forEachIndexed { y, row ->
            row.forEachIndexed { x, dark ->
                if (dark) for (dy in 0 until scale) for (dx in 0 until scale) luminance[(margin + y * scale + dy) * width + 60 + margin + x * scale + dx] = 0x10
            }
        }
        assertEquals(qr, decodeQr(luminance, width, side))
        assertNull(decodeQr(ByteArray(640 * 480) { 0x7F }, 640, 480))
    }

    @Test
    fun aCamerasRowsArePackedAndItsSizeChosen() {
        // Rows 6 long holding a picture 4 wide.
        val plane = byteArrayOf(1, 2, 3, 4, 0, 0, 5, 6, 7, 8, 0, 0)
        assertEquals(listOf<Byte>(1, 2, 3, 4, 5, 6, 7, 8), packRows(plane, 6, 4, 2).toList())
        assertEquals(listOf<Byte>(1, 2, 3, 4), packRows(byteArrayOf(1, 2, 3, 4), 2, 2, 2).toList())
        // The last row of a plane may stop at the picture's edge.
        assertEquals(8, packRows(byteArrayOf(1, 2, 3, 4, 0, 0, 5, 6, 7, 8), 6, 4, 2).size)
        assertEquals(1280 to 720, pickSize(listOf(4000 to 3000, 1920 to 1080, 1280 to 720, 640 to 480)))
        assertEquals(640 to 480, pickSize(listOf(4000 to 3000, 640 to 480)))
        assertNotNull(pickSize(listOf(4000 to 3000)))
        assertNull(pickSize(emptyList()))
        assertEquals(280, scanCrop(1280, 720).left)
        assertEquals(720, scanCrop(1280, 720).side)
    }
}
