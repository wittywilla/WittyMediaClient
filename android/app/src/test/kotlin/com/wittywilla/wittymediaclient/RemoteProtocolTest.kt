// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.SseEvent
import com.wittywilla.wittymediaclient.net.json
import com.wittywilla.wittymediaclient.net.remote.CANT_DO
import com.wittywilla.wittymediaclient.net.remote.ChannelEvent
import com.wittywilla.wittymediaclient.net.remote.CommandPacer
import com.wittywilla.wittymediaclient.net.remote.DeviceLife
import com.wittywilla.wittymediaclient.net.remote.DeviceList
import com.wittywilla.wittymediaclient.net.remote.Feature
import com.wittywilla.wittymediaclient.net.remote.Heartbeat
import com.wittywilla.wittymediaclient.net.remote.LifeStep
import com.wittywilla.wittymediaclient.net.remote.RemoteCapabilities
import com.wittywilla.wittymediaclient.net.remote.RemoteCommand
import com.wittywilla.wittymediaclient.net.remote.RemoteDevice
import com.wittywilla.wittymediaclient.net.remote.RemoteInfo
import com.wittywilla.wittymediaclient.net.remote.RemoteQueue
import com.wittywilla.wittymediaclient.net.remote.RemoteState
import com.wittywilla.wittymediaclient.net.remote.RemoteTrack
import com.wittywilla.wittymediaclient.net.remote.RemoteWire
import com.wittywilla.wittymediaclient.net.remote.ServerClock
import com.wittywilla.wittymediaclient.net.remote.StopReason
import com.wittywilla.wittymediaclient.net.remote.WatchEvent
import com.wittywilla.wittymediaclient.net.remote.applyWatchEvent
import com.wittywilla.wittymediaclient.net.remote.canPlay
import com.wittywilla.wittymediaclient.net.remote.commandProblem
import com.wittywilla.wittymediaclient.net.remote.deviceCapabilities
import com.wittywilla.wittymediaclient.net.remote.deviceKind
import com.wittywilla.wittymediaclient.net.remote.livePositionSec
import com.wittywilla.wittymediaclient.net.remote.offerFor
import com.wittywilla.wittymediaclient.net.remote.pickerOrder
import com.wittywilla.wittymediaclient.net.remote.readChannelEvent
import com.wittywilla.wittymediaclient.net.remote.readWatchEvent
import com.wittywilla.wittymediaclient.net.remote.remoteErrorWords
import com.wittywilla.wittymediaclient.net.remote.trackId
import com.wittywilla.wittymediaclient.net.remote.trackIndex
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// The server's docs/REMOTE-PROTOCOL.md, as this app keeps to it. The JSON here is what a real server sent.
class RemoteProtocolTest {
    private val all = listOf("seek", "volume", "queue", "audio", "subtitles", "navigate", "rate")

    @Test
    fun theServersOwnAnswersAreRead() {
        val info = json.decodeFromString<RemoteInfo>(
            """{"controlOthers":false,"enabled":true,"features":["seek","volume"],"kinds":["web","tv"],"limits":{"ackTimeoutMs":8000,"commandEveryMs":200,"heartbeatSec":30,"idleSec":75,"queueItems":200,"reconnectSec":30,"stateEveryMs":500,"somethingNew":7},"minV":1,"navigateKeys":["up"],"v":1,"newField":{"a":1}}""",
        )
        assertTrue(info.enabled)
        assertEquals(200, info.limits.commandEveryMs)
        assertEquals(500, info.limits.stateEveryMs)

        val list = json.decodeFromString<DeviceList>(
            """{"devices":[{"id":"4121","name":"Sam TV","kind":"tv","userId":2,"userName":"Sam","v":1,"capabilities":{"mediaKinds":["video","audio"],"features":["seek","volume","queue","teleport"]},"online":true,"state":{"v":1,"status":"playing","itemId":1,"positionSec":100,"durationSec":420,"rate":1,"volume":0.5,"muted":false,"audio":"1","subtitle":"off","queue":[1,2],"screen":"player","hologram":true},"stateAt":1794414601028,"mine":true,"thisSession":false,"title":"Metropolis Test","itemKind":"video"}],"serverTimeMs":1794414603746}""",
        )
        val tv = list.devices.single()
        assertEquals("Sam TV", tv.name)
        assertEquals(1L, tv.state.itemId)
        assertEquals(listOf(1L, 2L), tv.state.queue)
        // The server leaves a queueIndex of 0 out.
        assertEquals(0, tv.state.queueIndex)
        assertEquals(0.5, tv.state.volume!!, 0.0)
        assertEquals("Metropolis Test", tv.title)
    }

