# Platforms

It's one app on every platform, but how you control the connection and which permissions it needs differ from platform to platform. How VPN mode differs from Proxy mode is explained on the [Modes](/en/modes) page.

## Android

Android 7.0 or newer. Each release has two APKs: the regular one and `armeabi-v7a` for 32-bit firmware.

### Connecting and disconnecting

You can connect and disconnect:

- with the button in the app;
- with the “Connect” and “Disconnect” buttons in the notification;
- with the Quick Settings tile;
- with the home screen widget;
- with the “Connect” and “Disconnect” shortcuts that appear when you long-press the app icon.

The notification can show speed and connection time: “Behaviour” → “Notifications”.

If the VPN was on, it turns itself back on after an app update and after the phone restarts.

### Permissions

All permissions except VPN are gathered on the “Permissions” screen in “Advanced” settings. It shows what has been granted and where to change it.

| Permission | What it's for |
|---|---|
| VPN | VPN mode; the system asks for it on the first connection |
| Notifications | the VPN status notification and subscription update notifications |
| Unrestricted background work | without it the system may not let you turn the VPN on from the notification shade |
| Autostart | a firmware setting; without it the VPN may not turn on from the shade and may drop in the background |
| Camera | scanning QR codes |
| Install apps | installing updates |

### If the VPN drops in the background

Open “About” → “App log” → “Why the app was closed”. It lists the system's own records: when the firmware stopped the app, when memory ran out, when there was a crash or an update. The button at the top of the screen copies the whole log, send it to the [chat](https://t.me/keqdroid) along with your question.

## Android TV

Same APK. The app is controlled with the remote. To mark servers for Auto, hold OK on the “Auto” button.

It's easier to send a subscription from your phone than to type the address with the remote:

1. On the TV, open “Servers” → add menu → “Receive from phone”. The TV shows a QR code.
2. On the phone, in keqdroid, tap “Scan QR code”, point the camera at the TV screen and pick the subscription.

The phone sends the subscription over your home network, so both devices must be on the same Wi-Fi network. If the phone says the code has expired, reopen the receive screen on the TV.

## Windows

Windows 10 and 11, x64. Each release has a `setup.exe` installer and a portable `zip`.

| | Installer | Portable |
|---|---|---|
| where it goes | Program Files, with a Start menu shortcut and, if you want, a desktop one | any folder |
| updating from the app | the new version is installed by the installer, without its windows | files are replaced in the same folder |
| uninstalling | “Apps” in Windows Settings | delete the folder |

Both versions use the same settings in `%APPDATA%\com.keqdroid\keqdroid\`, so only one of them can run at a time. When uninstalling, the installer stops the cores, removes the system proxy, autostart and the `keqdroid://` link handler, and asks whether to delete settings, subscriptions and logs as well. By default they are kept.

### Modes

In Proxy mode the app sets the system proxy itself, no admin rights needed. TUN mode does need admin rights: the app offers to restart with them, and your chosen mode is kept.

### Tray and autostart

These settings are in the “Windows” section:

| Setting | What it does |
|---|---|
| “Minimize to tray on close” | the close button hides the window to the tray instead of quitting |
| “Start with Windows” | the app starts when you sign in |
| “Start with admin rights” | autostart with the rights TUN needs |
| “Start in the tray, without a window” | no window opens on autostart |
| “Connect on autostart” | after autostart the app connects to the selected server |

The tray icon menu lets you connect or disconnect, pick a server, switch between Proxy and TUN, open the window and quit.

The window remembers its size and position.

### Hotkeys

Hotkeys are set in “Advanced” settings, in the “Hotkeys” section. They can connect and disconnect, switch between TUN and Proxy, move to the server with the best ping, and show or hide the window. On Windows they work from any window, even when the app is in the tray.

Ctrl+V adds links from the clipboard on the “Servers” tab and a subscription on the “Subscriptions” tab.

## Linux

x86_64, distributions on par with Ubuntu 22.04 and Debian 12 or newer.

| Package | For |
|---|---|
| `.deb` | Debian, Ubuntu, Mint |
| `.rpm` | Fedora, openSUSE |
| `PKGBUILD` | Arch: build it with `makepkg -si` in its folder |
| `.AppImage` | any distribution, no installation |
| `.tar.gz` | any distribution: unpack and run |

The packages install the app so that only root can change its files.

### Modes

In Proxy mode the app writes the system proxy into GNOME and KDE settings. Firefox picks it up from there in any desktop environment. In other environments, set the address `127.0.0.1` and the port in your programs manually.

TUN mode needs root: when you connect, the app asks for your password through `pkexec`. If you turn on “Passwordless TUN” in “Permissions”, the app installs a polkit rule once and stops asking for the password.

### Tray and autostart

The “Linux” section has “Minimize to tray on close”, “Start at login” and “Connect on autostart”.

With “Minimize to tray on close” on, the close button doesn't quit the app: the window hides to the tray, or gets minimized if there is no tray. In Hyprland, Sway, niri and river the window is simply hidden. Ctrl+Q quits the app.

On Linux, hotkeys only work while the app window has focus.

## Backup

“Advanced” settings have “Backup & restore”. It saves four sections to a file and restores them from a file, and you can pick each one separately:

| Section | What's inside |
|---|---|
| Split Tunneling | the app lists |
| Subscriptions | subscriptions along with their card images |
| Servers (and active server) | servers and which one is selected |
| App settings | routes, routing profiles, core, DNS, ping, appearance and language settings |

The backup leaves out what belongs to the specific device: connection mode, TUN settings, LAN Proxy, the local proxy password, autostart, tray and hotkeys. A restored section fully replaces the current data. When restoring, you pick the file first and then the sections from it.
