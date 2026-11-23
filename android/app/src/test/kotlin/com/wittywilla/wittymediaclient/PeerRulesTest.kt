// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.PeerInfo
import com.wittywilla.wittymediaclient.net.PeerRules
import com.wittywilla.wittymediaclient.net.json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// Reaching a server from away (net/PeerRules.kt): the same rules as Apple's PeerConnect.swift.
class PeerRulesTest {
    private val id = "12D3KooWHeHn5nGucGC7AMeiXHmEugreQUmXSmSoUsLdnCz2J8UR"

    @Test
    fun anIdIsAnEd25519PeerId() {
        assertTrue(PeerRules.isId(id))
        assertFalse(PeerRules.isId(id.dropLast(1)))
        assertFalse(PeerRules.isId(id.replace('H', '0')))
        assertFalse(PeerRules.isId("QmYyQSo1c1Ym7orWxLYvCrM2EmxFTANf8wXmmE7DWjhx5N"))
    }

    @Test
    fun hintsAreMultiaddrsOnlyAndNotThisDevice() {
        val got = PeerRules.hints(
            listOf("/ip4/10.0.0.2/tcp/19742", "/ip4/127.0.0.1/tcp/1", "/ip6/::1/tcp/1", "http://evil", "/dns4/a.example/tcp/1;rm", "/ip4/10.0.0.2/tcp/19742") +
                List(20) { "/ip4/10.0.1.$it/udp/1/quic-v1" },
        )
        assertEquals("/ip4/10.0.0.2/tcp/19742", got[0])
        assertEquals(12, got.size)
        assertTrue(got.none { it.contains("127.0.0.1") || it.contains("::1") || it.contains(";") })
    }

    @Test
    fun aNameThatCameInAnInviteIsShownAsPlainText() {
        fun name(n: String) = PeerRules.invite("wittymedia://p2p/$id?s=abcdefABCDEF0123_-xy&n=" + java.net.URLEncoder.encode(n, "UTF-8"))!!.name
        assertEquals("Homegnp.exe", name("Home\u202egnp.exe"))
        assertEquals("Bank", name(" \u2066Bank\u2069\u001b "))
        assertEquals("TV", name("\ufeffTV\u200f"))
        val house = String(Character.toChars(0x1F3E0))
        assertEquals(house.repeat(80), name(house.repeat(90)))
    }

    @Test
    fun anInviteIsReadAndNothingElse() {
        val link = "wittymedia://p2p/$id?s=abcdefABCDEF0123_-xy&n=Home%20server&a=%2Fip4%2F10.0.0.2%2Ftcp%2F19742&a=bad"
        val invite = PeerRules.invite(link)!!
        assertEquals(id, invite.serverId)
        assertEquals("abcdefABCDEF0123_-xy", invite.secret)
        assertEquals("Home server", invite.name)
        assertEquals(listOf("/ip4/10.0.0.2/tcp/19742"), invite.hints)
        assertNull(PeerRules.invite("http://p2p/$id?s=abcdefABCDEF0123"))
        assertNull(PeerRules.invite("wittymedia://p2p/$id?s=short"))
        assertNull(PeerRules.invite("wittymedia://p2p/notanid?s=abcdefABCDEF0123"))
        assertNull(PeerRules.invite("10.0.0.2:9797"))
    }

    @Test
    fun theConfigurationIsWhatTheLibraryTakes() {
        val config = json.parseToJsonElement(PeerRules.configuration("k", id, listOf("/ip4/10.0.0.2/tcp/1", "/ip4/127.0.0.1/tcp/1"), 80)).jsonObject
        assertEquals("k", config["key"]!!.jsonPrimitive.content)
        assertEquals(id, config["serverId"]!!.jsonPrimitive.content)
        assertEquals("[\"/ip4/10.0.0.2/tcp/1\"]", config["hints"].toString())
        // A port below 1024 is never asked for.
        assertEquals("0", config["port"]!!.jsonPrimitive.content)
        val join = json.parseToJsonElement(PeerRules.joinConfiguration("k", "K7QM-2XHD", "x".repeat(100), "Android TV")).jsonObject
        assertEquals(60, join["name"]!!.jsonPrimitive.content.length)
        assertTrue(PeerRules.isJoinCode("K7QM-2XHD"))
        assertFalse(PeerRules.isJoinCode("K7QM-2XHI"))
        assertFalse(PeerRules.isJoinCode("K7QM2XHD"))
    }