    @Test
    fun channelEventsAreReadAndUnknownOnesSkipped() {
        val hello = readChannelEvent(SseEvent("hello", """{"capabilities":{"mediaKinds":["video"],"features":["seek"]},"deviceId":"4121","heartbeatSec":30,"serverTimeMs":1794414600461,"v":1}"""))
        assertEquals(ChannelEvent.Hello("4121", RemoteCapabilities(listOf("video"), listOf("seek")), 30, 1794414600461), hello)

        val command = readChannelEvent(SseEvent("command", """{"v":1,"id":"5dfa","type":"seek","bySec":-10,"sender":{"userName":"Sam"},"sentAt":1794414601038,"extra":"x"}""")) as ChannelEvent.Command
        assertEquals("seek", command.command.type)
        assertEquals(-10.0, command.command.bySec!!, 0.0)
        assertEquals("Sam", command.command.sender.userName)

        // A cast arrives as a play: a queue with no queueIndex starts at its first entry.
        val play = readChannelEvent(SseEvent("command", """{"v":1,"id":"73b6","type":"play","itemId":1,"queue":[1,2],"positionSec":101.384,"audio":"1","subtitle":"off"}""")) as ChannelEvent.Command
        assertEquals(RemoteQueue(listOf(1, 2), 0), RemoteQueue.from(play.command))

        assertEquals(ChannelEvent.Bye("replaced"), readChannelEvent(SseEvent("bye", """{"reason":"replaced"}""")))
        assertNull(readChannelEvent(SseEvent("fireworks", """{"a":1}""")))
        assertNull(readChannelEvent(SseEvent("command", "not json")))
    }

    @Test
    fun aControllersListFollowsTheStream() {
        val a = RemoteDevice(id = "a", name = "A", online = true)
        val b = RemoteDevice(id = "b", name = "B")
        var list = applyWatchEvent(emptyList(), WatchEvent.Snapshot(DeviceList(listOf(a, b))))
        assertEquals(listOf("a", "b"), list.map { it.id })
        list = applyWatchEvent(list, WatchEvent.Device(b.copy(online = true)))
        assertTrue(list[1].online)
        list = applyWatchEvent(list, WatchEvent.Device(RemoteDevice(id = "c")))
        assertEquals(3, list.size)
        list = applyWatchEvent(list, WatchEvent.Gone("a"))
        assertEquals(listOf("b", "c"), list.map { it.id })
        // A snapshot replaces everything.
        assertEquals(listOf("a"), applyWatchEvent(list, WatchEvent.Snapshot(DeviceList(listOf(a)))).map { it.id })

        assertEquals(WatchEvent.Gone("4121"), readWatchEvent(SseEvent("gone", """{"id":"4121"}""")))
        assertNull(readWatchEvent(SseEvent("party", "{}")))
        assertTrue(readWatchEvent(SseEvent("snapshot", """{"devices":[],"serverTimeMs":5}""")) is WatchEvent.Snapshot)
    }

    @Test
    fun whatIsSentIsExactlyTheProtocols() {
        val announce = json.parseToJsonElement(RemoteWire.announce("Living room TV", "tv", deviceCapabilities(volumeFixed = true), "")).jsonObject
        assertEquals("1", announce["v"]!!.jsonPrimitive.content)
        assertFalse("deviceId" in announce)
        assertTrue("deviceId" in json.parseToJsonElement(RemoteWire.announce("x".repeat(90), "phone", deviceCapabilities(false), "abc")).jsonObject)
        assertEquals(60, json.parseToJsonElement(RemoteWire.announce("x".repeat(90), "phone", deviceCapabilities(false), "abc")).jsonObject["name"]!!.jsonPrimitive.content.length)

        assertEquals("""{"id":"c1","ok":true}""", RemoteWire.ack("c1", null))
        assertEquals("""{"id":"c1","ok":false,"error":"Nothing is playing."}""", RemoteWire.ack("c1", "Nothing is playing."))

        assertEquals("""{"v":1,"type":"pause"}""", RemoteWire.simple("pause").toString())
        assertEquals("""{"v":1,"type":"seek","bySec":-10.0}""", RemoteWire.seekBy(-10.0).toString())
        assertEquals("""{"v":1,"type":"play","queue":[812,813],"queueIndex":1}""", RemoteWire.playQueue(listOf(812, 813), 1).toString())
        assertEquals("""{"v":1,"type":"play","itemId":812,"positionSec":3.5}""", RemoteWire.play(812, 3.5).toString())
        assertEquals("""{"v":1,"type":"cast","from":"9e2d"}""", RemoteWire.cast("9e2d").toString())
        assertEquals("""{"v":1,"type":"volume","level":1.0}""", RemoteWire.volume(4.0).toString())
        assertEquals("""{"v":1,"type":"navigate","key":"select"}""", RemoteWire.navigate("select").toString())
    }

