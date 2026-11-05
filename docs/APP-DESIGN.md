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
| A profile tile chosen | The avatar lifts 3 and gains two rings concentric with it, `background` 3 then `text` 3, as on the web (on a TV: lifts 6, grows 1.06, rings 4 and 4) |
| Something appearing | 200 ms fade, and 8 up |
| Focus on a TV | 1.06 scale and a concentric 4-wide ring in `text`; number pad keys fill with `text` instead (see On a TV) |

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
5. **Names with a face:** wherever an avatar shows with the person's names (profile tiles, the password screen, You's
   header, Sign in a TV), the profile name and the `@username` under it are **centred under the avatar**, on every
   device. Where the screen's words start at the left, as on a TV's sign-in screens, the avatar and its names move
   there together as one centred group; the names never align to the left edge on their own.
6. **Sizes:** 28 in the floating bar, 88 in You's header (120 on a tablet), 104 in the phone's profile grid, 120 on the password
   screen, 140 in a tablet's grid, 200 on a TV.

### Profile tile

The avatar, then 10 below it the profile name in Label semibold, then the username as `@name` in Secondary,
**whenever a profile name is set and is not exactly the username**, even when the two differ only in capitals
("Ziggy" over "@ziggy" stays, since the username is what to type): so a person sees both, or just the one there is.
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

Back to the profiles. The avatar at 120 (200 on a TV), with the profile name in Headline and `@username` in Secondary
(when it differs) centred under it, as one group: centred on a phone, at the start of the words on a TV;
Body `passwordHint` ("Enter your password or PIN."); the password field ("Password", lock icon, show/hide), focused at
once; Problem; Primary `signIn` ("Sign in"); Quiet `forgotPassword` ("Forgot your password?"), which opens the server's
help on it inside the app (on Apple TV: a QR card to it).

A wrong password (401) clears the field, keeps the focus in it, outlines it and its label in `danger`, shakes it once
(not with Reduce Motion) and says `errWrongPassword`; typing again takes the red away. On the sign-in form both fields
turn red and the words are `errWrongNameOrPassword`. A 429 shows the server's own words, which say how long to wait.

When the server asks for a second step (two-factor), the same screen asks for `twoFactorTitle` with the six code boxes
and an authenticator note, without a number pad on a phone (the system keyboard, numeric, with one-time-code
autofill), with it on a TV. A wrong code shakes the boxes and says `errWrongCode`. Under them, Quiet `useRecoveryCode`
swaps the boxes for one field, `recoveryLabel` (key icon), with `recoveryTitle` and `recoveryHint` above and Primary
`signIn`; Quiet `useAuthenticatorCode` swaps back. A wrong one says `errWrongRecovery`.

### 6. Sign in

Back (when there are profiles). Lockup; Title `signInTitle` ("Sign in"); the username field (person icon, username
keyboard, Return to the password); the password field; Problem; Primary `signIn`; then the Quiet code links as in 4.

### 7. Enter the security code

Back. Title `codeTitle`; a `panel` pill with the server mark (24) and its name; Body `codeHint`; the code boxes; the
number pad; Quiet `usePassword` and `showCodeInstead`; the fingerprint in Caption, `textHint`.

### 8. Sign in with a code

Back. Lockup; Title `pairTitle`; Body `pairHint`; the address in Label, `accentText`, selectable; the code in Display monospaced,
letters 8 apart, in a `panel` card radius 14; the QR card with `pairScan`; a spinner and `pairWaiting`; when it ends,
Problem and Primary `pairNew`. Quiet: `codeTitle`, `usePassword`, `changeServer`.

### Tablet

The same screens in the same single column, centred; the profile grid uses the room. In landscape the column stays
centred: nothing stretches to the edges.

## You and settings

