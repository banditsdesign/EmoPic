# Security Policy

EmoPic is a menu-bar utility that asks for two powerful macOS permissions — **Accessibility**
(to insert text into other apps) and a **keyboard event tap** (for `:colon:` shortcuts). How
those are handled is the core of this project's security posture, so findings in that area are
taken seriously even though the app has no accounts, no server and no telemetry.

## Reporting a vulnerability

**Preferred:** [report privately via GitHub](https://github.com/banditsdesign/EmoPic/security/advisories/new)
— *Report a vulnerability* opens a private advisory that only you and the maintainers can see.
(If that option is missing, private vulnerability reporting hasn't been enabled on the repo yet;
use the email below instead.)

**Email:** `nick@banditsdesign.com.au`

Please don't open a public issue for anything that is actually exploitable. Ordinary bugs,
crashes and UX problems are very welcome as regular issues.

### What to expect

- **Acknowledgement within 5 business days.**
- **Assessment within 15 business days**, with a rough severity and whether it will be fixed.
- **Fix shipped in the next release** for anything Medium or above; Critical issues get a
  patch release as soon as it's practical.
- You will be credited in the release notes if you want to be.

No bounty — EmoPic is free and open source — but disclosure credit is on offer.

## Supported versions

| Version | Supported |
| ------- | --------- |
| 1.0.x   | ✅        |
| < 1.0   | ❌        |

Fixes ship to the [latest release](https://github.com/banditsdesign/EmoPic/releases/latest) on
GitHub. EmoPic 1.0.4 and later can also check for updates automatically once you enable it in
Settings → About (off by default) — but until that version reached users, plan on downloading a
new DMG and checking the release page.

## Verifying what you downloaded

Releases are signed with a **Developer ID Application** certificate, built with the **hardened
runtime** and enabled timestamps, then **notarized and stapled** by Apple. Gatekeeper should
accept the DMG and the app without any right-click-to-open dance.

```sh
# The DMG: Apple notarization ticket present?
spctl -a -vvv --type open --context context:primary-signature EmoPic-1.0.3.dmg

# The app: Developer ID signature, hardened runtime, deep verification
codesign -dvvv --strict --deep /Applications/EmoPic.app
spctl -a -vvv /Applications/EmoPic.app          # expect: accepted, source=Notarized Developer ID
```

If either check fails, do **not** run the app — open an issue and say where you got it.

Out of scope for tamper reports: the app's own bundled emoji dataset cannot change after build
(it is compiled into the bundle; there is no runtime download), and preferences live in a
user-owned plist that requires existing access to your account to touch.

## Scope

**In scope**

- Bypass or abuse of the keyboard event tap — e.g. keystrokes reaching anywhere they shouldn't,
  or suppression of input the user didn't intend to lose.
- Incorrect targeting of text insertion: writing into the wrong app, wrong field, or clobbering
  a selection.
- Circumvention of secure input (password fields) or the app exclusion list.
- Signature/notarization/update-integrity problems.
- Anything that lets a third-party app escalate privileges through EmoPic.

**Out of scope**

- Attacks requiring physical access to, or admin control of, the victim's Mac.
- Malware that already holds Accessibility access — at that point macOS itself is compromised;
  EmoPic grants no privilege the user didn't already hand out.
- Vulnerabilities in macOS, in the apps EmoPic types into, or in Apple's emoji fonts.
- Social-engineering a user into granting Accessibility access (documented behaviour, not a bug —
  though reports that our prompt wording is misleading are welcome).

## How EmoPic limits its own reach

Not a substitute for reporting real issues, but useful context for triage:

- The event tap is a **session** tap: it lives only while the app runs, and characters always
  pass through unless the tap is actively completing a `:shortcode:` pattern.
- Keystrokes are examined **in memory only**; nothing is logged, stored or transmitted, and the
  in-flight `:shortcode` fragment is discarded on app switch, modifier combo, or pattern death.
- Before any Accessibility write, EmoPic verifies the target's selected text matches exactly what
  the user typed, and verifies the frontmost app is still the app it started from. Fail either
  check and the text is left alone.
- Secure input (password fields) and user-excluded apps are skipped.
- Clipboard fallback saves and restores the previous pasteboard contents, guarded by change count.
- Network use is limited to the opt-in update check — off by default, and exactly what it sends
  is spelled out in [PRIVACY.md](PRIVACY.md).
