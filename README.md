# EmoPic - Emoji Picker for macOS

A free, open-source emoji picker that lives in your menu bar and supports Slack-style colon shortcuts.

## Features

- **Menu Bar Picker**: Click the emoji icon to open a searchable emoji picker
- **Slack-style Shortcuts**: Type `:smile`, `:thumbsup:`, etc. anywhere on your Mac
- **Skin Tone Support**: Pick your preferred skin tone for hand, person, and other emoji
- **Light & Dark Mode**: Automatically follows your system appearance
- **Frequently Used**: Your most-used emoji rise to the top
- **Categories & Search**: Browse by category or search by name/alias

## How It Works

### Menu Bar Picker
Click the 🎨 emoji icon in your menu bar to open the picker window. Search or browse categories to find the emoji you want.

### Slack-style Shortcuts
Type a colon `:` in any text field to trigger the emoji picker. Type more characters to filter. Press `Enter`/`Tab` to insert, or `Escape` to dismiss.

### Keyboard Shortcuts
- `⌘ Space` - Toggle the emoji picker window
- `↑/↓` - Navigate picker results
- `Enter/Tab` - Insert selected emoji
- `Escape` - Close picker / dismiss shortcut mode

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
