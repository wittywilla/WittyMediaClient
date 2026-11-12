// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.p2p

import com.wittywilla.wittyconnect.mobile.Listener
import com.wittywilla.wittyconnect.mobile.Mobile

// The connector library built from WittyMediaServer's pkg/wittyconnect/mobile with gomobile.
internal object PeerBridge {
    fun make(): PeerNative = object : PeerNative {
        override fun newKey(): String = Mobile.newKey()
        override fun deviceId(key: String): String = Mobile.deviceID(key)
        override fun start(config: String, onState: (String) -> Unit): PeerLink {
            val session = Mobile.start(config, object : Listener {
                override fun onState(state: String) = onState(state)
            })
            return object : PeerLink {
                override val port: Int get() = session.port().toInt()
                override val secret: String get() = session.secret()
                override fun state(): String = session.state()
                override fun knownAddrs(): String = session.knownAddrs()
                override fun networkChanged() = session.networkChanged()
                override fun enrol(secret: String, name: String, platform: String): String = session.enrol(secret, name, platform)
                override fun close() = session.close()
            }
        }
        override fun newJoinCode(): String = Mobile.newJoinCode()
        override fun startJoin(config: String): PeerJoining {
            val joining = Mobile.startJoin(config)
            return object : PeerJoining {
                override fun await(): String = joining.await()
                override fun cancel() = joining.cancel()
            }
        }
        override fun setMemoryLimit(megabytes: Int) = Mobile.setMemoryLimit(megabytes.toLong())
        override fun freeMemory() = Mobile.freeMemory()
    }
}