    @Test
    fun theStateIsReadAndSaidPlainly() {
        assertTrue(PeerRules.state("""{"path":"direct","transport":"quic"}""").connected)
        assertEquals("Peer to peer · direct", PeerRules.state("""{"path":"direct"}""").words)
        assertEquals("Peer to peer · through a relay", PeerRules.state("""{"path":"relayed","community":true}""").words)
        assertEquals("Peer to peer · connecting directly…", PeerRules.state("""{"path":"relayed"}""").words)
        assertFalse(PeerRules.state("""{"path":"offline","error":"gone\u0007"}""").connected)
        assertEquals("gone", PeerRules.state("""{"path":"offline","error":"gone\u0007"}""").error)
        // Anything else is still connecting, not connected.
        assertEquals("connecting", PeerRules.state("""{"path":"teleported"}""").path)
        assertEquals("connecting", PeerRules.state("not json").path)
    }

    @Test
    fun whatARelayAllowsIsSaidAndNothingElseFromIt() {
        val s = PeerRules.state("""{"path":"relayed","community":true,"relayKbps":4000,"relayMaxHeight":720,"relayAllows":"Up to 4 Mbit/s per connection,\u0007 pictures up to 720p."}""")
        assertEquals(4000, s.relayKbps)
        assertEquals(720, s.relayMaxHeight)
        assertEquals("Peer to peer · through a relay · 4 Mbit/s, 720p", s.words)
        assertTrue(s.relayAllows.none { it.isISOControl() })
        assertEquals("Peer to peer · through a relay · 1.5 Mbit/s", PeerRules.state("""{"path":"relayed","community":true,"relayKbps":1500}""").words)
        // Nonsense, a relay that only introduces, or a direct path, says no limits.
        val odd = PeerRules.state("""{"path":"relayed","community":true,"relayKbps":"4000","relayMaxHeight":99999}""")
        assertEquals(0, odd.relayKbps)
        assertEquals(0, odd.relayMaxHeight)
        assertEquals(0, PeerRules.state("""{"path":"relayed","community":false,"relayKbps":4000}""").relayKbps)
        assertEquals(0, PeerRules.state("""{"path":"direct","relayKbps":4000}""").relayKbps)
    }

    @Test
    fun anAnswerKeepsOnlyASixDigitCodeAndARealId() {
        val ok = PeerRules.answer("""{"ok":true,"code":"123456","serverName":"Home","serverId":"$id","addrs":["/ip4/10.0.0.2/tcp/1","x"]}""")
        assertTrue(ok.ok)
        assertEquals("123456", ok.code)
        assertEquals(id, ok.serverId)
        assertEquals(listOf("/ip4/10.0.0.2/tcp/1"), ok.addrs)
        val odd = PeerRules.answer("""{"ok":true,"code":"12345a","serverId":"nope"}""")
        assertEquals("", odd.code)
        assertEquals("", odd.serverId)
        assertEquals("expired", PeerRules.answer("""{"ok":false,"reason":"expired"}""").reason)
    }

    @Test
    fun whatIsKeptIsCleanedOnTheWayIn() {
        assertNull(PeerInfo("nope").cleaned())
        val kept = PeerInfo(id, listOf("/ip4/10.0.0.2/tcp/1", "/ip4/127.0.0.1/tcp/1"), 80).cleaned()!!
        assertEquals(0, kept.port)
        assertEquals(1, kept.hints.size)
        assertEquals("http://p2p-smsousldncz2j8ur.localhost", PeerRules.awayOnlyUrl(id))
        assertTrue(PeerRules.isAwayOnlyUrl(PeerRules.awayOnlyUrl(id)))
        assertEquals(listOf("/ip4/10.0.0.2/tcp/1"), PeerRules.knownAddrs("""["/ip4/10.0.0.2/tcp/1"]"""))
    }
}