The third tab, **You** (`youTab`), holds the person, their account, this device's choices and, for an administrator,
the server. Its icon in the floating bar (and the TV's top bar) is the person's avatar at 28, a circle, ringed in
`accent` 2 wide when the tab is chosen. One rule decides where each thing lives:

- **What belongs to the person** is native: their names, password, two-step sign-in, devices, signing in a TV, and
  this device's theme.
- **What the server's owner manages** (libraries, profiles of others, transcoding, backups…) opens the server's own
  page for it inside the app, signed in, titled with the row's name and with a native Back. On Apple TV, which has no
  browser, the row opens the QR card for that page instead, and Android TV shows the same card.
- Every row the server would refuse is hidden, not greyed: no Server group for a non-administrator, no password row
  for a Kids or Guest profile, no game rows without a games library.

### The page

A single column, gutter 16, at most 640 wide and centred on a tablet; it scrolls under the floating bar.

1. **Header**, centred: the avatar at 88 (120 on a tablet); 12 below it the profile name in Title; under that
   `@username · Role` in Secondary, `textSecondary`, where Role is `roleAdmin`, `roleAdult`, `roleKids` or `roleGuest`
   (the @username is always shown here: this is the account). Then 16 below, Secondary button `switchProfile`
   ("Switch profile", icon `person.2` / `group`), which ends this sign-in and opens Who's watching.
2. The **groups**, each a grouped list (see Components) with its caption, 24 apart:

| Group | Row | Icon tile | Value | Opens | Shown to |
|---|---|---|---|---|---|
| `groupAccount` | `rowNames` Name and username | `person.text.rectangle` / `badge`, `#0a6fb8` | the profile name | Names (native) | everyone |
| | `rowPassword` Password | `key` / `key`, `#3e5bd0` | | Password (native) | adults, admins |
| | `rowTwoStep` Two-step sign-in | `lock.shield` / `shield_lock`, `#2e7d3c` | `on` / `off` | Two-step (native) | adults, admins, when the server offers it |
| | `rowDevices` Your devices | `ipad.and.iphone` / `devices`, `#7f46b8` | how many | Devices (native) | everyone |
| `groupHousehold` | `rowSignInTv` Sign in a TV | `tv` / `tv`, `#bd2f85` | | Sign in a TV (native) | adults, admins; not on a TV |
| | `rowProfiles` Profiles and parental limits | `figure.2.and.child.holdinghands` / `family_restroom`, `#b8500d` | | `/settings/users` | adults, admins |
| `groupYours` | `rowYourYear` Your year | `sparkles` / `auto_awesome`, `#c9302f` | | `/review` | everyone |
| | `rowCollections` Collections and playlists | `square.stack` / `library_books`, `#0e7c6f` | | `/collections` | everyone |
| | `rowShareLinks` Share links | `link` / `link`, `#0a6fb8` | | `/settings/sharing` | everyone |
| | `rowActivity` Activity | `waveform.path.ecg` / `monitoring`, `#99690a` | | `/settings/activity` | everyone |
| | `rowGameSettings` Game settings | `gamecontroller` / `sports_esports`, `#7f46b8` | | `/settings/games` | with a games library |
| | `rowControllers` Controllers | `dpad` / `gamepad`, `#3e5bd0` | | `/controllers` | with a games library |
| `groupDevice` | `rowTheme` Theme | `paintpalette` / `palette`, `#0e7c6f` | the theme's name | Theme (native) | everyone |
| `groupServer` | `rowLibraries` Libraries | `books.vertical` / `video_library`, `#5d6474` | | `/settings/libraries` | admins |
| | `rowMetadata` Metadata and artwork | `photo.on.rectangle` / `image_search` | | `/settings/metadata` | admins |
| | `rowFixMatches` Fix matches | `wand.and.stars` / `auto_fix_high` | | `/fix-matches` | admins |
| | `rowPlayback` Playback and discs | `play.rectangle` / `smart_display` | | `/settings/playback` | admins |
| | `rowLiveTv` Live TV and tuners | `antenna.radiowaves.left.and.right` / `live_tv` | | `/settings/channels` | admins |
| | `rowGaming` Consoles and cores | `gamecontroller` / `sports_esports` | | `/settings/gaming` | admins |
| | `rowGamePcs` Game PCs | `desktopcomputer` / `computer` | | `/settings/couch` | admins |
| | `rowTranscoding` Live transcoding | `bolt` / `bolt` | | `/settings/transcoding` | admins |
| | `rowLibraryTranscoding` Library transcoding | `arrow.triangle.2.circlepath` / `autorenew` | | `/settings/library-transcoding` | admins |
| | `rowRemote` Remote access | `globe` / `public` | | `/settings/remote` | admins |
| | `rowAppearance` Appearance and branding | `paintbrush` / `brush` | | `/settings/appearance` | admins |
| | `rowWittyRigs` WittyRigs | `server.rack` / `dns` | | `/settings/wittyrigs` | admins |
| `groupMaintenance` | `rowLogs` WittyLog | `doc.text.magnifyingglass` / `article` | | `/settings/logs` | admins |
| | `rowDiagnoser` WittyDiagnoser | `stethoscope` / `stethoscope` | | `/settings/diagnoser` | admins |
| | `rowModules` Modules | `puzzlepiece.extension` / `extension` | | `/settings/modules` | admins |
| | `rowBackup` Backup | `externaldrive` / `backup` | | `/settings/backup` | admins |
| | `rowRepair` Repair | `wrench.and.screwdriver` / `build` | | `/settings/repair` | admins |
| | `rowReset` Reset | `arrow.counterclockwise` / `restart_alt`, `danger` | | `/settings/reset` | admins |
| `groupHelp` | `rowHelp` Help | `questionmark.circle` / `help`, `#99690a` | | `/help` | everyone |
| | `rowAboutServer` About this server | `info.circle` / `info`, `#5d6474` | the server's version | `/settings/about` | everyone |
| | `rowLegal` Legal | `doc.plaintext` / `gavel`, `#5d6474` | | `/legal` | everyone |
| | `rowLicences` Licences | `text.book.closed` / `menu_book`, `#5d6474` | | Licences (native) | everyone |
| | `rowAppLog` This app's log | `list.bullet.rectangle` / `receipt_long`, `#5d6474` | | Log (native) | everyone |

   Server and Maintenance rows all take `#5d6474` unless the table says otherwise: a quiet group for the owner's tools.

3. **This server**: a server card (not pressable) with its name, address and, under it in Caption `textHint`, the
   fingerprint; then Secondary `changeServer` and Destructive `signOut` ("Sign out", icon sign-out), full width, 12 apart.
4. A Caption line, centred, `textHint`: the app's name and version.

### Names

Back; Title `rowNames`. The profile-name field (`profileNameLabel`, at most 60) with `profileNameHint` under it; the
username field (`usernameLabel`, at most 40) with `usernameHint`; for Kids and Guest the username is shown, not editable,
with `usernameKidsHint`. A toggle row in a grouped list: `showUsernameLabel` with `showUsernameHint`. Primary `save`,
busy while saving, then `saved` as an ok-coloured line for 2 seconds. The avatar at 64 above the fields follows the
profile name as it's typed, so its colour can be seen changing. `PUT /api/v1/users/{me}/profile`.

### Password

Back; Title `rowPassword`; Body `passwordChangeHint` ("At least 8 characters. Your other devices will be signed out.").
Fields: `currentPasswordLabel`, `newPasswordLabel`, `repeatPasswordLabel`, all password fields with the eye. Checked
before sending: `errPasswordShort`, `errPasswordsDiffer`. A 403 is `errCurrentPassword` on the first field, in red as on
sign-in. Primary `changePassword`; when it's done, a check, `passwordChanged`, and Back. `PUT /api/v1/users/{me}/password`.

### Two-step sign-in

Back; Title `rowTwoStep`. From `GET /api/v1/me/2fa`:

- **Off:** Body `twoStepIntro`; Primary `twoStepTurnOn`. Then, one step at a time in the same screen:
  1. `twoStepConfirmTitle`: the password field; Primary `continue` → `POST /me/2fa/setup`.
  2. `twoStepScanTitle`: the QR card of the `uri`, 200 (on a phone also Secondary `twoStepOpenApp`, which opens the
     `otpauth:` address so an authenticator on this phone takes it); under it `twoStepKeyLabel` and the secret in
     monospaced Label, in groups of four, with a copy button. Then the six code boxes and the numeric keyboard (number
     pad on a TV); six digits send `POST /me/2fa/confirm`. Wrong: shake and `errWrongCode`.
  3. `twoStepSavedTitle`: Body `twoStepSavedHint`; the recovery codes in a `panel` card, monospaced, two columns;
     Secondary `copyAll`; Primary `twoStepDone`, which is the only way on, so they aren't skipped by accident.
- **On:** a `panel` card with a check in `ok`, `twoStepOnTitle` and `twoStepCodesLeft` (how many recovery codes are
  left; under 3, in `danger`). Destructive `twoStepTurnOff` asks for the password and a code in a sheet, then
  `POST /me/2fa/disable`.

### Your devices

Back; Title `rowDevices`; Body `devicesHint`. A grouped list from `GET /api/v1/sessions`, this device first: an icon
tile by kind (`iphone` / `smartphone` for phones, `ipad` / `tablet`, `tv` / `tv`, `desktopcomputer` / `computer`,
`globe` / `language` for a browser), the device's name in Label, and in Secondary where it is (`whereMachine`,
`whereHome`, `whereVpn`, `whereInternet`) and when it was last seen ("Active now" within 5 minutes, then relative).
This device has a `thisDevice` pill in `border`; any other has a trailing Quiet `signOut` (on a TV: OK on the row,
then a confirmation). Under the list, Destructive `signOutOthers`, with a confirmation, when there are others.
`DELETE /api/v1/sessions/{id}`, `DELETE /api/v1/sessions`.

