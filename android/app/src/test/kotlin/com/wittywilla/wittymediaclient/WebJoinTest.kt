// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.PeerRules
import com.wittywilla.wittymediaclient.net.WebJoin
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

// Enter a code (net/WebJoin.kt): the same keys and proofs as the server's p2p.DeriveWebJoin and WebJoinProof
// (internal/p2p/webjoin_test.go holds these same values) and the desktop app's desktop/code.js. A change here is a
// change of the wire format, to be made in all three.
class WebJoinTest {
    private fun hex(b: ByteArray) = b.joinToString("") { "%02x".format(it) }

    @Test
    fun theServersVectors() {
        val keys = WebJoin.deriveNow(WebJoin.clean("k7qm 2xhd"))
        assertEquals("7570bed5d42ed757a21d20977ab7222b47d6a3ad37e493928f642d59bda56ed9", hex(keys.find))
        assertEquals("5258c623e6e31dee14dc3a9139e33dae09f7b558b63211be3989babcb0e6002d", hex(keys.proof))
        val dn = ByteArray(16) { it.toByte() }
        val sn = ByteArray(16) { (100 + it).toByte() }
        val server = WebJoin.proof(keys.proof, "server", dn, sn, "ed25519-key-text")
        assertEquals("7e3132a96c5430476c4ea7c809fa9ef4748f853b0af4ba078d35a4f3f02af2fe", hex(server))
        assertNotEquals(hex(server), hex(WebJoin.proof(keys.proof, "device", dn, sn, "ed25519-key-text")))
    }

    @Test
    fun aCodeAsAPersonTypesIt() {
        assertEquals("K7QM2XHD", WebJoin.clean(" k7qm-2xhd "))
        assertEquals("K7QM2XHD", WebJoin.clean("K7QM 2XHD"))
        assertEquals("1000000A", WebJoin.clean("IOOO-OOOA")) // the letters that look like digits taken for them
        assertEquals("", WebJoin.clean("K7QM-2XH")) // too short
        assertEquals("", WebJoin.clean("K7QM-2XHDD")) // too long
        assertEquals("", WebJoin.clean("K7QM-2XHU")) // U is no symbol of a code
        assertEquals("K7QM-2XHD", WebJoin.show("K7QM2XHD"))
    }

    // A 0.8.5 server that restarted since it made the code says so (404, reason "restarted"); anything else is a
    // server that doesn't know the code.
    @Test
    fun aRestartIsReadFromTheRefusal() {
        assertEquals("restarted", WebJoin.reasonOf("""{"reason":"restarted","error":"This code expired because the server restarted."}"""))
        assertEquals("", WebJoin.reasonOf("""{"error":"not found"}"""))
        assertEquals("", WebJoin.reasonOf("not json"))
    }

    // Typed where an address goes: a code as shown is a code, a computer's name stays an address.
    @Test
    fun aCodeOrAnAddress() {
        assertTrue(WebJoin.looksLikeCode("K7QM-2XHD"))
        assertTrue(WebJoin.looksLikeCode("k7qm 2xhd"))
        assertTrue(WebJoin.looksLikeCode("K7QM2XHD"))
        for (name in listOf("mediabox", "homelab1", "nas.local", "192.168.1.50", "server:9797", "K7QM-2XHD.lan")) {
            assertFalse(name, WebJoin.looksLikeCode(name))
        }
    }

    // The QR code on a 0.8.5 server's Connect a device: the web address the page was opened at, and the code.
    @Test
    fun theQrCodesAddressAtHomeAndCode() {
        val id = "12D3KooWHeHn5nGucGC7AMeiXHmEugreQUmXSmSoUsLdnCz2J8UR"
        val base = "wittymedia://p2p/$id?s=abcdefghijklmnopqrstuv"
        val qr = PeerRules.invite("$base&h=http%3A%2F%2F192.168.1.50%3A9797&c=K7QM2XHD")!!
        assertEquals("http://192.168.1.50:9797", qr.home)
        assertEquals("K7QM2XHD", qr.code)
        assertEquals("https://nas.local", PeerRules.invite("$base&h=https%3A%2F%2Fnas.local&c=k7qm-2xhd")!!.home)
        // Both or neither; a plain web address only; an old link has neither and is the invite it always was.
        for (q in listOf(
            "&h=http%3A%2F%2F192.168.1.50%3A9797",
            "&c=K7QM2XHD",
            "&h=http%3A%2F%2F192.168.1.50%3A9797&c=hello",
            "&h=ftp%3A%2F%2F192.168.1.50&c=K7QM2XHD",
            "&h=http%3A%2F%2Fme%3Apw%40192.168.1.50&c=K7QM2XHD",
            "&h=http%3A%2F%2F192.168.1.50%3A9797%2Fsettings&c=K7QM2XHD",
            "&h=javascript%3Aalert(1)&c=K7QM2XHD",
            "",
        )) {
            val got = PeerRules.invite(base + q)!!
            assertEquals(q, "", got.home)
            assertEquals(q, "", got.code)
        }
    }
}
