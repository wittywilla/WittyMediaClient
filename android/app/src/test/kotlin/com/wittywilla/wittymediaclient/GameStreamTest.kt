package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.games.AnnexB
import com.wittywilla.wittymediaclient.games.GameCheck
import com.wittywilla.wittymediaclient.games.GameConsole
import com.wittywilla.wittymediaclient.games.GameControls
import com.wittywilla.wittymediaclient.games.GameDetails
import com.wittywilla.wittymediaclient.games.GameEvent
import com.wittywilla.wittymediaclient.games.GameModes
import com.wittywilla.wittymediaclient.games.GameSession
import com.wittywilla.wittymediaclient.games.GameSettings
import com.wittywilla.wittymediaclient.games.PictureFit
import com.wittywilla.wittymediaclient.games.StreamMessage
import com.wittywilla.wittymediaclient.games.blockedTitle
import com.wittywilla.wittymediaclient.games.blockedWords
import com.wittywilla.wittymediaclient.games.canPlay
import com.wittywilla.wittymediaclient.games.problemFrom
import com.wittywilla.wittymediaclient.net.json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// What arrives on a game's WebSocket, and the answers around it, as the local server sends them.
class GameStreamTest {
    private fun hex(s: String) = s.chunked(2).map { it.toInt(16).toByte() }.toByteArray()

    // The sequence parameter set of the NES 240p Test Suite's first keyframe from the local server, doubled to 512x448.
    private val sps = hex("6742c01fda0200e69a810100a000027100012574d1e30654")

    @Test
    fun binaryMessagesSayWhatTheyAre() {
        val video = StreamMessage.parse(byteArrayOf(1, 1, 0, 0, 0, 1, 0x67)) as StreamMessage.Video
        assertTrue(video.keyframe)
        assertEquals(5, video.size)
        val jpeg = StreamMessage.parse(byteArrayOf(2, 0xFF.toByte(), 0xD8.toByte())) as StreamMessage.Jpeg
        assertEquals(1, jpeg.offset)
        // 32040 Hz, and a stray byte left off so left and right stay where they are.
        val pcm = StreamMessage.parse(byteArrayOf(3, 0x28, 0x7D, 0, 0, 1, 2, 3, 4, 5)) as StreamMessage.Pcm
        assertEquals(32040, pcm.rate)
        assertEquals(4, pcm.length)
        assertTrue(StreamMessage.parse(byteArrayOf(0xF2.toByte(), 1)) is StreamMessage.Timing)
        assertNull(StreamMessage.parse(ByteArray(0)))
    }

    @Test
    fun eventsAreJson() {
        assertEquals(GameEvent.Hello("h264"), GameEvent.parse("""{"type":"hello","video":"h264"}"""))
        assertEquals(GameEvent.Frame(256, 224), GameEvent.parse("""{"type":"frame","width":256,"height":224}"""))
        val rumble = GameEvent.parse("""{"type":"rumble","port":1,"effect":1,"strength":65535}""") as GameEvent.Rumble
        assertEquals(1, rumble.port)
        assertEquals(1, rumble.effect)
        assertEquals(1.0, rumble.strength, 1e-9)
        assertEquals(GameEvent.Ended("It crashed"), GameEvent.parse("""{"type":"ended","text":"It crashed"}"""))
        assertEquals(GameEvent.Unknown("later"), GameEvent.parse("""{"type":"later","x":1}"""))
        assertNull(GameEvent.parse("not json"))
    }

    @Test
    fun modesAreTheServersOrderOfWhatThisAppCanUse() {
        val session: GameSession = json.decodeFromString(
            """{"id":"abc","itemId":1922,"console":"nes","width":256,"height":224,"aspect":1.3061,"modes":[{"id":"webrtc","video":["h264","vp8"]},{"id":"ws-h264"},{"id":"ws-jpeg"},{"id":"ws-av1"}]}""",
        )
        assertEquals(listOf("ws-h264", "ws-jpeg"), GameModes.order(session.modeIds))
        // An older server names them.
        val older: GameSession = json.decodeFromString("""{"id":"abc","modes":["ws-jpeg"]}""")
        assertEquals(listOf("ws-jpeg"), GameModes.order(older.modeIds))
        assertEquals(GameModes.supported, GameModes.order(emptyList()))
        assertEquals("jpeg", GameModes.video("ws-jpeg"))
        assertEquals("h264", GameModes.video("ws-h264"))
    }

