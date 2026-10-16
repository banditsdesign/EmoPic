# EmoPic - Emoji Picker for macOS

A free, open-source emoji picker that lives in your menu bar and supports Slack-style colon shortcuts.

## Features

- **Menu Bar Picker**: Click the menu bar icon to open a searchable emoji picker (native macOS menu)
- **Slack-style Shortcuts**: Type `:smi` in any app's text field and a suggestion popup appears at the caret — navigate with `↑`/`↓`, insert with `Enter`/`Tab` or click (requires Accessibility permission, granted once)
- **Skin Tone Support**: Pick your preferred skin tone for hand, person, and other emoji
- **Light & Dark Mode**: Automatically follows your system appearance
- **Frequently Used**: Your most-used emoji rise to the top
- **Launch at Login**: Optional auto-start when you sign in (toggle in Settings)
- **Auto-Update (optional)**: Check GitHub for a new release weekly — off by default — and install it with one click when you approve. See [PRIVACY.md](PRIVACY.md) for what a check sends
- **Categories & Search**: Browse by category or search by name/alias
- **Keyboard Navigable**: `↑`/`↓` to move, `Enter` or `Tab` to insert, `Esc` to back out — the picker needs no mouse
- **Custom Descriptions**: Right-click any emoji to attach your own words — search and `:colon:` suggestions match them instantly, and your text shows as the emoji's tooltip. Manage them all in Settings → Custom Descriptions

## How It Works

### Menu Bar Picker
Click the **double-chevron** (`chevron.up.2`) icon in your menu bar to open the picker window or its dropdown menu (Open Emoji Picker, Settings…, Quit). Search or browse categories to find the emoji you want.

### Slack-style Shortcuts
Type `:smi` in a text field **in any app** and a suggestion popup appears at the caret with matching emoji. `↑`/`↓` move the highlight, `Enter`/`Tab` or a click inserts the highlighted pick, `Esc` dismisses. You can still just keep typing the full `:smile:` and the closing `:` confirms the top match — the pattern is swapped for the emoji by deleting it with synthetic backspaces and pasting with ⌘V (the clipboard is saved and restored). The paste-based swap is what makes it work everywhere, including the apps whose Accessibility text APIs are unreliable or silently refuse writes — Messages, Pages and Word. The monitor is a system-wide event tap: characters always type through, and the swap only ever replaces text the monitor itself buffered (it flushes on every click, arrow key, shortcut and app switch), so nothing you typed can be lost — worst case the literal pattern stays visible. Grant Accessibility access when prompted (System Settings → Privacy & Security → Accessibility); the feature activates without relaunch. Excluded apps (set in Preferences) and secure password fields are skipped — a focused secure field is detected and never deleted into. The popup can be turned off in Settings → Colon Shortcuts to leave only the closing-`:` inline behaviour.

### Custom Descriptions
Right-click an emoji in the picker (grid or search row) and choose **Edit Description…** to attach free-form text — e.g. tag 🙋 with “bob, office mascot”. Every word joins that emoji's keywords: picker search, the `:colon:` suggestion popup, and the closing-`:` replacement all match them from the next keystroke, and the text replaces the built-in name as the emoji's tooltip/label. Custom keywords are keyed to the base emoji (skin-tone variants inherit them) and are stored locally in your preferences — never in the dataset, never leaving your machine. Review, edit inline or delete them in **Settings → Custom Descriptions**. If a keyword exactly equals a built-in shortcode, yours wins.

### Keyboard Shortcuts
- `⌥⌘E` - Toggle the emoji picker window (global hotkey, works in any app — presets configurable in Settings)
- `⌘,` - Open Settings
- `⌘Q` - Quit EmoPic

Inside the picker window — the whole thing is usable without a mouse:

- `↑` / `↓` - Move through the results. In the 4-wide category grid vertical keys step a whole row (so you land on the emoji directly below); `←` / `→` step one cell
- `Enter` or `Tab` - Insert the highlighted emoji. Skin-tone emoji open the tone chooser first, exactly as a click does
- `Esc` - Clear the search field; press it again with the field empty to close the picker

### Privacy
- **No telemetry — and no network unless you ask.** The emoji dataset is bundled inside the signed app bundle. EmoPic makes no connection whatsoever until you turn on *Automatically check for updates* (off by default) or press *Check for Updates…* yourself; then the only traffic is one request to GitHub for the release feed, plus the download if you choose to install. No identifiers, no system information, no analytics.
- The colon-shortcut monitor uses a system-wide keyboard event tap, but keystrokes are examined **in memory only** — never logged, stored, or transmitted. At most the current `:shortcode` fragment (ASCII) is held, and it is discarded the moment you switch apps, press a modifier combo, or the pattern dies.
- Password fields (secure input) and apps on your exclusion list are skipped, and a replacement only happens after EmoPic verifies the selected text matches exactly what you typed.
- Full details — every value EmoPic stores, where it lives, and how to erase it — in [PRIVACY.md](PRIVACY.md).

## Architecture

```
EmoPic/
├── App/                    # App entry point, lifecycle
├── MenuBar/                # Menu bar status item, menu
├── Picker/                 # Emoji picker SwiftUI view
├── Emoji/                  # Emoji data model, loading, categories
├── Shortcuts/              # Colon shortcuts (session CGEventTap) + global hotkey
├── Insertion/              # Accessibility-based text insertion
├── Settings/               # Preferences, frequent emojis
└── Utilities/              # App-wide utilities
```

## Tech Stack

- **Swift 5.9+**
- **SwiftUI** for picker UI
- **AppKit** (`NSTabViewController`) for the native menu-bar menu and Settings toolbar panes
- **Clipboard ⌘V paste** (with clipboard save/restore) to insert text into any app — the one method that works everywhere, including Messages/Pages/Word; the **Accessibility API** is used read-only for caret positioning and secure-field detection
- **Carbon global hotkey** (⌥⌘E) + session **CGEventTap** for system-wide colon shortcuts

## Building

Requires Xcode 15+ and macOS 14+ (Sonoma).

Prebuilt: grab `EmoPic-1.1.1.dmg` from the [latest GitHub Release](https://github.com/banditsdesign/EmoPic/releases). Open the disk image and drag EmoPic to Applications. Apple-**notarized**, Developer ID signed, hardened runtime — Gatekeeper accepts it directly. First launch asks for Accessibility access once (for text insertion).

## Security

EmoPic asks for two powerful permissions — Accessibility and a keyboard event tap — and uses them narrowly (see [PRIVACY.md](PRIVACY.md)). To report a vulnerability, or to verify that a download is genuinely ours, see [SECURITY.md](SECURITY.md).

## License

MIT — see [LICENSE](LICENSE). Third-party data attribution in [NOTICE](NOTICE).
