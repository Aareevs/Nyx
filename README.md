<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/readme/logo-dark.svg">
    <img src="docs/assets/readme/logo.svg" width="160" alt="Nyx logo">
  </picture>
</p>

<h1 align="center">Nyx</h1>

<p align="center">
  A menu bar utility and Dynamic Island for your Mac.<br>
  Install only what you use.
</p>

<p align="center">
  <sub>Nyx is a fork of <a href="https://github.com/vorssaint/vorssaint-utils">Vorssaint</a> by <a href="https://x.com/vorssaint">@vorssaint</a>, released under the same GPL-3.0 license. Credit for the foundation goes to them.</sub>
</p>

<p align="center">
  <img src="docs/assets/readme/panel-mixer.png" width="196" alt="Volume mixer with per app sliders, one app boosted past 100 percent">
  <img src="docs/assets/readme/panel-system.png" width="196" alt="System tab with temperatures, usage graphs and memory pressure">
  <img src="docs/assets/readme/panel-controls.png" width="196" alt="Window controls with the app switcher and Dock features">
  <img src="docs/assets/readme/panel-utilities.png" width="196" alt="Utilities with cleaner, media tools and clipboard">
</p>

Per app volume, a real system monitor, a better app switcher, window snapping, Dock previews, clipboard history, text snippets, a file shelf, an uninstaller. The utilities Mac users usually buy one by one, together behind a single menu bar icon, with no account, no telemetry and no subscription.

## Install only what you use

Choose individual features or start with a preset. Uninstalled features stop loading and disappear from the interface; reinstalling restores their settings. Setup asks only for the permissions your choices need.

<p align="center">
  <img src="docs/assets/readme/features-hub.png" width="720" alt="The Features hub in Settings, installing and uninstalling whole features">
</p>

Reorder or hide panel sections, choose a compact layout, and export settings to another Mac.

<p align="center">
  <img src="docs/assets/readme/settings-general.png" width="720" alt="General settings with appearance, language and the Menu bar folder">
</p>

## Everything it does

### Sound

- **Volume mixer.** Set volume per app, boost quiet audio past 100%, and pin or reorder favorites. No audio driver required.
- **Per app output.** Play music through speakers while a call uses your headset.
- **Output switcher.** Switch audio outputs with a shortcut and lower the volume when headphones disconnect.
- **Microphone tools.** Choose a preferred input, adjust its level on supported devices, and apply available microphone mute or input-volume controls with one shortcut. Siri and some apps may still hear you; Mic Mute is not a privacy lock. Its indicator shows that the feature is on, not that every app receives silence.
- **Music app blocker.** Prevent unwanted Music launches after detected playback-button presses. Requires Accessibility.

### Know what your Mac is doing

- **System monitor.** CPU, GPU, memory, temperatures, battery health and power use, with history graphs and a view of energy-hungry apps.
- **Menu bar readouts.** Put your chosen readings, usage bars, or battery time directly in the menu bar.
- **Network.** See live traffic, session totals and your local IP address, or run a speed test.
- **Alerts.** Get notified about sustained CPU load, high temperatures, memory pressure, low disk space or low battery.

### Windows and the Dock

- **App switcher.** Switch between apps and windows with live previews, search and display filters. A simpler mode works without screen capture.
- **Window layout.** Snap windows into layouts, move them between displays and restore earlier positions using shortcuts, screen edges or modifier-drag gestures.
- **Dock Preview.** Hover over Dock icons to preview windows across desktops. Switch, close, move or snap them from the preview.
- **Dock clicks.** Click an active app's Dock icon to minimize, hide or cycle through its windows.
- **Maximize windows.** Use the green button to fill the screen without creating another Space.
- **Fixed Space order.** Keep Spaces in the order you set instead of rearranging them by recent use. Turning it off restores your previous setting.
- **Quit on close.** Quit selected apps when their last window closes.
- **Quit and close protection.** Prevent accidental ⌘Q or ⌘W with a hold, double press or extra modifier, per app.

### Keyboard and mouse

- **Text snippets.** Expand short triggers into text with clipboard, date and time variables, or insert snippets from a searchable menu.
- **Smooth scrolling.** Give your mouse wheel a fluid glide with adjustable speed and response.
- **Pointer acceleration.** Disable mouse acceleration and restore your previous setting when turned off.
- **Linear scrolling.** Make every mouse wheel notch scroll the same number of lines, however fast the wheel spins.
- **Focus follows mouse.** Bring the window under the pointer forward after an adjustable pause.
- **Scroll direction.** Invert vertical and horizontal mouse scrolling independently of the trackpad.
- **Scroll sideways while holding a key.** Turn vertical wheel movement into horizontal scrolling while holding a chosen key.
- **Side buttons.** Use mouse Back and Forward buttons in Finder, browsers and compatible apps.
- **Mouse button shortcuts.** Assign keys to extra buttons and side wheels, or use button-drag gestures for Spaces and Mission Control.
- **Middle click.** Turn a three-finger trackpad press into a middle click.
- **Apps to leave alone.** Exclude chosen apps from mouse enhancements.
- **Extra click filter.** Ignore accidental rapid clicks from worn mouse buttons without delaying normal clicks.
- **Key debounce.** Filter repeated letters caused by a worn keyboard.
- **Super key.** Use Caps Lock or a right-side modifier as a shortcut combination, with a separate tap action and app exclusions.
- **Keyboard shortcuts.** Manage feature shortcuts in one place, including optional takeover of supported macOS shortcuts while a feature is active.