### Sign in a TV

Back; Title `rowSignInTv`; Body `signInTvHint` ("Type the code your TV shows."). The six code boxes and the numeric
keyboard; six digits send `POST /pair/info`. Then a `panel` card: the device's name in Label, platform and address in
Secondary, and `signInTvAs` with the profiles it may sign in as (the person, and Kids and Guest profiles they look
after) as profile tiles at 72, the person first and chosen. Primary `signInTvApprove`, Quiet `signInTvDeny`. Done:
a check in `ok` and `signInTvDone`. Quiet `signInTvInvite` ("The TV asks for a code?") makes one instead
(`POST /pair/invite`) and shows it in Display monospaced in a `panel` card with how long it lasts.

### Theme

Back; Title `rowTheme`; Body `themeHint` ("Only on this device. The server's own pages follow it too."). A grouped
list: `themeAutomatic` (light or dark with the device), `themeServer` (the server's choice, named), then each theme in
`shared/data/themes.json` with a 28 swatch (its background, a card stripe and an accent dot) and a check on the
chosen one. Choosing applies at once, with a 200 ms cross-fade. Kept per server on the device.

### On a tablet and a TV

A tablet uses the same page at 640 wide. A TV puts the header on the left third (avatar 200, names, `switchProfile`,
`signOut`), vertically centred, and the groups in a focusable list on the right two-thirds; a row's screen replaces
the list. The TV's rows are 72 high with 32 icon tiles, Label at TV size, and the focus ring around the whole row.

## Feature map

Where every part of the server is in the apps. **Native** is built into the app; **Page** is the server's own page
inside the app (signed in, with a native Back); **QR** is the card to open that page on a phone, on a TV that can't
show it. Desktop apps are the web interface, so everything is there.

| Feature | Phone and tablet | TV |
|---|---|---|
| Choosing a server, address, security code, pairing | Native | Native |
| Who's watching, password, two-step, recovery code, sign-in form | Native | Native |
| Home: hero, libraries, Jump back in, Next up, Recently added | Native | Native |
| Search | Native | Native |
| Movies, shows, seasons, episodes, item pages | Native | Native |
| Video playback, resume, next episode | Native | Native |
| Music, audiobooks, podcasts: browse and player | Native | Native |
| Photos | Page | Native viewer |
| Books, comics, PDF reader | Page | QR |
| Shorts, creators, channel videos | Page | QR |
| Radio | Page | QR |
| Live TV guide and watching | Page | Native |
| Recordings and series rules | Page | QR |
| Games (WittyPlay) | Page (iPhone and iPad) | QR |
| Game PCs and rigs (Moonlight) | Native | Native |
| DVD and Blu-ray menus, CD player | Page | QR |
| Collections and smart playlists | Page | QR |
| Your year, history | Page | QR |
| Names, password, two-step sign-in, devices | Native | Native |
| Sign in a TV | Native | — (a TV is what gets signed in) |
| Theme on this device | Native | Native |
| Profiles of others, parental limits, sign-in screen style | Page | QR |
| Share links, activity, game settings, controllers | Page | QR |
| Every server setting (Server and Maintenance groups) | Page | QR |
| Help, legal, about the server | Page | QR |
| Licences and this app's log | Native | Native |
| Server setup (first run) | Page, in the browser | QR |

Anything added to the server's menus later goes in the table above before it ships: as a Page row at least.

## On a TV

Apple TV and Android TV are the same app to look at. Sizes are given in TV units: one TV unit is one point on Apple TV
(1920×1080) and half a dp on Android TV (960×540 dp), so a layout measured in one is the same in the other.

- **Focus** is a 4-wide ring in `text`, 4 outside the focused thing, and a 1.06 scale. The ring is **concentric**: each
  of its corners is the thing's own radius plus its distance out (so a radius 14 key has a ring whose outer edge is
  radius 22), never the thing's radius drawn larger. The ring scales with the thing. Focusable things sit at least 16
  apart, so a focused one's ring never touches or covers a neighbour, and nothing that can take focus sits in a row or
  list that clips it: rows leave 24 above and below for the ring. No system highlight, no parallax: the same on both.
  Focus starts on the screen's main action and comes back where it was left.
