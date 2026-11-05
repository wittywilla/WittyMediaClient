package com.wittywilla.wittymediaclient.ui

// docs/APP-DESIGN.md, "Avatar": the web's colours and the web's sum, so a person keeps the same colour
// on every device and in the browser. Apart from the screen, so it can be tested without one.

// All dark enough for white words.
val AVATAR_COLOURS = listOf(
    0xFFC9302F, 0xFFB8500D, 0xFF99690A, 0xFF2E7D3C, 0xFF0E7C6F,
    0xFF0A6FB8, 0xFF3E5BD0, 0xFF7F46B8, 0xFFBD2F85, 0xFF8D6444,
)

// The profile name, or the username when there isn't one.
fun avatarName(displayName: String, username: String): String = displayName.ifEmpty { username }

// The web walks the name by code point and adds each one's first UTF-16 unit, so an emoji counts
// only its first half. Kept to 32 bits, as the web's `>>> 0` does.
fun avatarSum(name: String): Long {
    var sum = 0L
    var i = 0
    while (i < name.length) {
        sum = (sum * 31 + name[i].code) and 0xFFFFFFFFL
        i += Character.charCount(name.codePointAt(i))
    }
    return sum
}

fun avatarColour(name: String): Long = AVATAR_COLOURS[(avatarSum(name) % AVATAR_COLOURS.size).toInt()]

// The first letter, whole even when it's outside the first plane.
fun avatarInitial(name: String): String {
    val trimmed = name.trim()
    if (trimmed.isEmpty()) return "?"
    return String(Character.toChars(trimmed.codePointAt(0))).uppercase()
}

// The username goes under the profile name only when there is one and it says something else.
fun showsUsername(displayName: String, username: String): Boolean = displayName.isNotEmpty() && displayName != username
