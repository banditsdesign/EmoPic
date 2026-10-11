# EmoPic - Emoji Picker for macOS

A free, open-source emoji picker that lives in your menu bar and supports Slack-style colon shortcuts.

## Features

- **Menu Bar Picker**: Click the emoji icon to open a searchable emoji picker
- **Slack-style Shortcuts**: Type `:smile:` or `:thumbsup:` in any app's text field and it becomes 😄 (requires Accessibility permission, granted once)
- **Skin Tone Support**: Pick your preferred skin tone for hand, person, and other emoji
- **Light & Dark Mode**: Automatically follows your system appearance
- **Frequently Used**: Your most-used emoji rise to the top
- **Categories & Search**: Browse by category or search by name/alias

## How It Works

### Menu Bar Picker
Click the 🎨 emoji icon in your menu bar to open the picker window. Search or browse categories to find the emoji you want.

### Slack-style Shortcuts
Type `:smile:` in a text field **in any app** and it becomes 😄. The monitor is a system-wide event tap: characters always type through, and the typed pattern is swapped for the emoji on confirm (closing `:`, space, tab, or Enter) via the Accessibility API — if the target app rejects the write, your literal `:smile:` stays untouched, nothing is ever swallowed. Grant Accessibility access when prompted (System Settings → Privacy & Security → Accessibility); the feature activates without relaunch. Excluded apps (set in Preferences) and secure password fields are skipped.

### Keyboard Shortcuts
- `⌥⌘E` - Toggle the emoji picker window (global hotkey, works in any app — presets configurable in Settings)

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
- **AppKit** for menu bar integration
- **Accessibility API** for inserting text into any app
- **NSEvent monitor** for global keyboard shortcuts

## Building

Requires Xcode 15+ and macOS 14+ (Sonoma).

## License

MIT
