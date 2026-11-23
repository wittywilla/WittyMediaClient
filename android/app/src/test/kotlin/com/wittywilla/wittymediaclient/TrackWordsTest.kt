// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.Track
import com.wittywilla.wittymediaclient.player.TrackWords
import org.junit.Assert.assertEquals
import org.junit.Test

// The same cases as apple/WittyKit/Tests/WittyKitTests/PlayerLookTests.swift, so all three players name tracks alike.
class TrackWordsTest {
    @Test
    fun theServersLanguageNameComesFirst() {
        val n = TrackWords.audio(Track(index = 1, language = "eng", languageName = "English", codec = "ac3", channels = 6), 1)
        assertEquals("English", n.title)
        assertEquals("", n.sub)
        assertEquals("AC3 · 5.1", n.detail)
    }

    @Test
    fun codesAreNamedWhenTheServerDidNot() {
        assertEquals("German", TrackWords.languageOf("ger"))
        assertEquals("German", TrackWords.languageOf("deu"))
        assertEquals("French", TrackWords.languageOf("fre"))
        assertEquals("Japanese", TrackWords.languageOf("jpn"))
        assertEquals("Portuguese", TrackWords.languageOf("pt-BR"))
        assertEquals("", TrackWords.languageOf("und"))
        assertEquals("", TrackWords.languageOf(""))
    }

    @Test
    fun anUnlabelledTrackIsNumberedNeverUnknown() {
        assertEquals("Track 2", TrackWords.audio(Track(index = 4, codec = "aac", channels = 2), 2).title)
        assertEquals("Subtitles 3", TrackWords.subtitle(Track(index = 7, language = "und", codec = "subrip"), 3).title)
        // With no language, the track's own name is the best there is.
        assertEquals("Director's cut", TrackWords.audio(Track(index = 4, title = "Director's cut"), 1).title)
    }

    @Test
    fun theTracksOwnNameAndMarksGoUnderneath() {
        val sdh = TrackWords.subtitle(Track(index = 3, language = "eng", languageName = "English", codec = "subrip", sdh = true), 2)
        assertEquals("English", sdh.title)
        assertEquals("SDH", sdh.sub)
        assertEquals("Text", sdh.detail)
        val forced = TrackWords.subtitle(Track(index = 4, language = "eng", title = "Signs", codec = "hdmv_pgs_subtitle", forced = true), 3)
        assertEquals("English", forced.title)
        assertEquals("Signs · Forced", forced.sub)
        assertEquals("Pictures", forced.detail)
        // A title that only repeats the language, or already says what the mark says, isn't said twice.
        assertEquals("", TrackWords.subtitle(Track(index = 5, language = "eng", title = "English", codec = "ass"), 1).sub)
        assertEquals("English SDH", TrackWords.subtitle(Track(index = 6, language = "eng", title = "English SDH", sdh = true), 1).sub)
        assertEquals("Commentary", TrackWords.audio(Track(index = 2, language = "eng", commentary = true, channels = 2), 2).sub)
    }

    @Test
    fun theLineJoinsWhatThereIs() {
        assertEquals("English · Commentary · AAC · Stereo", TrackWords.audio(Track(index = 2, language = "en", title = "Commentary", codec = "aac", channels = 2), 1).line)
    }

    @Test
    fun aRepeatedIndexIsListedOnce() {
        val t = Track(index = 1, language = "eng")
        assertEquals(1, TrackWords.audioList(listOf(t, t)).size)
    }
}
