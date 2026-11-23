# TV settings parity with the desktop Settings

Every setting in the server's desktop Settings (WittyMediaServer `web/src/pages/SettingsPage.tsx` and its pages under
`web/src/pages/settings/`, the Appearance page, the SDUI routes for modules' settings), what the Android TV and Apple TV
apps showed for it before 0.8.2-alpha, and what they show now. The TV level is the server's (`docs/TV-MODE.md`,
`pkg/sdui/data/tvlevels.json`): **full** works with a remote, **view** shows the values, **desktopOnly** is a card that
says to use the WittyMediaClient app on a computer or a web browser, with the address and a QR code.

Issue: wittywilla/WittyMediaClient#72. Target: 0.8.2-alpha.

## How the TV apps draw them

The pages a TV now draws itself are described once, as data, in [`shared/data/tv-settings.json`](../shared/data/tv-settings.json):
each page in the shape of a module's settings (the server's `docs/SDUI-MODULES.md`: pages, groups, rows of kind `bool`,
`enum`, `int`, `info`), with where each value is kept. Both apps draw them with the module-settings rows they already
had, in their own TV settings design (Android TV: `DesignScreen` rows with the ring and lift, Apple TV: `SettingsScreen`
and `ListGroup` rows with the focus lift):

- a switch row says On or Off and a press changes it;
- a choice row opens its options (chips on Android TV, a list on Apple TV);
- a number has − and + with the row's step (Activity's history: 50 tasks a press);
- a **view** row is its value, still a stop for the remote, and the page says once at its top where it is changed;
- a **desktopOnly** row says "On a computer" with its current value where there is one, and opens the card with the
  address and QR code. Back leaves the card, so there is no dead end.

Each change is saved as it is made, through the endpoints the server's own pages use, so a change on the TV is the same
setting on every device:

| Store | Read | Written | What |
|---|---|---|---|
| `server` | `GET /api/settings` | `PUT /api/settings` with the changed keys | The administrator's settings for the whole server |
| `ui` | `GET /api/me/ui` | `PUT /api/me/ui` with everything there now plus the change (as `web/src/ui/userPrefs.ts`) | The profile's own choices, on every device |
| `streaming` | `GET /api/me/streaming` | `PUT /api/me/streaming` with `{home, away}` | The profile's video quality |
| `about` | `GET /api/about` | (read only) | The version and modules |

Words are keys in `shared/data/strings.en.json`, the apps' translation file (they ship English; the language names in
Language are each language's own). Code: Android `net/TvSettings.kt` and `ui/TvSettingsScreens.kt`, Apple WittyKit
`TvSettings.swift` and `App/TvSettingsViews.swift`; tests `TvSettingsTest.kt` and `TvSettingsTests.swift` check that
every word has a key, every row has a store, and that changes are sent as the web sends them.

## Summary