    @Test
    fun stateIsReportedAsTheTableSays() {
        assertEquals("""{"v":1,"status":"idle","muted":false,"screen":"home"}""", RemoteState(status = "idle", screen = "home").toJson())
        val playing = RemoteState(
            status = "playing", itemId = 812, positionSec = 12.5, durationSec = 5400.0, rate = 1.0, volume = 0.6, muted = false, audio = "1", subtitle = "off",
            audioTracks = listOf(RemoteTrack("1", "English · 5.1", "en")), queue = listOf(812, 813), queueIndex = 0, screen = "player",
        )
        val sent = json.decodeFromString<RemoteState>(playing.toJson())
        assertEquals(playing, sent)
        // A device with no volume of its own leaves it out, and a number that isn't one never goes.
        val fixed = json.parseToJsonElement(playing.copy(volume = null, positionSec = Double.NaN).toJson()).jsonObject
        assertFalse("volume" in fixed)
        assertEquals("0.0", fixed["positionSec"]!!.jsonPrimitive.content)
        // Idle with an item left over from before says nothing of it.
        assertFalse("itemId" in json.parseToJsonElement(playing.copy(status = "idle").toJson()).jsonObject)
    }

    @Test
    fun aDeviceAnnouncesOnlyWhatItCanDo() {
        val tv = deviceCapabilities(volumeFixed = true)
        assertEquals(listOf("video", "audio"), tv.mediaKinds)
        assertFalse(Feature.VOLUME in tv.features)
        assertTrue(tv.features.containsAll(listOf("seek", "queue", "audio", "subtitles", "navigate", "rate")))
        assertTrue(Feature.VOLUME in deviceCapabilities(volumeFixed = false).features)
        assertEquals("tv", deviceKind(tv = true, tablet = false))
        assertEquals("tablet", deviceKind(tv = false, tablet = true))
        assertEquals("phone", deviceKind(tv = false, tablet = false))
    }

    @Test
    fun aRemoteOffersOnlyWhatTheDeviceListed() {
        val state = RemoteState(
            status = "playing", itemId = 1, durationSec = 100.0, queue = listOf(1, 2),
            audioTracks = listOf(RemoteTrack("0"), RemoteTrack("1")), subtitleTracks = listOf(RemoteTrack("2")),
        )
        val full = RemoteDevice(id = "a", online = true, capabilities = RemoteCapabilities(listOf("video"), all), state = state)
        val offer = offerFor(full)
        assertTrue(offer.transport && offer.seek && offer.volume && offer.queue && offer.audio && offer.subtitles && offer.navigate && offer.rate)

        val little = offerFor(full.copy(capabilities = RemoteCapabilities(listOf("video"), listOf("seek"))))
        assertTrue(little.seek && little.transport)
        assertFalse(little.volume || little.queue || little.audio || little.subtitles || little.navigate || little.rate)

        // Offline: nothing can be sent. Idle: only what doesn't need something open.
        val off = offerFor(full.copy(online = false))
        assertFalse(off.transport || off.seek || off.volume || off.navigate)
        val idle = offerFor(full.copy(state = RemoteState()))
        assertTrue(idle.volume && idle.navigate)
        assertFalse(idle.transport || idle.seek || idle.queue || idle.rate)
        // Something this account may not see: pause and volume, nothing that would say what it is.
        val hidden = offerFor(full.copy(hidden = true, state = RemoteState(status = "playing")))
        assertTrue(hidden.transport && hidden.volume)
        assertFalse(hidden.seek || hidden.audio || hidden.queue)
        // One sound track is no choice, and a queue of one has no next.
        val single = offerFor(full.copy(state = state.copy(audioTracks = listOf(RemoteTrack("0")), queue = listOf(1))))
        assertFalse(single.audio || single.queue)

        assertTrue(canPlay(full, "video"))
        assertFalse(canPlay(full, "book"))
        assertFalse(canPlay(full.copy(online = false), "video"))
        assertFalse(canPlay(full.copy(capabilities = RemoteCapabilities(listOf("video"), listOf("seek"))), "video", queued = 3))
    }

