package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.ui.spacedArcs
import org.junit.Assert.assertEquals
import org.junit.Test

// The website's icons pack an arc's flags against the next number, as browsers allow.
class WebIconTest {
    @Test
    fun arcFlagsAreWrittenOut() {
        assertEquals("M11 7h2v2h-2zm1 -9a10 10 0 1 0 0 20 10 10 0 0 0 0 -20z", spacedArcs("M11 7h2v2h-2zm1-9a10 10 0 100 20 10 10 0 000-20z"))
        assertEquals("M15.5 14h-.8l-.3 -.3a6.5 6.5 0 1 0 -.7 .7", spacedArcs("M15.5 14h-.8l-.3-.3a6.5 6.5 0 10-.7.7"))
    }
}
