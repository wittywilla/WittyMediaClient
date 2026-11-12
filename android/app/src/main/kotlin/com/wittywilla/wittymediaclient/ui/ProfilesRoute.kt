// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.runtime.Composable
import com.wittywilla.wittymediaclient.net.FEATURE_SWITCHING

// The household's screens in the app's own stack (the server's docs/PROFILES.md): Who's watching for switching
// profile without signing out, and, under You → Profiles, what an adult manages for the profiles in their care.

data class HouseholdRoute(val screen: HouseholdScreen) : Route {
    override val key = "household-" + screen.key
}

sealed interface HouseholdScreen {
    val key: String

    data object Who : HouseholdScreen {
        override val key = "who"
    }

    data object Profiles : HouseholdScreen {
        override val key = "profiles"
    }

    // A name and a picture: one's own picture, or both for someone managed.
    data class Look(val userId: Long) : HouseholdScreen {
        override val key = "look-$userId"
    }

    data class Limits(val userId: Long) : HouseholdScreen {
        override val key = "limits-$userId"
    }

    data class Report(val userId: Long) : HouseholdScreen {
        override val key = "report-$userId"
    }

    data object ParentsPin : HouseholdScreen {
        override val key = "parents-pin"
    }
}

@Composable
fun HouseholdRouteScreen(nav: Nav, s: Map<String, String>, route: HouseholdRoute) {
    when (val screen = route.screen) {
        HouseholdScreen.Who -> WhoIsWatchingScreen(nav, s)
        HouseholdScreen.Profiles -> ProfilesScreen(nav, s)
        is HouseholdScreen.Look -> LookScreen(nav, s, screen.userId)
        is HouseholdScreen.Limits -> LimitsScreen(nav, s, screen.userId)
        is HouseholdScreen.Report -> ReportScreen(nav, s, screen.userId)
        HouseholdScreen.ParentsPin -> ParentsPinScreen(nav, s)
    }
}

// "Switch profile" on You, and on the time-up notice. A server that switches opens Who's watching, which itself
// signs out where the server doesn't list its profiles to this device; an older server signs out, as before.
fun switchProfile(nav: Nav) {
    if (nav.has(FEATURE_SWITCHING)) {
        if (nav.current != HouseholdRoute(HouseholdScreen.Who)) nav.push(HouseholdRoute(HouseholdScreen.Who))
    } else {
        nav.signOut()
    }
}
