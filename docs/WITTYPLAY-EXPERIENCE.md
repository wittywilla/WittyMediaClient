# WittyPlay: the games experience

**Prototype:** [WittyPlay prototype](https://claude.ai/artifact/ArXyR6wEt5xHdHkapHYE2p): the Shelves home (and the
two directions it was chosen over), the moment a game boots, the game menu built from each core's data (one screen, two
screens, discs), every input method with hints that match it, the TV, and every server theme. Click through it; every
screen carries its notes. It's private to its owner until shared from its Share menu.

**Status:** settled. The decisions are recorded under [Decisions](#decisions); build to this page.

WittyPlay is the games part of WittyMediaServer: the server runs every game and streams it, and a device shows the
picture and sends the controls back ([How the apps look](APP-DESIGN.md#games-everywhere-wittyplay)). This page is
everything around that stream, on every device: the contract the Apple player (iPhone, iPad, Apple TV, Vision Pro), the
Android player (phones, tablets, Android TV) and the website's games pages are built and checked against. Sizes,
colour roles, type, motion and the shell (strip, floating bar, Back) are [APP-DESIGN's](APP-DESIGN.md); this page adds
what games need.

The idea: **a classics service made of your own games.** Your consoles are shelves you browse like a well-kept record
shop; each one has its own colour and character; a game you're in the middle of has a ribbon in it and opens exactly
where you left it, on any device; you can keep as many moments as you like, rewind a mistake, choose how the picture
looks, and play together on one screen or from several. All of it in WittyMediaServer's own words and look, and every
part of it works by touch, controller, TV remote and keyboard.

- [Legally distinct](#legally-distinct)
- [Words](#words)
- [The games home: Shelves](#the-games-home-shelves)
- [Signature details](#signature-details)
- [Where everything is](#where-everything-is)
- [On a phone](#on-a-phone)
- [Feature complete](#feature-complete)
- [Adapts to each core](#adapts-to-each-core)
- [Input, for every screen](#input-for-every-screen)
- [Themes](#themes)
- [On a tablet and Vision Pro](#on-a-tablet-and-vision-pro)
- [On a TV](#on-a-tv)
- [On the website](#on-the-website)
- [Server work](#server-work)
- [States](#states)
- [Access](#access)
- [Decisions](#decisions)
- [Checking a build against this](#checking-a-build-against-this)

## Legally distinct

A hard rule, checked on every screen before it ships. WittyPlay takes the *kind* of experience a classics service offers
(a curated library, consoles as collections, instant resume, rewind, save points, display filters, playing together) and
copies nothing of any console maker's.

- **No names.** No product, service or feature name of a console maker appears in the apps, the website, the strings,
  asset names or anything a person sees. WittyPlay's own words are under [Words](#words). Consoles are named in plain
  text ("NES", "Game Boy"), which only says what a game is for.
- **No layouts, menus, sounds, icons, colours or trade dress.** Every screen is built from APP-DESIGN's components and
  the shapes below: shelves and spines, the shrinking picture card, tiles. Icons are SF Symbols and Material Symbols as
  APP-DESIGN maps them, or our own drawings. A console's colour comes from its own covers, never its maker's brand.
- **Spines are ours.** A spine is a tinted strip with the title, the console's short name and the era's grain. It never
  reproduces a box's real spine, label or packaging art.
- **No console logos or brand artwork.** WittyPlay's screens never show a console logo, even where the server's owner
  has downloaded logos for its own pages. Controllers are the server's generic drawings (`pad.art`: `one`, `two`,
  `four`, `six`, `handle`, `dual`), never a product's outline.
- **Button hints are our drawing.** A hint shows the label the connected pad prints, as plain text or a plain outline
  shape in the theme's `text` colour, inside our own round key: never the maker's colours, typeface or glyph artwork.
  "Position only" (a diamond of four dots with the one to press filled) is always available, and is what a pad we can't
  identify gets.
- **Sounds are original.** Every interface sound is synthesized for WittyPlay from simple tones and noise (see
  [Sound and haptics](#sound-and-haptics)) and checked against the console makers' start-up and menu sounds so none
  resembles one. They're off until someone turns them on.
- **Pictures in anything published** (this repository, screenshots, store listings, the prototype) are the openly
  licensed demo games credited in the server's `docs/images/CREDITS.md`, or illustrations we draw. Never retail games.

## Words

Plain words, from `shared/data/strings.en.json` once added. Keys use a `wp` prefix. The words are confirmed: they go
into `strings.en.json` and the website as they are, and change only together.

| What | WittyPlay says | Key | Server's own name |
|---|---|---|---|
| The games part | WittyPlay | — | WittyPlay module |
| A console's games, as a row | **Shelf**, named by the console ("NES") | `wpShelf` | console filter |
| A console's own page | **Collection** | `wpCollection` | console view |
| One game on a shelf | **Spine**; turned to show its cover, **face out** | — | item |
| A group of consoles by time or kind | **Era**: 8-bit, 16-bit, Early 3D, Disc era, Pocket | `wpEras` | — |
| Games for two or more | **Made for two** | `wpMadeForTwo` | `players` facet |
| A game in progress | a **ribbon** in its spine | — | slot 0 exists |
| The automatic save (slot 0) | **Where you left off** | `wpWhereYouLeftOff` | auto state |
| A save state with its picture (slots 1–99) | **Moment**; Save a moment, Save here, Play from here | `wpMoment`, `wpSaveMoment`, `wpSaveHere`, `wpPlayFromHere` | save state, slot |
| Slot 100, slot 101 | **Before you loaded**, **Before starting over** | `wpBeforeYouLoaded`, `wpBeforeStartingOver` | undo, autoprev |
| Going back in time | **Rewind** (held); "Let go to play from here" | `wpRewind`, `wpRewindHint` | `rewind` |
| How the picture is drawn | **Look**: Clean, Scanlines, CRT TV, Arcade, Handheld LCD, Smooth | `wpLook` | `display.*` presets |
| A player's place, 1 to 4 | **Seat**; Free; Join a game; Watching | `wpSeats`, `wpSeatFree`, `wpJoinGame`, `wpWatching` | port |
| Playing with someone on another server (reserved, not built) | **Multiplayer**, greyed out; "Play with someone on another server. Coming later." | `wpMultiplayer`, `wpMultiplayerLater` | — |
| The pause menu | **Game menu** | `wpGameMenu` | game menu |
| A collection playing by itself | **Channel**; on a TV left alone, **Leave it on** | `wpChannels`, `wpLeaveItOn` | — |
| Moving a running game here | **Continue here**; "Playing on {device}", "Moved from {device}" | `wpContinueHere`, `wpPlayingOn`, `wpMovedFrom` | — |
| Leaving | **Save and quit** | `wpSaveAndQuit` | stop |

Other strings: `wpContinuePlaying` "Continue playing", `wpEveryGame` "Every game, A to Z", `wpYoursOn` "Yours on
{console}", `wpLookFor` "Look for {console} games", `wpControlsFor` "Controls for {console} games", `wpHowYouPlay` "How
you play it", `wpMoreLikeThis` "More like this", `wpYourNotes` "Your notes", `wpStartOver` "Start over",
`wpStartDefault` "Start with default settings", `wpGettingReady` "Getting it ready", `wpStartingOnServer` "Starting on
your server", `wpConnectingTo` "Connecting to this {device}", `wpResetGame` "Reset the game", `wpArrangeTouch` "Arrange
touch controls", `wpPressStart` "Press Start", `wpPressSelect` "Press Select", `wpMomentSaved` "Moment saved",
`wpCantPlayYet` "Can't play yet", `wpScreens` "Screens", `wpSwapScreens` "Swap screens", `wpDiscs` "Discs",
`wpChangeDisc` "Change disc", `wpMemoryCards` "Memory cards", `wpShortcuts` "Shortcuts", `wpButtonHints` "Button hints",
`wpMultiplayer` "Multiplayer", `wpMultiplayerLater` "Play with someone on another server. Coming later.",
and the states' words under [States](#states).

## The games home: Shelves

Decided on 5 November 2026, from three directions explored in the prototype (Shelves, a Timeline of eras, Channels).

**Shelves is the games home.** Each console is a shelf of **spines**, standing on a ledge, in its covers' colour. The
shelf's first game is turned **face out**. Touch a spine and it **pulls out** to face you, with Resume or Play under the
shelf. A game in progress has a **ribbon** in its spine; a favourite a small star. Long shelves get **letter dividers**,
like a record shop's. Above the shelves, the one obvious next step: **Where you left off**, the last moment's picture,
large.

It scales: 415 SNES games are a long shelf with dividers, not a wall of covers. Every input moves along it naturally:
along a shelf, between shelves, a letter at a time on the triggers. Each console gets a personality (colour, grain,
type, the shape of its spines) without a logo. Resume points have a physical place: the ribbon. It costs the server
nothing, and it belongs to a media server that keeps books and records as well as games.

The other two directions live inside it:

- **The Timeline is the Eras page** (from an era tile, or the Era chip in Search): a living timeline you drag through,
  the year in huge numerals, the era's name and grain changing as you go, consoles as bands from launch to their last
  years (filled with their covers' colour when you have games for them, outlined when you don't), and your games from
  consoles alive in that year underneath.
- **Channels is the TV's Leave it on mode and a row on the phone's home.** Every collection is a channel already playing
  an attract preview of its games and your moments, in the console's Look, with Now and Next as WittyTV's guide says it,
  and Play. On a TV left alone for two minutes on the games home, it starts flicking through channels like a
  screensaver that sells the library; any press stops it on that game.

## Signature details

### A console's personality

Every shelf, collection page and spine takes its character from data, within the theme, so a new console gets one
without design work:

| Part | From | Example |
|---|---|---|
| Colour | The tint of its covers (a 16-pixel copy, colourful parts counting more), at least 38% saturation and 30% lightness on spines and bands | NES teal from its covers; Pocket a warm brown |
| Grain | The era's pixel: dots 12 apart for 8-bit, 10 for 16-bit, 7 for Pocket, a triangle mesh for Early 3D, rings for Disc era, at 16–35% | Behind the band, on spines, on era tiles |
| Type | The era's treatment of the console's name, in the platform's own faces (SF and SF Mono on Apple, Roboto and Roboto Mono on Android, the website's): 8-bit in monospaced capitals with 6% tracking; Pocket monospaced over a faint LCD grid; 16-bit extra-bold, tight; Early 3D bold italic; Disc era light, wide capitals | "NES" and "MASTER SYSTEM" in monospaced capitals |
| Spine shape | The console's media: cartridges 176 high; handheld boxes 136; disc cases thin (24 wide) with a sheen | A Pocket shelf sits lower |
| Sound | The era's short boot motif (see Sound and haptics) | A square-wave rise for 8-bit |
| Look | The era's default Look | Scanlines for 8-bit, Handheld LCD for Pocket |

### Resume points

- **The ribbon.** A game with a slot 0 has a notched `accent` ribbon (14 wide, 40 long; 22×52 on a TV) standing out of
  the top of its spine, its face-out cover, its Continue card and Where you left off. It's how in-progress games are
  found at a glance, on every shelf.
- **Where you left off** is the first thing on the home: the last moment's picture at 343×214, drifting very slowly (a
  14-second pan between 1.04 and 1.14, still with Reduce Motion), the game, time played and where, and Resume.
- **The last thing you saw is the first thing you see.** Resuming, the boot shows the moment's picture, and the live
  picture cross-fades in from it, so it feels like unpausing, not loading.
- **Continue here.** A game playing on another device sits in the dock above the floating bar; one press moves it here
  from the same moment.

### The moment a game boots

1. The spine (or card) lifts out into the middle as the game's box, 200×150, in 500 ms, over the cover's glow.
2. The steps show what's happening: Getting it ready (with progress, for archives), Starting on your server, Connecting.
3. When the first frame arrives, the picture **switches on**: a bright line across the middle opens to the full picture
   in 500 ms, and the era's boot motif plays if sounds are on. Resuming, it cross-fades from the moment instead.
4. With Reduce Motion, a 300 ms fade. With a slow start, the steps stay; the switch-on never plays over a blank picture.

### Motion with meaning

| What | How | Why |
|---|---|---|
| Pulling a spine | Grows from its width to face out (120×160) and lifts 6, 280 ms, ease-out; the shelf's info slides in under it | You took it off the shelf |
| Focus on a spine (pad, remote, keys) | Lifts 10 (28 on a TV) and takes the ring | It's in your hand |
| Opening the game menu | The picture shrinks into its card (from 1.5×, 260 ms); the menu rises 8 and fades in | The game is paused behind, not gone |
| Saving a moment | The new moment slides in from Save here, 200 ms; a light haptic; the toast | It's kept, and you can see where |
| Rewind | The picture drains to 55% saturation and a lighter band sweeps down it once a second | Time running backwards |
| Changing channel | The next channel slides in from below, 380 ms | Like a channel up |
| Attract previews | A 14-second pan and 0.9 s cross-fades | Alive, never busy |
| Swapping screens | The two screens trade places, 240 ms | The touch screen moved |

Everything respects Reduce Motion: pans stop, slides become fades, the rewind band and the disc's spin stop.

### Sound and haptics

Off by default; **Menu sounds** in Game settings → Sound turns them on for this device. All are synthesized at run time
(or rendered once from the same recipe), short and quiet, under the system's own volume and silent switch.

| Sound | Recipe |
|---|---|
| Focus moves | A 25 ms sine at 2.1 kHz, very quiet |
| Pull a spine | A 80 ms low-passed noise burst with a 132→96 Hz sine thump |
| Open | Two triangle notes, a fifth apart, 50 ms apart |
| Back | The same, falling |
| Moment saved | A 30 ms click of high noise, then two rising triangle notes |
| Channel | A soft noise sweep and a short rising sine |
| Rewind (held) | A falling sawtooth, very quiet, while held |
| Boot, 8-bit | Four square-wave notes rising a fifth then an octave (G4 C5 G5 C6), 75 ms apart |
| Boot, Pocket | Three triangle notes in thirds (F5 A5 C6) |
| Boot, others | One soft sine chord (C4 G4 C5 E5), 600 ms |

**Haptics** on phones, following the system's setting: a light tap when a spine is pulled, a moment is saved, or a
touch control is pressed; a soft continuous buzz while rewinding. On Apple, Core Haptics; on Android,
`VibrationEffect` with the predefined click and tick. Controllers rumble only for the game.

### Attract previews

Wherever a game sits large (the TV's preview, a game's backdrop, Channels, Where you left off), it moves: its pictures
drift and cross-fade, drawn in its Look. In order of preference: the game's metadata video if the server has one
(server work), its screenshots, and the person's own moments. A preview never starts a game on the server.

## Where everything is

```
Games library (WittyPlay home: Shelves)      /library/{id}
├── Where you left off, Continue playing
├── Shelves: one per console, Made for two, genres, series, Every game A to Z
├── Collection (a console)                   /library/{id}?console=nes
├── Eras (the timeline)                      /library/{id}?era=8-bit            (server work: era)
├── Channels                                 /library/{id}?view=channels
├── Search and filters                       /search?kind=game, and the library's own search
└── A game                                   /item/{id}
    ├── Moments                              /item/{id}#moments
    ├── Look · Seats · Controls (also in the game menu)
    └── Playing                              /game/{id}?resume=1 | ?slot=n | ?safe=1
        ├── Boot
        ├── Rewind (held)
        └── Game menu (built from the core's capabilities)
            ├── Moments, Screens, Discs, Look, Seats, Memory cards
            ├── Controllers                  /controllers?console=…
            ├── Arrange touch controls
            ├── Shortcuts
            └── Game settings                the server's settings screen, drawn from its schema
Join a game                                  /play/join?code=…                  (server work: seats)
The dock                                     above the floating bar, on every page, while a game plays on another device
```

- **Getting in:** the Games library in the strip and the Menu, as every library, and the dock.
- **Getting out of a game:** Save and quit; Back (Android, and a remote's Back opens the game menu first); or leaving
  the app: the game is stopped and saved after 60 seconds with nobody connected.
- **Deep links:** `wittymediaclient://game/{id}` and `…/join/{code}` open the same screens in the apps; the website's
  addresses do the same in a browser. A QR code for joining carries the website's address, which the apps claim as a
  universal link / app link.

## On a phone

Sizes for a phone 375 wide, in points (dp on Android), as APP-DESIGN. Gutter 16. Every screen below the library has
APP-DESIGN's 40 round Back.

### Home: Shelves

The Games library page in the shell (library strip, floating bar), top to bottom:

1. **Title row:** "Games" in Title (24 semibold), the count in 15 `textHint`, a Ghost "Filters" (32 high).
2. **Where you left off:** a card 343×214, radius large, the slot 0 picture filling it (`object-fit: cover`,
   pixel-crisp, in the game's Look), drifting; a black gradient from the bottom (86% to 0 at 70%); over it, 14 in:
   "Where you left off" in Caption at 80% white, the title in 22 semibold, "console · time played · when on device" in 13;
   **Resume** (Primary pill, 32 high) at the right. The ribbon 22 from the right edge. The whole card resumes.
3. **On the go:** the other games in progress as 152×114 picture cards (radius medium) with a ribbon and a 3-high
   progress line of time played (`accent` on white 30%), title 14 semibold, "time played · when" 12 `textHint`; then a
   **Moments** card (`panel`, the moment icon) that opens every moment.
4. **Shelves**, 26 apart. Each: a heading (the console's name in its era's type, the era in Caption `textHint`, the count
   in 13 `textHint`, "All ›" for its collection), then the **ledge**: spines in a row, 3 apart, 26 above for ribbons and
   the lift, standing on a 3-high line of `text` at 13% with a soft shadow under it. Order: one shelf per console (most
   games first), Made for two, the server's genre and series shelves, Favourites, Recently added, **Every game, A to Z**
   with letter dividers, and a **Channels** row last.
   - **Spine:** 34 + up to 14 by title length wide (rounded to whole points), 176 high (136 handheld, 24 wide for disc
     cases), radius 4 at the top; the tint with a left-lit gradient (white 14% to 0 at 28%, black 22% at the right); the
     era's grain at the top fading by 70%; the title vertical, 12.5 semibold white with a 1-down shadow, from 24 below
     the top; the console's short name in a 18-high chip (black 28%) at the foot, 9 bold monospaced.
   - **Face out:** 120×160 (104×136 handheld), radius 6, the cover (the box art; with none, the first screenshot),
     lifted 6 with a shadow `0 14 22` black 60%.
   - **Pulled out:** the chosen spine becomes face out with a 2 `accent` ring (2 out); under the ledge, a `panel` card
     (radius large): title 17 semibold, "console · maker · genre · players" 13, Where you left off when there is one,
     and **Resume** or **Play** (Primary pill) and **About** (Ghost pill). Pulling another closes the first.
   - **Letter dividers:** 22×64 tabs in `card` with a `border` outline, the letter in 11 bold monospaced at the top.
5. 120 of room at the foot (190 with the dock).

### The dock: Continue here

While this account's game runs on another device, a bar sits above the floating bar on every page (as the mini player
does for music): 60 high, radius large, `panel`, `border` outline, shadow `0 8 24` black 35%. The game's picture 44
(radius 8), the title in 14 semibold, then an 8 `ok` dot with a 3 halo, the device's name and its seat dots in 12
`textSecondary`; Secondary pill **Continue here** (32 high). Pressing it starts the game here from the same moment; the
other device shows "This game moved to {device}". The rest of the bar opens the game's page. It hides while a game plays
on this device, and moves up above the prompt bar when one shows.

### A collection

A console's page: a **band** 260 high in the console's colour with its grain fading down; "{era} · Collection" in Caption
at 80% white, the name in 48 extra-bold in its era's type, "{full name} · {count} games" in 15 at 85%. On a light theme
the band is pale and its words `text`. Then sort chips (Most popular, A to Z, Newest first, Made for two); **Yours on
{console}** (Look, Controls, Settings for this console: the per-console settings, where people expect them); Continue
playing for this console; the shelf of every game, and a grid three across for a long collection.

### Eras

Direction B as a page: the year in 84 extra-bold (letters −4, tabular), the era's name in 15 semibold `textSecondary`,
its grain behind both; the timeline (34 per year, bands 22 high in lanes 28 apart, a 2-wide `accent` line marking the
year in the middle); "Around {year}" and your games from consoles alive then. Dragging, a pad's ◀ ▶, or a remote's swipe
moves through the years; a band opens its collection.

### Channels

Direction C as a full-screen page: each channel fills the screen with its attract preview; the channel number in 44 bold
monospaced and its name in 15 semibold top left; a Caption of what it holds, the game in 28 bold, "console · maker", Play
(Primary pill), and "Next on {channel}: {game}" with a 30×22 picture. A rail at the right: up, down and the channels as
dots. Swipe, wheel, the rail, or a pad's ▲ ▼ change channel.

### A game

APP-DESIGN's item page, for a game:

1. Back; the **backdrop** 220 high: an attract preview of the game's screenshots, drifting, fading into `background`.
2. **The box** 120×160, radius medium, overlapping the backdrop by 60; "{console} · {era}" as a Caption beside it, and
   for two or more players the seat dots and "Made for two".
3. The title in 30 semibold (letters −0.66); facts (maker · genre · 1–{n} players) in 15 `textSecondary`.
4. **Actions, one row:** **Resume** (Primary pill, filling the row) when slot 0 exists, else **Play**; Favourite (44
   Secondary square pill, `star`); "⋯" for Start over, Start with default settings, Settings for this game, Controllers,
   Versions, Files and advanced (battery save in and out, patches, cheats file), and the administrator's tools (which
   file in the archive, split a version, console, core, edit details, artwork, not a game).
5. **Where you left off:** a `panel` card with the slot 0 picture 96×72 and its ribbon, "{when} · {device}" and "{time}
   played".
6. **Moments** row (200×150), **About this game**, **How you play it** (Ready on your server or why not; Look; Seats;
   **Multiplayer**, greyed out, right under Seats; Controls; Rewind), **Pictures**, **More like this**, **Your notes**.

A game that can't play replaces 4 and 5 with its [state card](#states); Play never appears for it.

### Moments

From a game, the game menu, or On the go. Title "Moments", "{n} of 99 · {size} of 4 GB · on every device". Two across at
4:3: **Where you left off** first ("Automatic"), then moments newest first, then **Before you loaded** and **Before
starting over** ("Undo"). Under each: name 14 semibold, when and device 12. A moment's sheet: the picture, its name,
"{when} · {device} · slot {n}", **Play from here**, Rename, Download, Delete (asks first). **Saving a moment** takes the
lowest free slot, so nothing is overwritten by accident; with all 99 used it asks to replace the oldest. Quick save does
the same; quick load plays from the newest.

### Boot

As [The moment a game boots](#the-moment-a-game-boots): the box 200×150 at 210 from the top over the cover's glow; the
title 22 semibold; "Picking up where you left off", "Starting from {moment}", "Starting a new game" or "Moving from
{device}" in 14; the steps (14, 18 circles: done `ok` with a check, current an `accent` ring turning, later `textHint`);
Quiet Cancel. A mode that shows no picture in 12 seconds is dropped for the next in `modes`, without asking.

### Playing

- **Upright:** the picture full width under the status bar at the session's `aspect`, on black; a bar 10 under it with
  the game menu button (40 round, `card`), the touch bar (Rewind held, Fast-forward held, Save a moment: 36-high pills,
  held ones `accent`) and the seats' avatars at 22; the touch controls below on the account's controller background.
- **Sideways:** the picture in the middle at full height; touch controls over the sides at 55%; the menu button and touch
  bar in a column at the top left.
- **A controller or keyboard** connecting hides the touch controls and the touch bar, and shows once, for 3 seconds, how
  to open the game menu with that input ("View + Menu or Home: game menu", "Esc: game menu · ?: shortcuts").
- **Touch controls** (our drawing): D-pad a plus of two `card` bars with `control` outline and `text` arrows at 60%; face
  buttons `card` circles with the console's letter 22 semibold; Select and Start 72×30 pills; pressed, `accent` and a
  haptic. Positions, sizes and opacity from the touch layout for this console, device and orientation.

### Two screens

For a console whose capabilities say two screens (DS, 3DS): the screens drawn by the app from the core's layout, upright
**stacked** by default (two 300×225, 4 apart), with **Side by side**, **One big** (the other inset at the top right with a
shadow) and **One at a time** from the game menu or the layout key. The screen that takes touch has a fine
`accentText` outline; a press there is the stylus (a white ring ripples out). **Swap** in the touch bar trades the
screens; touch follows the touch screen. The pad is the console's four-button shape with L and R above.

### Arranging touch controls

From the game menu: the game dimmed to 55%; every control outlined 1.5 dashed `accentText`, 6 out; the chosen one solid
`accent`. Drag to move; a sheet (radius extra) with the control's name, Size and Opacity sliders with monospaced values,
chips to show or hide each control (the touch bar's included), **Done**, Reset. "Saved for this {device}, upright.
Sideways has its own." For two screens, the touch screen is kept clear of controls.

### Rewind

Held: the touch bar's Rewind, Select and L on a pad (`hotkeys.pad.rewind`), Backspace on a keyboard. While held the
game runs backwards, the picture drains and the tape band sweeps; along its foot, "−07.4 s" in 22 monospaced semibold
and a 6-high track of what's kept (`emulation.rewindSeconds`) with a white playhead moving left. Let go to play on.
**With a remote:** Rewind in the game menu closes the menu into rewind: hold ◀, OK plays on, Back leaves it paused there.
Rewind is **on by default for 8-bit, 16-bit and Pocket consoles** (20 seconds, within the administrator's memory limit)
and off elsewhere until someone turns it on. When it's off for this game, the button and tile say "Rewind is off" and
open the setting.

### The game menu

Opens from the menu button, the menu chord or the pad's home button, Escape, or a remote's Back. The game pauses and
every held button is let go. **Every section comes from the core's capabilities** (see [Adapts to each
core](#adapts-to-each-core)):

1. **The picture card:** 248×186 (two screens: 170×256, stacked), radius large, `border` ring, shadow `0 18 40` black
   45%, shrinking in from the full picture. The title 17 semibold; "Paused · seat dots · names" in 13.
2. **Resume**, Primary pill, full width, focused first; with a pad or keyboard, its key beside it.
3. **Tiles**, 76 high, `card`, radius large, icon 22 over 11.5 words; four across for four, three across for five or six.
   Save a moment always; Rewind and Fast-forward when the core allows; **Swap screens** for two screens; **Change disc**
   for more than one disc; Screenshot. Each tile shows its shortcut for the input in use in its top right corner.
4. **Moments:** Save here first (dashed `control` outline, `plus`), then this game's moments, 116×87.
5. **Screens** (two screens): four layout tiles with small diagrams (Stacked, Side by side, One big, One at a time),
   the chosen one ringed `accent`; Swap; "Touch goes to the {bottom} screen, wherever it is. With a controller, the right
   stick moves a pointer there."
6. **Discs** (more than one): a card per disc with a disc drawing, the one in the drive ringed and turning slowly; press
   another to change disc (`{"type":"disc"}`).
7. **Look:** 96×72 previews of this very picture in each Look; the chosen one ringed.
8. **Seats:** as many as the console has ports (four with a multitap, "With a multitap" on the extra ones); each with the
   avatar, name and how they play, and the controller type when the core offers types ("DualShock ▾", "Light gun ▾").
   Under the seats, **Multiplayer**, greyed out (see [Multiplayer](#multiplayer-reserved)).
9. **Memory cards** (when the core keeps them): each card, whose it is ("This game's own", "Shared by your PlayStation
   games") and how many saves.
10. Rows: Controllers (with "Light gun: aim with touch, a mouse or the right stick" for a light-gun console), Arrange
    touch controls (touch devices), Cheats (when the core has them), Region (when the core has one; "changes next time
    the game starts"), Game settings, **Press Start** and **Press Select** (remotes), Reset the game, **Shortcuts**.
11. **Save and quit**, Secondary pill, full width; "Saving…" until the server answers.

Sideways and on tablets and TVs the menu is a split: the picture card on the left, the menu scrolling on the right.

### Look

The server's five presets (Clean, Scanlines, CRT TV, Arcade, Handheld LCD) and Smooth, previewed two across on the
game's picture; **Use it for** chips (This game, Every {console} game, All my games) write the `game`, `console` or
`person` level; Whole pixels only, Shape, Fine-tune (the server's Picture settings: scanlines, curve, mask, glow,
vignette, LCD grid, blend, colour, bezel). Drawn on the device by one shader ported from the website's `web/display.ts`
(Metal on Apple, GLSL ES on Android). Flicker stays off with Reduce Motion.

### Seats

Four seats (two across, 132 high, `panel`): "Seat {n}", the avatar 40, name, how they play; a free seat outlined with
how to take it. Joining from another device: a four-letter code (from APP-DESIGN's TV-code alphabet) in 52×64 boxes and
a QR card, lasting 10 minutes; a joiner gets the picture and their own controls, or "Controller only". **Watching** shows
who's watching. Pressing a button on a new controller takes the next free seat; dragging a seat onto another swaps them.

**Who can take a seat:** the host's own devices always; other adults and Kids profiles on the server, with the code;
Guest only with the code. Saves, moments and play time stay the host's. The host can free any seat.

### Multiplayer (reserved)

Playing a game together with someone on **another WittyMediaServer** is reserved and **not built**. It's separate from
Seats, which are for people on this server. Every device shows it so that it reads as the natural next step after
Seats, and every device shows it the same way:

- **Where:** in the game menu, a row right under the seats; on a game's page, a row in How you play it right under
  Seats. A game for two or more players (Made for two) shows it the same as any other.
- **How:** a grouped-list row in its normal place and size, at 55% opacity: a 28 icon tile (`globe` / `public`,
  quiet), **Multiplayer** (`wpMultiplayer`) in Body, and under it in Secondary `textHint` "Play with someone on
  another server. Coming later." (`wpMultiplayerLater`). No chevron, no value, no press state.
- **Not an action:** it does nothing when pressed, is left out of the focus order on a TV and with a pad or keyboard,
  and a screen reader reads it as "Multiplayer, unavailable. Play with someone on another server. Coming later."
  (`aria-disabled` on the web; the `.notEnabled` trait on Apple; `isEnabled = false` on Android).
- **Server:** nothing, and no API. When it's built, it gets its own design and its own section here.

### Controllers

Tabs **Buttons**, **Seats**, **Background**. The console's pad drawn as our generic shape (`pad.art`), the chosen key
`accent`; scope chips (Any controller or the connected one by name, {console}, Only {game}) pick the profile a change
goes into; mappings as rows with the button's hint glyph and name, what presses it, Swap when used twice; then **Button
hints** (Your pad's labels / Position only), Rumble, Stick dead zone, Turbo, Calibrate sticks, Light gun calibration
(light-gun cores), Game menu shortcut, Profiles (copy, export, import; not on TVs).

### Search and filters

The field (44, radius medium, `card`), consoles as chips, then Made for two, Era, Genre, Sort chips (the last three open
the filter sheet: Sort, Era, Players, Genre, Series, Decade, Rating). Results three across. Typing searches after 300 ms.

## Feature complete

Every WittyPlay feature the server has today, and where it is in this design, so nothing is lost. "Server page" means
the server's own page inside the app (a QR card on a TV), as APP-DESIGN's settings do.

| Server feature | Route or setting | Where it is |
|---|---|---|
| Games libraries, consoles and counts | `/games/consoles?library=` | A shelf per console; Collections; Eras |
| The games home | `/games/home`: hero, continue, recent, favourites, mostPlayed, genre and series shelves | Where you left off, On the go, shelves, the TV's preview |
| Facets and sorting | `/games/facets`, `/items?kind=game&sort=` | Search's chips and filter sheet; letter dividers; triggers jump letters |
| Favourites and notes | `/games/{id}/meta` | The star on spines and the Favourite button (top face button); Your notes |
| Recently played | `/games/recent` | On the go |
| Metadata and pictures | items, `/games/{id}` art | The game's page, the backdrop's attract preview |
| What a game needs | `/games/{id}/check` | State cards in Play's place; "Can't play yet" on spines and cards |
| Unpacking from archives | `/games/{id}/prepare` | Boot: Getting it ready, with progress |
| Versions, archives, discs list | `/games/{id}/versions`, `PUT /version`, `POST /split` | ⋯ → Versions (administrators: which file, split) |
| Console, not a game, review lists | `PUT /console`, `POST /not-a-game`, `/games/review` | ⋯ administrator's tools; Needs a look is a server page |
| Importing and scanning | `/libraries/{id}/games/import` | A progress line under the library's title row, as the website's |
| Cores, custom cores and consoles | `/gaming/...` | Install a core in the no-core state (server page); a custom console is one more shelf, from its own data |
| BIOS files | `bios` in consoles and `/check` | The BIOS state card; ⋯ → Files and advanced lists what's found |
| Graphics-card consoles | `needsGpu` | Its state card |
| Encrypted files | 422 `encrypted` | Its state card; stays listed |
| Starting, resuming, safe mode | `POST /games/{id}/play` `{resume, safeMode}` | Resume, Play, Start over, Start with default settings |
| Connection modes | `/games/modes`, session `modes` | Automatic, with fallback; Use another connection on the error screen; Game settings → Connection |
| Picture shape, rotation, real size | session `aspect`, `turns`; `geometry`, `rotation`, `frame` events | The player draws to them |
| Save states, automatic, undo | slots 1–99, 0, 100, 101; `/saves`, `/thumb`, `DELETE` | Moments, Where you left off, Before you loaded, Before starting over |
| Moving saves | `/saves/{slot}/file`, `/battery` | A moment's Download; ⋯ → Files and advanced (battery save in and out) |
| Save, load, reset, pause | `/play/{sid}/action` | Save a moment, Play from here, Reset the game; the menu pauses |
| Speed, slow motion, frame advance | `speed`, `advance` | Fast-forward tile and shortcut; slow motion and next frame as shortcuts and in Game settings |
| Rewind | `rewind`, `emulation.rewind` | Rewind (held), the tile, the tape bar |
| Undo load | `undo` | A moment that won't load offers Undo load; Before you loaded |
| Change disc | `disc`, session `discs` | Discs in the game menu; Change disc tile |
| Controller type per port | session `devices`, `device` | Seats: the type under each seat |
| Core options, live | `/games/{id}/core-options`, `option` | Mapped ones as sections (Screens, Region, Memory cards); the rest in Game settings → Core options |
| Settings and levels | `/games/settings`, schema, levels | Look's Use it for; Yours on {console}; Settings for this game; Game settings (drawn from the schema) |
| Display presets and bezels | `presets`, `/game-bezels` | Look; Fine-tune → Bezel |
| Custom settings files | `document`, `/validate` | Game settings → Settings file (a keyboard device; a QR card on a TV) |
| Limits | `maxSpeed`, `rewindBytes`, `runAhead` | Speeds offered up to the limit; rewind's seconds |
| Cheats | `/games/{id}/cheats`, import | Cheats in the game menu; ⋯ → Files and advanced → Cheats file |
| Patches | `/games/{id}/patches` | ⋯ → Files and advanced → Patches (adults only) |
| On-screen numbers | `osd.*`, `/play/{id}/stats` | Game settings → On-screen numbers; the O key |
| Speed or steadiness | `emulation.latency`, `0xF5` | Game settings → Speed and rewind |
| Screenshots | `/play/{id}/screenshot` | The Screenshot tile and F8 |
| Messages, rumble, ended, shutdown | events | A toast; the pad rumbles; the states |
| Touch screens | `pad.pointer`, the 6-byte pointer state | Touch on the touch screen; a pointer from the right stick |
| Controls as data | `/consoles/{c}/controls` | Controllers, touch layouts, button hints, the remote's mapping |
| Controller profiles | `/game-profiles` and resolve, copy, export, import | Controllers → scope chips and Profiles |
| Touch layouts | `PUT /consoles/{c}/controls` kind `touch` | Arrange touch controls |
| Background picture | `/game-background` | Controllers → Background; behind the touch controls |
| Shortcuts | `hotkeys.*` | Shortcuts overlay; Game settings → Shortcuts |
| One game per account; idle stop | server rules | The dock; Continue here; the Stopped while away state |
| Game PCs | `console: rig` | A "This PC" shelf that opens Game PCs |
| Server setup for games | `/settings/gaming` | Server page (administrators) |

## Adapts to each core

The game menu, the player, controller setup and touch layouts build themselves from one **capability** object per
console and core, so a new core or console needs data, not new screens. Missing keys mean "no": the section isn't shown.

### The object

On `/games/consoles` for each console (what its usual core does), and on the session for the core actually running
(which wins). Server work: WittyPlay's console tables (`controls.go`, `traits.go`) hold the console's part, and what
the running core reports fills in the rest (whether it can save states, its controller types, its options).

```json
"capabilities": {
  "screens": {
    "count": 2, "touch": 1, "aspect": "4:3",
    "layouts": ["stacked", "side", "big", "single"], "swap": true, "gap": true,
    "options": { "layout": "melonds_screen_layout", "stacked": "Top/Bottom", "side": "Left/Right",
                 "big": "Hybrid Top", "single": "Top Only", "swap": "melonds_swapscreen_mode" }
  },
  "input": {
    "ports": 2, "multitap": 4, "sticks": 2, "analogTriggers": true,
    "pointer": "touch", "motion": true, "keyboard": false, "mic": false
  },
  "media": { "discs": true, "memoryCards": 2, "bios": "optional", "region": { "option": "pcsx_rearmed_region" } },
  "play": { "rumble": true, "rewind": true, "fastForward": true, "slowMotion": true, "cheats": true,
            "runAhead": true, "patches": "single-file" },
  "picture": { "aspect": "4:3", "integer": true, "look": "scan", "turns": 0 }
}
```

- `pointer`: `touch` (a touch screen: DS, 3DS), `lightgun` (aim and fire: light guns on NES, PlayStation and others),
  `mouse` (relative movement), or absent.
- `screens.options` maps WittyPlay's layout names to the core's own option values. Today these are core options (melonDS:
  `melonds_screen_layout`, `melonds_swapscreen_mode`, `melonds_screen_gap`, `melonds_touch_mode`; Azahar:
  `citra_layout_option`, `citra_swap_screen`, `citra_large_screen_proportion`). Until the server sends `screens`, the app
  keeps this table in `shared/data/wittyplay-capabilities.json`.
- The session's `discs` and `devices` stay as they are and fill Discs and Seats.

### What reads it

| Part of the UI | Reads | Shows |
|---|---|---|
| Player | `screens`, `picture` | One picture or two screens; their layout and gap; which takes touch; aspect and whole pixels |
| Touch on the picture | `input.pointer` | Touch: the stylus. Light gun: a tap aims and fires (the trigger is the game's fire button). Mouse: drag moves, tap clicks. None: a tap shows the bar |
| Game menu tiles | `play.rewind`, `play.fastForward`, `screens.swap`, session `discs` | Rewind, Fast-forward, Swap screens, Change disc |
| Game menu sections | `screens.count`, session `discs`, `media.memoryCards`, `input.ports`, `input.multitap`, session `devices`, `media.region`, `play.cheats` | Screens, Discs, Memory cards, Seats with controller types, Region, Cheats |
| Controller setup | `pad` (from `/controls`), `input.sticks`, `input.analogTriggers`, `input.pointer`, `input.motion` | The drawing, analog sticks and triggers, light-gun calibration, motion ("Tilt this phone": its gyroscope, where the core takes motion) |
| Touch layout | `pad`, `screens.touch`, `input.pointer` | Its controls, keeping the touch screen clear; a crosshair for a light gun |
| Seats | `input.ports`, `input.multitap`, session `devices` | How many seats, "With a multitap", controller types |
| Look | `picture.look`, `picture.integer` | The console's default Look; Whole pixels only |
| Keyboard | `input.keyboard` | For computers with keyboards (not among today's consoles): the system keyboard over the picture, and a physical keyboard passes through |
| Moments | `play` (whether states can be saved) | Save a moment; for a core that can't, "This core can't save moments" and battery saves only |

### Examples

| Console | Screens | Input | Media | Play |
|---|---|---|---|---|
| NES | 1, 4:3, whole pixels | 2 ports, multitap 4, light gun | — | Rewind, cheats, run-ahead; Scanlines |
| SNES | 1 | 2 ports, multitap 5, mouse, light gun | — | Rewind, cheats; Scanlines |
| N64 | 1 | 4 ports, stick first, analog | — | Rumble; Clean |
| Game Boy, Color, Advance | 1 | 1 port | — | Rewind; Handheld LCD |
| DS | 2, touch on the bottom | 1 port, touch, microphone | BIOS optional | Rewind, cheats; Handheld LCD |
| 3DS | 2, touch on the bottom | 1 port, stick, motion | — | Graphics card; Clean |
| PlayStation | 1 | 2 ports, multitap 8, DualShock, light gun, mouse | Discs, 2 memory cards, region, BIOS optional | Rumble, rewind, cheats; CRT TV |
| PlayStation 2 | 1 | 2 ports, analog sticks and triggers | Discs, memory cards per game, BIOS required (LRPS2) | Graphics card; Clean |
| Mega Drive, Master System | 1 | 2 ports, light gun on Master System | — | Rewind, cheats; Scanlines |

(Port counts and devices come from each core; the table is what to expect, not a rule.)

## Input, for every screen

Every screen works by touch, game controller, TV remote and keyboard, and shows hints for the one in use (the last one
touched, as the website's `useInputKind` does). Touch shows no hints.

### Per screen

| Screen | Touch | Controller | TV remote | Keyboard |
|---|---|---|---|---|
| Home (Shelves) | Tap a spine to pull it; tap again or Resume to play; swipe a shelf; long-press a spine to peek its last moment | D-pad or stick moves along and between shelves; confirm pulls, confirm again plays; top button favourite; left button search; bumpers jump shelves; triggers jump letters; Start plays the focused game | Swipe or clickpad moves; OK pulls then plays; Play/Pause plays the focused game; long-press OK: More | Arrows move; Enter pulls, Enter plays; F favourite; / search; PgUp/PgDn shelves; a letter jumps to it on A to Z |
| Eras | Drag the timeline | ◀ ▶ a year at a time, bumpers an era | Swipe | ← → years, PgUp/PgDn eras |
| Channels | Swipe up and down | ▲ ▼ channels; confirm plays | Channel up and down, or swipe; OK plays | ↑ ↓; Enter |
| A game | Tap | Confirm on Resume; top button favourite; Back | OK; Back | Enter; F; Esc |
| Boot | Cancel | Back cancels | Back cancels | Esc cancels |
| Playing | The touch layout; the menu button; the touch bar | The game has every button; Select + Start or the pad's home button opens the game menu; Select + a button for shortcuts | The remote is a fallback pad (D-pad, OK as A, Play/Pause as B); **Back opens the game menu** | The keyboard layout; Esc opens the game menu; shortcuts below |
| Game menu | Tap | Moves and confirms; Back or the menu chord resumes | Moves; OK; Back resumes | Arrows; Enter; Esc resumes |
| Two screens | Touch the touch screen; Swap | The right stick moves a pointer on the touch screen, R3 presses it; Select + top button swaps | — (a remote can't play a touch game; the menu says so and offers to join from a phone) | Mouse on the touch screen; Tab swaps; F6 next layout |
| Controllers | Tap a row, then press | Choose a row, then press | Choose, then press on a pad | Choose, then press a key |

### TV remote (Siri Remote, Android TV remote)

- **Focus** moves with the clickpad's swipes and clicks (Siri Remote) or the D-pad (Android TV); **select** is the
  clickpad's click or the centre button; **Back** is ‹ (or Menu on older Siri Remotes) and the Back key; **Play/Pause**
  plays the focused game straight away.
- **In a game**, the remote is a fallback pad from `/consoles/{c}/controls` → `defaults.remote` (D-pad moves, OK is A,
  Play/Pause is B). **Back opens the game menu and is never a game button**, so the game never loses an input it needs.
  The menu has Press Start and Press Select, and a Note: "This game wants a controller for {buttons}" when the console
  has more than the remote can reach.
- The TV/Home button stays the system's.

### Game controller

- **The whole interface is drivable from a pad**, on phones and tablets too: focus appears the moment a pad is used,
  with the ring (3 wide, 3 out on a phone; 4 and 4 on a TV) and a prompt bar above the floating bar.
- **Confirm and back follow the pad's family:** pads labelled A at the bottom confirm with the bottom button; pads
  labelled A on the right confirm with the right one (as the website's `tv.ts` maps them); shape-labelled pads confirm
  with the bottom one.
- **The game menu:** Select and Start together always; the pad's home button where the platform passes it to the app
  (`GCController` `buttonHome` when the system doesn't keep it; Android `KEYCODE_BUTTON_MODE`); Options alone never, as
  games use it.
- **Hints match the connected pad.** The family comes from the platform (`GCController.productCategory` and
  `GCDevicePhysicalInput` on Apple; vendor and product on Android, against the server's `/game-controllers` table), and
  gives each button's label: A/B/X/Y in their places, the shoulder and trigger names (LB/RB and LT/RT, L/R and ZL/ZR,
  L1/R1 and L2/R2), and View/Menu, −/+ or Select/Options. Drawn as our own glyphs (see Legally distinct). An unknown pad
  gets position only. **Button hints** in Controllers can choose position only everywhere.

### Touch

- In a game: the touch layout, the menu button, the touch bar; on two screens, the touch screen.
- In menus: tap; swipe along shelves; long-press a spine to **peek** (its last moment's picture rises above it with
  Resume, Moments, Favourite); drag the timeline; swipe channels; pull the game menu's sheet up to see all of it.

### Keyboard

On the website, the desktop apps, and an iPad, Android tablet or phone with a keyboard. **?** shows the shortcuts
overlay anywhere; Game settings → Shortcuts changes the in-game ones (`hotkeys.key.*`).

| In menus | Key |
|---|---|
| Move | Arrows |
| Open; pull a spine | Enter |
| Back | Esc |
| Search | / |
| Favourite | F |
| Next or last shelf, era | PgDn, PgUp |
| First, last | Home, End |
| Jump to a letter on A to Z | The letter |
| Shortcuts | ? |

| Playing | Key | Pad (hold Select, then) |
|---|---|---|
| Game menu | Esc | Select + Start, or the pad's home button |
| Save a moment | F2 | R2 |
| Play from the newest moment | F4 | L2 |
| Rewind (hold) | Backspace | L |
| Fast-forward (hold) | Space | R |
| Slow motion | B | top button (X/Y by family) |
| Pause | P | left button |
| Next frame | N | → |
| Screenshot | F8 | right button |
| Mute | M | — |
| On-screen numbers | O | — |
| Full screen | F11 (browser and desktop apps) | — |
| Swap screens | Tab | top button |
| Next screen layout | F6 | — |
| Change disc | F7 | — |

Game keys always win: a shortcut never takes a key the game's layout uses (the server's rule), and Tab, F6, F7 and F11
are new shortcuts for the server's `hotkeys.key.*` list.

### Focus, order and labels

- Focus follows reading order: title row, Where you left off, On the go, then shelf by shelf, left to right. It starts
  on the screen's main action (Resume) and comes back where it was left, after a game too.
- Focus is always visible with a pad, remote or keyboard, and never shown for touch.
- Every control has a spoken label: "Thwaite, NES, in progress", "Resume Super Tilt Bro., last played yesterday on Living
  room TV", "Seat 2, Ann, light gun", "Look, Scanlines, chosen", "Swap screens, Tab".

## Themes

Every server theme works, through APP-DESIGN's translation.

- **The picture is the one fixed colour:** a game's letterbox is black in every theme, as video is.
- **Cover colour:** deep (`hsl(h, min(s, 62%), 26%)`) on a dark theme, pale (`hsl(h, min(s, 70%), 84%)`) on a light
  one, as the website's `useCoverTint`, for the page's glow and the TV's preview. **Spines and collection cards keep the
  deep tint** (with the 38% minimum) and white words on every theme, so they read as objects on a shelf, not panels.
- **High contrast:** grain off; ledges and card outlines `text` at 40%.
- **Accent** marks the primary action, ribbons, the chosen Look, a held touch button, the rewind track and the current
  boot step; nothing else.

## On a tablet and Vision Pro

The phone's screens with more room; gutter 32.

- **Home:** Where you left off 560×315 beside On the go (two columns in landscape); spines 44–60 wide, 220 high (170
  handheld); face out 160×213.
- **A game:** at 700 wide and over, two columns: box, title, actions, Where you left off, How you play it on the left (360);
  Moments, About, Pictures, More like this on the right.
- **Playing:** sideways is the main way; touch controls in the margins at 100%. Two screens side by side by default.
- **The game menu** is always the split.
- **Vision Pro:** the tablet's layout in a window; the game's picture can be pulled out as its own window, keeping its
  aspect. A controller is the way to play; without one, the touch controls are a panel under the picture, pressed by
  looking and pinching, with a Note that a controller plays better.

## On a TV

Apple TV and Android TV look **identical**. Sizes in TV units (APP-DESIGN's On a TV). Gutter 90. Focus is the 4-wide `text`
ring 4 out, concentric, and 1.06; rows leave room for it.

### Shelves on a TV

As the prototype's TV screen:

- **Top bar** (APP-DESIGN) 24 from the top, fading to 35% when focus is below the second shelf.
- **The preview** (the top 420, from 112): the focused game rises here. On the right, its attract preview at 560×420
  (radius large) in its Look; on the left, "{console} · {era}" in 20 semibold Caption, the title in 64 bold (letters
  −1.4), facts in 24, Where you left off in 22 with an `accent` dot, then **Resume** (or Play) and **More** as 66-high
  pills. It follows focus after 140 ms, so flicking along a shelf doesn't flicker it. **Focus starts on Resume.**
- **Shelves** from 560, in a clipped area above the prompt bar: Continue playing as 360×270 cards with ribbons and
  captions; then each console's shelf with its heading in the era's type at 26–28, spines 66×300 (232 handheld), the
  first face out 228×300. Focused, a spine lifts 28 and grows 1.06 inside the ring; the shelf scrolls to keep it in view
  and the shelves move up so the focused one sits under the preview.
- **Prompt bar** along the bottom, 72 high: the input's hints, 36 apart (a remote: OK Open, Back Back, Play/Pause Play
  now, Hold OK More; a pad: the pad's labels for Open, Back, Favourite, Search, and the bumpers for Shelves; a keyboard:
  the keys, and ? Shortcuts).
- **Leave it on:** after two idle minutes on this screen, Channels takes over full screen; any press brings back the
  shelves with the game that was showing in focus.

### A game on a TV

The backdrop's attract preview across the whole screen, darkened from the left; on the left 45%: "{console} · {era}",
the title 48 bold, facts 24, then **Resume**, **Moments**, Favourite and "⋯" as pills, Resume focused; Where you left off
as a line. Below: Moments (304×228), About, How you play it (pills: Look, Seats, Controls, Rewind), More like this.

### Playing and the game menu on a TV

The picture at full height on black; nothing else. **Back opens the game menu** as the split: the picture card on the left
55% with the title in 38 and the seats; on the right (640 wide), Resume focused, the tiles 2×2 (296×120, icon 32 over
24), Moments 240×180, Screens and Discs as on the phone at TV size, Look 200×150, Seats 140, rows 72 high: Controllers,
Game settings (a QR card to the server's page), Press Start, Press Select, Reset the game, Save and quit; Multiplayer
sits greyed under the seats and focus passes over it. Back resumes.

### Seats on a TV

The TV is where people gather, so its Seats screen leads with joining: the code in 96 monospaced boxes and the QR card at
280 on the left, the four seat cards (2×2, 360×200) on the right. Phones that join a game shown on a TV are controllers
("Controller only") by default.

## On the website

The website's games pages take everything marked **→ web**, so there is one design.

### At phone width

Identical to the phone above (APP-DESIGN's one mobile design). The website's player is the phone's.

### At desktop width

- **Home:** Shelves, wider: Where you left off 640×360 beside On the go; spines 48–64 wide, 240 high; the page's colour as
  today. Hover lifts a spine 4; click pulls it.
- **A game:** two columns, at most 1200 wide.
- **Playing:** the picture centred at full height; the game menu as the split, 420 wide on the right; keyboard shortcuts
  shown on each tile; ? for the overlay.
- **Couch mode** (`/big`) becomes the TV layout, prompts included.

### What the website's games pages change into (→ web)

| Today | Becomes |
|---|---|
| Library: cover flow, then Consoles as text tiles, then rows | **Shelves**: Where you left off, On the go, a shelf per console with spines, Made for two, A to Z with dividers, Channels |
| Console view (`?console=`) | A **collection**: the band, its era's type, Yours on {console} |
| Game page: Play, star, ⋯ centred; How it plays; Save states list | APP-DESIGN's item layout with the attract backdrop, Resume / Favourite / ⋯, Where you left off with its ribbon, Moments, How you play it |
| Game menu tiles over the game | The picture card, Resume, tiles with their shortcuts, and sections built from the capabilities (Screens, Discs, Memory cards, Seats with types) |
| Display presets in Settings → Picture | **Look** with previews and the level chips |
| Quick save writes one slot | Save a moment takes the next free slot |
| Controller screen: Players tab | **Seats**; button hints by the pad's labels or position |
| Couch mode | The TV layout, prompt bar and Leave it on |
| Start: a spinner | The boot: steps, then the switch-on |
| No sign of a game on another device | **The dock**, Continue here |
| Keyboard shortcuts in Settings only | The **?** overlay everywhere |

## Server work

Nothing here blocks the first native build: everything marked "exists" in the prototype's notes ships first.
Multiplayer needs nothing: it's reserved and shown greyed out.

1. **Capabilities** per console and per running core (see [Adapts to each core](#adapts-to-each-core)), on
   `/games/consoles` and the session, with the core-option mapping for screens and the layout names.
2. **The running game:** `GET /games/playing` → `{id, itemId, title, console, startedAt, device: {id, name, kind},
   seats}` or 204; a device sends its name and kind with play; a `moved` event names the device that took over.
3. **Moments' names and devices:** `PUT /games/{id}/saves/{slot}` `{name}`; `name` and `device` in the list; quick save's
   "next free slot" (`states.quickSlot: 0`).
4. **Rewind by default** for 8-bit, 16-bit and Pocket consoles within the administrator's limit, and a `rewind` event with
   the seconds kept.
5. **Eras and years:** `era`, `launched` and `ended` per console; `era=` on `/items` and facets.
6. **Made for two** as a `players` shelf in `/games/home`.
7. **Seats for other profiles:** `POST /play/{sid}/invite` → `{code, expires}`; `POST /play/join`; seat tokens; a `seats`
   event; the host can free a seat; saves stay the host's. Adults and Kids join with the code, Guest only with the code.
8. **More input:** a motion state message (gyroscope and accelerometer, for cores with motion), a light-gun flag on the
   pointer message (aim plus trigger), and a relative mouse message.
9. **Shortcuts:** swap screens, next screen layout, change disc, and full screen in `hotkeys.*`; touch-bar keys in touch
   layouts; a Smooth preset; per-console default Looks.
10. **Attract clips:** the game's metadata video, when a metadata source has one, served like its pictures.
11. Later: screenshots into the person's Photos library, games in `/review`, soundtrack and booklet matching.

## States

Each takes Play's place on a game's page (a state card: `panel`, radius large, 14 inside, an icon in a 36 circle tinted
18% of its colour, the headline in 15 semibold, what to do in 13, small buttons), on every device; the same words come
from a refused start in the player. On a TV: 24 and 20, a 48 circle, pill actions. On shelves the spine or card carries
"Can't play yet".

| State | From | Says | Actions |
|---|---|---|---|
| **No core** | `/check` `reason: core`; 409 `needCore` | "This server can't play {console} games yet" · "It needs a core for this console. Ask whoever runs the server." | Administrators: **Install a core** |
| **BIOS needed** | `reason: bios`, `bios[]`; 409 `needBios` | "{console} games need a BIOS file" · "From a console you own. Put it in a folder named `BIOS` inside your {console} games folder." Each file, needed or found | **Try again**. Never where to get one |
| **Needs a graphics card** | `needsGpu` and a refused start | "This game needs a graphics card" · "Its console is drawn with one, and this server has none it can use." | — |
| **Not playable here** | console `unavailable` | The server's words | — |
| **Encrypted** | 422 `encrypted` | "This game file is encrypted" · "WittyPlay plays unencrypted copies only. Nothing here decrypts a file, so this one will never start." | None; it stays listed |
| **Getting it ready** | `prepare` | "Unpacking from its archive · {done} of {total}", or "Waiting for other games to unpack" | Cancel |
| **Busy** | 503 | "The server is busy" · "It's running as many games as it allows. Try again when one finishes." | Try again |
| **File gone** | 404 | "This game's file has gone" · "It was moved or deleted. Put it back, or scan the library again." | — |
| **No picture** | no frame on any mode | "The picture can't reach this {device}" · "The game started on your server, but its picture isn't getting through. A firewall or the network is usually why. The game waits a minute for you." | **Try again**, Use another connection, "Leave. Your game is saved." |
| **Reconnecting** | the connection drops | The last frame at 35%, "Reconnecting…"; within 60 seconds it comes back by itself | Leave |
| **The game stopped** | `ended` | "The game stopped" · the server's words · "Your last moment was saved." | **Resume**, Start with default settings, Leave |
| **Moved** | `moved` | "This game moved to {device}" | Continue here, Leave |
| **The game ended itself** | `shutdown` | Back to the game's page, toast "The game ended" | — |
| **Stopped while away** | 30 minutes without input | "Stopped after 30 minutes without a press, and saved." | Resume |
| **A remote and a touch game** | `pointer: touch` on a TV with only a remote | "This game needs touch. Join it from a phone or tablet." with the join code | Join from a phone |
| **Can't save moments** | a core without states | "This core can't save moments. The game saves itself as it normally would." | — |
| **Guest and Kids** | 403 | Guest: no uploads; Kids: no patches. Rows hidden, not greyed | — |
| **A PC's game** | `console: rig` | Plays through Game PCs | Opens it there |
| **Loading a page** | — | APP-DESIGN's grey shapes: spines as grey strips on a ledge | — |
| **No games yet** | empty library | "No games here yet" · "Add a games folder in Libraries." | Administrators: the button |

A moment that won't load leaves the game as it was and says so, with **Undo load**.

## Access

- Every control has a spoken label (see Input). The game picture is "Game picture, {title}" and isn't read further.
- Seats always show their number as well as their colour; ribbons are also said ("in progress").
- Type follows Dynamic Type and Android's font scale everywhere except the player's touch controls, which follow the
  touch layout's sizes. Spine titles scale too; spines widen to fit.
- Reduce Motion: see Motion with meaning. Fast-forward and flicker carry the server's cautions; flicker stays off.
- Sounds are never the only sign of anything.

## Decisions

Confirmed by the user on 5 November 2026:

1. **Shelves is the games home.** The Timeline is the Eras page inside it; Channels is the TV's Leave it on mode and a
   row on the phone's home.
2. **The words** are Shelf, Spine, Collection, Era, Made for two, Moment, Where you left off, Look, Seat, Channel, Leave
   it on, Continue here and Game menu, as under [Words](#words). They go into `strings.en.json` and the website as they
   are, and change only together.
3. **Button hints** show the connected pad's own labels, drawn in WittyPlay's style (letters, and shapes as plain
   outlines in the theme's colour) with no maker's colours or artwork. **Position only** stays as a setting, and is what
   a pad that can't be identified gets.
4. **Seats:** other adults and Kids profiles join someone's game with a code; Guest only with a code; saves stay with
   the host. Same-account joining ships first with today's API.
5. **Rewind is on by default** for 8-bit, 16-bit and Pocket consoles (20 seconds, within the administrator's memory
   limit).

Defaults that stand: one WittyPlay home per games library, as today; menu sounds off until turned on; haptics following
the system.

## Checking a build against this

For each screen, at phone, tablet and TV sizes and in a light and a dark theme, compare a screenshot with the prototype
and this page: sizes, colour roles, the words' keys, focus on a TV, and the legal list at the top. Drive every screen
with each input: touch, a pad of each family, a TV remote, a keyboard; check hints match and focus is always visible.
Switch the game menu through a one-screen, a two-screen and a disc console and check it builds from the capabilities
alone. Then play the openly licensed demo games through the whole flow on the local server: pull a spine, boot, rewind,
save a moment, change the Look, quit, resume on another device.
