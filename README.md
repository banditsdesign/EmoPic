# EmoPic - Emoji Picker for macOS

A free, open-source emoji picker that lives in your menu bar and supports Slack-style colon shortcuts.

## Features

- **Menu Bar Picker**: Click the menu bar icon to open a searchable emoji picker (native macOS menu)
- **Slack-style Shortcuts**: Type `:smi` in any app's text field and a suggestion popup appears at the caret — navigate with `↑`/`↓`, insert with `Enter`/`Tab` or click (requires Accessibility permission, granted once)
- **Skin Tone Support**: Pick your preferred skin tone for hand, person, and other emoji
- **Light & Dark Mode**: Automatically follows your system appearance
- **Frequently Used**: Your most-used emoji rise to the top
- **Launch at Login**: Optional auto-start when you sign in (toggle in Settings)
- **Categories & Search**: Browse by category or search by name/alias
- **Custom Descriptions**: Right-click any emoji to attach your own words — search and `:colon:` suggestions match them instantly, and your text shows as the emoji's tooltip. Manage them all in Settings → Custom Descriptions

## How It Works

### Menu Bar Picker
Click the **double-chevron** (`chevron.up.2`) icon in your menu bar to open the picker window or its dropdown menu (Open Emoji Picker, Settings…, Quit). Search or browse categories to find the emoji you want.

### Slack-style Shortcuts
Type `:smi` in a text field **in any app** and a suggestion popup appears at the caret with matching emoji. `↑`/`↓` move the highlight, `Enter`/`Tab` or a click inserts the highlighted pick, `Esc` dismisses. You can still just keep typing the full `:smile:` and the closing `:` confirms the top match — the pattern is swapped for the emoji via the Accessibility API. The monitor is a system-wide event tap: characters always type through, and if the AX write fails your literal text stays untouched, nothing is ever swallowed. Grant Accessibility access when prompted (System Settings → Privacy & Security → Accessibility); the feature activates without relaunch. Excluded apps (set in Preferences) and secure password fields are skipped. The popup can be turned off in Settings → Colon Shortcuts to leave only the closing-`:` inline behaviour.

### Custom Descriptions
Right-click an emoji in the picker (grid or search row) and choose **Edit Description…** to attach free-form text — e.g. tag 🙋 with “bob, office mascot”. Every word joins that emoji's keywords: picker search, the `:colon:` suggestion popup, and the closing-`:` replacement all match them from the next keystroke, and the text replaces the built-in name as the emoji's tooltip/label. Custom keywords are keyed to the base emoji (skin-tone variants inherit them) and are stored locally in your preferences — never in the dataset, never leaving your machine. Review, edit inline or delete them in **Settings → Custom Descriptions**. If a keyword exactly equals a built-in shortcode, yours wins.

### Keyboard Shortcuts
- `⌥⌘E` - Toggle the emoji picker window (global hotkey, works in any app — presets configurable in Settings)
- `⌘,` - Open Settings
- `⌘Q` - Quit EmoPic

### Privacy
- **No network access. No telemetry.** The emoji dataset is bundled inside the signed app bundle; EmoPic never phones home.
- The colon-shortcut monitor uses a system-wide keyboard event tap, but keystrokes are examined **in memory only** — never logged, stored, or transmitted. At most the current `:shortcode` fragment (ASCII) is held, and it is discarded the moment you switch apps, press a modifier combo, or the pattern dies.
- Password fields (secure input) and apps on your exclusion list are skipped, and a replacement only happens after EmoPic verifies the selected text matches exactly what you typed.
- Full details — every value EmoPic stores, where it lives, and how to erase it — in [PRIVACY.md](PRIVACY.md).

Planned:
- `↑/↓` - Navigate picker results
- `Enter/Tab` - Insert selected emoji
- `Escape` - Close picker

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
- **Accessibility API** for inserting text into any app
- **Carbon global hotkey** (⌥⌘E) + session **CGEventTap** for system-wide colon shortcuts

## Building

Requires Xcode 15+ and macOS 14+ (Sonoma).

Prebuilt: grab `EmoPic-1.0.3.dmg` from the [latest GitHub Release](https://github.com/nicktangithub/EmoPic/releases). Open the disk image and drag EmoPic to Applications. Apple-**notarized**, Developer ID signed, hardened runtime — Gatekeeper accepts it directly. First launch asks for Accessibility access once (for text insertion).

## Security

EmoPic asks for two powerful permissions — Accessibility and a keyboard event tap — and uses them narrowly (see [PRIVACY.md](PRIVACY.md)). To report a vulnerability, or to verify that a download is genuinely ours, see [SECURITY.md](SECURITY.md).

## License

MIT — see [LICENSE](LICENSE). Third-party data attribution in [NOTICE](NOTICE).
