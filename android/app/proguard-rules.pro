# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 WittyWilla and contributors
# The peer-to-peer library's Java side is called from its Go side through JNI, by name: R8 must keep it whole.
-keep class go.** { *; }
-keep class com.wittywilla.wittyconnect.** { *; }
-dontwarn go.**
-dontwarn com.wittywilla.wittyconnect.**
