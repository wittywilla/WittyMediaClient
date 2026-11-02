# What the owner needs to do

Things only you can do, in the order they make sense. Nothing here has been done for you: no accounts,
no signing and no publishing. Prices are what these programmes have charged and may have changed, so
check the sign-up page before paying.

## Decisions

These change what gets built. Each has a recommendation.

1. **Windows 7.** Supporting it means a second desktop app, frozen on a 2022 browser engine that stopped
   getting security fixes in October 2023. *Recommendation: don't. Windows 7 users can use a browser.*
   See [the design](DESIGN.md#windows-7).
2. **The app's ID.** Android and Apple use `com.wittywilla.wittymediaclient`. Once published it can never
   change, so say now if you want something else.
3. **The name people see.** Every app is "WittyMediaClient". The Xcode project and its targets are still called WittyMedia, which
   nobody sees.
4. **Artwork.** Every app needs an icon, and TVs need a wide banner too.

## Step 1: Let CI build the apps

CI builds the Android and Apple apps on GitHub's computers. Android's build and tests have already passed on this machine. For the Apple
apps this is the first time their code will ever be compiled. **Expect failures the first time**: fixing them is normal.

The native apps need the `client-contract` branch merged too, or they can't connect. Nothing here pushes
or merges, so that's your call. The simplest way is to ask your main Claude session to merge both
branches and push them, once you're happy.

Pushing runs Android's build on GitHub's machines, which accepts the Android SDK licence terms there on
your behalf. Read them at <https://developer.android.com/studio/terms> if you want to check first.

GitHub Actions is free for public repositories. For a private one, the Mac builds use your free minutes
quickly.

## Android on this machine

**Nothing to do here.** You decided, and accepted Google's Android SDK licence (`android-sdk-license`), and the tools are installed in WSL at
`~/android-sdk`. They take about 12 GB, plus 3.6 GB for an Android 6 image added to test the oldest version the app supports, under that same
licence. Any Claude chat can build the APKs and run them on emulators, and the `dev` user is already in the `kvm` group.

Nothing else has been accepted, and `sdkmanager` here doesn't ask first: it installs and accepts by itself. Google TV, Play, preview and ARM images
come under other licences and aren't installed, so a chat has to read a package's licence before installing it. Some older images are under a
preview licence too, such as the Android 8, 9, 10 and 11 TV images and the Android 9 phone image.

## Step 2: Try Android (free, no account)

Once CI is green:

1. On GitHub, open the repository's **Actions** tab, then the latest **wittymediaclient** run.
2. Under **Artifacts**, download **wittymedia-android-sideload**, and unzip it to get an `.apk` file.
3. Put it on the device:
   - **Phone or tablet:** copy it over and open it. Android asks you to allow installing from that app.
   - **Android TV, Google TV, Fire TV:** in Settings, turn on Developer options and network debugging
     (the menu differs by device). Then, from a computer with Android's `adb` tool, run the two commands
     below, using your device's address.

```bash
adb connect 192.168.1.50
```

```bash
adb install app-sideload.apk
```

This build is signed with a throwaway key. It's for testing only, and can't be updated to a store version
without uninstalling first.

**Please check on a real device and report back:** does it start, connect, sign in, and play? Are the
remote and focus usable? Is it smooth, and is there sound? Those two couldn't be checked on an emulator. A cheap TV stick is the most useful test there is.

Connecting is your main requirement and it has only run on emulators, where finding a server goes through network translation, so these matter most:

1. With a server running on the same network, does it appear by itself under "On your network"?
2. On a TV, is it already highlighted, so one press of OK chooses it? Does it stay put once you've moved?
3. On the server's web page, open your name, choose **Sign in a TV**, press **Get a code**. Can you
   type the six digits with only the arrows and OK, and does it sign you straight in?
4. Type a wrong code. Does it say so in plain words and let you try again?
5. Close and reopen the app. Does it go straight to the home screen?
6. Change the server's address (restart it on another port, or let the router give it a new one), then
   reopen the app. Does it find the server again?

The music player needs a real device too, as emulators make no sound:

7. Play an album, turn the screen off, and wait for the next song. Is there sound all the way, with no gap you'd mind?
8. Use the lock screen's buttons, and headphone or Bluetooth buttons if you have them. Does a phone call pause it?
9. On a TV, press Home while it plays. Does the card on the home screen open the app? On the emulator its Open button did nothing, because of the system.
10. Play an audiobook for a minute, close it, and reopen it on another device. Does it say Resume, and go to the same place?

## Step 3: Try Apple (needs a Mac)

Apple only allows building and installing from a Mac. **Everything that can be done without one has been. Nothing
further can be checked until these steps run.**

**First, the quick check, which needs no Apple account.** It takes about 20 minutes, most of it Xcode building, and
touches nothing but the folder it runs in.

1. Install **Xcode** from the Mac App Store (free), open it once, and let it finish installing its parts.
2. In Terminal, install the tool that makes the Xcode project, if you don't have it. This needs [Homebrew](https://brew.sh).

```bash
brew install xcodegen
```

3. Get the code onto the Mac. If the branch has been pushed, clone it as usual. If not, make a single file of it on the PC, in the repository's
   folder, copy that file over by USB or a shared folder, and open it on the Mac:

```bash
git bundle create WittyMediaClient.bundle clients-ui-audit
```

```bash
git clone -b clients-ui-audit WittyMediaClient.bundle WittyMediaClient
```

4. Run the check:

```bash
bash WittyMediaClient/apple/scripts/check-on-mac.sh
```

5. Send back the folder it names at the end, `apple/build-logs`. It holds a report, every build's log, and a picture of each app's first
   screen. **Expect compile errors:** this code has never met Apple's compiler. Fixing them from those logs is the next job, and it
   can be done from Windows, one run of this script at a time.

**Then, once that builds, on your own devices:**

1. Install **Xcode** from the Mac App Store (free), and open it once.
2. In Terminal, install the tool that creates the Xcode project: `brew install xcodegen`. This needs
   [Homebrew](https://brew.sh).
3. In the `apple` folder, run `xcodegen generate`, then open
   `WittyMedia.xcodeproj`.
4. In Xcode's settings, under **Accounts**, add your Apple ID.
5. Choose a target such as **WittyMedia-tvOS**. Under **Signing & Capabilities**, pick your team.
6. Pair your device. For Apple TV: on the TV, go to Settings, Remotes and Devices, Remote App and Devices.
   In Xcode, open Window, Devices and Simulators.
7. Choose the device at the top of the window and press Run.

A free Apple ID should be enough to run your own builds, but they expire after about a week. The first
launch asks permission to find devices on your network, and should be allowed.

**The Top Shelf on Apple TV needs one more thing.** The app and its Top Shelf share a folder through an App
Group, `group.com.wittywilla.wittymediaclient`, which belongs to your signing team:

1. In Xcode, select **WittyMedia-tvOS**, then **Signing & Capabilities**, and check the App Groups box has that
   group ticked. Press the refresh button beside it if it's red.
2. Do the same for **WittyMedia-TopShelf**, and pick your team there too.

It isn't known whether a free Apple ID can do this. If it can't, delete the two
`com.apple.security.application-groups` entries from `apple/project.yml` and generate the project again. The
app works the same, with an empty Top Shelf.

**On iPhone and iPad, please check:** that Music, a book, photos, a DVD's menu and the TV guide each open inside the app, signed in, and that the
system's Back and the swipe from the edge both get out of them. Download a photo's original, and see that it's in Files, under this app.

**Please check on an Apple TV and report back:** nothing here has ever run, so all of this is open.

1. Does the Siri Remote move through everything, with focus always visible? Try swiping and clicking the clickpad.
2. Does Back ever quit from the middle of signing in? It should only leave from the top of a tab.
3. Scan the QR code on the sign-in screen with a phone. Does it open the server's page with the code filled in?
4. Play something. Does the TV switch to the film's frame rate and HDR, does Back leave the player, and does a
   5.1 file have 5.1 sound? Do the Audio and Subtitles menus work?
5. Leave the app with something playing, then come back. Is the place kept?
6. Put the app in the top row of the Home screen. Does the Top Shelf show what you were watching, and does choosing it
   open that thing, signing in first if needed?
7. Open Music, choose an album and a track. Does sound play, and does the next track follow by itself?
8. Open Photos and a photo. Do left and right on the remote go through them, and does Back leave?
9. Choose TV guide and a channel, with a channel made on the server. Does the picture start, and does Back leave it?

**Before submitting to Apple:** the app needs an icon and a Top Shelf image in an asset catalog, which don't exist
yet, and the iPhone app's background audio will need explaining: it's there for picture in picture.

## Step 4: Publish, when you're ready

Only worth doing once the apps work on real devices.

| Store | Cost | Reaches |
|---|---|---|
| Apple Developer Program | About $99 a year | App Store and TestFlight, for all Apple devices |
| Google Play Console | About $25, once | Android phones, tablets, Android TV, Google TV |
| Amazon Appstore | Free | Fire TV |
| Microsoft Store | Optional | Windows |
| LG, Samsung | Free developer accounts, as far as is known | webOS and Tizen, when those clients exist |

**Signing keys.** Android needs a signing key made once, kept private and backed up. If it's lost, you
can't update the app, unless you use Google's Play App Signing, which is recommended. Never put a key in
this repository: `.gitignore` already refuses `*.key` files.

**Windows and Mac warnings.** Unsigned desktop apps trigger security warnings when opened. Removing them
needs a code-signing certificate (Windows) or the Apple programme (Mac).

**Store reviews.** Both Apple and Google ask for a way to test a media app. You'd need to give reviewers a
working server, or a demo mode, which doesn't exist yet. Apple also asks why the app uses plain HTTP on the
local network and needs local network access. The reason is that home media servers run that way.

**Consoles.** PlayStation, Xbox and Nintendo all need you to apply to and be accepted by a developer
programme, usually as a company. Nothing can be built until then.

## Check the desktop installers

These ran for real under Wine and in Linux containers, and only a person with the machine can do the rest.
[INSTALLING.md](INSTALLING.md) says what each step should do.

**On a real Windows (a Windows Sandbox or a spare account is enough):**

1. Build it with `npm run package:win` in `desktop/`, or take the setup from a release.
2. Run `wittymediaclient-<version>-windows-amd64-setup.exe`. Choose **Only for me**, then the default folder. Check the desktop
   shortcut and the Start menu entry, and that the app opens and connects.
3. In **Settings > Apps > Installed apps**, find WittyMediaClient and uninstall it. Answer **No** to the question, and check
   `%APPDATA%\WittyMediaClient` is still there.
4. Install again, **Anyone who uses this computer** this time. Windows asks for an administrator. Uninstall, answer **Yes**, and
   check that `%APPDATA%\WittyMediaClient` and `C:\Program Files\WittyMediaClient` are gone.

**On a Mac:**

1. Take the `.dmg` for your chip from a release, or run `npm run package:mac` in `desktop/`.
2. Open it. Check that the window shows the app, Applications and the uninstaller without anything overlapping, and drag the app across.
3. Open the app, using **Open Anyway** in **System Settings > Privacy & Security**, and connect to a server.
4. Quit it, and run **Uninstall WittyMediaClient.command** from the `.dmg`. Check the list it shows, type `yes`, and check that the
   list is gone. If something of the app's stays in `~/Library`, tell your main Claude session its name so it can be added.

**Signing.** Until these are signed, Windows and macOS warn on every download. For Windows, a code-signing certificate; for
macOS, the Apple Developer Program and its notarising. Then set electron-builder's `CSC_LINK` and `CSC_KEY_PASSWORD` secrets in the
release workflow, remove its `CSC_IDENTITY_AUTO_DISCOVERY: 'false'`, and remove `identity` and `hardenedRuntime` from `mac` in
`desktop/package.json`, which make the stand-in signature an unsigned Mac build needs. Ask your main Claude session to make that change when you
have them.

## FreeBSD and Plasma Bigscreen, on real hardware

Both have run in virtual machines here, so this is the part that hasn't: [PLATFORMS.md](PLATFORMS.md#freebsd-plasma-bigscreen-and-linux).

**A TV box running Plasma Bigscreen:** install the `.rpm` or `.deb`, and try it from the sofa with the TV's own remote.

1. Is it readable from where you sit? Is anything cut off at the edges of the TV?
2. Does the remote's Back button work at all? KDE warns that many TVs keep Back and Home for themselves.
3. Is video smooth? Nothing here has tried hardware decoding.

**A FreeBSD desktop:** `sudo pkg install ./wittymediaclient-*.pkg`, then start WittyMediaClient from your desktop's menu. Does it play with sound? Then try `wittymediaclient --uninstall`.

**To list it in FreeBSD's own packages,** someone would need to submit a port, and to list it on Flathub, someone would need to make and submit a Flatpak. Neither needs doing first.
