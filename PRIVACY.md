# Privacy Policy

**EmoPic has no server, no accounts, no analytics, no crash reporting and no advertising SDK —
and by default it makes no network connection at all.** Nothing you type, pick or name leaves
your Mac. The single exception is the software-update check, which you have to turn on; exactly
what it sends is set out below.

This document describes exactly what the app stores and touches, and how to erase it.

## Network

**By default EmoPic makes no network connections at all.** No analytics, no crash reporting, no
accounts, no ads, no background phone-home. The emoji dataset is bundled inside the signed app
bundle, so there is nothing to fetch — an earlier build had a dataset download fallback, and it
was deleted precisely to remove the app's only network surface.

The one exception is software updates, and it is opt-in. EmoPic contacts GitHub only if you:

- turn on **Automatically check for updates** (Settings → About — **off by default**), or
- choose **Check for Updates…** from the menu bar yourself.

When you do, the app fetches one small file — the release feed — from `raw.githubusercontent.com`.
If an update is found and you choose to install it, it downloads the package from GitHub Releases
and asks again before restarting.

What that request carries:

- the app version, in the user agent string (e.g. `EmoPic/1.0.4`);
- **nothing else about your machine** — Apple's optional system profiling is disabled
  (`SUEnableSystemProfiling = false` and `sendsSystemProfile = false`), so no macOS version,
  hardware model, language list or usage data is sent;
- no sign-in, no account, and no unique, persistent or hardware identifier.

GitHub's servers still see what they see for any web request — IP address, timestamp, user agent —
and log it under their
[privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).

Builds 1.0 through 1.0.3 predate the update mechanism and make no network connection under any
circumstances.

## Permissions, and what they are used for

### Accessibility

Used to insert emoji into the focused text field of the frontmost app, and — for `:colon:`
shortcuts — to read the text just before the caret so it can be replaced.

EmoPic requests this once, and only ever:

- reads the focused element's role (to skip secure/ password fields) and its current selection,
- writes a replacement at the caret after verifying it matches exactly what you typed.

It does not read other apps' windows, menus, or documents, and it doesn't inspect the target app
beyond the focused element.

### Keyboard event tap (for `:colon:` shortcuts)

A session `CGEventTap` observes key-down events so `:smi` can trigger suggestions.

- Keystrokes are examined **in memory only** — never logged, never written to disk, never sent
  anywhere.
- At most the current `:shortcode` fragment (ASCII, a handful of characters) is held briefly, and
  it is discarded the moment you switch apps, hit a modifier combination, or the pattern breaks.
- Characters always type through; the tap only swallows keystrokes while it is actively navigating
  a suggestion popup, and a replacement happens only after it verifies the text at the caret.
- Turn the feature off in **Settings → Colon Shortcuts** and no popup appears; you can revoke the
  Accessibility permission at any time in **System Settings → Privacy & Security → Accessibility**
  and the picker still works.

### Login item (optional)

**Settings → Launch at login** registers EmoPic as a login item via Apple's `SMAppService` API.
The toggle reflects the real registration status with the system. No other background persistence
is used — no daemons, agents or kernel extensions.

## What EmoPic stores on your Mac

All in one user-owned preferences file, `~/Library/Preferences/net.emopic.app.plist`:

| What | Key | Notes |
| ---- | --- | ----- |
| Skin tone preference | `selectedSkinTone` | |
| Recently used emoji | `recentEmojiIDs` | Last 30, most-recent first |
| Enabled categories | `enabledCategories` | |
| Excluded apps | `excludedApps` | Bundle IDs you've told EmoPic to ignore |
| Colon-shortcut options | `enableColonShortcuts`, `showColonSuggestions` | |
| Frequent strip in picker | `showFrequentInPicker` | |
| Global hotkey | `hotKeyCode`, `hotKeyModifiers`, `hotKeyEnabled` | |
| Last-opened settings pane | `settingsTab` | |
| Launch-at-login mirror | `launchAtLogin` | Mirrors the system's login-item status |
| Custom emoji descriptions | `customEmojiDescriptions` | Your words for each emoji (issue #1) |

Notes:

- **Custom descriptions** are free text you type. They become searchable keywords on this Mac
  only, and are editable or removable in **Settings → Custom Descriptions**.
- Recents are emoji identifiers, not the content of your documents. EmoPic never sees or stores
  the surrounding text of what you're writing.
- These values are stored in the standard preferences domain, not an iCloud key-value store, so
  they are not synced to your other devices.
- Nothing is added to the clipboard except during the clipboard paste fallback, and the previous
  clipboard contents are restored afterwards.

## Erasing everything

```sh
defaults delete net.emopic.app
```

Or quit EmoPic and delete `~/Library/Preferences/net.emopic.app.plist`. There is no server-side
data to delete, because no data was ever sent anywhere. Deleting the app bundle from
`/Applications` leaves the preferences file behind until you remove it this way.

To revoke permissions: **System Settings → Privacy & Security → Accessibility**, deselect EmoPic;
**System Settings → General → Login Items**, switch EmoPic off.

## Changes

If this policy changes, the change will be described in the release notes for the version that
introduces it, and this document updated in the same release.

## Questions

Open an issue, or email `nick@banditsdesign.com.au`.
