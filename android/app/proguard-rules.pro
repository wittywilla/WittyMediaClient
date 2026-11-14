# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 WittyWilla and contributors
# The peer-to-peer library's Java side is called from its Go side through JNI, by name: R8 must keep it whole.
-keep class go.** { *; }
-keep class com.wittywilla.wittyconnect.** { *; }
-dontwarn go.**
-dontwarn com.wittywilla.wittyconnect.**

# WebRTC (WittyPlay's version 2 stream): libwebrtc finds its Java side by name through JNI, org.jni_zero's
# JniInit first, so R8 must keep both whole or the app ends the moment a game's stream starts.
-keep class org.webrtc.** { *; }
-keep class org.jni_zero.** { *; }
