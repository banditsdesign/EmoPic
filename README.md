# EmoPic - Emoji Picker for macOS

A free, open-source emoji picker that lives in your menu bar and supports Slack-style colon shortcuts.

## Features

- **Menu Bar Picker**: Click the emoji icon to open a searchable emoji picker
- **Slack-style Shortcuts**: Type `:smile:` or `:thumbsup:` to insert emoji (currently limited to EmoPic's own windows — cross-app support via a global event tap is planned)
- **Skin Tone Support**: Pick your preferred skin tone for hand, person, and other emoji
- **Light & Dark Mode**: Automatically follows your system appearance
- **Frequently Used**: Your most-used emoji rise to the top
- **Categories & Search**: Browse by category or search by name/alias

## How It Works

### Menu Bar Picker
Click the 🎨 emoji icon in your menu bar to open the picker window. Search or browse categories to find the emoji you want.

### Slack-style Shortcuts
Type `:smile:` in a text field and it becomes 😄. **Current scope:** the shortcut monitor uses an app-local event monitor, so replacement happens only in EmoPic's own text fields. Cross-app replacement (global `CGEventTap` + Accessibility text APIs) is the next milestone — see [docs/NEXT_STEPS_PLAN.md](docs/NEXT_STEPS_PLAN.md).

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
├── Shortcuts/              # Slack-style colon shortcut detection
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
