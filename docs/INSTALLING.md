# Installing and removing the desktop app

WittyMediaClient for Windows, macOS and Linux comes from the project's
[releases page](https://github.com/wittywilla/WittyMediaClient/releases). The list of checksums there has every
file in it. The builds aren't code-signed yet, so Windows and macOS warn about them: see each section.

| You have | Download | What it is |
|---|---|---|
| Windows 10 or later | `wittymediaclient-<version>-windows-amd64-setup.exe` | The setup wizard |
| A Mac with Apple silicon | `wittymediaclient-<version>-macos-arm64.dmg` | The disk image: drag the app to Applications |
| A Mac with an Intel chip | `wittymediaclient-<version>-macos-x64.dmg` | The same |
| Debian, Ubuntu and relatives | `wittymediaclient-<version>-linux-amd64.deb` | A package |
| Fedora and relatives | `wittymediaclient-<version>-linux-amd64.rpm` | A package |
| Any other Linux | `wittymediaclient-<version>-linux-amd64.AppImage` | One file that runs as it is |

The Mac `.zip` files hold the same app as the `.dmg`, for people who prefer them.

## What it keeps, and where

Settings (the servers you've used and your window size), saved sign-ins, logs and caches. They're yours and
are kept separately for each account on the computer, so removing the program leaves them unless you say otherwise.

| System | Folder |
|---|---|
| Windows | `%APPDATA%\WittyMediaClient` |
| macOS | `~/Library/Application Support/WittyMediaClient` |
| Linux | `~/.config/WittyMediaClient` |

An early build may have left a folder called `WittyMedia` next to it. Removing the app's data removes that as well.

The app adds no startup entry, no address handler and no service. It never holds your films or music: those stay
on your server, and nothing here touches them.

## Windows

**Install.** Open the setup. Windows may say it "protected your PC", because the build isn't signed: choose
**More info**, then **Run anyway**. Choose **Only for me**, which needs no administrator, or **Anyone who uses this
computer**, then the folder. It makes a desktop shortcut and a Start menu entry. Running a newer setup upgrades in place.

**Remove.** **Settings > Apps > Installed apps > WittyMediaClient > Uninstall**, or **Uninstall WittyMediaClient** in the
program's folder. It then asks whether to delete your settings, saved sign-ins, logs and caches too. If you installed it
for everyone, the question covers your own account's data only: other accounts' folders are theirs to remove.

It removes exactly the files it installed. If you put something of your own in its folder, that and the folder stay.

**Without any windows, for scripts:**

```bat
wittymediaclient-<version>-windows-amd64-setup.exe /S
wittymediaclient-<version>-windows-amd64-setup.exe /S /allusers
wittymediaclient-<version>-windows-amd64-setup.exe /S /D=C:\Some\Folder
"Uninstall WittyMediaClient.exe" /S
"Uninstall WittyMediaClient.exe" /S /RemoveData
```

`/allusers` needs an administrator, and the uninstaller needs it too for a copy installed that way. Silently, your
settings stay unless `/RemoveData` is given. `/D=` has to come last and takes no quotes.

## macOS

**Install.** Open the `.dmg` and drag **WittyMediaClient** to **Applications**. The first time, the Mac refuses a build
that isn't signed: in **System Settings > Privacy & Security**, choose **Open Anyway**.

**Remove everything.** Run **Uninstall WittyMediaClient.command**, which is on the `.dmg`. If you no longer have that, it's
also inside the app, so you can run this in Terminal:

```bash
"/Applications/WittyMediaClient.app/Contents/Resources/Uninstall WittyMediaClient.command"
```

It lists what it found and asks before removing anything. Add `--dry-run` to see the list and stop. It looks for:

- `/Applications/WittyMediaClient.app`, and the same in `~/Applications`
- `~/Library/Application Support/WittyMediaClient` and `WittyMedia`
- `~/Library/Caches/WittyMediaClient`, `com.wittywilla.wittymediaclient` and `com.wittywilla.wittymediaclient.ShipIt`
- `~/Library/HTTPStorages/com.wittywilla.wittymediaclient` and the same with `.binarycookies`
- `~/Library/Logs/WittyMediaClient`
- `~/Library/Preferences/com.wittywilla.wittymediaclient.plist` and `.helper.plist`
- `~/Library/Saved Application State/com.wittywilla.wittymediaclient.savedState`
- `~/Library/WebKit/com.wittywilla.wittymediaclient`

The first time you double-click it, the Mac may refuse it for the same reason as the app: right-click it and choose **Open**.
Dragging the app to the Trash removes only the app, and leaves everything else in the list.

## Linux

**`.deb`:**

```bash
sudo apt install ./wittymediaclient-<version>-linux-amd64.deb
sudo apt remove wittymediaclient        # or: sudo apt purge wittymediaclient
```

**`.rpm`:**

```bash
sudo dnf install ./wittymediaclient-<version>-linux-amd64.rpm
sudo dnf remove wittymediaclient
```

Both bring in the libraries the app needs and add the `wittymediaclient` command and a menu entry. Installing a newer
package upgrades in place. Removing takes away everything on the system, including the menu entry, the command and any
security profile the package added. A plain `apt remove` and a purge do the same, since it has no system-wide settings.

**A package can't reach anyone's home folder**, so removing it leaves your settings, and it says so. To remove yours:

```bash
rm -rf ~/.config/WittyMediaClient ~/.config/WittyMedia
```

The system's own libraries, which many programs share, may also have made `~/.cache/fontconfig`, `~/.cache/mesa_shader_cache*`
and `~/.local/share/pki/nssdb` when the app ran. They aren't the app's, so nothing here removes them.

**AppImage:** make it executable and run it. To remove it, delete the file, then run the same command.

## For developers

In `desktop/`:

```bash
npm ci --ignore-scripts
npm run package:win      # or package:linux, package:mac
```

The results go in `desktop/out/`. Windows needs building on Windows, and `.dmg` on a Mac. `.rpm` needs the `rpm` tool. A
version tag builds them all: see `.github/workflows/release.yml`.

`scripts/test/installers-linux.sh` and `scripts/test/installers-wine.sh` run the packages for real in throwaway
containers, and compare the file system and registry from before and after. Both say at the top how to call them.

**What the tests can't prove.** Wine isn't Windows, and nothing here can run a Mac. On a real Windows, check the wizard, the
question when uninstalling, both ways of installing, and Add or Remove Programs. On a real Mac, check the `.dmg` window and run
the uninstaller. [OWNER-STEPS.md](OWNER-STEPS.md) has those steps.
