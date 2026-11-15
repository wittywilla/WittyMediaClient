// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import android.util.Log
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.isRoot
import androidx.compose.ui.test.printToString
import androidx.compose.ui.test.junit4.accessibility.enableAccessibilityChecks
import androidx.compose.ui.test.tryPerformAccessibilityChecks
import androidx.test.espresso.Espresso.onView
import androidx.test.espresso.accessibility.AccessibilityChecks
import androidx.test.espresso.action.ViewActions.swipeUp
import androidx.test.espresso.matcher.ViewMatchers
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

// Every main screen, as someone would reach it, in landscape and in portrait, through the Accessibility Test Framework's
// checks (what TalkBack and Switch Access need: labels, touch target sizes, contrast, duplicate descriptions), both
// Compose's (enableAccessibilityChecks) and Espresso's (AccessibilityChecks.enable(), run from the root view on a
// swipe). It runs against a real server the app is already signed in to (a debug build, data kept), so it is run by
// hand on a device, not by the unit tests:
//
//   adb shell am instrument -w -e title <item id> -e games <games library id> -e library <a library id> \
//     com.wittywilla.wittymediaclient.test/androidx.test.runner.AndroidJUnitRunner
//
// Screenshots go to the app's files, a11y/<screen>-<orientation>.png; every finding is logged under the tag WittyA11y,
// and the test fails at the end if any screen had one.
@RunWith(AndroidJUnit4::class)
class ScreensAccessibilityTest {
    @get:Rule
    val compose = createAndroidComposeRule<MainActivity>()

    private val args = InstrumentationRegistry.getArguments()
    private val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
    private val app get() = compose.activity.application as WittyApp

    // The places to check. A library, a title and the games library are given as arguments, else the first the server
    // has: a films library and its first title, and the first games library.
    private fun screens(): List<Pair<String, String>> {
        val libraries = runCatching { kotlinx.coroutines.runBlocking { app.api.libraries() } }.getOrDefault(emptyList())
        val films = libraries.firstOrNull { it.type == "movies" } ?: libraries.firstOrNull { it.type != "games" }
        val library = args.getString("library") ?: films?.id?.toString()
        val title = args.getString("title") ?: films?.let { f -> runCatching { kotlinx.coroutines.runBlocking { app.api.items(f.id, 0, 1) }.items.firstOrNull()?.id?.toString() }.getOrNull() }
        val games = args.getString("games") ?: libraries.firstOrNull { it.type == "games" && it.console != "rig" }?.id?.toString()
        return listOfNotNull(
            "home" to "/",
            "libraries" to "/libraries",
            library?.let { "library" to "/library/$it" },
            title?.let { "title" to "/item/$it" },
            "settings" to "/settings",
            "manage-libraries" to "/manage/libraries",
            games?.let { "manage-library" to "layer:/manage/library/$it" },
            games?.let { "games-library" to "/library/$it" },
            "together" to "/page/wittyplay-online?tab=together",
            "wittyplay-settings" to "/page/wittyplay-settings",
        )
    }

    @Test
    fun screensPassTheChecks() {
        AccessibilityChecks.enable().setRunChecksFromRootView(true)
        compose.enableAccessibilityChecks()
        val out = File(compose.activity.getExternalFilesDir(null), "a11y").apply { deleteRecursively(); mkdirs() }
        val found = ArrayList<String>()
        settle(8_000)
        val screens = screens()
        Log.i(TAG, "screens: $screens")
        for (turn in 0..1) {
            if (turn == 0) device.setOrientationNatural() else device.setOrientationLeft()
            settle(2_000)
            val orientation = if (compose.activity.resources.configuration.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE) "landscape" else "portrait"
            for ((name, path) in screens) {
                compose.runOnUiThread { app.debugPath = "/" }
                settle(2_000)
                compose.runOnUiThread { app.debugPath = path }
                // WittyPlay's pages are its website in a frame, slower to come.
                settle(if (path.startsWith("/page/wittyplay")) 10_000 else 5_000)
                // The system's own tip the first time an app hides the bars: not the app's, and it takes the window's focus.
                device.findObject(androidx.test.uiautomator.By.text("Got it"))?.click()?.also { settle(1_000) }
                device.takeScreenshot(File(out, "$name-$orientation.png"))
                runCatching { compose.onAllNodes(isRoot())[0].tryPerformAccessibilityChecks() }.onFailure { note(found, name, orientation, "compose", it) }
                // Espresso's checks run from the root view on any view action: a swipe leaves the screen as it was.
                runCatching { onView(ViewMatchers.isRoot()).perform(swipeUp()) }.onFailure { note(found, name, orientation, "espresso", it) }
            }
        }
        device.unfreezeRotation()
        Log.i(TAG, "${found.size} finding(s)")
        assertTrue(found.joinToString("\n\n"), found.isEmpty())
    }

    // For finding what a check means: the screen's semantics, every node, in the log (run with -e dump <address>).
    @Test
    fun dumpTree() {
        val path = args.getString("dump") ?: return
        settle(8_000)
        compose.runOnUiThread { app.debugPath = path }
        settle(5_000)
        compose.onAllNodes(isRoot(), useUnmergedTree = true).fetchSemanticsNodes(atLeastOneRootRequired = false).indices.forEach { i ->
            compose.onAllNodes(isRoot(), useUnmergedTree = true)[i].printToString(Int.MAX_VALUE).lines().forEach { Log.i(TAG, it) }
        }
    }

    private fun note(found: MutableList<String>, name: String, orientation: String, by: String, e: Throwable) {
        val words = "$name ($orientation, $by): ${e.message.orEmpty()}"
        // Espresso waits for the screen to be still before its action, which a page with a spinner never is: that run
        // didn't happen, and the Compose checks of the same screen stand. It is said, not counted.
        if (by == "espresso" && !e.javaClass.name.contains("Accessibility")) {
            Log.i(TAG, "not run: ${words.take(200)}")
            return
        }
        Log.w(TAG, words)
        found += words
    }

    // Real time, not the test clock: the app's pages have spinners that never stop, so it is never idle.
    private fun settle(ms: Long) = Thread.sleep(ms)

    companion object {
        const val TAG = "WittyA11y"
    }
}