    @Test
    fun thePickerLeavesThisAppOutAndPutsOnlineFirst() {
        val list = listOf(
            RemoteDevice(id = "1", name = "Zed", online = false), RemoteDevice(id = "2", name = "me", online = true, thisSession = true),
            RemoteDevice(id = "3", name = "kitchen", online = true), RemoteDevice(id = "4", name = "Bedroom", online = true),
        )
        assertEquals(listOf("4", "3", "1"), pickerOrder(list).map { it.id })
    }

    @Test
    fun aPlayingDeviceMovesOnFromItsLastReport() {
        val state = RemoteState(status = "playing", itemId = 1, positionSec = 1312.4, durationSec = 5400.0, rate = 1.0)
        assertEquals(1314.2, livePositionSec(state, 1_794_000_008_200, 1_794_000_010_000), 1e-9)
        assertEquals(1316.0, livePositionSec(state.copy(rate = 2.0), 1_794_000_008_200, 1_794_000_010_000), 1e-9)
        // Paused or buffering stays put; a clock a little behind never goes backwards; never past the end.
        assertEquals(1312.4, livePositionSec(state.copy(status = "paused"), 1_794_000_008_200, 1_794_000_010_000), 0.0)
        assertEquals(1312.4, livePositionSec(state.copy(status = "buffering"), 1_794_000_008_200, 1_794_000_010_000), 0.0)
        assertEquals(1312.4, livePositionSec(state, 1_794_000_008_200, 1_794_000_000_000), 0.0)
        assertEquals(5400.0, livePositionSec(state, 1_000, 99_000_000), 0.0)

        // The server's clock, from an answer's serverTimeMs and a clock that doesn't jump.
        val clock = ServerClock()
        assertFalse(clock.known)
        clock.heard(serverTimeMs = 1_794_000_010_000, localMs = 50_000)
        assertEquals(1_794_000_011_500, clock.now(51_500))
        clock.heard(0, 99)
        assertEquals(1_794_000_011_500, clock.now(51_500))
    }

    @Test
    fun everyCommandIsCheckedBeforeItIsObeyed() {
        val caps = RemoteCapabilities(listOf("video", "audio"), all)
        fun ok(c: RemoteCommand) = assertNull(c.toString(), commandProblem(c, caps))
        fun bad(c: RemoteCommand, with: RemoteCapabilities = caps) = assertTrue(c.toString(), commandProblem(c, with) != null)
        ok(RemoteCommand(type = "play", itemId = 812))
        ok(RemoteCommand(type = "play", queue = listOf(1, 2, 3), queueIndex = 2, itemId = 3))
        ok(RemoteCommand(type = "play", queue = listOf(1, 2)))
        bad(RemoteCommand(type = "play"))
        bad(RemoteCommand(type = "play", queue = listOf(1, 2), queueIndex = 2))
        bad(RemoteCommand(type = "play", queue = listOf(1, 2), queueIndex = 0, itemId = 2))
        bad(RemoteCommand(type = "play", itemId = 1, positionSec = -3.0))
        bad(RemoteCommand(type = "play", queue = List(201) { it + 1L }))
        listOf("pause", "resume", "stop", "next", "previous").forEach { ok(RemoteCommand(type = it)) }
        ok(RemoteCommand(type = "seek", positionSec = 754.5))
        ok(RemoteCommand(type = "seek", bySec = -10.0))
        bad(RemoteCommand(type = "seek"))
        bad(RemoteCommand(type = "seek", positionSec = Double.NaN))
        ok(RemoteCommand(type = "volume", level = 0.4))
        bad(RemoteCommand(type = "volume", level = 1.4))
        ok(RemoteCommand(type = "mute", muted = true))
        bad(RemoteCommand(type = "mute"))
        ok(RemoteCommand(type = "audio", audio = "2"))
        bad(RemoteCommand(type = "audio"))
        ok(RemoteCommand(type = "subtitle", subtitle = "off"))
        ok(RemoteCommand(type = "rate", rate = 1.25))
        bad(RemoteCommand(type = "rate", rate = 9.0))
        ok(RemoteCommand(type = "navigate", key = "select"))
        bad(RemoteCommand(type = "navigate", key = "power"))

        // A command type this app has never heard of is answered, never ignored.
        assertEquals(CANT_DO, commandProblem(RemoteCommand(type = "teleport"), caps))
        // What this device never said it can do.
        val tv = deviceCapabilities(volumeFixed = true)
        assertEquals(CANT_DO, commandProblem(RemoteCommand(type = "volume", level = 0.4), tv))
        assertEquals(CANT_DO, commandProblem(RemoteCommand(type = "mute", muted = true), tv))
        bad(RemoteCommand(type = "play", queue = listOf(1, 2)), RemoteCapabilities(listOf("video"), listOf("seek")))
    }

