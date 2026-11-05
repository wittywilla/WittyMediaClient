package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.ui.avatarColour
import com.wittywilla.wittymediaclient.ui.avatarInitial
import com.wittywilla.wittymediaclient.ui.avatarName
import com.wittywilla.wittymediaclient.ui.showsUsername
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// The four names docs/APP-DESIGN.md gives, which the Apple app's tests check too.
class AvatarTest {
    private fun hex(colour: Long) = "#%06x".format(colour and 0xFFFFFF)

    @Test
    fun theSpecsFourNamesGetTheWebsColours() {
        assertEquals("#bd2f85", hex(avatarColour("test")))
        assertEquals("#0a6fb8", hex(avatarColour("Ann")))
        assertEquals("#0e7c6f", hex(avatarColour("Émile")))
        assertEquals("#99690a", hex(avatarColour("Mum 👩")))
    }

    @Test
    fun theProfileNameComesFirst() {
        assertEquals("Ann", avatarName("Ann", "ann"))
        assertEquals("ann", avatarName("", "ann"))
    }

    @Test
    fun theInitialIsTheFirstLetterInCapitals() {
        assertEquals("É", avatarInitial(" émile"))
        assertEquals("👩", avatarInitial("👩 Mum"))
        assertEquals("?", avatarInitial("  "))
    }

    @Test
    fun theUsernameShowsOnlyWhenItSaysSomethingElse() {
        assertTrue(showsUsername("Ann", "ann"))
        assertFalse(showsUsername("", "ann"))
        assertFalse(showsUsername("ann", "ann"))
    }
}
