package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.versionParts
import org.junit.Assert.assertEquals
import org.junit.Test

// The version line at the foot of a page, as the website writes it (components/common.tsx VersionTag).
class PageFootTest {
    @Test
    fun theNumberAndTheStageInCapitals() {
        assertEquals("0.6.2" to "ALPHA", versionParts("0.6.2-alpha"))
        assertEquals("1.0.0" to "BETA", versionParts("v1.0.0-beta.3"))
        assertEquals("2.1.0" to "", versionParts("2.1.0"))
        assertEquals("dev" to "DEV", versionParts("dev"))
        assertEquals("dev" to "", versionParts(""))
    }
}
