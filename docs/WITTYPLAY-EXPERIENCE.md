# WittyPlay: the games experience

**Prototype:** [WittyPlay prototype](https://claude.ai/artifact/ArXyR6wEt5xHdHkapHYE2p), the key phone screens and the TV home,
clickable, in every server theme, with these notes beside each screen. It's private to its owner until shared from its
Share menu.

WittyPlay is the games part of WittyMediaServer: the server runs every game and streams it, and a device shows the
picture and sends the controls back ([How the apps look](APP-DESIGN.md#games-everywhere-wittyplay)). This page is what
the games look like and how they work around that stream, on every device. It's the contract the Apple player (iPhone,
iPad, Apple TV, Vision Pro), the Android player (phones, tablets, Android TV) and the website's games pages are built
and checked against. Sizes, colour roles, type, motion and the shell (strip, floating bar, Back) are
[APP-DESIGN's](APP-DESIGN.md); this page only adds what games need.

The idea: **a classics service made of your own games.** Consoles are collections you browse like shelves; a game
opens where you left it on any device; you can save as many moments as you like, each with its picture, rewind a
mistake, choose how the picture looks, and play together on one screen or from several. All of it in
WittyMediaServer's own words and look.

- [Legally distinct](#legally-distinct)
- [Words](#words)
- [Where everything is](#where-everything-is)
- [On a phone](#on-a-phone)
- [Themes](#themes)
- [On a tablet and Vision Pro](#on-a-tablet-and-vision-pro)
- [On a TV](#on-a-tv)
- [On the website](#on-the-website)
- [Features, and what the server has](#features-and-what-the-server-has)
- [Server work](#server-work)
- [States](#states)
- [Motion and access](#motion-and-access)
- [Decisions to confirm](#decisions-to-confirm)
- [Checking a build against this](#checking-a-build-against-this)

## Legally distinct

This is a hard rule, checked on every screen before it ships. WittyPlay takes the *kind* of experience a classics
service offers (a curated library, consoles as collections, instant resume, rewind, save points, display filters,
playing together) and copies nothing of any console maker's.

- **No names.** No product, service or feature name of a console maker appears in the apps, the website, the strings,
  asset names or anything a person sees. WittyPlay's own words are under [Words](#words).
- **No layouts, menus, sounds, icons, colours or trade dress.** Every screen here is built from APP-DESIGN's components.
  The game menu is the picture shrinking into a card over a sheet of tiles and rows (on a TV and sideways, a split),
  not modelled on any console's menu. Icons are SF Symbols and Material Symbols as APP-DESIGN maps them, or our own
  drawings. Colours are the theme's, and a collection's colour comes from its own covers.
- **No console logos or brand artwork.** Consoles are named in text ("NES", "Game Boy"), which only says what a game
  is for. WittyPlay's screens never show a console logo, even where the server's owner has downloaded logos for its
  own pages. Controllers are the server's own generic drawings (`pad.art`: `one`, `two`, `four`, `six`, `handle`,
  `dual`), never a product's outline.
- **No makers' button symbols.** Prompts show a button by its **position**: a diamond of four dots with the one to
  press filled. The console's own letter goes beside it only when it's a letter or a number (A, B, X, Y, 1, 2), as
  the server's controls data names it. Shapes are never drawn. (See [Decisions](#decisions-to-confirm).)
- **No interface sounds.** WittyPlay is silent outside the game; phones give a light haptic on the game menu's tiles
  and when a moment is saved.
- **Pictures in anything published** (this repository, screenshots, store listings, the prototype) are the openly
  licensed demo games credited in the server's `docs/images/CREDITS.md`, never retail games.

## Words

Plain words, from `shared/data/strings.en.json` once added. Keys are proposed with a `wp` prefix; the English is final
once confirmed.

| What | WittyPlay says | Key | Server's own name |
|---|---|---|---|
| The games part | WittyPlay | — | WittyPlay module |
| A console's games | **Collection**, named by the console ("NES") | `wpCollection` | console filter |
| A group of consoles by time or kind | **Era**: 8-bit, 16-bit, Early 3D, Disc era, Pocket | `wpEras` | — |
| A curated row | Shelf, by its title | — | `shelves` |
| Games for two or more | **Made for two** | `wpMadeForTwo` | `players` facet |
| The automatic save (slot 0) | **Where you left off** | `wpWhereYouLeftOff` | auto state |
| A save state with its picture (slots 1–99) | **Moment**; Save a moment, Save here, Play from here | `wpMoment`, `wpSaveMoment`, `wpSaveHere`, `wpPlayFromHere` | save state, slot |
| Slot 100, slot 101 | **Before you loaded**, **Before starting over** | `wpBeforeYouLoaded`, `wpBeforeStartingOver` | undo, autoprev |
| Going back in time | **Rewind** (held); "Let go to play from here" | `wpRewind`, `wpRewindHint` | `rewind` |
| How the picture is drawn | **Look**: Clean, Scanlines, CRT TV, Arcade, Handheld LCD, Smooth | `wpLook` | `display.*` presets |
| A player's place, 1 to 4 | **Seat**; Free; Join a game; Watching | `wpSeats`, `wpSeatFree`, `wpJoinGame`, `wpWatching` | port |
| The pause menu | **Game menu** | `wpGameMenu` | game menu |
| The touch row of shortcuts | Touch bar | `wpTouchBar` | `hotkeys.touchBar` |
| Moving a running game here | **Continue here**; "Playing on {device}", "Moved from {device}" | `wpContinueHere`, `wpPlayingOn`, `wpMovedFrom` | — |
| Leaving | **Save and quit** | `wpSaveAndQuit` | stop |

Other strings, by screen: `wpContinuePlaying` "Continue playing", `wpConsoles` "Consoles", `wpYoursOn` "Yours on
{console}", `wpLookFor` "Look for {console} games", `wpControlsFor` "Controls for {console} games", `wpHowYouPlay` "How
you play it", `wpMoreLikeThis` "More like this", `wpYourNotes` "Your notes", `wpStartOver` "Start over",
`wpStartDefault` "Start with default settings", `wpGettingReady` "Getting it ready", `wpStartingOnServer` "Starting on
your server", `wpConnectingTo` "Connecting to this {device}", `wpResetGame` "Reset the game", `wpArrangeTouch` "Arrange
touch controls", `wpPressStart` "Press Start", `wpPressSelect` "Press Select", `wpMomentSaved` "Moment saved",
`wpCantPlayYet` "Can't play yet", and the states' words under [States](#states).

## Where everything is

```
Games library (WittyPlay home)  /library/{id}
├── Collection (a console)      /library/{id}?console=nes
├── Era                         /library/{id}?era=8-bit           (server work: era)
├── Shelf, See all              /library/{id}?genre=… | ?series=… | ?players=2
├── Search and filters          /search?kind=game, and the library's own search
└── A game                      /item/{id}
    ├── Moments                 /item/{id}#moments
    ├── Look · Seats · Controls (also in the game menu)
    └── Playing                 /game/{id}?resume=1 | ?slot=n | ?safe=1
        ├── Starting
        ├── Rewind (held)
        └── Game menu
            ├── Moments, Look, Seats
            ├── Controllers     /controllers?console=…
            ├── Arrange touch controls
            └── Game settings   the server's settings screen
Join a game                     /play/join?code=…                  (server work: seats)
The dock                        above the floating bar, on every page, while a game plays on another device
```

- **Getting in:** the Games library in the strip and the Menu, as every library, and the dock while a game plays on
  another device.
- **Getting out of a game:** Save and quit, Back (Android, and the remote's Back opens the game menu first), or leaving
  the app: the game is stopped and saved after 60 seconds with nobody connected.
- **Deep links:** `wittymediaclient://game/{id}` and `…/join/{code}` open the same screens in the apps; the website's
  addresses above do the same in a browser. A QR code for joining carries the website's address, which the apps
  claim as a universal link / app link.

## On a phone

Sizes are for a phone 375 wide, in points (dp on Android), as APP-DESIGN. Gutter 16. Every screen below the library
has APP-DESIGN's 40 round Back.

### Home

The Games library page, inside the shell: the library strip with Games underlined, the floating bar, and the dock when
a game plays elsewhere.

1. **Title row:** "Games" in Title (24 semibold), the count in 15 `textHint`, and a Ghost "Filters" (32 high) at the
   right, as APP-DESIGN's library pages.
2. **Cover flow** (the website already has it, `CoverFlow.tsx`): the hero shelf's games, the most interesting in the
   middle. Covers 176×220 (the picture fills it, `object-fit: cover`, pixel-crisp under 512 pixels wide), radius
   medium, a shadow of black 45%, 30 blur, 12 down. Side covers turn 48° away, scale 0.86, sit back 120, and fade 12%
   for each step out; four on each side at most. A swipe or a tap on a side cover turns to it in 240 ms. Under it,
   centred: the title in 24 semibold, the facts (console · maker · seats when two or more) in 13 `textSecondary`, then
   **Resume** or **Play** (Primary pill) and **About this game** (Ghost pill), 10 apart.
3. **The page's colour** comes from the cover in front: a 16-pixel copy, its colourful parts counting more, made deep
   on a dark theme and pale on a light one (the website's `useCoverTint`). It fills the top 640 and fades into
   `background` by the bottom, cross-fading over 400 ms when the cover changes. Nothing is blurred.
4. **Continue playing:** moment cards 200×150, radius medium, the picture of where you left off (the save's `thumb`),
   a 32 accent play circle 8 from its lower left; under it the title in 14 semibold and "console · time played · when"
   in 12 `textHint`. Pressing one resumes it at once. "Moments ›" on the right opens every moment across games.
5. **Consoles:** collection cards 236×132, radius large, filled with that console's colour (the tint of its first
   covers, deep, whatever the theme), under a grain of dots at 16% white whose size is the era's pixel (12 for 8-bit,
   10 for 16-bit, 7 for Pocket, 5 for Early 3D, 4 for Disc era). Up to three covers fan out from the right (64×84,
   radius 8, −9°, −1°, 8°). The console's short name in 26 extra-bold white, letters −0.5, two lines at most, 34 from
   the bottom; the count in 12 at 85% white; the era as a Caption pill top left. Ordered by how many games.
6. **Eras:** tiles 148×92, radius large, `panel` with a `border` outline, the era's name in 17 bold and its years or
   kind in 12 `textHint`. Behind the words, the era's grain in `accent` at 32%, fading out towards the lower left: dots
   12 apart for 8-bit, 7 for 16-bit, an LCD grid for Pocket, a triangle mesh for Early 3D, rings for Disc era. Only eras
   with games show.
7. **Shelves**, each a Section title with "See all ›": Made for two, Favourites, then the server's genre and series
   shelves, Most played, Recently added. Game cards are 112 wide, the box 3:4 (150 high), radius medium; title 14
   semibold, two lines; "console · genre" in 12 `textHint`. A game for two or more carries a seats badge top left (a
   pill in `background` at 82%, the seat dots and "2P"); one that can't play yet carries "Can't play yet" in `warn`
   instead.
8. 110 of room under the last row for the floating bar (180 with the dock).

### The dock: Continue here

While this account's game runs on another device, a bar sits 10 above the floating bar on every page (as the mini
player does for music): 60 high, radius large, `panel`, `border` outline, the shadow `0 8 24` black 35%. The game's
picture 44 (radius 8), the title in 14 semibold, then a 8 `ok` dot with a 3 halo, the device's name and its seat dots
in 12 `textSecondary`; Secondary pill **Continue here** (32 high) at the right. Pressing it starts the game here from
the same moment (see [Continue here](#features-and-what-the-server-has)); the other device shows "This game moved to
{device}". Tapping elsewhere on the bar opens the game's page. It hides while a game plays on this device.

### A collection

A console's games, reached from its card.

- **Band** 260 high: the console's colour, its grain masked from top to bottom, fading into `background` over the last
  120. On it, 16 from the left and 28 from the bottom: "{era} · Collection" as a Caption at 80% white, the short name
  in 48 extra-bold white (letters −1.2), and "{full name} · {count} games" in 15 at 85% white. On a light theme, the
  band is the pale tint and its words are `text`.
- **Sort chips** in one row: Most popular, A to Z, Newest first, Made for two.
- **Yours on {console}:** a grouped list: Look for {console} games (its value, the Look in use at the console level),
  Controls for {console} games ("Your layout" or "Default"), Settings for {console} games (the server's console
  level). These are the per-console settings, where people expect them.
- Continue playing for this console, when there is any, then **All {n} games** as a grid three across, 12 apart.

### An era

The same page as a collection, for every console in the era: the band carries the era's grain in `accent` over
`panel`, the era's name in 48 extra-bold `text`, its years under it; then a row of its collections, then its games.

### A game

APP-DESIGN's item page, for a game:

1. Back; the **backdrop** 220 high: the game's first screenshot from its metadata, else its box, pixel-crisp, fading
   into `background` from 30% down.
2. **The box** 120×160, radius medium, overlapping the backdrop by 60 at the left, the shadow `0 10 24` black 40%.
   Beside it, at its foot: "{console} · {era}" as a Caption, and for two or more players the seat dots and "Made for
   two" in 13 `textSecondary`.
3. The title in 30 semibold, letters −0.66, 14 under the box; the facts (maker · genre · 1–{n} players) in 15
   `textSecondary`.
4. **Actions, one row:** **Resume** (Primary pill, filling the row) when slot 0 exists, else **Play**; Favourite (a 44
   Secondary square pill, `star`, filled `accentText` when on); "⋯" (44 Secondary square pill) for Start over, Start
   with default settings, Settings for this game, Controllers, Files and advanced (battery save in and out, patches,
   cheats file), and the administrator's tools (versions, console, core, edit details, artwork, not a game).
5. **Where you left off:** a `panel` card, radius large, 10 inside: the slot 0 picture 96×72 (radius 8), then "Where
   you left off" in 15 semibold over "{when} · {device}" and "{time played} played" in 13 `textSecondary`. Pressing it
   resumes, as Resume does. Shown only when slot 0 exists.
6. **Moments:** "See all {n} ›"; moment cards 200×150 with the moment's name (or "Moment {slot}") and "{when} ·
   {device}". Pressing one opens its sheet (see Moments).
7. **About this game:** the overview in 15 `textSecondary`, Read more past four lines.
8. **How you play it:** a grouped list. Ready on your server (a check in `ok`, the core's name and "streams to this
   {device}") or the reason it can't play; **Look** (its value); **Seats** ("{n} players"); **Controls** ("Touch, or
   any controller", or the controller connected); **Rewind** ("20 seconds", or Off). Each opens its screen.
9. **Pictures** (the metadata's screenshots, as the website's `GameShots`), **More like this** (same series, then
   genre, then console), **Your notes** (a `panel` field, saved on leaving it, `PUT /games/{id}/meta`).

A game that can't play replaces 4 and 5 with its [state card](#states); Play never appears for it.

### Moments

From "See all" on a game, the game menu, or Continue playing's "Moments ›" (every game's, newest first, grouped by
game).

- Title "Moments" under the game's name as a Caption; "{n} of 99 · {size} of 4 GB · on every device" in 13
  `textSecondary`.
- A grid two across, 12 apart, pictures 4:3 (the console's own shape inside it, `object-fit: cover`), radius medium.
  **Where you left off** comes first with an "Automatic" badge, then moments newest first, then **Before you loaded**
  and **Before starting over** with an "Undo" badge when they exist. Under each: name in 14 semibold, "{when}" and
  "{device}" in 12 `textHint`.
- **A moment's sheet:** the picture at the sheet's width (radius large), its name in Headline, "{when} · {device} ·
  slot {n}" in 13 `textSecondary`; Primary pill **Play from here** (starts the game with `?slot=n`, or loads it at
  once when this game is running), then rows Rename, Download, and Delete in `danger`, which asks first.
- Automatic, Before you loaded and Before starting over can be played from, not renamed or deleted.
- **Saving a moment** takes the lowest free slot from 1 to 99, so nothing is overwritten by accident. With all 99
  used, it asks to replace the oldest. Quick save on a controller or keyboard does the same; Quick load plays from the
  newest moment.

### Starting

A full screen in `background` with the cover's colour as a glow from the top (120% × 70% at the top centre, the tint
60% into `background`, fading out by 70%).

- The box at 168×126 (the game picture's shape), radius large, the shadow `0 18 40` black 45%; the title in 20
  semibold; "Picking up where you left off", "Starting from {moment}", "Starting over" or "Moving from {device}" in 14
  `textSecondary`.
- **Steps** in 14, 10 apart, each with an 18 circle: done ones `textSecondary` with a check on `ok`; the current one
  `text` semibold with an `accent` ring turning (still with Reduce Motion); later ones `textHint`. **Getting it ready**
  shows only for a game in an archive, with "{done} of {total}" and a 6-high `accent` bar (`POST /games/{id}/prepare`,
  once a second). Then **Starting on your server** (`POST /games/{id}/play`), **Connecting to this {device}** (until the
  first frame).
- Quiet **Cancel** under them stops it and goes back.
- A mode that shows no picture in 12 seconds is dropped for the next in `modes`, without asking.

### Playing, upright

- **The picture** fills the width at the top, under the status bar, at the session's `aspect` (never the video's own
  shape), on black. It follows `geometry`, `rotation` and `frame` events. The Look draws on it (see Look).
- **The bar** 10 under the picture, 16 from the sides: the game menu button (40 round, `card`, `pause` icon) on the
  left; the **touch bar** in the middle when it's on (`hotkeys.touchBar`): Rewind (held), Fast-forward (held, or a
  toggle with `emulation.ffMode`), and Save a moment, as 36-high pills of `card` at 85%, held ones filled `accent`; on
  the right, the avatars of the seats in use at 22, circles.
- **Touch controls** below, on the account's controller background (`/game-background`, at its `dim`) or the cover's
  glow: positions, sizes and opacity from the touch layout for this console, this device, upright
  (`/consoles/{c}/controls`, `defaults.touch.portrait`). Our drawing: the D-pad a plus of two `card` bars (radius 12,
  1-wide `control` outline) with `text` arrows at 60%; face buttons `card` circles with a 1-wide `control` outline and
  the console's letter in 22 semibold; Select and Start as 72×30 pills in 12 semibold `textSecondary`. Pressed, a
  button fills `accent` with `onAccent` words and gives a light haptic (Android and iPhone alike). Sliding between
  buttons works.
- A controller connecting hides the touch controls and the touch bar (a toast says "Controller 1 is Seat 1"); the
  last one leaving brings them back.
- The status bar and home indicator stay; the screen doesn't sleep while a game plays.

### Playing, sideways

The picture in the middle at full height; the touch controls over the sides at 55% (the layout's landscape set),
the D-pad lower left, face buttons lower right, Select and Start top right; the game menu button and the touch bar
in a column at the top left. Status bar hidden. Turning the phone keeps the game running; only the layout changes.

### Arranging touch controls

From the game menu. The game paused and dimmed to 55% behind; every control outlined in a 1.5 dashed `accentText`
line 6 out; the chosen one in a 2 solid `accent` line. Drag to move. A sheet at the bottom (radius extra) names the
chosen control in 17 semibold with Primary pill **Done**; Size and Opacity sliders with their values in monospaced
12; chips to show or hide each control, Rewind, Fast-forward and Save a moment included; "Saved for this {device},
upright. Sideways has its own." in 12 `textHint`. Reset (Quiet) goes back to the console's default.

### Rewind

Held: the touch bar's Rewind, Select and L on a controller (the server's `hotkeys.pad.rewind`), Backspace on a
keyboard. While held:

- The game runs backwards (`{"type":"rewind","on":true}`), the picture at 55% saturation, and a faint lighter band
  sweeping down it once a second, like a tape winding (not with Reduce Motion).
- Along the picture's foot, over a black-to-clear gradient 92 high: the rewind icon and the time back as "−07.4 s" in
  22 monospaced semibold, tabular; a 6-high track of what's kept (`emulation.rewindSeconds`, 20 by default) with an
  `accent` fill and a white playhead moving left; "Let go to play from here · 20 seconds kept" in 12 at 80% white.
- Letting go plays on from there, with a toast "Playing on from here".
- **With a remote**, which can't hold a button for the game: Rewind in the game menu closes the menu into rewind:
  hold ◀ to go back, OK to play on, Back to leave it where it is paused.
- When rewind is off for this game, the touch bar's button and the menu's tile say "Rewind is off" and open the
  setting; the server refuses the action with its message otherwise.

### The game menu

Opens from the menu button, Start and Select together, the controller's home button, Escape, or a remote's Back. The
game pauses (`{"type":"pause","on":true}`) and every held button is let go.

- **The picture shrinks** into a card at the top: 248×186, radius large, a 1-wide `border` ring and the shadow `0 18
  40` black 45%, over `background` at 94%, in 240 ms from where it was (a fade alone with Reduce Motion). Under it: the
  title in 17 semibold and "Paused · {seat dots} {names}" in 13 `textSecondary`.
- **Resume**, Primary pill, full width. It's the one primary action, and has focus first.
- **Four tiles**, 72 high, four across, 8 apart, `card`, radius large, icon 22 over words in 12 medium: **Save a
  moment** (toast "Moment saved · slot {n}", the new moment appears first in the row below), **Rewind**, **Fast-forward**
  (held; "No sound while it runs"), **Screenshot** (`GET /play/{id}/screenshot`, kept in the person's Photos library
  where the server allows, else shared to the system).
- **Moments** (Section 17 semibold, "All {n} ›"): a sideways row of 116×87 moments, the first a dashed `control`
  outline with a `plus` in `accentText`, **Save here**.
- **Look** ("Fine-tune ›"): 96×72 previews of this very picture in each Look, the chosen one ringed (2 `background`,
  then 2 `accent`), names in 12. Choosing one applies at once, for this game.
- **Seats** ("Invite ›"): four across, each a `panel` tile with the seat number in Caption, the avatar at 36 (a circle)
  or a dashed `control` circle with `plus` for a free seat, and the name and how they play ("Touch", "Controller",
  "Her phone").
- A grouped list: **Controllers**, **Arrange touch controls** (touch devices), **Game settings** (the server's settings
  screen, signed in: picture, sound, speed and rewind, saves, cheats, shortcuts, on-screen numbers, core options,
  patches, settings file), **Press Start**, **Press Select** (TVs and remotes), **Change disc** (when `discs` > 1), **Reset
  the game** (asks first).
- **Save and quit**, Secondary pill, full width, then 24 of room. It sends `DELETE /play/{sid}` and waits for the
  answer before leaving, showing "Saving…" in the button.

### Look

The server's display presets are WittyPlay's Looks: **Clean** (sharp pixels), **Scanlines**, **CRT TV**, **Arcade**,
**Handheld LCD** (`GET /games/settings/schema` → `presets`), and **Smooth** (`display.scaling: smooth`), each drawn by
the device from `display.*` (`scanlines`, `curve`, `mask`, `glow`, `vignette`, `lcdGrid`, `blend`, colour, bezel). A
Look costs the server nothing.

- Previews two across at 4:3, on the game's current picture (the last frame, drawn through the same shader), names
  under them; the chosen one ringed.
- **Use it for:** chips This game, Every {console} game, All my games, writing the `game`, `console` or `person`
  level (`PUT /games/settings`). The chip lit is the level the current Look comes from.
- Rows: **Whole pixels only** (`display.integer`), **Shape** (`display.aspect`), **Fine-tune** (the server's Picture
  settings).
- The default, until someone chooses: Handheld LCD on Pocket consoles, Scanlines on 8- and 16-bit, Clean elsewhere,
  as server-level defaults per console (server work, small).
- The shader is ours: one fragment shader in Metal on Apple and GLSL ES on Android, ported from the website's
  (`web/display.ts`, about 60 lines, only numbers from the settings as uniforms), so a Look is the same everywhere.
  Flicker stays off with Reduce Motion, as on the website.

### Seats

From the game menu, a game's page, or "Invite" on the seats row.

- Title "Seats", "Up to four players. Each seat is one controller, wherever it is." in 15 `textSecondary`.
- **Seat cards** two across, 10 apart, 132 high, `panel`, radius large, 14 inside: "Seat {n}" in Caption (a check by
  this device's own), the avatar at 40, the name in 15 semibold, how they play in 12.5 `textSecondary` ("This phone ·
  touch", "Controller 2", "Ann's phone · joined with a code"). A free seat has no fill and a 1.5 `control` outline, a
  dashed circle with a controller or phone icon, "Free", and how to take it.
- **On one screen:** pressing any button on a new controller takes the next free seat; a toast says which. Dragging a
  seat onto another swaps them (the server's port, `{"type":"device"}` per port where the console offers device types).
- **Join from another phone or tablet:** a `panel` card with the code as four boxes 52×64 (radius medium, `card`, 30
  monospaced semibold), a QR card at 120 of the join address, and "In WittyPlay on the other device: Join a game, then
  this code. It lasts 10 minutes." in 13 `textHint`. The joining device shows the picture and its own touch controls
  (or only the controls, "Controller only", to save its battery and the network), and sends its seat's port.
- **Watching:** a row with how many are watching and where. Anyone joined can give up their seat and keep watching.
- A seat's colour is its person's avatar colour; the seat number always shows too, so colour is never the only sign.

### Controllers

The server's controller screen, native: tabs **Buttons**, **Seats** (the Seats screen above) and **Background**.

- The console's pad (`pad.art`) drawn as a generic shape on a `panel` card up to 320 wide: body `card` with a 1.5
  `control` outline, keys `raised`, the chosen key `accent` with `onAccent` letter. The caption names what it is: "Our
  own drawing of a two-button pad; NES names its buttons B and A".
- **Scope chips:** Any controller (or the one connected, by name), {console}, Only {game}. They decide which profile a
  change goes into (`/game-profiles`, the most exact one wins).
- **Mappings** as a grouped list: the position glyph (20) and the console's name for the button, then what presses it
  ("Bottom button", "Right trigger", "Left stick right"), a chevron. Choose a row, then press what you want for it; a
  source used twice is shown on both rows with Swap.
- Then Rumble, Stick dead zone (a stepper on TVs), Turbo per button, Calibrate sticks, Menu shortcut, and
  Export / Import (not on TVs).
- **Background:** the account's picture behind the touch controls and this screen (`/game-background`), with fit,
  position and dim.

### Search and filters

The library's search, for games: the field (44, radius medium, `card`, search icon), consoles as chips in one row
(All first), then **Made for two**, **Era**, **Genre** and **Sort** chips, each of the last three opening the filter
sheet. Results three across as game cards, the count as a Section title. The filter sheet (radius extra, `panel`): Sort,
Era, Players (Made for two, 3 or more), Genre, Series, Decade, Rating, as chip groups with Caption headings; Primary
**Done**. Typing searches title, series and maker after 300 ms; "/" focuses the field on a keyboard.

## Themes

Every server theme works, through APP-DESIGN's translation, with nothing drawn from CSS.

- **The picture is the one fixed colour:** a game's letterbox is black in every theme, as video is.
- **Cover colour:** deep (`hsl(h, min(s, 62%), 26%)`) on a dark theme, pale (`hsl(h, min(s, 70%), 84%)`) on a light
  one, as the website's `useCoverTint`. Words on a pale band are `text`; on a deep band, white with a 1-down shadow.
- **Collection cards** keep the deep tint and white words on every theme, so they read as pictures, not panels.
- **High contrast:** the grain behind collections and eras is off; card outlines are `text` at 40%.
- **Accent** marks the primary action, the chosen Look, a held touch button, the rewind track and the current step;
  nothing else.
- Everything in the prototype can be checked in all eight built-in themes with its swatches.

## On a tablet and Vision Pro

The phone's screens with more room; gutter 32.

- **Home:** cover flow covers 220×275; moment cards 240×180; collection cards 280×158; game cards 128. In landscape
  the cover flow shows six covers on each side.
- **A game:** at 700 wide and over, two columns: the box (160×213), title, actions, Where you left off and How you play
  it on the left (360 wide); Moments (two rows), About, Pictures and More like this on the right.
- **Playing:** sideways is the main way; the picture at full height in the middle, the touch controls in the side
  margins at 100% (they're off the picture), touch bar along the top left. Upright, the picture takes the top half.
- **The game menu** is always the split: the picture card on the left (up to 55% of the width), the menu scrolling on
  the right (at most 420 wide).
- **Vision Pro:** the tablet's layout in a window; the game's picture can be pulled out as its own window, which keeps
  its aspect. A controller is the way to play; with none, the touch controls show as a panel under the picture,
  pressed by looking and pinching, and a Note says a controller plays better.

## On a TV

Apple TV and Android TV look **identical**. Sizes in TV units (APP-DESIGN's On a TV). Gutter 90. Focus is the 4-wide
`text` ring 4 out, concentric, and 1.06; rows leave 24 above and below for it.

### TV home

As the prototype's TV screen.

- **Top bar** (APP-DESIGN): Home, TV guide, Search, Libraries, You, as pills 56 high, 24 from the top; the clock at the
  right in 24 `textSecondary`. It fades out when focus goes below the second row, and back when it returns.
- "Games" in 38 semibold and the count in 24 `textHint`, 112 from the top.
- **Cover flow:** 280×210 covers from 162, sides turned 46°, 0.86, 190 apart. The front cover takes focus; ◀ ▶ there
  turn the covers. Under it, from 398: the title in 48 bold (letters −0.8), facts in 24 `textSecondary`, then **Resume**
  (Primary pill, 66 high, 36 inside) and **About this game** (Secondary pill), 24 apart. **Focus starts on Resume.**
- **Continue playing** from 624: moment cards 304×228 (radius large), title 24 semibold 14 under, facts 20
  `textHint`, 32 apart. Focused, the picture takes the ring and grows; the facts brighten to `textSecondary`.
- **Consoles:** collection cards 480×270, the name in 56 extra-bold (two lines at most, 250 wide), "{era} · {count}
  games" in 22, three covers 130×172 fanned. Going down to this row moves the page up 470.
- Then Eras (tiles 296×184) and the shelves, as on the phone, cards 224 wide (3:4).
- **Prompt bar** along the bottom, 72 high, `panel` at 92% with a `border` top line, 90 in: position glyph (30) and its
  meaning, 40 apart: Open (bottom), Back (right), Favourite (top), Search (left), the bumpers as outlined "L" "R" keys
  for Sections, and at the right, what ◀ ▶ do where focus is. A remote shows only OK, Back and Play/Pause.
- **Buttons** as the website's couch mode has them: top face button marks a favourite, left searches, View changes the
  sort, the bumpers jump between sections, the triggers jump along the alphabet when sorted by title.

### A game on a TV

The backdrop across the whole screen, darkened from the left by `background` (100% to 40% at the middle to 0%); on the
left 45% inside the gutter: "{console} · {era}" in Caption 18, the title in 48 bold, the facts in 24, then **Resume**,
**Moments**, Favourite and "⋯" as pills, Resume focused; Where you left off as a line under them ("Where you left off:
yesterday, 21:58, Living room TV"). Below, rows: Moments (304×228), About (a focusable block that opens the full text),
How you play it (pills: Look, Seats, Controls, Rewind), More like this.

### Playing on a TV

The picture at full height, centred, at its aspect, on black; nothing else on screen. Controllers play; the remote is
a fallback pad (APP-DESIGN and `/consoles/{c}/controls` → `defaults.remote`: D-pad moves, OK is A, Play/Pause is B).
**Back opens the game menu**, never a game button. A toast shows for 3 seconds when a controller takes a seat.

### The game menu on a TV

The split: the picture shrinks to a card filling the left 55% inside the gutter (radius large), with the title in 38
semibold and "Paused · seats" in 24 under it; the menu is a focusable column on the right (640 wide): **Resume**
(Primary pill, focused), the four tiles as a 2×2 grid (each 296×120, icon 32 over words in 24), Moments as a row of
240×180 with Save here first, Look as a row of 200×150 previews, Seats as four 140 tiles, then rows 72 high with 32
icon tiles: Controllers, Game settings (a QR card to the server's page on Apple TV and Android TV alike), **Press
Start**, **Press Select**, Change disc, Reset the game, and **Save and quit**. Back closes the menu and resumes.

### Seats on a TV

The TV is where people gather, so its Seats screen leads with joining: the code in 96 monospaced boxes and the QR card
at 280 on the left half, the four seat cards (2×2, 360×200) on the right. Phones that join are controllers for the TV:
"Controller only" is their default when they join a game shown on a TV.

## On the website

The website's games pages are WittyPlay's reference for anything this page doesn't change, and take everything marked
**→ web**, so there is one design.

### At phone width

Identical to the phone above (APP-DESIGN's one mobile design: at 700 wide and under for the shell, 760 for pages). The
website's player is the phone's: the same bar, touch controls, touch bar, rewind and game menu. The dock shows on every
page.

### At desktop width

- **Shell:** the server's sidebar and top bar, unchanged.
- **Home:** the cover flow as today (covers 280×350), then the same rows as the phone, with cards at 240×180 (moments),
  300×168 (collections), 150 (games); the page's colour as today.
- **A game:** two columns as the tablet, at most 1200 wide.
- **Playing:** the picture centred at full height; touch controls only on touch screens. The game menu is a panel on
  the right, 420 wide, over the dimmed page, with the picture shrinking to the left as on a TV. Keyboard shortcuts as
  today, shown in the menu beside each tile (Space, Backspace, F2, F4, F8).
- **Couch mode** (`/big`) becomes the TV layout above, prompts included.

### What the website's games pages change into (→ web)

| Today | Becomes |
|---|---|
| Library: Consoles as text tiles with counts | **Collections**: cards with the cover colour, the era grain and fanned covers; an **Eras** row; **Made for two** shelf |
| Library on a phone: Title row, cover flow, sections | Same order as the phone's Home here; Continue playing shows moment pictures (it does) and opens straight into the game |
| Console view (`?console=`): the same page narrowed | A **collection** page: the band, sort chips, **Yours on {console}** (Look, Controls, Settings for the console) |
| Game page: Play, star, ⋯ centred; "How it plays" panel; Save states list with download and delete | APP-DESIGN's item layout (box overlapping the backdrop), **Resume / Favourite / ⋯** in one row, **Where you left off** card, **Moments** row with names and devices, **How you play it** list (Look, Seats, Controls, Rewind) |
| Game menu: tiles over the game | The picture shrinks into a card, Resume, four tiles, Moments, Look previews, Seats, rows, **Save and quit** |
| Display presets in Settings → Picture | **Look** with previews on the game's picture, and the level chips |
| Quick save writes one slot (`states.quickSlot`) | Save a moment takes the next free slot; quick load plays the newest |
| Controller screen: Players tab | **Seats** tab; prompts by position (also in couch mode and the library's prompt bar) |
| Couch mode: today's ten-foot pages | The TV layout and prompt bar here |
| Rewind: a hold with a message | The rewind bar and counter |
| Start: a spinner | The steps |
| No sign of a game on another device | **The dock**, Continue here |

## Features, and what the server has

| Feature | What a person gets | On the server today | Server work | Devices |
|---|---|---|---|---|
| **Instant resume** | Resume on Home, the game page and the dock opens where you left off, on any device | Slot 0 written on every stop; `continue` in `/games/home`; one game per account, saved when another starts | — | All |
| **Continue here** | A game running on the TV shows on the phone's dock; one press moves it, from the same moment, without a save and load | The same account may connect up to 8 viewers to its session | `GET /games/playing` (the account's running session and its device); the device name in `ended` when it moves | All |
| **Moments** (several save points with pictures) | Up to 99 per game, each with its picture, name, time and device; never overwritten by accident | Slots 1–99 with a PNG each; 0, 100, 101; download and upload; 4 GB per game | A name and the device per moment (`PUT /games/{id}/saves/{slot}` `{name}`, and `name`, `device` in the list); "next free slot" for quick save | All |
| **Rewind** | Hold to go back up to 20 seconds; see how far | `rewind` action, `emulation.rewind`, `rewindSeconds`, admin memory limit; off by default | On by default for 8-bit, 16-bit and Pocket consoles; how much is kept, as an event | All |
| **Looks** (display filters) | Clean, Scanlines, CRT TV, Arcade, Handheld LCD, Smooth, previewed on the game | `display.*` and five presets; levels person, console, game | A Smooth preset; per-console default Looks | All (drawn on the device) |
| **Per-console and per-game controls** | Controls and Looks for a console from its collection; for a game from its page | Profiles scoped to controller, console, game; settings levels; touch layouts per console, device, orientation | Touch bar keys in a touch layout | All |
| **Seats on one screen** | Up to four controllers on one device, swapped by dragging | Four ports; device types per port | — | All |
| **Seats from several devices** | Join a game with a code or QR, from another phone, a tablet or a browser; phones as controllers for a TV | The same account's devices can connect and send their own port | Invites and seat tokens for other profiles; who holds which seat | All |
| **Watching** | Others see the game without a seat | 8 viewers a session | Viewers from other profiles (with seats) | All |
| **Shelves** | Made for two, genres, series, Most played, Favourites, Recently added | `shelves` (genre, series), `mostPlayed`, `favourites`, `recent`; `players` facet | Made for two as a shelf | All |
| **Collections and Eras** | Consoles as collections; eras across consoles | Consoles with counts; decades | `era` per console and as a filter | All |
| **Cover colour** | Each page and collection takes its covers' colour | The website works it out on the device | — | All |
| **Your year in games** | Hours played, most played, moments saved, in Your year | Play time per game; `/review` | Games in `/review` | All |
| **Soundtrack** | "Listen to the soundtrack" when the Music library has it | — | Matching games to albums | All (later) |
| **The booklet** | "Read the booklet" when a manual sits beside the game | The Books reader | Finding a manual beside a game | All (later) |
| **Screenshots in Photos** | A screenshot lands in the person's own Photos | `GET /play/{id}/screenshot` | Saving it to a Photos library | All |
| **Game PCs** | A PC's games as one more collection, "This PC" | WittyRigs / `console: rig` | — | All |

## Server work

In the order the build needs it. All of it in WittyMediaServer and WittyPlay; none blocks the first native build,
which can ship everything marked "exists" first.

1. **The running game.** `GET /games/playing` → `{id, itemId, title, console, startedAt, device: {id, name, kind},
   seats}` or 204. A device sends its name and kind with `POST /games/{id}/play` (`"device": {...}`). When a viewer on
   another device takes over, the server sends `{"type":"moved","device":"Living room TV"}` to the others.
2. **Moments' names and devices.** `PUT /games/{id}/saves/{slot}` `{name}` (up to 60 characters); `name` and `device`
   in `GET /games/{id}/saves`; the device recorded at save time. A "next free slot" mode for quick save
   (`states.quickSlot: 0`).
3. **Rewind by default** for 8-bit, 16-bit and Pocket consoles, inside the administrator's memory limit; a `rewind`
   event with the seconds kept, at most once a second, while the game menu or the rewind bar shows it.
4. **Eras.** `era` on `/games/consoles`, and `era=` on `/items` and `/games/facets`. Until then, apps read
   `shared/data/wittyplay-eras.json` (8-bit: NES, Master System, Atari 7800; 16-bit: SNES, Mega Drive, PC Engine, Neo
   Geo; Early 3D: N64, PlayStation, Saturn; Disc era: PlayStation 2, Dreamcast, GameCube; Pocket: Game Boy, Game Boy
   Color, Game Boy Advance, Game Gear, Lynx, DS, 3DS, PSP; anything else by its first year).
5. **Made for two** as a `players` shelf in `/games/home`.
6. **Seats for other profiles.** `POST /play/{sid}/invite` → `{code, expires}` (four letters from APP-DESIGN's TV-code
   alphabet, 10 minutes); `POST /play/join` `{code}` → `{sid, seat, token}`; the token lets that profile's device
   connect to that session and send only its seat's port; `GET /play/{sid}/seats` and a `seats` event; the host can
   free a seat. Saves, moments and play time stay the host's.
7. **Touch bar keys** (`rewind`, `fastForward`, `moment`) accepted in a touch layout.
8. **A Smooth preset** beside the five, and per-console default Looks at the server level.
9. **One home across games libraries:** `/games/home` with no `library` answers for every games library the profile can
   see, each item carrying its library (see [Decisions](#decisions-to-confirm)).
10. Later: screenshots into Photos, games in `/review`, soundtrack and booklet matching.

## States

Each takes Play's place on a game's page (a state card), on every device, and the same words come from a refused
start in the player. A state card: `panel`, radius large, 14 inside; an icon in a 36 circle tinted 18% of its colour;
the headline in 15 semibold; what to do in 13 `textSecondary`; its actions as small buttons. On a TV: 24 and 20, a
48 icon circle, actions as pills. On shelves the game's card carries "Can't play yet".

| State | From | Says | Actions |
|---|---|---|---|
| **No core** | `/check` `reason: core`; 409 `needCore` | "This server can't play {console} games yet" · "It needs a core for this console. Ask whoever runs the server." | Administrators: **Install a core** (the server's Consoles and cores page; a QR card on a TV) |
| **BIOS needed** | `/check` `reason: bios`, `bios[]`; 409 `needBios` with `file` | "{console} games need a BIOS file" · "From a console you own. Put it in a folder named `BIOS` inside your {console} games folder." Then each file: needed and missing in `danger`, found in `ok`, and the folder if found | **Try again** (checks again). Never where to get one |
| **Needs a graphics card** | `/check` `needsGpu` and a refused start | "This game needs a graphics card" · "Its console is drawn with one, and this server has none it can use." | — |
| **Not playable here** | console `unavailable` | The server's own words | — |
| **Encrypted** | 422 `encrypted` | "This game file is encrypted" · "WittyPlay plays unencrypted copies only. Nothing here decrypts a file, so this one will never start." | None; it stays listed |
| **Getting it ready** | `prepare` `reading`, `unpacking`, `waiting` | "Getting it ready" · "Unpacking from its archive · {done} of {total}", or "Waiting for other games to unpack" | Cancel |
| **Starting** | play, connecting | The steps (see Starting) | Cancel |
| **Busy** | 503 | "The server is busy" · "It's running as many games as it allows. Try again when one finishes." | Try again |
| **File gone** | 404 | "This game's file has gone" · "It was moved or deleted. Put it back, or scan the library again." | — |
| **No picture** | no frame on any mode | "The picture can't reach this {device}" · "The game started on your server, but its picture isn't getting through. A firewall or the network is usually why. The game waits a minute for you." | **Try again**, Use another connection, Quiet "Leave. Your game is saved." |
| **Reconnecting** | the connection drops | The last frame dimmed to 35%, "Reconnecting…" with a spinner; within 60 seconds it comes back by itself | Leave |
| **The game stopped** | `ended` | "The game stopped" · the server's `text` · "Your last moment was saved." | **Resume**, Start with default settings, Leave |
| **Moved** | `moved` (server work) | "This game moved to {device}" | Continue here, Leave |
| **The game ended itself** | `shutdown` | Back to the game's page, toast "The game ended" | — |
| **Stopped while away** | 30 minutes without input | On return: "Stopped after 30 minutes without a press, and saved." | Resume |
| **Guest and Kids** | 403 | Guest: no uploads (moment upload, battery save in, background); Kids: no patches. The rows are hidden, not greyed | — |
| **A PC's game** | 409 `rig` / `console: rig` | Plays through Game PCs, not WittyPlay's player | Opens it there |
| **Loading a page** | — | APP-DESIGN's grey shapes in the layout's places, never a spinner on an empty page | — |
| **No games yet** | empty library | "No games here yet" · "Add a games folder in Libraries." (administrators: the button) | — |

A moment that won't load leaves the game as it was and says so, with **Undo load** (`undo`) offered.

## Motion and access

| What | How |
|---|---|
| Turning the cover flow | 240 ms ease; colour cross-fade 400 ms |
| Opening the game menu | The picture shrinks to its card in 240 ms; the sheet fades in and rises 8. Reduce Motion: a 200 ms fade |
| A moment saved | The new moment slides into the row from the Save here tile, 200 ms; a light haptic; the toast |
| Rewind | The tape band sweeps once a second; off with Reduce Motion |
| A held touch button | Fills `accent` at once (no transition: the game's response is the feedback) |
| A seat taken | The seat's avatar fades in with a 3 lift |
| TV focus | APP-DESIGN's 1.06 and ring, 150 ms |

- Every control has a spoken label: "Resume Super Tilt Bro., NES, last played yesterday", "Seat 2, Ann, her phone",
  "Look, Scanlines, chosen". The game picture is "Game picture, {title}" and isn't read further.
- Seats always show their number as well as their colour.
- Type follows Dynamic Type and Android's font scale on every screen except the player's touch controls, which follow
  the touch layout's sizes.
- Fast-forward and flicker carry the server's cautions; flicker is forced off with Reduce Motion.

## Decisions to confirm

Before the Apple and Android builds start:

1. **The words.** Moment, Where you left off, Look, Seat, Collection, Era, Made for two, Continue here, Game menu. Once
   confirmed they go into `strings.en.json` and the website's wording, and change only together.
2. **One WittyPlay home for every games library**, with the library as a chip (Games, Retail Games…), or one home per
   library as today. One home needs server work (`/games/home` across libraries); per library needs none.
3. **Rewind on by default for 8-bit, 16-bit and Pocket consoles**, at 20 seconds within the administrator's memory
   limit (32 MB a running game, 16 MB on small servers), or off until each person turns it on, as today.
4. **Who can take a seat in someone's game:** other adults on the server with a code; Kids profiles too; Guest only
   with a code; saves stay the host's. Same-account joining (a phone as a controller for your own TV) can ship first
   with today's API; other profiles need the server work above.
5. **Button prompts by position, never a maker's symbols**, on every device, the website's couch mode included: the
   four-dot diamond with the button filled, and the console's letter beside it only when it's a letter or number.
   Today's couch mode shows each controller's own letters and shapes.

## Checking a build against this

For each screen, at phone, tablet and TV sizes and in a light and a dark theme, compare a screenshot with the
prototype and this page: sizes, colour roles, the words' keys, focus on a TV, and the legal list at the top (no maker's
names, logos, symbols, sounds or layouts; demo games only in anything published). Then play the openly licensed demo
games through the whole flow on the local server: start, rewind, save a moment, change the Look, quit, resume on
another device.
