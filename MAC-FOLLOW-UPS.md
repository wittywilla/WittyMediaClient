# Mac and Linux follow-ups: TV levels

Written 2026-11-18 with WittyMediaServer #469 (what a TV offers: the server's TV levels, its `docs/TV-MODE.md`).
Android TV was done on the PC. Nothing below was run; each item needs a Mac or Plasma Bigscreen.

**For Claude on the Mac:** work through this list, tick items off, and delete this file once it is empty.
Merge nothing and don't release or tag without the owner's OK.

## Apple TV (tvOS)

1. Decode `tvLevels` from `GET /sdui/catalog` (screens by address, with `:name` and a trailing `*`, first match
   wins; parts by id), as `android/.../net/TvLevels.kt` does. Keep the old behaviour when it is missing.
2. Wherever tvOS shows `OpenOnPhone` or `ModuleOnPhonePage` for a server page, decide by the table instead: a
   `desktopOnly` screen is the card; anything else the app can draw itself is drawn. Console and gaming screens
   (controllers, mapping, game settings) must never be the card.
3. The card: the table's `note` as its words, the address, the QR code, and the lines of
   `GET /sdui/tv-summary/{summary}`. When the server address is one only the TV can reach, use the first of the
   summary's `addresses` in the QR code. Focus starts on Back; Menu leaves.
4. An SDUI page whose rendered document says `page.tv` = `desktopOnly` or `view` is the card (with the page shown
   read only under it for `view`). Module settings pages and rows with `tv` show their values read only on tvOS.
5. The app's own editors on tvOS (layout, name and logo, making a canvas, if tvOS has them) are the card when the
   parts `app.layout-editor`, `app.brand-editor` and `title.canvas` are `desktopOnly`.
6. iPhone, iPad and the Mac app keep every screen: only tvOS follows the table.

## Plasma Bigscreen

7. Plasma Bigscreen shows the server's own pages with `?tv=1`, so it follows the table without changes. Check on
   the real shell: open You, then Libraries, Live transcoding and Channels and tuners; each should be the card with
   Back focused, and Back (Escape from the remote) should return. Open Controllers and My game settings: both should
   work fully with a pad.
8. The desktop app started with `--tv`: the same check on Linux, Windows and macOS. Started without `--tv` it must
   still open every editor.
