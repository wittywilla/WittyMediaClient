package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.DeviceSession
import com.wittywilla.wittymediaclient.net.ProfileUpdate
import com.wittywilla.wittymediaclient.net.TwoFactorStatus
import com.wittywilla.wittymediaclient.net.json
import com.wittywilla.wittymediaclient.net.themeSyncScript
import com.wittywilla.wittymediaclient.ui.YouOpens
import com.wittywilla.wittymediaclient.ui.YouWho
import com.wittywilla.wittymediaclient.ui.deviceKind
import com.wittywilla.wittymediaclient.ui.groupsOfFour
import com.wittywilla.wittymediaclient.ui.roleKey
import com.wittywilla.wittymediaclient.ui.tvCodeTyped
import com.wittywilla.wittymediaclient.ui.youGroups
import kotlinx.serialization.encodeToString
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// docs/APP-DESIGN.md, "You and settings": who sees which rows, and what they open.
class YouTest {
    private val adult = YouWho(admin = false, adult = true, hasGames = false, twoStepAvailable = true, onTv = false)

    private fun rows(who: YouWho) = youGroups(who).flatMap { it.rows }.map { it.key }
    private fun groups(who: YouWho) = youGroups(who).map { it.key }

    @Test
    fun theServerGroupsAreOnlyForAnAdministrator() {
        assertFalse("groupServer" in groups(adult))
        assertFalse("groupMaintenance" in groups(adult))
        val admin = adult.copy(admin = true)
        assertTrue("groupServer" in groups(admin))
        assertTrue("rowReset" in rows(admin))
    }

    @Test
    fun aKidsProfileHasNoPasswordTwoStepOrHousehold() {
        val kids = adult.copy(adult = false)
        assertFalse("rowPassword" in rows(kids))
        assertFalse("rowTwoStep" in rows(kids))
        assertFalse("groupHousehold" in groups(kids))
        assertTrue("rowNames" in rows(kids))
        assertTrue("rowDevices" in rows(kids))
    }

    @Test
    fun gameRowsNeedAGamesLibrary() {
        assertFalse("rowGameSettings" in rows(adult))
        assertTrue("rowControllers" in rows(adult.copy(hasGames = true)))
    }

    @Test
    fun twoStepOnlyWhenTheServerOffersIt() {
        assertFalse("rowTwoStep" in rows(adult.copy(twoStepAvailable = false)))
    }

    @Test
    fun aTvDoesntSignInTvs() {
        assertFalse("rowSignInTv" in rows(adult.copy(onTv = true)))
        assertTrue("rowProfiles" in rows(adult.copy(onTv = true)))
    }

    @Test
    fun whatEachRowOpens() {
        val all = youGroups(adult.copy(admin = true, hasGames = true)).flatMap { it.rows }.associateBy { it.key }
        assertEquals(YouOpens.Page("/settings/users"), all.getValue("rowProfiles").opens)
        assertEquals(YouOpens.Page("/review"), all.getValue("rowYourYear").opens)
        assertTrue(all.getValue("rowNames").opens is YouOpens.Native)
        assertEquals("danger", all.getValue("rowReset").tint)
    }

    @Test
    fun roles() {
        assertEquals("roleAdmin", roleKey(true, "adult"))
        assertEquals("roleAdult", roleKey(false, "adult"))
        assertEquals("roleKids", roleKey(false, "kids"))
        assertEquals("roleGuest", roleKey(false, "guest"))
    }

    @Test
    fun aTvsCodeIsItsEightLettersInCapitals() {
        assertEquals("QVSFNQCQ", tvCodeTyped("qvsf-nqcq"))
        assertEquals("BCDF", tvCodeTyped("b c d f 1 2 a e"))
        assertEquals(8, tvCodeTyped("BCDFGHJKLMNP").length)
    }

    @Test
    fun devicesByName() {
        assertEquals("phone", deviceKind("Google sdk_gphone64_arm64"))
        assertEquals("tv", deviceKind("Google sdk_google_atv64_arm64"))
        assertEquals("browser", deviceKind("Chrome on macOS"))
        assertEquals("tablet", deviceKind("iPad"))
    }

    @Test
    fun theSecretInFours() {
        assertEquals("ABCD EFGH IJ", groupsOfFour("ABCDEFGHIJ"))
    }

    @Test
    fun onlyWhatChangedIsSent() {
        assertEquals("""{"showUsername":true}""", json.encodeToString(ProfileUpdate(showUsername = true)))
        assertEquals("""{"displayName":"Ann"}""", json.encodeToString(ProfileUpdate(displayName = "Ann")))
    }

    @Test
    fun whatTheServerSays() {
        val list = json.decodeFromString<List<DeviceSession>>(
            """[{"id":"a1","userId":2,"userName":"ann","device":"Pixel 9","lastSeen":1730000000,"where":"home","current":true}]""",
        )
        assertTrue(list.first().current)
        assertEquals("home", list.first().where)
        assertEquals(TwoFactorStatus(on = false, recoveryLeft = 0, available = true), json.decodeFromString<TwoFactorStatus>("""{"on":false,"recoveryLeft":0,"available":true}"""))
    }

    @Test
    fun serverPagesFollowTheThemeChosenHere() {
        assertTrue("setItem('wms.theme', 'paper')" in themeSyncScript("paper")!!)
        assertTrue("removeItem('wms.theme')" in themeSyncScript("")!!)
        assertNull(themeSyncScript("x');alert(1);('"))
    }
}