- **Sign-in screens** put the words on the left half and the actions on the right half, vertically centred, inside the
  90 gutter; the glow sits behind the words. Who's watching is the exception: centred, with the tiles in one row.
- **Profile tiles** are 200 avatars in one centred row, 48 apart, with the names under them. Focused, **only the
  avatar** reacts: it lifts 6 and grows 1.06, with a `background` band 4 wide and then the `text` ring 4 wide around it,
  both concentric with its corners. The name brightens from `textSecondary` to `text` and keeps its size; the badge
  moves with the avatar. The row leaves 24 above the avatars, so the lifted ring is never cut off.
- **The code pad** is on the right, the code boxes on the left. Its keys are `card`, radius 14, 96 high and **16
  apart**. A focused key has **no ring**: it fills with `text`, its digit or the delete icon turns `background`, and it
  grows 1.06, as both systems' own keyboards do; a grid of rings would crowd the keys. Pressed, it dims as any button.
  Digits on a remote's number keys also type.
- **Fields** open the system's keyboard; on Android TV the IME, on Apple TV the system keyboard, which a phone can type into.
- **Top bar:** Home, Search and You as pills along the top, 24 from the top edge, the chosen one filled `accent` with
  its name; up from the first row reaches it.
- **What a TV can't show** (the server's pages on Apple TV) is a QR card to open that page on a phone, with its address
  under it. Android TV shows the same card, so the two stay the same.

## Checking a build against this

For each screen, in a phone, a tablet and a TV size, compare a screenshot with this page: the glow, the lockup, the
column's width, the sizes in the tables, the wording keys, and focus. `android-reference/` (not committed) holds the
Android screenshots used while building the Apple side.
