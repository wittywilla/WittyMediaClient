// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.p2p

// The connector library, as the app sees it. The bridge that calls the real one (src/p2p) is compiled only when the
// library was built into the app (android/scripts/build-wittyconnect.sh); otherwise a bridge that has nothing
// (src/nop2p), and the app works the same without connecting from away. Every call can block: none on the main thread.
interface PeerNative {
    fun newKey(): String
    fun deviceId(key: String): String
    fun start(config: String, onState: (String) -> Unit): PeerLink
    fun newJoinCode(): String
    fun startJoin(config: String): PeerJoining
    fun setMemoryLimit(megabytes: Int)
    fun freeMemory()
}

// One connection to one server, from away.
interface PeerLink {
    val port: Int
    val secret: String
    fun state(): String
    fun knownAddrs(): String
    fun networkChanged()
    // Blocks for up to 75 seconds.
    fun enrol(secret: String, name: String, platform: String): String
    fun close()
}

// Looking for the server that is told this device's code.
interface PeerJoining {
    // Blocks until the server answers, the code runs out, or cancel.
    fun await(): String
    fun cancel()
}

object PeerLibrary {
    val native: PeerNative? by lazy { runCatching { PeerBridge.make() }.getOrNull() }
    val available: Boolean get() = native != null
}
