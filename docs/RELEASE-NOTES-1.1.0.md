# Nyx 1.1.0

## What's new

- **Chat in the island.** Talk to Claude, OpenAI, Gemini or NVIDIA with your own API key, from the island, from its own page (⌥⌘H), or with an optional shortcut (Option+Shift+Space) that attaches the text you have selected. Replies stream in as they are written, code comes in boxes with a copy button, and past chats are kept on your Mac.
- **Send files to Chat.** Attach images, PDFs, Word, Excel (`.xlsx`), CSV and text files with the paperclip, with a preview before you send and the file shown on the message afterwards.
- **YouTube and YouTube Music playlists.** Paste a playlist link and play it inside Nyx with no browser. The island's player has play, pause, next, previous and seek, and an optional YouTube sign-in so your Premium applies.
- **Tap the notch to open it (experimental).** Tap the notch with a fingertip and the island opens. It is off by default, works on supported MacBooks in a lit room, and can miss a tap or open on its own. Adapted from Sentient OS, with thanks.
- **Uninstaller: select all,** and an **optional cleanup offer** when you drag an app to the Trash (needs Full Disk Access).
- **MP4 or MOV** for compressed videos in Media tools.
- **The time of day beside a running timer** on the closed island.

## Bug fixes

- Spotify: a playlist whose songs Spotify withholds now says so, and Play still works.
- Spotify: when Nyx has to start Spotify for you, it opens quietly in the Dock with no window in the way.
- The island's player works for YouTube: pause, next, previous and the seek bar all respond, and the duplicate "Nyx" in the source list is gone.
- Streaks now count a GitHub commit you made today as soon as GitHub lists it.
- The island hides over an app's own full screen on every display and returns afterwards. Mirrored and native notification banners are hidden (including on macOS 26), and the island stays off status items on macOS 27.
- Uninstaller sizes no longer miss folders next to a symbolic link.

## Good to know

- **Reddit streaks are marked by hand.** reddit.com doesn't allow apps to read your streak, so Nyx can't see it. You tap **Mark done** each day and Nyx counts the days you mark. GitHub and LeetCode are read automatically from your public username.
- **Spotify playback needs Spotify Premium,** as before.
- **Tap to open is experimental.** It needs a lit room and a MacBook that exposes the sensors, light touches may not register, and a strong breeze or a bump on the desk can occasionally open the island.
- Fixes for the notch, notification banners and the uninstaller came from the open-source Vorssaint project.