    @Test
    fun trackIdsAreThePlaybackAnswersIndexAsText() {
        assertEquals(1, trackIndex("1"))
        assertEquals(-1, trackIndex("off"))
        assertNull(trackIndex("english"))
        assertNull(trackIndex("-4"))
        assertNull(trackIndex(null))
        assertEquals("off", trackId(-1))
        assertEquals("3", trackId(3))
    }

    @Test
    fun theQueueMovesAndFollowsThePlayer() {
        val q = RemoteQueue(listOf(812, 813, 814), 0)
        assertEquals(812L, q.current)
        assertNull(q.previous())
        val second = q.next()!!
        assertEquals(813L, second.current)
        assertNull(second.next()!!.next())
        assertEquals(0, second.previous()!!.index)
        // The next episode started by itself: the queue follows. Something from outside it stands alone.
        assertEquals(2, q.movedTo(814).index)
        assertEquals(q, q.movedTo(812))
        assertEquals(RemoteQueue(listOf(99), 0), q.movedTo(99))
        // The same item twice: the one ahead is the one meant.
        assertEquals(2, RemoteQueue(listOf(5, 6, 5), 1).movedTo(5).index)
        assertEquals(RemoteQueue(listOf(7), 0), RemoteQueue.from(RemoteCommand(type = "play", itemId = 7)))
        assertNull(RemoteQueue().current)
    }

    @Test
    fun aDeviceComesBackAsTheTableSays() {
        val life = DeviceLife(reconnectSec = 30)
        assertEquals(LifeStep.Announce(0), life.start())
        assertEquals(LifeStep.Open(0), life.announced("dev1"))
        assertFalse(life.online)
        life.opened()
        assertTrue(life.online)

        // A drop: the same channel again, a little later each time, while the server still keeps the device.
        assertEquals(LifeStep.Open(1000), life.closed(null, 100_000))
        assertFalse(life.online)
        assertEquals(LifeStep.Open(2000), life.lost(101_000))
        assertEquals(LifeStep.Open(4000), life.lost(103_000))
        assertEquals(LifeStep.Open(8000), life.lost(107_000))
        // 16 s more would land past the 30 s the server keeps it: announce instead, with the old id.
        assertEquals(LifeStep.Announce(16000), life.lost(115_000))
        assertEquals("dev1", life.deviceId)
        assertEquals(LifeStep.Open(0), life.announced("dev2"))
        life.opened()
        assertEquals(LifeStep.Open(1000), life.closed(null, 200_000))

        // Each bye.
        life.opened()
        assertEquals(LifeStep.Stop(StopReason.Replaced), life.closed("replaced", 0))
        life.opened()
        assertEquals(LifeStep.Stop(StopReason.Removed), life.closed("removed", 0))
        life.opened()
        assertEquals(LifeStep.Announce(0), life.closed("idle", 0))
        life.opened()
        assertEquals(LifeStep.Stop(StopReason.SignedOut), life.closed("signed-out", 0))
        life.opened()
        assertEquals(LifeStep.Announce(DeviceLife.SERVER_STOPPING_WAIT_MS), life.closed("server-stopping", 0))
        // A reason from a newer server is a drop like any other.
        life.opened()
        assertTrue(life.closed("moon-phase", 500_000) is LifeStep.Open)
    }

