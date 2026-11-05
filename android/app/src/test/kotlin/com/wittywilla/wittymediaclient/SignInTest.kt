package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.Credentials
import com.wittywilla.wittymediaclient.net.Profiles
import com.wittywilla.wittymediaclient.net.ServerStatus
import com.wittywilla.wittymediaclient.net.asksForCode
import com.wittywilla.wittymediaclient.net.brandLogoUrl
import com.wittywilla.wittymediaclient.net.json
import kotlinx.serialization.encodeToString
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// What the sign-in screens read from the server, as WittyMediaServer's internal/server sends it.
class SignInTest {
    @Test
    fun profilesCarryTheProfileName() {
        val profiles = json.decodeFromString<Profiles>(
            """{"style":"profiles","profiles":[{"id":1,"name":"ann","displayName":"Ann","kind":"kids","hasPassword":false}]}""",
        )
        assertEquals("Ann", profiles.profiles.first().displayName)
        assertEquals("ann", profiles.profiles.first().name)
    }

    @Test
    fun anOlderServerWithoutProfileNamesStillReads() {
        val profiles = json.decodeFromString<Profiles>("""{"style":"profiles","profiles":[{"id":1,"name":"ann"}]}""")
        assertEquals("", profiles.profiles.first().displayName)
    }

    @Test
    fun theSecondStepIsAskedForOnlyBy401WithTwoFactor() {
        assertTrue(asksForCode(401, """{"error":"Enter the 6-digit code from your authenticator app.","twoFactor":true}"""))
        assertFalse(asksForCode(401, """{"error":"invalid name or password"}"""))
        assertFalse(asksForCode(429, """{"error":"Too many tries.","twoFactor":true}"""))
        assertFalse(asksForCode(401, "not json"))
    }

    @Test
    fun theCodeGoesOnlyWhenThereIsOne() {
        val first = json.encodeToString(Credentials("ann", "secret", "Pixel"))
        assertFalse("code" in first)
        val second = json.encodeToString(Credentials("ann", "secret", "Pixel", "123456"))
        assertTrue(""""code":"123456"""" in second)
    }

    @Test
    fun theServersOwnLogo() {
        val status = json.decodeFromString<ServerStatus>("""{"name":"WittyMediaServer","brandName":"Ann's films","brandLogo":"1730000000"}""")
        assertEquals("Ann's films", status.brandName)
        assertEquals("http://10.0.0.5:9797/api/v1/branding/logo?v=1730000000", brandLogoUrl("http://10.0.0.5:9797", status.brandLogo))
        assertEquals("", brandLogoUrl("http://10.0.0.5:9797", ""))
    }
}
