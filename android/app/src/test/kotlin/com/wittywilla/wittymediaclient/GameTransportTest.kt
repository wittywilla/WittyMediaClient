package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.games.ArrivalDelay
import com.wittywilla.wittymediaclient.games.GameEvent
import com.wittywilla.wittymediaclient.games.GameModeInfo
import com.wittywilla.wittymediaclient.games.GameRoute
import com.wittywilla.wittymediaclient.games.GameSession
import com.wittywilla.wittymediaclient.games.GameTransport
import com.wittywilla.wittymediaclient.games.GamesApi
import com.wittywilla.wittymediaclient.games.PadState
import com.wittywilla.wittymediaclient.games.StreamHello
import com.wittywilla.wittymediaclient.games.StreamMessage
import com.wittywilla.wittymediaclient.games.WebSocketV1Transport
import com.wittywilla.wittymediaclient.games.WebSocketV2Transport
import com.wittywilla.wittymediaclient.games.seatsRequest
import com.wittywilla.wittymediaclient.net.Api
import com.wittywilla.wittymediaclient.net.json
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

// Version 2 of the game stream (the server's docs/GAMING-STREAM.md), and both WebSocket transports against a live server.
class GameTransportTest {
    @Test
    fun version2FramesCarryTheirNumberAndTime() {
        // 0x11, key, frame 7, 90 kHz time 180000 (two seconds), then the Annex B frame.
        val frame = byteArrayOf(0x11, 1, 7, 0, 0, 0, 0x20, 0xBF.toByte(), 0x02, 0, 0, 0, 0, 1, 0x67)
        val video = StreamMessage.parse(frame) as StreamMessage.Video
        assertTrue(video.keyframe)
        assertEquals(7L, video.frame)
        assertEquals(180_000L, video.timestamp90k)
        assertEquals(10, video.offset)
        assertEquals(5, video.size)
        val opus = StreamMessage.parse(byteArrayOf(0x12, 0x80.toByte(), 0xBB.toByte(), 0, 0, 1, 2, 3)) as StreamMessage.Opus
        assertEquals(48_000L, opus.timestamp48k)
        // Version 1's frames have neither.
        assertEquals(-1L, (StreamMessage.parse(byteArrayOf(1, 0, 0, 0, 1, 0x41)) as StreamMessage.Video).timestamp90k)
    }

    @Test
    fun version2EventsAreRead() {
        val stream = GameEvent.parse(
            """{"type":"stream","v":2,"conn":"k3","transport":"websocket","video":"h264","audio":"pcm","width":512,"height":448,
            "aspect":1.3333,"fps":60.0988,"rate":48000,"turns":0,"ports":5,"motion":false,"leds":[{"index":0,"state":1}],"pace":60,
            "seats":[{"port":0,"conn":"k3","name":"Pixel 9","you":true},{"port":1,"conn":"k4","name":"Living room","you":false}],"kbps":5800}""",
        ) as GameEvent.Stream
        assertEquals("h264", stream.video)
        assertEquals(60.0988, stream.fps!!, 1e-9)
        assertEquals(5, stream.ports)
        assertEquals(listOf(0 to 1), stream.leds)
        assertEquals(listOf(GameEvent.Seat(0, "Pixel 9", true), GameEvent.Seat(1, "Living room", false)), stream.seats)
        val rumble = GameEvent.parse("""{"type":"rumble","port":0,"effect":0,"motor":"weak","strength":32768,"ms":300}""") as GameEvent.Rumble
        assertEquals(1, rumble.effect)
        assertEquals(300, rumble.ms)
        assertEquals(GameEvent.Refused("seat-taken", "Player 2 is taken", 1), GameEvent.parse("""{"type":"error","code":"seat-taken","port":1,"text":"Player 2 is taken"}"""))
        assertEquals(GameEvent.Ended("Saved and stopped", "stopped"), GameEvent.parse("""{"type":"ended","code":"stopped","text":"Saved and stopped"}"""))
        assertEquals(GameEvent.Led(2, 255), GameEvent.parse("""{"type":"led","index":2,"state":255}"""))
    }

    @Test
    fun theHelloSaysWhatThisDeviceIs() {
        val hello = StreamHello("WittyMediaClient Android 0.3.0", "android-abc", "Pixel 9", video = emptyList(), seats = listOf(0, 2), hz = 59.94f, width = 1080, height = 2424)
        val o = hello.toJson(type = true)
        assertEquals("hello", o["type"]!!.jsonPrimitive.content)
        assertEquals(2, o["v"]!!.jsonPrimitive.content.toInt())
        assertEquals(0, o["video"]!!.jsonArray.size) // a picture a frame
        assertEquals("pcm", o["audio"]!!.jsonArray[0].jsonPrimitive.content)
        assertEquals(listOf(0, 2), o["seats"]!!.jsonArray.map { it.jsonPrimitive.content.toInt() })
        assertEquals(59.94, o["display"]!!.jsonObject["hz"]!!.jsonPrimitive.content.toDouble(), 1e-3)
        assertFalse(hello.toJson(type = false).containsKey("type"))
        assertEquals("""{"type":"seats","ports":[1],"take":true}""", seatsRequest(listOf(1), take = true).toString())
    }