    @Test
    fun refusalsDecideWhetherToTryAgain() {
        val life = DeviceLife()
        assertEquals(LifeStep.Stop(StopReason.Disabled), life.refused(403, "disabled"))
        assertEquals(LifeStep.Stop(StopReason.TooOld), life.refused(400, "version"))
        assertEquals(LifeStep.Stop(StopReason.SignedOut), life.refused(403, "no-session"))
        assertEquals(LifeStep.Stop(StopReason.SignedOut), life.refused(401, ""))
        // The server has forgotten the device: announce at once for a new id.
        assertEquals(LifeStep.Announce(0), life.refused(404, "no-device"))
        assertEquals(LifeStep.Announce(DeviceLife.TOO_MANY_WAIT_MS), life.refused(429, "too-many"))
        assertEquals(LifeStep.Announce(7000), life.refused(429, "rate", retryAfterSec = 7))
        assertTrue(life.refused(500, "") is LifeStep.Announce)
    }

    @Test
    fun stateGoesOnChangeWhilePlayingAndAsAHeartbeat() {
        val beat = Heartbeat(stateEveryMs = 500, heartbeatSec = 30)
        assertTrue(beat.due(0, "idle", false))
        beat.sent(0, "idle")
        assertFalse(beat.due(400, "playing", true)) // a change, but too soon after the last
        assertTrue(beat.due(500, "playing", true))
        beat.sent(500, "playing")
        assertFalse(beat.due(4000, "playing", true))
        assertTrue(beat.due(5500, "playing", true)) // every five seconds while playing
        beat.sent(5500, "playing")
        assertTrue(beat.due(6000, "paused", false))
        beat.sent(6000, "paused")
        assertFalse(beat.due(20_000, "paused", false))
        assertTrue(beat.due(31_000, "paused", false)) // the heartbeat, before the 30 s are up
        beat.sent(31_000, "paused")

        // 429: the latest goes again a moment later, even though nothing changed since.
        beat.refused(31_000, retryAfterSec = 1)
        assertFalse(beat.due(31_500, "paused", false))
        assertTrue(beat.due(32_000, "paused", false))
        beat.reset()
        assertTrue(beat.due(32_001, "paused", false))
    }

    @Test
    fun everyErrorCodeHasItsSentence() {
        val codes = listOf(
            400 to "bad-command", 400 to "version", 403 to "disabled", 403 to "no-session", 403 to "not-allowed-there", 404 to "no-device", 404 to "no-item",
            404 to "no-command", 409 to "offline", 409 to "unsupported", 409 to "refused", 409 to "nothing-playing", 413 to "", 429 to "rate", 429 to "too-many",
            503 to "busy", 504 to "timeout",
        )
        val said = codes.map { (status, code) -> remoteErrorWords(status, code, "") }
        said.forEach { assertTrue(it, it.length > 10 && it.first().isUpperCase() && it.endsWith(".")) }
        // The device's own reason is what's shown for a refusal.
        assertEquals("Nothing is playing.", remoteErrorWords(409, "refused", "Nothing is playing."))
        // The server's words for a program are not shown.
        assertFalse(remoteErrorWords(400, "bad-command", "unknown command type").contains("unknown command type"))
        assertTrue(remoteErrorWords(429, "rate", "", retryAfterSec = 5).contains("5 seconds"))
        // A code from a newer server falls back to its sentence, or the status.
        assertEquals("Something new.", remoteErrorWords(418, "teapot", "Something new."))
        assertTrue(remoteErrorWords(500, "", "").contains("500"))
    }

    @Test
    fun commandsAreSpacedAndADragSendsItsLastValue() {
        val pacer = CommandPacer(everyMs = 200)
        assertEquals(0, pacer.waitMs(1000))
        pacer.sent(1000)
        assertEquals(150, pacer.waitMs(1050))
        // A dragged volume: only the last value goes when the time comes.
        pacer.offer(RemoteWire.volume(0.1))
        pacer.offer(RemoteWire.volume(0.2))
        pacer.offer(RemoteWire.seekTo(40.0))
        pacer.offer(RemoteWire.volume(0.3))
        assertNull(pacer.take(1100))
        assertEquals(RemoteWire.seekTo(40.0), pacer.take(1200))
        pacer.sent(1200)
        assertNull(pacer.take(1300))
        assertEquals(RemoteWire.volume(0.3), pacer.take(1400))
        assertFalse(pacer.pending)
    }
}
