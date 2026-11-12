# Updates and release signing

New versions are published on the [Releases](https://github.com/Lemonochka/keqdroid/releases) page on GitHub. The app finds out about them by itself and only installs an update if the release is signed with the keqdroid key.

## When the app checks

- at launch;
- when you come back to the app, if more than 6 hours have passed since the last check;
- when you tap “Check for updates” in settings.

Drafts and pre-releases are not offered. When the VPN is on, the request to GitHub goes through the server.

## New version dialog

The dialog has “Update”, “Later” and “Skip this version” buttons. It shows up no more often than set in “Behaviour” → “Tell me about a new version”: every day, every 3 days (the default) or once a week. A skipped version no longer brings up the dialog, but settings still show that an update is available.

## Authenticity check

Every release has a `SHA256SUMS` file with the hashes of all files, and `SHA256SUMS.sig` with its Ed25519 signature. Before installing, the app:

1. downloads `SHA256SUMS` and `SHA256SUMS.sig`;
2. checks the signature with the key built into the app;
3. compares the hash of the downloaded file with the one in `SHA256SUMS`.

If the signature is missing or doesn't match, or the hash is different, the file is deleted and not installed. There are two keys: the main one and a backup kept outside GitHub. The backup key exists so that losing the main one doesn't cut off updates for good.

The full country database on Android is checked the same way: “About” → “Download the full database” downloads `geoip.dat` from the latest release and accepts it only if its hash is signed.

## How an update is installed

| Where | What happens |
|---|---|
| Android | the APK opens in the system installer; the “Install apps” permission is needed |
| Windows, installer | the new version installs over the old one without installer windows, Windows may ask for admin rights; then the app restarts |
| Windows, portable | files in the app folder are replaced, and the app restarts |
| Linux, `.deb` | `apt-get install` through `pkexec`, the system asks for your password |
| Linux, `.rpm` | `rpm -U` through `pkexec`, the system asks for your password |
| Linux, AppImage | the file is replaced in place; if its folder isn't writable, the new version is saved to Downloads |
| Linux, `.tar.gz` | files in the app folder are replaced |
| Linux, Arch | the release page opens, update the package through `PKGBUILD` |
| Linux, app folder not writable | the release page opens |

The app downloads the same kind of file it was installed from: an AppImage updates to an AppImage, a `.deb` to a `.deb`. On Fedora Silverblue, Kinoite, Bazzite and other atomic systems, packages are installed by `rpm-ostree`, so the `.rpm` is just saved to Downloads.

If the VPN was on, it turns back on after the update: on Android after the APK is installed, on a computer after the restart.

## Verify a file yourself

Releases after 0.35.0 are built in GitHub Actions straight from the [keqdroid repository](https://github.com/Lemonochka/keqdroid). You can check that a file was built there with:

```bash
gh attestation verify <file> --repo Lemonochka/keqdroid
```

To check a file's hash against `SHA256SUMS`, run for example:

```bash
sha256sum -c SHA256SUMS --ignore-missing
```

Code signing for Windows is still being set up, so Windows builds are not signed yet.