### Clipboard, files and links

- **Clipboard history.** Search local text, image and file history, pin favorites, preview entries and paste with shortcuts.
- **Auto clear clipboard.** Clear the system clipboard after a delay, sleep or lock, while keeping saved history.
- **Paste as plain text.** Paste without formatting while preserving the original clipboard content.
- **Shelf.** Park files, text and links near your cursor while dragging, then drop or share them later.
- **Finder shortcuts.** Move files with ⌘X and ⌘V, rename with F2, or paste copied images as PNG files.
- **Clean URL.** Remove tracking parameters from links, manually or automatically.

### Everyday tools

- **Dynamic Island.** Keep music (with your Spotify playlists), notifications, calendars, timers, downloads and everyday controls around the camera cutout, or a simulated one on other Macs. Customize sections and shortcuts, with optional lyrics, a live equalizer, camera preview and file tools.
- **AI agents.** Follow Claude, Codex, OpenCode, GitHub Copilot and Antigravity in the Dynamic Island: plan limits and when they reset where available, tokens, API value, models, projects and live work, with a notice when a long task finishes. Codex's banked resets can be used from there too, and each extra Codex account (`CODEX_HOME`) can have a limits card of its own. Copilot uses local CLI/app session logs; its token totals update when shutdown metrics arrive, and aggregate API-value estimates use base rates.
- **Command Bar.** Search apps, windows, files, clipboard history, snippets and app menu commands from one field. Calculate, convert units, find emoji or run saved scripts.
- **Quick panel.** Open a floating palette of favorite tools with ⌃⌘V.
- **Quick toggles.** Switch appearance, hide desktop icons, eject disks, empty the Trash, lock the screen and more.
- **Quit apps.** See every open app in one list and quit them one by one, all at once or all but the one in front.
- **Radial menu.** Open a customizable wheel of apps, files, shortcuts and tools around the pointer, with profiles and submenus.
- **Scratchpad.** Keep autosaved notes in tabs, with Markdown preview and export, in a floating window or Dynamic Island.
- **Cleaning Mode.** Lock keyboard input while cleaning, with a black screen or a small visible indicator.

<p align="center">
  <img src="docs/assets/readme/island-music.png" width="400" alt="The Dynamic Island showing the music player">
  <img src="docs/assets/readme/island-spotify.png" width="400" alt="Choosing a song from your Spotify playlists in the island">
</p>
<p align="center">
  <img src="docs/assets/readme/island-agents.png" width="400" alt="AI agent usage for Claude and Codex in the island">
  <img src="docs/assets/readme/island-tools.png" width="400" alt="The island's page of tools and shortcuts">
</p>

### Capture and create

- **Screen capture.** Switch between screenshots, recording, text recognition and color picking in one selector with a pixel magnifier.
- **Screenshot.** Capture an area, window, screen or scrolling page. Annotate, crop, redact, add backgrounds and watermarks, pin captures, and send them through the Share menu.
- **Screen recording.** Record with separate system-audio and microphone tracks. Trim, cut, add automatic zooms, blur private details and export video or GIFs.
- **Camera preview.** Check your camera in a floating mirror or Dynamic Island before a call.
- **Copy text from screen.** Recognize text offline from any screen area, or read a QR code.
- **Color picker.** Copy a screen color as HEX, RGB, HSL or SwiftUI code.
- **Media tools.** Compress and edit videos, batch-convert images, add watermarks, make GIFs and extract text, all locally.

### App management

- **App updates.** Check store apps and supported developer feeds in one list, and open an app's own updater.
- **Cleaner.** Remove caches, logs and app leftovers, manually or on a schedule.
- **Messaging downloads.** Review, organize or move messaging downloads to the Trash using retention rules.
- **Uninstaller.** Remove apps and review their related caches, preferences and helpers before moving them to the Trash.

### Energy and display

- **Keep awake.** Keep your Mac working on a timer, with the lid closed, or while selected apps, power or external displays are present.
- **Displays.** Control individual displays and brightness, with hardware control where supported, half or quarter steps for the brightness keys, optional extra dimming below a monitor's minimum, and software dimming as a fallback.
- **Extra brightness.** Use a MacBook Pro XDR display's HDR headroom to go beyond its normal maximum brightness.
- **Bluetooth on sleep.** Disconnect Bluetooth during sleep and restore it on wake only if Nyx turned it off.

