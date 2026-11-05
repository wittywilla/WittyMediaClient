# How the apps look

One design for every native app: iPhone and Android phones first, then iPad and Android tablets,
then Apple TV and Android TV, which mirror the phone's design for a room and look **identical to each
other**. Apple Vision Pro takes the tablet's. The desktop apps (Windows, macOS, Linux, FreeBSD,
Plasma Bigscreen) are the server's own web interface in a window: only their connect screen,
`shared/connect/`, is the apps', and it follows the same look.

This is the contract both codebases are built and checked against. Where Apple and Android differ, it's
only where each system has its own convention: the status bar, the back gesture, the keyboard. Wording
comes from `shared/data/strings.en.json`, so every app says the same thing. Every feature the server
offers is reachable from every app: arranged for the device, never left out. See [Feature map](#feature-map).

- [Principles](#principles)
- [Foundations](#foundations)
- [Brand](#brand)
- [Components](#components)
- [Signing in](#signing-in)
- [You and settings](#you-and-settings)
- [Feature map](#feature-map)
- [On a TV](#on-a-tv)
- [Checking a build against this](#checking-a-build-against-this)

## Principles

1. **The pictures are the colour.** Posters and backdrops carry the colour; everything around them is
   quiet, in the theme's neutrals. The accent marks one thing per screen: the main action, or what's chosen.
2. **One obvious next step.** Each screen has one primary button. Everything else is secondary or a link.
3. **Calm, not empty.** Generous space on a 4-point grid, nothing crowded against an edge, nothing
   floating without a reason.
4. **People, not accounts.** Profiles are faces: a coloured tile with an initial, the same colour on every
   device and in the browser.
5. **Plain words.** Short sentences in the shared wording. Errors say what happened and what to do.
6. **Touch, remote and voice alike.** 44-point targets on a phone; on a TV every control is reachable with
   arrows and OK, and focus is always visible. Every control has a spoken label.
7. **Motion that explains.** Short fades and lifts (150–240 ms) that show where something came from.
   With Reduce Motion on, nothing moves that the person didn't move.

## Foundations

### Colour roles

From the server's theme (`shared/data/themes.json`, chosen by `/api/status` → `theme`):

| Role | Use |
|---|---|
| `background` | The page |
| `panel` | Raised areas: the floating bar, grouped lists, sheets |
| `card` | Filled controls: secondary buttons, keys, server cards, avatar placeholders |
| `border` | Hairlines, outlines of fields, the selected chip's fill |
| `text`, `textSecondary`, `textHint` | Words, quieter words, hints and placeholders |
| `accent`, `onAccent`, `accentText` | The primary button and its words; accent-coloured words and icons on the page |
| `danger`, `ok` | Errors and destructive actions; success |

Derived, the same on every platform:

- **Glow:** the sign-in screens have a soft light at the top, `accent` at 16% opacity in an ellipse
  70% of the width and 60% of the height, centred on the top edge, fading out by 70%. (The web's
  `radial-gradient(70% 60% at 50% 0%, accent/.16, transparent 70%)`.)
- **Scrim:** words over a picture sit on `background` fading in from 0% to 100%.

### Type

Sizes for a phone; a tablet uses the same; a TV uses the TV column. On Apple these are the nearest text
styles, so Dynamic Type still works; on Android they're `sp`.

| Name | Phone | TV | Weight | Use |
|---|---|---|---|---|
| Display | 30 | 48 | Bold | "Who's watching?", the wide hero's title |
| Title | 24 | 38 | Semibold | A page's heading |
| Headline | 20 | 30 | Semibold | The hero title on a phone, a profile's name on the password screen |
| Section | 17 | 26 | Semibold | Above a row or a group |
| Body | 15 | 24 | Regular | Sentences |
| Label | 15 | 24 | Medium | Buttons, rows, tiles |
| Secondary | 13 | 20 | Regular | Facts, explanations |
| Caption | 12 | 18 | Medium | Badges, field labels when raised, the legal note |

### Space, size and shape

- **Grid:** 4, 8, 12, 16, 20, 24, 32, 40, 48, 64.
- **Gutter** (page side margin): phone 16, tablet 32, TV 90 (Apple TV's safe area; 45 dp on Android TV).
- **Targets:** at least 44 high on a phone and tablet; buttons are 52 high on the sign-in screens.
- **Radii:** 6 small, 10 medium (buttons, fields, posters, keys), 14 large (cards, grouped lists),
  20 extra (sheets), pills fully round. Avatars: 22% of their size.
- **Shadows:** none, except the floating bar (black 25%, 8 blur, 2 down).

### Motion

| What | How |
|---|---|
| A button pressed | 0.97 scale and 85% opacity while held |
| A screen pushed | The system's own transition |
| A profile tile chosen | The avatar lifts 3 and gains a ring (`background` 3, then `text` 3), as on the web |
| Something appearing | 200 ms fade, and 8 up |
| Focus on a TV | 1.06 scale and a 4-wide ring in `text`, no animation beyond that |

### Icons

SF Symbols on Apple, Material Symbols (rounded) on Android, mapped one to one:

| Meaning | Apple | Android |
|---|---|---|
| Server | `server.rack` | `dns` |
| Address | `link` | `link` |
| Person | `person` | `person` |
| Password | `lock` | `lock` |
| Show / hide password | `eye` / `eye.slash` | `visibility` / `visibility_off` |
| Code | `number` | `pin` |
| QR | `qrcode` | `qr_code_2` |
| Back | `chevron.left` | `arrow_back` |
| Next | `chevron.right` | `chevron_right` |
| Delete a digit | `delete.left` | `backspace` |
| Settings | `gearshape` | `settings` |
| Sign out | `rectangle.portrait.and.arrow.right` | `logout` |
| Warning | `exclamationmark.triangle.fill` | `warning` |
| Check | `checkmark` | `check` |

## Brand

- **Mark:** the server's icon (`web/public/icon.svg` in WittyMediaServer), drawn natively: a 64×64
  rounded square (radius 14) in `#1b1e25`, a ring of radius 20 and width 5, and a play triangle with
  points (27,23), (41,32), (27,41), both in a gradient from `#9d7bff` (top left) to `#5b3df5` (bottom right).
- **Wordmark:** "Witty**Media**Server" in Headline weight bold, with "Media" in `accentText`. When the server
  has a name of its own (`/api/status` → `brandName`), that name replaces the wordmark, in `text`.
- **Custom logo:** when `/api/status` → `brandLogo` isn't empty, the mark is the server's logo,
  `/api/branding/logo?v=<brandLogo>`, in the same rounded square.
- **Lockup:** mark then wordmark, 10 apart. Sizes: 32 mark on the connect and profile screens, 48 on a TV.

## Components

### Buttons

| Kind | Look | Use |
|---|---|---|
| Primary | `accent` fill, `onAccent` words, radius 10 (pill on Home and items) | The one main action |
| Secondary | `card` fill, `text` words | Other actions |
| Quiet | No fill, `accentText` words | Links: "Forgot your password?", "Change server" |
| Destructive | `card` fill, `danger` words | Sign out, forget, remove |

Full width in a column on the sign-in screens, 52 high, words centred, an optional leading icon 8 before the words.
While busy, the words are replaced by a spinner in the words' colour and the button keeps its size; it stays
focusable on a TV. Disabled only where pressing would do harm, at 55% opacity.

### Fields

Outlined: radius 10, 56 high, `border` 1 wide; focused, `accent` 2 wide. The label sits inside until the field
has focus or words, then rises to sit on the border, in Caption, `accentText` while focused. Optional leading icon
(`textSecondary`, 20) 16 from the edge, and a trailing action (show/hide password). The keyboard suits the field:
address, username, password. Return moves to the next field or does the main action. An error under a field is a
Caption line in `danger` with the warning icon.

### Avatar

The same as the web's, so each person keeps their colour on every device:

1. **Name:** the profile name, `displayName`, or the username, `name`, when that's empty.
2. **Colour:** `h = 0`; for each Unicode code point of the name, `h = (h × 31 + u) mod 2³²`, where `u` is that code
   point's first UTF-16 code unit. The colour is `AVATAR_COLORS[h mod 10]`:
   `#c9302f #b8500d #99690a #2e7d3c #0e7c6f #0a6fb8 #3e5bd0 #7f46b8 #bd2f85 #8d6444`.
   All are dark enough for white words (4.5:1). Tests in both apps check `"test"` → `#bd2f85`, `"Ann"` →
   `#0a6fb8`, `"Émile"` → `#0e7c6f` and `"Mum 👩"` → `#99690a` (an emoji outside the first plane) against this rule.
3. **Initial:** the first letter of the trimmed name, upper case, white, bold, at 43% of the tile's size.
4. **Shape:** a rounded square, radius 22% of its size. Small avatars (36 and under) are circles.
5. **Sizes:** 28 in the floating bar, 64 in You's header, 104 in the phone's profile grid, 120 on the password
   screen, 140 in a tablet's grid, 200 on a TV.

### Profile tile

The avatar, then 10 below it the profile name in Label semibold, then the username as `@name` in Secondary,
**only when a profile name is set and differs from the username**: so a person sees both, or just the one there is.
Kids and Guest profiles carry a badge on the avatar's lower edge, centred, half over it: a pill in `background`
with a 1-wide `border`, Caption words "Kids" or "Guest". A profile that signs in without a password (Kids or Guest
at home) goes straight in; the others open the password screen. Pressed or focused, the avatar lifts and gains the
ring (see Motion); the words brighten from `textSecondary` to `text`. Spoken as "Ann, @ann, Kids profile".

### Server card

A `card` row, radius 14, 16 inside: the server mark (the brand mark at 40, or the server's own logo once known),
then its name in Label semibold over its address in Secondary, then a chevron in `textHint`. The one last used carries
"Last used" as a Caption pill in `border`. Pressed: 0.98 scale. Connecting: the chevron becomes a spinner.

### Grouped list

For You and settings: a `panel` card, radius 14, rows 52 high (64 with a second line) with 16 inside, separated by
hairlines in `border` inset 52 from the leading edge when the row has an icon. A row: a 28 rounded-square icon tile
(radius 7) in a quiet tint of its colour, the title in Body, an optional value on the trailing side in Secondary, and
a chevron when it opens something. A Section caption sits 8 above each group, in Caption, `textSecondary`, upper case.

### Code entry

Six boxes in a row, 8 apart, each 48 wide and 56 high on a phone (88×100 on a TV), radius 10, `card` fill. A box with
a digit shows it in Title monospaced; the next box to fill has a 2-wide `accent` outline and a blinking caret. The
number pad below is a 3×4 grid of `card` keys 64 high (96 on a TV), radius 14, digits in Headline, with Delete
(the delete icon) bottom left and 0 two columns wide. A finished code turns the boxes' outlines `accent` while
it's checked; a wrong one shakes them once (not with Reduce Motion) and clears them.

### QR card

White, radius 14, 16 inside, the code black on white, at 180 on a phone and 280 on a TV, captioned under it in Caption.

### Messages

- **Problem:** a row with the warning icon in `danger` and the words in `text`. Inside a form it sits just above the
  primary button; for a whole screen, it's centred with Try again (primary) under it.
- **Note:** an info row in a `panel` card, for what isn't a failure ("This device can't search your network").
- **Toast:** a `panel` pill near the bottom for 3 seconds, for a change that worked ("Profile name saved").

## Signing in

Every sign-in screen has the glow, a single centred column (max 440 wide on a phone or tablet), and the lockup at the
top unless it shows a person instead. On a phone the column starts a third of the way down when it's short, and scrolls
when it isn't. Back, where there's somewhere to go back to, is the system's: the back button top left on Apple, the
back gesture or a top-left arrow on Android.

### 1. Choose your server

1. Lockup.
2. Display: `findTitle` ("Choose your server"). Under it in Body, `textSecondary`: `findSubtitle`.
3. Section: `foundServers` ("On your network"), with a small pulsing dot in `accent` beside it while searching.
4. Server cards for what's found. While nothing is: a Note with a spinner and `findSearching`; after six seconds
   `findNone`; where the device can't search, `findNotSupported`.
5. Section `recentServers` ("Used before") and its cards, the last used first.
6. `enterAddress` ("Enter an address"): Primary when nothing has been found or used, Secondary otherwise.
7. The legal note, `legalConnect`, in Caption, `textHint`, centred, at the bottom.

### 2. Enter your server's address

Back. Title `addressTitle`; Body `addressHint`; the address field (link icon) focused at once; Problem when there is
one; Primary `connect` ("Connect"), busy while connecting; the legal note.

### 3. This isn't the server you used before

The warning icon in a 64 circle of `danger` at 16%, centred; Title `identityTitle`; Body `identityHint`; a `panel` card
with the address and `fingerprintLabel`: the fingerprint in monospaced; Primary `back` (focused); Destructive
`identityTrust`.

### 4. Who's watching?

1. Lockup.
2. Display `whoTitle` ("Who's watching?"), centred.
3. The profile tiles, centred, wrapping: two columns on a phone (104 avatars), as many as fit on a tablet (140 avatars),
   24 apart across and 28 down. The first has focus on a TV.
4. Under the grid, centred, Quiet buttons on one line where they fit: `otherAccount` ("Sign in with another account"),
   `useCode` ("Sign in with a code"), and `codeTitle` ("Enter the security code") when this server proved its identity.
5. At the bottom: the server's name in Secondary with Quiet `changeServer` beside it ("Change server").

When the server shows no profiles (`style` isn't `profiles`), this screen is the sign-in form (6).

### 5. Password

Back to the profiles. The avatar at 120, centred; the profile name in Headline; `@username` in Secondary when it differs;
Body `passwordHint` ("Enter your password or PIN."); the password field ("Password", lock icon, show/hide), focused at
once; Problem; Primary `signIn` ("Sign in"); Quiet `forgotPassword` ("Forgot your password?"), which opens the server's
help on it inside the app (on Apple TV: a QR card to it).

When the server asks for a second step (two-factor), the same screen asks for `twoFactorTitle` with the six code boxes
and an authenticator note, without a number pad on a phone (the system keyboard, numeric, with one-time-code
autofill), with it on a TV.

### 6. Sign in

Back (when there are profiles). Lockup; Title `signInTitle` ("Sign in"); the username field (person icon, username
keyboard, Return to the password); the password field; Problem; Primary `signIn`; then the Quiet code links as in 4.

### 7. Enter the security code

Back. Title `codeTitle`; a `panel` pill with the server mark (24) and its name; Body `codeHint`; the code boxes; the
number pad; Quiet `usePassword` and `showCodeInstead`; the fingerprint in Caption, `textHint`.

### 8. Sign in with a code

Back. Title `pairTitle`; Body `pairHint`; the address in Label, `accentText`, selectable; the code in Display monospaced,
letters 8 apart, in a `panel` card radius 14; the QR card with `pairScan`; a spinner and `pairWaiting`; when it ends,
Problem and Primary `pairNew`. Quiet: `codeTitle`, `usePassword`, `changeServer`.

### Tablet

The same screens in the same single column, centred; the profile grid uses the room. In landscape the column stays
centred: nothing stretches to the edges.

## You and settings

*To follow, from the feature inventory: the You tab's header and groups, every per-person setting natively,
and every server-wide setting reachable.*

## Feature map

*To follow: every feature of the server, and where it is in each app (native screen, the server's page inside the app,
or on Apple TV a QR card to open it on a phone).*

## On a TV

Apple TV and Android TV are the same app to look at. Sizes are given in TV units: one TV unit is one point on Apple TV
(1920×1080) and half a dp on Android TV (960×540 dp), so a layout measured in one is the same in the other.

- **Focus** is a 4-wide ring in `text` around the focused thing, 4 outside it, and a 1.06 scale. No system highlight,
  no parallax: the same on both. Focus starts on the screen's main action and comes back where it was left.
- **Sign-in screens** put the words on the left half and the actions on the right half, vertically centred, inside the
  90 gutter; the glow sits behind the words. Who's watching is the exception: centred, with the tiles in one row.
- **Profile tiles** are 200 avatars in one centred row, 48 apart, with the names under them.
- **The code pad** is on the right, the code boxes on the left. Digits on a remote's number keys also type.
- **Fields** open the system's keyboard; on Android TV the IME, on Apple TV the system keyboard, which a phone can type into.
- **Top bar:** Home, Search and You as pills along the top, 24 from the top edge, the chosen one filled `accent` with
  its name; up from the first row reaches it.
- **What a TV can't show** (the server's pages on Apple TV) is a QR card to open that page on a phone, with its address
  under it. Android TV shows the same card, so the two stay the same.

## Checking a build against this

For each screen, in a phone, a tablet and a TV size, compare a screenshot with this page: the glow, the lockup, the
column's width, the sizes in the tables, the wording keys, and focus. `android-reference/` (not committed) holds the
Android screenshots used while building the Apple side.