    @Test
    fun theKeyframesParameterSetsAreFoundAndRead() {
        val frame = byteArrayOf(0, 0, 0, 1) + sps + byteArrayOf(0, 0, 0, 1, 0x68, 0xCE.toByte(), 0x3C, 0x80.toByte(), 0, 0, 1, 0x65, 1, 2, 3)
        val units = AnnexB.units(frame)
        assertEquals(listOf(AnnexB.SPS, AnnexB.PPS, AnnexB.IDR), units.map { AnnexB.type(frame, it) })
        assertEquals(sps.size, units[0].count())
        assertEquals(512 to 448, AnnexB.spsSize(sps))
        assertEquals(listOf<Byte>(0, 0, 0, 1, 0x68), AnnexB.withStartCode(frame, units[1]).take(5))
    }

    @Test
    fun thePictureKeepsTheGamesShape() {
        val plain = GameSettings.NONE
        // A NES picture, 1.306 wide, on a 1920x1080 screen: as tall as the screen.
        val fit = PictureFit.fit(plain, 1.306, 256.0, 224.0, 0, 1920f, 1080f)
        assertEquals(1080f, fit.height, 0.5f)
        assertEquals(1410f, fit.width, 1f)
        // Whole multiples: 224 four times.
        val whole = PictureFit.fit(GameSettings.of(mapOf("display.integer" to true)), 1.306, 256.0, 224.0, 0, 1920f, 1080f)
        assertEquals(896f, whole.height, 0.5f)
        // Turned a quarter, a tall picture on a wide screen.
        val turned = PictureFit.fit(plain, 4.0 / 3.0, 320.0, 240.0, 1, 1920f, 1080f)
        assertEquals(1, turned.turns)
        assertEquals(1080f, turned.height, 0.5f)
        assertEquals(810f, turned.width, 1f)
        val stretched = PictureFit.fit(GameSettings.of(mapOf("display.aspect" to "stretch")), 1.306, 256.0, 224.0, 0, 1000f, 500f)
        assertEquals(1000f, stretched.width)
        assertEquals(500f, stretched.height)
    }

    @Test
    fun aGameTheServerCantRunSaysWhyInItsOwnWords() {
        val check: GameCheck = json.decodeFromString(
            """{"bios":[],"console":"n64","core":{"id":"mupen64plus_next","name":"Mupen64Plus-Next"},"needsGpu":true,"ready":false,"reason":"gpu","message":"This server has no graphics card for the Nintendo 64."}""",
        )
        assertFalse(canPlay(check, GameConsole(id = "n64", ready = true), null))
        assertEquals("This server has no graphics card for the Nintendo 64.", blockedWords(check, null))
        assertEquals("This game needs a graphics card", blockedTitle(check.reason))
        // A reason this app doesn't know still shows the server's message under a plain heading.
        assertEquals("This console can't play here yet", blockedTitle("something-new"))
        // Until the check answers, the console's own `ready` decides; a file that's a problem never plays.
        assertTrue(canPlay(null, GameConsole(ready = true), null))
        assertFalse(canPlay(GameCheck(ready = true), GameConsole(ready = true), GameDetails(problem = "This file is encrypted.")))
        assertEquals("Not today", blockedWords(null, GameConsole(unavailable = "Not today")))
    }

    @Test
    fun startingSaysWhatWentWrong() {
        assertEquals("Busy", problemFrom(503, """{"error":"Busy"}"""))
        assertTrue(problemFrom(409, """{"needCore":true,"console":"gba"}""").contains("core"))
        assertTrue(problemFrom(503, "").contains("as many games"))
    }

    @Test
    fun controlsAndSettingsDecodeFromTheServer() {
        val c: GameControls = json.decodeFromString(
            """{"console":"nds","pad":{"face":[],"pointer":true,"art":"four"},"controls":[],
            "defaults":{"gamepad":{"0":{"b":0},"2":null},"touch":{"landscape":{"dpad":{"x":0.13,"y":0.62,"size":0.36,"opacity":0.55}},"portrait":{}}},
            "saved":{"gamepad":{},"keyboard":null,"touch":{"landscape":{"dpad":{"x":0.2,"y":0.6,"size":0.3,"opacity":0.6}}}}}""",
        )
        assertTrue(c.pad.pointer)
        assertTrue(c.defaults.gamepad.containsKey("2"))
        assertNull(c.defaults.gamepad["2"])
        // This device's saved layout wins over the console's.
        assertEquals(0.2, c.touchLayout("landscape").getValue("dpad").x, 1e-9)
        assertTrue(c.touchLayout("portrait").isEmpty())
        val s: GameSettings = json.decodeFromString("""{"resolved":{"values":{"states.quickSlot":3,"states.resume":"ask","audio.mute":false,"audio.volume":0.5}}}""")
        assertEquals("3", s.text("states.quickSlot", "1"))
        assertEquals(0.5, s.number("audio.volume", 1.0), 1e-9)
        assertFalse(s.flag("audio.mute", true))
        assertEquals("ask", s.text("states.resume", "never"))
    }
}
