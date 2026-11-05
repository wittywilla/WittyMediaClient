# How the apps look

One design for every native app: iPhone and Android phones first, then iPad and Android tablets,
then Apple TV and Android TV, which mirror the phone's design for a room and look **identical to each
other**. Apple Vision Pro takes the tablet's. The desktop apps (Windows, macOS, Linux, FreeBSD,
Plasma Bigscreen) are the server's own web interface in a window: only their connect screen,
`shared/connect/`, is the apps', and it follows the same look.

On a phone, the reference is the server's own website at phone size: the apps look and work like it, and what this
page improves on it goes back to the website, so there is one mobile design (see One mobile design with the website).

This is the contract both codebases are built and checked against. Where Apple and Android differ, it's
only where each system has its own convention: the status bar, the back gesture, the keyboard. Wording
comes from `shared/data/strings.en.json`, so every app says the same thing. Every feature the server
offers is reachable from every app: arranged for the device, never left out. See [Feature map](#feature-map).

- [Principles](#principles)
- [Foundations](#foundations)
- [Themes](#themes)
- [One mobile design with the website](#one-mobile-design-with-the-website)
- [Brand](#brand)
- [Components](#components)
- [Signing in](#signing-in)
- [You and settings](#you-and-settings)
- [Discs and the remote](#discs-and-the-remote)
- [Feature map](#feature-map)
- [On a TV](#on-a-tv)
- [Checking a build against this](#checking-a-build-against-this)

## Principles

0. **Everything everywhere.** Every feature of the server works on every device: phones, tablets, Apple TV, Android TV,
   Vision Pro and the desktop apps. Each is built the way that's best for that device, natively where the device can't
   show the server's pages (Apple TV has no web engine, so WittyTV's looks and WittyPlay are built natively there). No
   feature is "on another device only".

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

From the theme in use, translated from the server's theme tokens (see Themes):

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
| Home | `house` | `home` |
| Libraries | `books.vertical` | `video_library` |
| Games | `gamecontroller` | `sports_esports` |
| Live TV | `tv` | `live_tv` |
| Search | `magnifyingglass` | `search` |

## Themes

Every theme the server has works in every app: the built-in ones, any the owner uploaded or made for everyone, and the
look a person made for themselves with the theme maker. The apps read them as data and translate them; nothing is
drawn from CSS.

### Where they come from

- `GET /api/v1/themes` lists them: `id`, `name`, `scheme` (`dark` or `light`), `preview` (`bg`, `surface`, `text`,
  `accent`), `webOnly`, and which is the server's `default`.
- `GET /api/v1/themes/{id}/tokens.json` is one theme: `colors` by CSS variable name (`--bg-2` is `bg-2`), `lengths`
  (`radius`), `scheme`.
- `GET /api/v1/me/ui` → `customTheme` (`name`, `scheme`, `accent`, `tint`, `corners`) is the person's own, made with the
  theme maker.
- `shared/data/themes.json` (the built-ins) ships in the apps, so the first screen has colours before any answer, and a
  server that can't be reached still looks right.

Each theme read is kept per server on the device, by id and the theme list's `modTime`, and read again only when that
changes.

### Translation

| App role | Web token | Missing? |
|---|---|---|
| `background` | `bg` | `preview.bg` |
| `panel` | `bg-2` | `background` mixed 4% towards `text` |
| `card` | `bg-3` | `preview.surface`, else `background` mixed 9% towards `text` |
| `raised` (a chosen chip, a pressed row) | `bg-4` | `card` mixed 6% towards `text` |
| `border` | `border` | `text` at 10% |
| `control` (outlines of fields and ghost buttons) | `control-line` | `text` at 20% |
| `text` | `fg` | `preview.text` |
| `textSecondary` | `fg-2` | `text` at 72% over `background` |
| `textHint` | `fg-3` | `text` at 55% over `background` |
| `accent` | `accent` | `preview.accent` |
| `accentPressed` | `accent-2` | `accent` mixed 10% towards black |
| `onAccent` | `accent-fg` | white or `#0e1013`, whichever reads better on `accent` |
| `accentText` | `accent-text` | `accent` |
| `danger`, `ok`, `warn` | `danger`, `ok`, `warn` | the default theme's |
| `scrim` | `overlay` | black at 60% |
| radius | `lengths.radius` | 10 |
| light or dark | `scheme` | from `background`'s lightness |

- **Colours** are read as `#RGB`, `#RRGGBB` or `#RRGGBBAA`; anything else counts as missing. Anything missing after
  the fallbacks comes from the default theme. A colour with alpha (the web's `border` is `fg` at 10%) is kept with it.
- **Corners follow the theme:** `radius` is the medium radius (buttons, fields, posters). Small is `radius − 4` (at
  least 2), large is `radius + 4` (cards, grouped lists, library tiles), extra is `radius + 10` (sheets). Pills stay
  round, and avatars stay 22% of their size.
- **The theme maker** is ported exactly from the server's `web/src/ui/themeMaker.ts` (`makeTheme`): the same HSL
  steps and the same contrast checks, so a person's own look is the same colour on every device. Both apps test it
  against `shared/data/theme-maker-examples.json`, worked out by running that code.
- **`webOnly` themes** still work; they're marked "Looks plainer in the app" in the list, as their extra CSS can't come.

### Choosing

You → Theme (see You and settings) lists: Automatic (light or dark with the device: `light` or `default`), the
server's choice (named), "Made by you" when the account has a `customTheme`, then every theme from `GET /themes` with
a swatch drawn from its `preview`. The choice is kept per server on the device, as the web keeps it per browser.
Choosing applies at once, with a 200 ms cross-fade; the server's pages inside the app are told the same choice.

TVs use the same layer and the same list. WittyTV's guide keeps its own looks on top: see On a TV.

## Brand

- **Mark:** the server's icon (`web/public/icon.svg` in WittyMediaServer), drawn natively: a 64×64
  rounded square (radius 14) in `#1b1e25`, a ring of radius 20 and width 5, and a play triangle with
  points (27,23), (41,32), (27,41), both in a gradient from `#9d7bff` (top left) to `#5b3df5` (bottom right).
- **The app is WittyMediaClient.** Its name on the device, and its wordmark wherever no server has been added yet,
  is "Witty**Media**Client" in Headline weight bold, with "Media" in `accentText`, after the mark. WittyMediaServer is
  the server's name, never the app's.
- **A server's identity comes only once it's added.** Until a server has been added to the app (its address entered or
  chosen, and its identity checked), the app shows nothing the server says about itself: no name, no logo. After that,
  wherever that server is meant (its sign-in screens, its card under "Used before", You's This server card), its
  identity is:
  - **Name:** `/api/status` → `brandName`, or "Witty**Media**Server" (styled as the wordmark) when it has none.
  - **Logo:** when `/api/status` → `brandLogo` isn't empty, `/api/branding/logo?v=<brandLogo>` in the mark's rounded
    square; otherwise the mark.
  - Both are kept with the saved server (the logo's picture too, cached by its version), so the server list shows
    them before the server answers, and they're refreshed each time it does.
- **Lockup:** mark then wordmark. On a phone or tablet: a 32 mark, the wordmark in Headline (20) bold, 10 apart. **On a
  TV it reads from across the room:** a 72 mark, the wordmark in 48 bold (the size of Display), 20 apart, and a
  server's own logo at the same 72. Choose your server and Enter an address show the app's lockup; the screens of one
  server show that server's. Where a TV names the server in a line (the sign-in screens' foot, You), it's Label (24)
  with a 32 logo, not Secondary.

## One mobile design with the website

The server's own website, on a phone, is the reference for the phone apps: the same shell, the same pages, the same
measurements, so moving between the website and an app is seamless. Where this page improves on the website, the
website takes the improvement too (marked **→ web**), so there is one mobile design, not two. Sizes are from the
website at 375 wide.

### The shell

- **The floating bar** sits 16 from the sides and the bottom (above the home indicator): a pill 60 high, `card` fill,
  1-wide `control` outline, the shadow `0 10 30` black 45%, 4 inside. Five buttons share its width, 50 high, icons only
  (24): **Home**, **TV guide**, **Search**, **Menu**, and **You** (the person's avatar, a 32 circle). The chosen one has
  a pill of `accent` at 14% behind it and its icon in `accentText`; the others are `textSecondary`. Spoken as their
  names ("You, Willow").
- **The library strip** runs along the top of Home and the library pages: the libraries' names, 15, `textSecondary`,
  20 apart, 44 high, scrolling sideways, the current one in `text` with a 2-high `accent` underline. Over a picture it
  has no background; once the page scrolls under it, it gains `background` at 85% with a blur, and a hairline
  (**→ web**: the website's strip stays transparent and floats over the cards).
- **Back** (**→ web**): every page below Home, a library or a tab's first page has a 40 round Back button, top left, a
  `background` at 70% circle with a chevron, over the picture where there is one. The library strip isn't shown there.
- **The activity button** (an admin's task activity) sits at the top right, 40, and never over the strip's words
  (**→ web**: it covers the last library name).
- **Menu** opens a side drawer from the left, 280 wide (at most 80%), `panel`: the lockup, then `LIBRARIES` as a
  Caption, then every library as a row 44 high with its icon in `textSecondary` and its name in Label. A scrim of
  `scrim` covers everything else, the floating bar and the activity button included (**→ web**: they show through it).
  Swiping left or tapping the scrim closes it.
- **Loading** (**→ web**): a page shows grey shapes where its content is coming (`card` at 60%, a slow 1.2 s shimmer;
  still with Reduce Motion), never an empty page with the version line in the middle.

### Home

1. **The hero** is the full width and 536 high on a phone (about two-thirds of the screen; 66% of the height at most
   on other sizes): the backdrop, darkened from the bottom by `background` at 100% / 94% at 34% / 72% at 56% / 0 at
   82%. Over it, 16 from the sides: the title in 30 semibold, letters −0.66, two lines at most; the facts (year · length ·
   genres) in 15 `textSecondary`, 8 below; the synopsis in 15 `textSecondary`, two lines, 12 below; then 20 below,
   **Play** (Primary) and **Details** (Ghost) side by side. Pager dots at the top right under the strip, with
   pause; it moves on every 8 s, and not at all with Reduce Motion.
2. **Your libraries**: Section title (20 semibold) with Quiet "Manage ›" for admins; a two-column grid, 8 apart, of
   library tiles.
3. **Rows**, each a Section title with "See all ›" (13 medium, `textSecondary`): Continue watching, Next up, Because you
   watch…, Recently added in each library. Each row scrolls sideways with snapping, 16 from the left edge.

### Playback and the media player

Playing looks and works as the website's player does on a phone, control for control; only the engine underneath is
the device's own (AVPlayer on Apple, ExoPlayer/Media3 on Android), for smooth playback, picture in picture, AirPlay and
Chromecast, and the lock screen. The website's code is the reference, in the server's `web/src/player/` and
`web/src/audio/`:

- **Video** (`player/VideoPlayer.tsx`, `player/Controls.tsx`, `player/chrome.tsx`, `player/TrackPicker.tsx`,
  `player/PlayInfoPanel.tsx`, `player/ViewSettings.tsx`, `player/PickIntroBar.tsx`): the same controls in the same
  places, the seek bar with chapter marks and preview, skip intro and credits, next episode, the audio and subtitle
  picker, speed, picture fit, the info panel, and the same timing for hiding the controls. Leaving the player for
  the rest of the app keeps it playing in the mini player dock, as `/play` does.
- **Discs** (`player/DvdPlayer.tsx`, `player/CdPlayer.tsx`, `player/InsertDisc.tsx`, `player/Remote.tsx`): menus,
  chapters, the remote, insert-disc, and the CD player.
- **Music, audiobooks, podcasts** (`audio/MiniPlayer.tsx`, `audio/NowPlaying.tsx`, `audio/controls.tsx`,
  `audio/QueuePanel.tsx`, `audio/LyricsPanel.tsx`, `audio/Karaoke.tsx`, `audio/SoundPanel.tsx`, `audio/visualizer.tsx`,
  `audio/nowplaying.css`): the mini bar above the floating bar, and Now Playing full screen with its artwork,
  backdrop, lyrics, karaoke, queue, Sound (EQ, loudness, vocals, key), sleep timer, repeat, shuffle, song radio and
  the visualizer.

Nothing is invented on top: where the app and the website differ, the website wins, unless this page marks an
improvement for both (**→ web**).

### Components

| Component | Look |
|---|---|
| **Button, Primary** | `accent` fill, `onAccent` words 14 semibold, 44 high, 16 inside, radius `radius`, an optional 18 icon 8 before |
| **Button, Ghost** | No fill, 1-wide `control` outline, `text` words; otherwise as Primary |
| **Button, Secondary** | `card` fill, `text` words |
| **Library tile** | 64 high, 10 inside, `panel` fill, 1-wide `border`, radius large; a 38 icon square (radius medium) in `accent` at 14% with the icon in `accentText`; 10 after it, the name in 15 semibold over the count in 12 `textHint`; one line each |
| **Poster card** | 104 wide on a phone (128 on a tablet), the poster 2:3, radius medium; under it 8 apart, the title in 14 semibold (two lines) and the facts in 12 `textHint`. 16 between cards |
| **Placeholder poster** (**→ web**) | No artwork: a gradient from the title's colour (the avatar rule on the title) to `card`, with the title in 15 semibold white over its lower third |
| **Category card** | Landscape 16:9, radius large, the backdrop with the hero's gradient, the name in 20 semibold and the count in 12, 12 from the lower left |
| **Section title** | 20 semibold, letters −0.24; its action on the right in 13 medium `textSecondary` with a chevron |
| **Chip** | 32 high, 12 inside, radius full, 13 medium; chosen: `raised` fill, `text`; others `textSecondary` |

### Library pages

The library strip; the library's name in Title with its count in 15 `textHint` beside it, and a Ghost **Filters**
button on the right; the sort chips in one sideways row (`SORT` as a Caption before them); then the library's
categories as category cards, studios, and rows. **An admin's tools** (All films, Fix matches, Categories, Scan) go
behind one Ghost "⋯" button that opens a sheet of rows (**→ web**: they take two rows of the screen today).

### An item

Back; the backdrop across the top, 220 high, fading into `background` (no hard line under it: **→ web**); the poster,
120 wide, overlapping it by 60 at the left; then the library's name as a Caption, the title in 30 semibold, the
tagline in italic `textSecondary`, the facts. Actions in one row: **Play** (Primary, `Resume` when started), **Save**
(Secondary), and "⋯" for everything else, admin tools included (**→ web**: five buttons in two rows and two styles
today). Then the synopsis, cast, extras and related, as rows.

### Search

The field 44 high, radius medium, `card`, with a search icon; results grouped (Films, Shows, Music, Books…), each as
poster cards three across on a phone (**→ web**: two across, which makes a poster fill half the screen).

### You

The avatar in the floating bar opens **You**. In the apps it is the You page (see You and settings). On the website,
on a phone, it opens a sheet from the bottom (**→ web**: a small menu today) with the same header (avatar 64, profile
name, `@username · Role`, Switch profile) and the same first rows (Your year, Appearance, Controllers, Settings, Help,
Sign in a TV, Sign out). Its Settings page uses the grouped list (**→ web**: tinted icon tiles, chevrons and cards,
keeping its one-line descriptions under each row, which the apps show too for the Server and Maintenance rows).

## Components

### Buttons

| Kind | Look | Use |
|---|---|---|
| Primary | `accent` fill, `onAccent` words, radius 10 (pill on Home and items) | The one main action |
| Secondary | `card` fill, `text` words | Other actions |
| Quiet | No fill, `accentText` words | Links: "Forgot your password?", "Change server" |
| Destructive | `card` fill, `danger` words | Sign out, forget, remove |

Full width in a column on the sign-in screens, 52 high, words centred, an optional leading icon 8 before the words.
**On a TV every button is a pill** (fully round), 66 high, the height of the systems' own text fields, with 32
inside, so a field and its buttons look like one family; a Quiet one is 56 high and takes the pill only as its focus
ring. Number pad keys stay rounded squares, as the systems' keyboards have them. No square-cornered button on a TV.
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

A `card` row, radius 14, 16 inside: for a saved server, its logo at 40 (see Brand) and its name in Label semibold over
its address in Secondary; for one only found, the plain server icon in a 40 `raised` square and its address over
`foundOnNetwork`; then a chevron in `textHint`. The one last used carries
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

1. The app's lockup (WittyMediaClient).
2. Display: `findTitle` ("Choose your server"). Under it in Body, `textSecondary`: `findSubtitle`.
3. Section: `foundServers` ("On your network"), with a small pulsing dot in `accent` beside it while searching.
4. Server cards for what's found, each showing **only its address** (host and port, as Label semibold) over
   `foundOnNetwork` ("Found on your network") in Secondary, with the plain server icon: a server says nothing about
   itself until it's added. While nothing is found: a Note with a spinner and `findSearching`; after six seconds
   `findNone`; where the device can't search, `findNotSupported`.
5. Section `recentServers` ("Used before") and its cards, the last used first, each with that server's own logo and
   name (see Brand) over its address. A found server that's also saved shows only under Used before.
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

Back; Title `rowSignInTv`; Body `signInTvHint` ("Type the code your TV shows."). **Eight letter boxes**, four, a dash,
then four, as the TV shows its code (`ABCD-EFGH`, letters from `BCDFGHJKLMNPQRSTVWXZ`), over the system keyboard in
capitals; any case typed counts, and the dash and spaces are ignored. On a phone the boxes are 34 wide and 48 high, 6
apart, so eight fit. The eighth letter sends `POST /pair/info` with the code as typed. (The six digits are the other
direction: the code `/pair/invite` makes, which the TV types on Enter the security code.) Then a `panel` card: the device's name in Label, platform and address in
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

## Games everywhere (WittyPlay)

Every game the server can run plays on every device. The server always runs the game and streams it
(`docs/GAMING-API.md` in the server: sessions, `ws-h264` video with `ws-jpeg` as the fallback, PCM sound, input up the same
socket); a device only shows the picture and sends the controls, so nothing about a console has to be on the device.

| Device | Player | Controls |
|---|---|---|
| Website (desktop and phone), desktop apps | The website's own player | Gamepad API, keyboard, and its touch layout on a phone |
| iPhone, iPad, Vision Pro | The one native Apple player (shared with Apple TV): VideoToolbox H.264, AVAudioEngine sound | GameController (Xbox, PlayStation, Switch, MFi): every button, analog sticks and triggers, rumble and light bar, touchpad and motion where the console uses them; up to four at once. With no controller, the account's touch layout from the server, drawn over the picture |
| Apple TV | The same native Apple player | GameController as above; the Siri Remote for menus and as a fallback pad |
| Android phone, tablet, Android TV | A native Android player: MediaCodec H.264, AudioTrack sound | Android's gamepad input (every button, sticks, triggers, rumble), several at once; the touch layout on phones and tablets; the TV remote for menus |

Around the player, every device shows the same things as the website's games: the library in couch mode, a game's page
(Play or Resume, saves, versions), the pause menu (save state, load state, controller settings, quit), and the
account's controller profiles (`/game-profiles`). A game the server can't run says why on its page (see the server's
readiness check), on every device alike; Play never appears for it. Saves are the server's, so a game started on one
device carries on from the same place on any other.

## Discs and the remote

DVDs and Blu-rays play with their own menus through the server's disc sessions (`/api/v1/dvd/{sid}/…`; the server's
`docs/DVD.md` and `docs/BLURAY.md`, "The remote"). Every DVD and Blu-ray form, and every copy of a disc's film, gets
the disc remote, named for its module. Which keys work is the server's rule, in its `web/src/player/remoteKeys.ts`
(with its tests), and the same on every device; a key that can't work stays in its place, greyed out.

| What's playing | How the app knows | Remote | Keys that work |
|---|---|---|---|
| A DVD image or folder | `kind` is `dvd-iso` or `dvd-folder` | WittyDVD | All but the colour keys |
| A Blu-ray image or folder | `kind` is `bluray-iso` or `bluray-folder` | WittyBluray | All; the colour keys while a Java menu shows (the presentation's `bdj`) |
| A disc with no menus, such as a BDAV recording | `disc.hasMenus` is false | As its disc | All but Top menu, and Menu unless the film has a pop-up menu, with the line "This disc has no menus" |
| A copy of a disc's film: a loose VOB or m2ts, a rip | `kind` is `video`, `discSource` is `dvd` or `bluray` | WittyDVD or WittyBluray | Play, pause, stop, seeking, previous and next chapter, a chapter by its number, sound and subtitles; the menu keys greyed out, with the line "This copy has no disc menus" |
| Any other video | `kind` is `video`, no `discSource` | WittyMedia | The same as a copy, without chapters by number or the line |

- **Menu** opens a Blu-ray's pop-up menu while the film plays (the title's menu is a pop-up, or a Java menu is on),
  and otherwise the disc's menu. **Top menu** is always the top menu, or a DVD's title menu.
- **A Java menu** lists no buttons, yet takes the arrows, OK, the digits, the colour keys and Menu: each goes
  as `{"type": "key", "key": …}` while `bdj` is set. A tap or click on the picture goes as
  `{"type": "pointer", "x", "y"}` on its 1920×1080 frame, and only when `bdj.pointer` is true.

**Phones** copy the website's remote at phone size (the server's `player/Remote.tsx`, `RemoteSheet`, and `.remote-sheet`
in `player.css`). A **Remote** button is in the player's controls and in the mini player. It opens a sheet along the
bottom, upright and on its side, opened each time it's wanted rather than remembered. Its first page has Top menu, Menu
and Return; the D-pad with OK; Audio, Subtitle and Angle; and previous, back 10 seconds, play, pause, forward 30
seconds, next and stop. Its second page (**1 2 3**) has the digits and the red, green, yellow and blue keys. On its
side, the first page is one row, so the picture keeps the top of the screen. From the mini player, it opens above the
dock, over the page. Until the apps have their own disc player, a disc opens the server's page, which has all of this.

**TVs** map the real remote's buttons, and offer the same remote from the player's controls for the keys a TV remote
lacks: Top menu, Menu (the pop-up menu), the colour keys, the digits and Angle. Apple TV and Android TV alike.

| Button | Apple TV (Siri Remote) | Android TV | Does |
|---|---|---|---|
| Arrows and OK | The clickpad | The D-pad | The arrows and OK in a menu or a Java menu; in the film, as the player's arrows always do |
| Back | Back | Back | Closes an open pop-up menu or the remote; in a menu, Return; otherwise as the player's Back |
| Play and pause | Play/Pause | Play/pause, play, pause | Play and pause |
| Previous and next chapter | None: the remote | Previous, next, and channel down and up | Previous and next chapter |
| Digits | None: the remote | 0 to 9 | Digits |
| Colour keys | None: the remote | Red, green, yellow, blue | The colour keys |
| Menu | None: the remote | Menu | Menu |

On a TV the remote opens from a **Remote** pill in the player's controls, as a panel along the bottom over the picture,
with the phone's two pages and its keys in the same order. Its keys are pills, with the focus ring of On a TV; focus
starts on OK in a menu and on play or pause in the film, and passes over greyed keys. Back closes it. The disc's
own menu stays visible above it, so a highlight can be followed while the D-pad moves it.

## Feature map

Where every part of the server is in the apps, and what's still to build: every feature reaches every device (see
Principles). **Native** is built into the app. **Page** is the server's own page inside the app (signed in, with a
native Back), used on phones and tablets for the owner's tools. **To build** is a native screen still to come on that
device; until it's there, that device shows a QR card for the page, which is a stopgap, not the design. Desktop apps
are the website, so everything is there. On Android TV, which has a web engine, a page may stand in as well; on Apple
TV, which has none, everything is native.

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
| Books, comics, PDF reader | Page | To build |
| Shorts, creators, channel videos | Page | To build |
| Radio | Page | To build |
| Live TV guide and watching, WittyTV's looks | Page | Native, every WittyTV look and layout |
| Recordings and series rules | Page | Native on both TVs, with reminders |
| Games (WittyPlay) | To build: the shared Apple player (Games everywhere, above), with the account's touch layout; the page until then | Native on Apple TV: a player for the server's stream (the server runs every game: see [WITTYPLAY-STREAMING.md](WITTYPLAY-STREAMING.md)), with couch mode's library and game page. The page on Android TV |
| Game PCs and rigs (Moonlight) | Native | Native |
| DVD and Blu-ray menus, the disc remote, CD player | Page: the server's player, whose remote is a sheet (Discs and the remote, above). A native disc player to build | To build: the disc player, with the real remote mapped and the remote from the player's controls (Discs and the remote, above). The page on Android TV until then |
| Collections and smart playlists | Page | To build |
| Your year, history | Page | To build |
| Names, password, two-step sign-in, devices | Native | Native |
| Sign in a TV | Native | — (a TV is what gets signed in) |
| Theme on this device | Native | Native |
| Profiles of others, parental limits, sign-in screen style | Page | To build |
| Share links, activity, game settings, controllers | Page | To build |
| Every server setting (Server and Maintenance groups) | Page | To build |
| Help, legal, about the server | Page | To build |
| Licences and this app's log | Native | Native |
| Server setup (first run) | Page, in the browser | To build |

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
  90 gutter; the glow sits behind the words. **Who's watching and the password screen are centred instead**, as one
  column: the person chosen stays in the middle of the screen. The password screen on a TV: the avatar at 200, the
  profile name in 38 semibold and `@username` in 24 `textSecondary` centred under it, `passwordHint` in 24
  `textSecondary` centred, then 32 below, the password field and Sign in, 640 wide, centred, then Forgot your
  password? centred. Two-step's code boxes and pad sit in the same column.
- **A focused field** on a TV shows only the focus ring (`text`, 4 wide, 4 out, concentric); its own outline stays
  `control`, and its label stays clear of the ring. Two outlines at once (`accent` and the ring) never show.
- **Profile tiles** are 200 avatars in one centred row, 48 apart, with the names under them. Focused, **only the
  avatar** reacts: it lifts 6 and grows 1.06, with a `background` band 4 wide and then the `text` ring 4 wide around it,
  both concentric with its corners. The name brightens from `textSecondary` to `text` and keeps its size; the badge
  moves with the avatar. The row leaves 24 above the avatars, so the lifted ring is never cut off.
- **The code pad** is on the right, the code boxes on the left. Its keys are `card`, radius 14, 96 high and **16
  apart**. A focused key has **no ring**: it fills with `text`, its digit or the delete icon turns `background`, and it
  grows 1.06, as both systems' own keyboards do; a grid of rings would crowd the keys. Pressed, it dims as any button.
  Digits on a remote's number keys also type.
- **Fields** open the system's keyboard; on Android TV the IME, on Apple TV the system keyboard, which a phone can type into.
- **Top bar:** one row of pills along the top, the same on both TVs, 24 from the top edge, in two parts. **On the left**,
  from the gutter and 16 apart: **Home, Libraries, Games, Live TV, Search**, each its icon and its name in Label.
  **Pinned to the right edge** (the gutter in from it), on the same row and centred with them: **You**, the person's
  avatar at 28 (a circle) with their name. Space keeps You apart from the rest, not a line. The chosen pill, You
  included, has `accent` at 14% behind it and its words in `accentText`; the others are `textSecondary`. Focused, a
  pill takes the ring and scale as any control. Focus moves along the whole row from left to right with You last, so
  right from Search reaches You. Up from a tab's first row lands on that tab's own pill. Back from inside a tab goes
  to the bar; Back from the bar goes to Home's pill; Back on Home's pill leaves the app. A screen opened from a tab
  has the whole screen, and Back from it returns to the tab.
  - **Libraries in the bar:** You → On this device → **Top menu** (TVs only) lists every library the profile can see,
    each with a tick when it's in the bar. Each one ticked there joins the bar after Search, as its library icon and
    name, in the server's order of libraries, and is a tab of its own: the library's page under the bar, opened as
    Home's rows open it. The choice is kept on the TV, per server and per profile. When the pills on the left don't fit,
    they scroll sideways with focus, so the focused pill is always in view; **You never moves**: it stays pinned at the
    right edge, always visible, with at least 32 of space before it.
  - **Libraries:** every library the profile can see, as a grid of tiles (the phone Menu's library list as a page):
    each tile is the library's icon in `accentText` on `accent` at 14%, then its name. Each opens the library as Home's
    rows do; a games library opens Games' view of it.
  - **Games:** WittyPlay's couch library. With one games library it opens straight in; with several, one row per
    library, as Home's rows are: the library's name, its games' covers (each opens that game's page) and a pill that
    opens the whole library.
  - **Live TV:** the WittyTV guide (below) in the account's WittyTV look, with Recordings reachable from it. Choosing
    the tab keeps focus on its pill, as every tab does; coming back from a channel puts it on that channel's cell.
  - All six always show. A server with no games or no live TV shows that tab with a plain empty state saying what's
    missing and that an owner adds it on the server's website (`gamesNone` / `gamesNoneDetail`, `liveTvNone` /
    `liveTvNoneDetail`). Never a broken or blank page.
- **Home's hero** on a TV: its words (title, facts, overview and buttons, in one column) may take up to half the
  screen, 900 wide. The title wraps to up to 3 lines at the Display size; only if it still doesn't fit does it shrink,
  to three quarters at most, and an ellipsis is the very last resort, so "Harry Potter and the Philosopher's Stone"
  shows in full. The overview keeps to 2 lines. The hero is at least 620 high and grows to fit its words, so nothing
  overlaps the first row. Titles under the posters in Home's rows take up to 2 lines.
- **Themes** are the same as on a phone, through the same translation (see Themes).
- **WittyTV** (the guide and live channels) keeps its own looks, chosen per account in `/me/ui` → `tvLook` with the
  owner's default in `/guide`: the colours of each of its themes (`modern`, `classic`, `satellite`, `teletext`,
  `listings`, `bigpicture`, `outline`, `compact`, `custom`) are worked out as `web/src/pages/tv/tvThemes.ts` does, and
  each theme's layout (`web/src/pages/tv/tvthemes.css`: row height, cell shape, the now line, the preview's place, the
  font) is built natively to match, on both TVs (Apple TV's `apple/App/Tv*.swift`, Android TV's `android/…/tv/`, one
  port of the other). The now line stands at the current time, with the time centred over it, as the page draws it.
- **Recording** is offered only where the server says it can be: a channel's `canRecord` (true only for tuner
  channels the profile may record; never for channels made from the library). Record and series record are hidden,
  not greyed, when it's false or missing, on every device and on the website alike; no app works it out for itself,
  and the server refuses otherwise.
- **What a TV can't show** (the server's pages on Apple TV) is a QR card to open that page on a phone, with its address
  under it. Android TV shows the same card, so the two stay the same.

## Checking a build against this

For each screen, in a phone, a tablet and a TV size, compare a screenshot with this page: the glow, the lockup, the
column's width, the sizes in the tables, the wording keys, and focus. `android-reference/` (not committed) holds the
Android screenshots used while building the Apple side.