    @Test
    fun aSlowLinkShowsAsGrowingDelay() {
        val delay = ArrivalDelay()
        // Frames 17 ms apart (1530 ticks of 90 kHz) arrive on time, then the link fills and each comes 20 ms later than the last.
        for (n in 0 until 30) delay.frame(1_000L + n * 17, n * 1530L)
        assertEquals(0, delay.takeWorst())
        for (n in 30 until 35) delay.frame(1_000L + n * 17 + (n - 29) * 20, n * 1530L)
        assertEquals(100, delay.takeWorst())
        // Taken: a new half second starts from nothing.
        assertEquals(0, delay.takeWorst())
    }

    @Test
    fun version2IsUsedWhereTheServerOffersIt() {
        val v1: GameSession = json.decodeFromString("""{"id":"a","modes":[{"id":"webrtc"},{"id":"ws-h264"},{"id":"ws-jpeg"}]}""")
        val v2: GameSession = json.decodeFromString("""{"id":"a","modes":[{"id":"webrtc","stream":2},{"id":"ws-h264","stream":2},{"id":"ws-jpeg","stream":2}]}""")
        assertEquals(listOf(GameRoute(1, "h264"), GameRoute(1, "jpeg")), GameRoute.plan(v1.modes.mapNotNull(GameModeInfo::from)))
        assertEquals(listOf(GameRoute(2, "h264"), GameRoute(2, "jpeg")), GameRoute.plan(v2.modes.mapNotNull(GameModeInfo::from)))
        assertEquals(listOf(GameRoute(2, "jpeg")), GameRoute.plan(v2.modes.mapNotNull(GameModeInfo::from), "ws-jpeg"))
        assertEquals(GameModeInfo("ws-jpeg"), GameModeInfo.from(json.parseToJsonElement("\"ws-jpeg\"")))
    }

    // A real game over each transport the server offers: the picture from a keyframe, sound, and input taken.
    // WMS_LIVE_URL, WMS_LIVE_TOKEN and WMS_LIVE_GAME (a game id this account may play, never one that needs a graphics card).
    @Test
    fun playsOverTheServersTransports() = runBlocking {
        val url = System.getenv("WMS_LIVE_URL").orEmpty()
        val token = System.getenv("WMS_LIVE_TOKEN").orEmpty()
        val game = System.getenv("WMS_LIVE_GAME")?.toLongOrNull() ?: 0
        assumeTrue(url.isNotEmpty() && token.isNotEmpty() && game > 0)
        val api = GamesApi(Api(url, token))
        val session = api.play(game, resume = true, safeMode = false)
        try {
            val offered = session.modes.mapNotNull(GameModeInfo::from)
            val routes = GameRoute.plan(offered).filter { it.video == "h264" } + GameRoute(1, "h264")
            for (route in routes.distinct()) {
                val opened = CountDownLatch(1)
                val keyframe = CountDownLatch(1)
                val sound = CountDownLatch(1)
                val described = AtomicInteger()
                val receiver = object : GameTransport.Receiver {
                    override fun opened() = opened.countDown()
                    override fun media(message: StreamMessage) {
                        if (message is StreamMessage.Video && message.keyframe) keyframe.countDown()
                        if (message is StreamMessage.Pcm) sound.countDown()
                    }
                    override fun event(event: GameEvent) {
                        if (event is GameEvent.Hello || event is GameEvent.Stream) described.incrementAndGet()
                    }
                    override fun lost(status: Int) {}
                }
                val hello = StreamHello("WittyMediaClient Android test", "android-live-test", "Live test")
                val transport = if (route.stream >= 2) WebSocketV2Transport(api, session.id, hello, receiver) else WebSocketV1Transport(api, session.id, "h264", receiver)
                try {
                    assertTrue("$route opened", opened.await(10, TimeUnit.SECONDS))
                    assertTrue("$route keyframe", keyframe.await(10, TimeUnit.SECONDS))
                    assertTrue("$route sound", sound.await(10, TimeUnit.SECONDS))
                    assertTrue("$route said what it sends", described.get() > 0)
                    transport.send(PadState(0, 0).encoded())
                    if (route.stream >= 2) transport.sendEvent(seatsRequest(listOf(0)))
                } finally {
                    transport.close()
                }
            }
        } finally {
            api.stop(session.id)
        }
    }
}

@Suppress("unused")
private fun JsonObject.text(key: String) = this[key]?.jsonPrimitive?.content