| | Pages and settings |
|---|---|
| **Added as full** (TV controls) | Video quality (2 choices), Skipping and content (7 switches, 10 choices), Appearance's motion (2 switches) and language (2 choices, administrators), Activity (1 switch for everyone; 1 switch, 2 choices and 2 numbers for administrators) |
| **Added as view** (values shown) | Playback (3 settings), Sharing and photos (8 settings), About (version and every module's version), the time zone |
| **Desktop only, with the note and QR code** (rows added) | Pages and menu, Network, Data folder (new rows); in pages: Make a theme, Import a theme, Your colours, Colours for everyone, Name and logo (with the name), Video quality limits, Clear the activity history, Your links, Updates, Licenses and formats |
| **Already there** | Theme and Look, Names, Password, Two-step sign-in, Devices, Profiles (where the server has parental controls), Module settings, Remote control and watch parties, Playing here (this device's skipping and canvases), the desktopOnly cards for Libraries, Metadata, Channels and tuners, Live and Library transcoding, Remote Access, WittyLog, WittyDiagnoser, Modules, Backup, Repair and Reset |

## The table

"Before" is what the app showed for the page on a TV before this change: **web** is the server's own page inside the
app in its TV mode (Android TV only), **card** the QR card, **phone card** Apple TV's "Open this on a phone or computer"
card (tvOS has no web view), **native** the app's own screen, **none** no row at all.

### Server (administrators)

| Page | Setting | Kept in | TV level | Android TV before | Apple TV before | Now (both) |
|---|---|---|---|---|---|---|
| Libraries | Libraries, folders, grouping, removing details | `/libraries`, `/settings` | desktopOnly | card (Manage libraries) | SDUI page | unchanged (card / SDUI page) |
| Pages and menu | Home, library and title pages, the menu, own pages, presets, drafts, history | `/sdui/…` | desktopOnly | none | none | **row added**: card |
| Metadata agents | Built-in agents, anime, saving information, custom agents | `/settings` | desktopOnly | card | card | unchanged |
| Playback | Fastest playback speed | `server` maxSpeed | view | web | phone card | **view** |
| Playback | TV episode layout | `server` episodeView | view | web | phone card | **view** |
| Playback | Streaming for viewers away from home | `server` remoteStreaming | view | web | phone card | **view** |
| Playback | Streaming on this device | browser only | (device) | web | phone card | not offered: the web keeps it in the browser |
| Playback | Video quality limits for each profile | `/users/{id}/stream-limits` | view | web | phone card | desktopOnly row (a dialog per profile) |
| Playback | Skipping, Content | `ui` autoSkip, contentFilters | full | web | phone card | **full**, in Skipping and content |
| Channels and tuners | Library channels, WittyTV options, tuners, IPTV, guide, bumpers | `/tv/…` | desktopOnly | card | card | unchanged |
| Live transcoding | Direct play, resolution, sound format, hardware encoders, picture quality | `server` | desktopOnly | card | card | unchanged |
| Library transcoding | Rules, Tdarr | `/library-transcoding` | desktopOnly | card | card | unchanged |
| Network | Port, what follows the port | `/network` | desktopOnly | none | none | **row added**: card |
| Data folder | Where the data is, moving it | `/data-folder` | desktopOnly (not in the server's table yet: server PR) | none | none | **row added**: card |
| Remote Access | Limits away from home, sign-in protection, peer to peer | `/remote` | desktopOnly | card | card | unchanged |
| Appearance | Name and logo | `server` brandName… | desktopOnly part | native editor → card | native editor | unchanged, and a row in Appearance with the name |
| Appearance | Language of the pages | `server` uiLanguage | full | web | none | **full** (27 languages) |
| Appearance | Disc menus and sound tracks | `server` audioLanguage, menuLanguage | full | web | none | **full** |
| Appearance | Time zone | `server` timeZone | view (restarts the server) | web | none | **view** |
| Appearance | Colours for everyone, module colours | `/theme/engine` | desktopOnly part | web (part card) | none | **desktopOnly row** |
| Game PCs, WittyRigs, Gaming | The modules' own pages | modules | full (module) | web | phone card | unchanged (the modules' own pages) |

### You

| Page | Setting | Kept in | TV level | Android TV before | Apple TV before | Now (both) |
|---|---|---|---|---|---|---|
| Profiles | People, passwords, limits | `/users`, `/parental` | view | native (parental controls) or web | native or phone card | unchanged |
| Sign-in and security | Your devices | `/sessions` | view | native | native | unchanged |
| Sign-in and security | Two-factor sign-in | `/me/2fa` | view | native | native | unchanged |
| Sign-in and security | Other people's two-factor sign-in | `/users` | view | none | none | not added: a reset is an administrator's action on a computer |
| Video quality | At home, Away from home | `streaming` prefs | full | none | none | **full** |
| Video quality | This device | browser only | (device) | none | none | not offered: the player's Quality menu sets it on a TV |
| Video quality | Limits (your profile, away from home) | `streaming` profile, remote | view | none | none | **view** |
| Appearance | Theme | device / `/me/theme` | full | native | native | unchanged, and linked from Appearance |
| Appearance | Look | `/sdui/config/experience` | full | native | native (with Theme) | unchanged, and linked from Appearance |
| Appearance | Make a theme (colours) | `ui` customTheme | desktopOnly part | web (part card) | none | **desktopOnly row** |
| Appearance | Import a theme | `/themes` | desktopOnly part | web (part card) | none | **desktopOnly row** |
| Appearance | Your colours | `/me/colours` | desktopOnly part | web (part card) | native (Your colours) | **desktopOnly row** (Apple keeps its own screen too) |
| Appearance | Moving posters | `ui` posterTilt | full | web | none | **full** |
| Appearance | Moving backgrounds | `ui` canvases | full | web; Playing here (device) | Skipping and moving pictures (device) | **full** (the profile's), device choice unchanged |
| Appearance | TV mode | browser only | (device) | web | none | not offered: the TV apps are always in it |
| Appearance | WittyTV look and colours | `/tv/settings`, `ui` | full | in the guide | in the guide | unchanged (the guide's own menu) |
| Appearance | Player: control bar, seek bar, chapter marks, hiding, picture, disc subtitle size | browser only | (device) | web; the player's menu | the player's menu | info row: the player's Options menu on the TV |
| Appearance | Edit layout | `/sdui/personal` | desktopOnly part | native → card | native | unchanged |
| Skipping (non-administrators: Appearance) | Skip intros, recaps, credits, adverts, previews, other parts; do as the file says | `ui` autoSkip | full | web; Playing here (device) | Skipping and moving pictures (device) | **full**, in Skipping and content |
| Activity | Show the activity button | `ui` activityHidden | full | web | phone card | **full** |
| Activity | Activity button for everyone, who can see it, who can see statistics | `server` | full | web | phone card | **full** (administrators) |
| Activity | Keep at most, for no longer than | `server` activityKeepCount, activityKeepDays | full | web | phone card | **full** (steppers, administrators) |
| Activity | Clear the history | `DELETE /system/tasks` | full | web | phone card | desktopOnly row (a destructive button, kept off the couch) |
| Sharing and photos | Allow uploads, largest upload, room for each person | `server` | view | web | phone card | **view** (administrators) |
| Sharing and photos | Allow links | `server` shareLinks | view | web | phone card | **view** (administrators) |
| Sharing and photos | Playing on other devices, accounts that control anyone | `server` remoteControl | view | web | phone card | **view** (the switch; the accounts list stays on a computer) |
| Sharing and photos | Watch parties, who can start one | `server` syncplay, syncplayCreate | view | web | phone card | **view** |
| Sharing and photos | Your links | `/shares` | view | web | phone card | desktopOnly row |
| Module settings | Every module's settings | `/sdui/modules/{id}/settings` | full (the module's own levels) | native | native | unchanged |
| My game settings, Controllers | WittyPlay's | WittyPlay | full | web | phone card | unchanged (WittyPlay's own pages) |

### System

| Page | Setting | TV level | Android TV before | Apple TV before | Now (both) |
|---|---|---|---|---|---|
| WittyLog | What is recorded, downloading logs | desktopOnly | card | card | unchanged |
| WittyDiagnoser | Disc and drive checks | desktopOnly | card | card | unchanged |
| Modules | Installing, updating, versions, stores | desktopOnly | card | card | unchanged |
| Backup | On demand, on a schedule, restoring | desktopOnly | card | card | unchanged |
| Repair, Reset | | desktopOnly | card | card | unchanged |
| About | Version and modules | full | web | phone card | **view** (each module and its version) |
| About | Updates (administrators) | full | web | phone card | desktopOnly row |
| About | This server, license, third-party licenses, formats | full | web | phone card | desktopOnly row (long documents) |
| Legal | Terms, notices | full | web | phone card | unchanged |

## Not done here, and why

- **The TV players don't read the profile's skipping yet.** Skipping and content now sets the profile's own choices
  (`/me/ui` autoSkip and contentFilters), which the web player follows on every device. The Android TV and Apple TV
  players still follow this device's own choice (Playing here; Skipping and moving pictures). Making them follow the
  profile's choice is a player change, a follow-up.
- **Device-only settings** (the web's "This device" quality, streaming and player look, TV mode) are kept in the
  browser and aren't settings of the server, so a TV has its own: the player's Options and Quality menus.
- **Other languages.** The apps ship English only (`strings.en.json`); every new word has a key, ready for the apps'
  translation when it comes.
