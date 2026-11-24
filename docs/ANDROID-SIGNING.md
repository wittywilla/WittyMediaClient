# Android signing and updates

Android installs a new version of an app over the old one, keeping its sign-in and settings, only when three things hold:

1. **The app ID is the same:** `com.wittywilla.wittymediaclient`, for phones and TVs alike.
2. **The signing certificate is the same.** If it differs, Android refuses with "App not installed", "package conflicts with an existing package" or `INSTALL_FAILED_UPDATE_INCOMPATIBLE`.
3. **The versionCode is not lower.** A release always raises it.

## What went wrong up to 0.6.0

Releases 0.5.1, 0.5.2 and 0.6.0 were the `sideload` build, which is signed with the *debug* key of the machine that builds it. Each of GitHub's build machines makes a new random debug key, so each release had a different certificate:

| Release | versionCode | Certificate | SHA-256 |
|---|---|---|---|
| 0.5.1 | 10 | `CN=Android Debug` | `1decb2dcfd22ed519b6dfaf9a3706b55d648a4042c0d98466372a5488034f8eb` |
| 0.5.2 | 11 | `CN=Android Debug` | `9e402407311513ce41de528550d6c87443a9defff0a26944c283635b5d0f039e` |
| 0.6.0 | 12 | `CN=Android Debug` | `6ebfc53ba4a2b27a26b720316d2540aa812cc6f281fe00db8fd54a32e5e1e027` |

The app ID, versionCodes, minimum Android version (6.0, API 23) and the five APKs of each release were all fine. Only the key changed. Those debug keys went with the machines that made them, so nothing can sign an update that installs over 0.6.0 or older. Key rotation (APK Signature Scheme v3) can't help either, because it needs the old key too.

**So the first release with the release key needs one uninstall,** and the sign-in is lost that once. Android keeps the sign-in sealed with a key in the device's Keystore, which an update keeps and an uninstall deletes. Every update after that installs over the last. That release's notes say so at the top, written by the release check below.

## How releases are signed now

- `release.yml` builds the `release` build type, signed with **the release key**: one permanent PKCS12 key, never in this repository. It reads the key from the **`android-release`** environment's secrets, which only version tags (`v*`) can use. Signing is v1 (Android 6), v2 (7 and later) and v3, so the key can be rotated one day without an uninstall.
- **The release key's certificate**, which every release from 0.6.1 on carries, has this SHA-256 fingerprint: `BB:7E:BE:53:9D:37:88:4D:65:B9:7B:9F:01:6B:CA:5D:01:BB:D9:99:80:01:3C:C0:A0:8E:75:7E:FA:A4:ED:72`. Check an APK with `apksigner verify --print-certs <apk>`.
- **No key, no release.** Without the secrets, the "The release key" step fails, and `-PreleaseSigning=required` makes Gradle fail too. A release never falls back to a debug key or a new one.
- **versionCode** comes from the versionName in `android/app/build.gradle.kts`: `(major × 10000 + minor × 100 + patch) × 100`. 0.6.1 is 60100, so the code always goes up with the version. All five APKs of a release share it, so any one can replace another.
- **`sideload`** is still signed with the build machine's debug key, for pull requests and testing on a device. It is never published.

## The release check

Before `publish`, the `android-update` job in `release.yml`:

1. downloads the previous release's universal and x86_64 APKs (`android/scripts/previous-release.sh`),
2. checks each new APK: one signer, not a debug key, all the same certificate and versionCode, the same app ID as before, a higher versionCode, and the same certificate as the previous release (`android/scripts/check-upgrade.sh`),
3. starts an Android emulator, installs the previous release, opens it so it writes its settings, puts a marker file in its data, installs the new APK over it with `adb install -r`, and checks the marker and every settings file are unchanged, the first-install time is the same (an uninstall would reset it), and the app opens and keeps running (`android/scripts/upgrade-test.sh`).

When the previous release was debug-signed, as 0.6.0 was, step 2 lets the change of key through once with a warning, writes the "uninstall once" note into the release notes, and skips step 3. Nothing can update a debug-signed release.

On every pull request, `ci.yml`'s `android-update` job checks the build's versionCode and app ID against the newest release. It also has the emulator reinstall the build over itself and checks the app's data is kept and it opens.

To check by hand, with `ANDROID_HOME` set:

```bash
bash android/scripts/check-upgrade.sh <folder of new APKs> <folder of the previous release's APKs>
```

```bash
OUT=shots bash android/scripts/upgrade-test.sh <old.apk> <new.apk>
```

## Making the release key (once)

Only the owner does this, once. **Keep the key safe:** if it is lost, no later version can update an installed app, and everyone has to uninstall once more.

### The quick way (Ubuntu on Windows, about 2 minutes)

1. Press **Start**, type **Ubuntu**, and open it.
2. Paste this line and press **Enter**. It makes the key in your Documents folder, outside every repository, and gives it to GitHub:
   ```bash
   bash /mnt/d/projects-0.8.0/WittyMediaClient/android/scripts/make-release-key.sh "/mnt/c/Users/$(cmd.exe /c 'echo %USERNAME%' 2>/dev/null | tr -d '\r')/Documents/WittyMediaClient-release-key" --upload
   ```
   It prints the key's fingerprint, then "GitHub has the key", then two secret names. It never shows the password.
   If it says `gh isn't installed here`, follow **By hand on GitHub** below from step 2.
3. Open **Documents › WittyMediaClient-release-key** in File Explorer and copy the whole folder somewhere safe and separate: a USB stick you keep, or a password manager's file storage. Never put it in a repository or send it to anyone.

### By hand on GitHub

1. Make the key with step 2 above, but without ` --upload` at the end.
2. Open <https://github.com/wittywilla/WittyMediaClient/settings/environments> and click **New environment**. Name it `android-release` and click **Configure environment**.
3. Under **Deployment branches and tags**, choose **Selected branches and tags**. Click **Add deployment branch or tag rule**, choose **Tag**, type `v*`, and click **Add rule**.
4. Under **Environment secrets**, click **Add environment secret**. Name: `ANDROID_RELEASE_KEYSTORE`. Value: open `keystore-base64.txt` from the key's folder in Notepad, press Ctrl+A, then Ctrl+C, and paste it. Click **Add secret**.
5. Click **Add environment secret** again. Name: `ANDROID_RELEASE_KEYSTORE_PASSWORD`. Value: the contents of `password.txt`, copied the same way. Click **Add secret**.
6. Back up the folder as in step 3 above.

The next release is then signed with the key. Its `android-update` job shows the key's fingerprint in the run's summary, so you can check it matches the one the script printed.
