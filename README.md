# EmoPic - Emoji Picker for macOS

A free, open-source emoji picker that lives in your menu bar and supports Slack-style colon shortcuts.

## Features

- **Menu Bar Picker**: Click the menu bar icon to open a searchable emoji picker (native macOS menu)
- **Slack-style Shortcuts**: Type `:smi` in any app's text field and a suggestion popup appears at the caret — navigate with `↑`/`↓`, insert with `Enter`/`Tab` or click (requires Accessibility permission, granted once)
- **Skin Tone Support**: Pick your preferred skin tone for hand, person, and other emoji
- **Light & Dark Mode**: Automatically follows your system appearance
- **Frequently Used**: Your most-used emoji rise to the top
- **Categories & Search**: Browse by category or search by name/alias

## How It Works

### Menu Bar Picker
Click the **⌃ chevron** icon in your menu bar to open the picker window or its dropdown menu (Open Emoji Picker, Settings…, Quit). Search or browse categories to find the emoji you want.

### Slack-style Shortcuts
Type `:smi` in a text field **in any app** and a suggestion popup appears at the caret with matching emoji. `↑`/`↓` move the highlight, `Enter`/`Tab` or a click inserts the highlighted pick, `Esc` dismisses. You can still just keep typing the full `:smile:` and the closing `:` confirms the top match — the pattern is swapped for the emoji via the Accessibility API. The monitor is a system-wide event tap: characters always type through, and if the AX write fails your literal text stays untouched, nothing is ever swallowed. Grant Accessibility access when prompted (System Settings → Privacy & Security → Accessibility); the feature activates without relaunch. Excluded apps (set in Preferences) and secure password fields are skipped. The popup can be turned off in Settings → Colon Shortcuts to leave only the closing-`:` inline behaviour.

### Keyboard Shortcuts
- `⌥⌘E` - Toggle the emoji picker window (global hotkey, works in any app — presets configurable in Settings)
- `⌘,` - Open Settings
- `⌘Q` - Quit EmoPic

Planned (see [docs/NEXT_STEPS_PLAN.md](docs/NEXT_STEPS_PLAN.md)):
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

## License

MIT