## Install

1. Download `Nyx-<version>.dmg` from the [latest release](https://github.com/Aareevs/Nyx/releases/latest).
2. Open it and drag **Nyx** into **Applications**.
3. Open Nyx. The first time, macOS blocks it, because Nyx is not signed with a paid Apple Developer ID. Go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**.
4. Allow only the permissions the features you want ask for.

To update, download the new `.dmg` and drag Nyx into Applications again, replacing the old one. Your settings and permissions stay. macOS may ask for **Open Anyway** once more.

## Uninstall

To remove Nyx completely, including its settings and permissions:

```sh
./Tools/uninstall.sh
```

## Private by default

Nyx is local-first, with no account, analytics or tracking. The network is touched only by things you can see: the speed test, optional online lyric lookup and the app update check for other apps you run yourself. The full story is in the [privacy notes](docs/PRIVACY.md).

Permissions get the same treatment. Every one is optional, the app explains each in plain words, shows which features actually use it, and even tells you when a permission you granted is no longer needed by anything, with a shortcut to revoke it.

<p align="center">
  <img src="docs/assets/readme/permissions.png" width="720" alt="The Permissions page showing what each permission does and which features use it">
</p>

See the [permissions guide](docs/PERMISSIONS.md) for which features need access and what remains available without it.

## What you need

- A Mac with Apple Silicon
- macOS 14 Sonoma or newer

### Build it yourself

```sh
cd path/to/nyx
./build.sh --dev            # build the separate Developer variant
./build.sh --dev --install  # install and launch it
./build.sh --install        # build and install the regular Nyx app
./Tools/make-release.sh     # package dist/Nyx-<version>.dmg to share
```

Xcode Command Line Tools are the only requirement.

## When something misbehaves

See [troubleshooting](docs/TROUBLESHOOTING.md) for launch problems, permissions and missing previews.

## Documentation

- [Privacy](docs/PRIVACY.md), what does and does not leave your Mac
- [Permissions](docs/PERMISSIONS.md), every macOS permission in plain words
- [Troubleshooting](docs/TROUBLESHOOTING.md), the common fixes

## What's new in Nyx

Nyx started from the open-source [Vorssaint](https://github.com/vorssaint/vorssaint-utils) and has since gone its own way. These are the things it has that Vorssaint does not:

- **Spotify playlists in the island.** Sign in once and browse your playlists, open one, and tap a song to play it on Spotify without opening the app. The login uses PKCE, so no secret is stored, and the login is kept in a private file only your account can read. **Choosing songs needs a Spotify Premium account.** Spotify only lets apps pick what plays for Premium users, so on a free account you can browse your playlists but not play from them.
- **Time and weather on the island.** The closed island shows the time on the left and the weather, with an emoji, on the right. The weather uses your approximate location if you allow it (Open-Meteo, no account).
- **Calculator in the island.** A new section with three modes: basic arithmetic (powers, roots, fractions), trigonometry (sin, cos, tan, csc, sec, cot and their inverses, in degrees or radians), and calculus (derivatives, integrals, complex numbers, factorials). Shortcut ⌥⌘K.
- **Menu bar folder.** Collapse the menu bar icons you rarely use into one folder, and click through to them without leaving the bar.
- **Antigravity usage.** The AI agents section reads Antigravity's conversations and shows its token use, models and cost, with its own card and the Gemini mark.
- **Claude limits fixed up.** Claude plan limits are read more reliably, and limit bars now default to showing how much you have used.
- **Copy image** on Recent Captures and on the Shelf, so a screenshot goes straight to your clipboard.
- **Downloads show their date.** Each finished download in the island lists when it was saved.
- **Back buttons on the Tools page** in the island, and on the tools that open from the menu panel, so you are never stuck inside a tool.
- **Smoother, lighter app.** Fan Control, Kill Process, Port Manager, Disk Image Installer, Homebrew management, the self-updater, feedback and link sharing are gone, along with the extra languages (English only), so there is no privileged helper and far less code to trust. The source is about 20% smaller.

## Credits

Nyx is built on [Vorssaint](https://github.com/vorssaint/vorssaint-utils), an open-source macOS utility by [@vorssaint](https://x.com/vorssaint). The original idea, structure and a large part of the code come from that project, and it is where to look for the upstream version. Everything under "What's new in Nyx" above was added on top by [Aareevs](https://github.com/Aareevs).

## License

[GPL 3.0 or later](LICENSE). Nyx is a modified version of Vorssaint, copyright 2026 Vorssaint, with Nyx's own changes copyright 2026 [Aareevs](https://github.com/Aareevs). As the license requires, the source stays open under the same terms. The Vorssaint name, logo and look are not part of this license (see the original [TRADEMARKS.md](https://github.com/vorssaint/vorssaint-utils/blob/main/TRADEMARKS.md)), and Nyx uses its own name, icon and identity.
