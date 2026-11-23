#!/usr/bin/env bash
# EmoPic release pipeline (issue #2).
#
#   scripts/release.sh <marketing-version> <build-number> [options]
#
# Options
#   --notes FILE     release notes markdown. These are not just release prose:
#                    generate_appcast embeds them in the appcast, and Sparkle
#                    shows them in the update dialog as the changelog. Default
#                    docs/release-notes-<version>.md (the repo's own convention)
#   --generate-notes let GitHub write the release body from merged PRs. The
#                    update dialog then has no real changelog to show and gets a
#                    stub that links to the release page instead — prefer writing
#                    the notes file.
#   --dry-run        run every preflight check and print the plan, change nothing
#   --skip-notarize  local testing only: no Apple notarization (Gatekeeper WILL
#                    block the result — never ship this)
#   --allow-private  permit running against a private repo (the Sparkle feed is
#                    403 to anonymous users until the repo is public, so updates
#                    cannot actually work yet — fine for plumbing tests)
#   --allow-any-branch  skip the "must be on main" guard
#
# Order is not arbitrary. Shipping v1.0 taught us: notarize the app → staple the
# app → stage the DMG → notarize the DMG → staple the DMG. Re-signing after
# stapling erases the ticket, and a DMG whose embedded app was never stapled
# fails Gatekeeper offline.
#
# Owner/repo are derived from the git remote at runtime, never hardcoded: the
# project moved from a personal account to the banditsdesign org once already,
# and a hardcoded owner is how a future move silently strands every installed
# copy on a 404 appcast.
#
# Notarization credentials: either a stored profile (`xcrun notarytool
# store-credentials --keychain-profile EmoPic …`, default profile name EmoPic, override with NOTARY_PROFILE) or the env vars APPLE_ID, APP_SPECIFIC_PASSWORD
# and TEAM_ID.
#
# Sparkle signing key — the key must match SUPublicEDKey. In preference order:
#   SPARKLE_ED_KEY_FILE=~/path/emopic-ed25519.txt   sign from an exported key file
#   SPARKLE_KEYCHAIN_ACCOUNT=<account>              a named Keychain item
#   (neither)                                        Keychain account 'emopic', then
#                                                    the shared 'ed25519' one — each
#                                                    verified against SUPublicEDKey
# See "Keychain collision" in docs/RELEASE_PROCESS.md: the default Keychain slot
# is shared by every Sparkle project on the machine, so another app's keygen
# silently replaces this one's key. Keep EmoPic on its own 'emopic' account.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

INFO_PLIST="EmoPic/Info.plist"
PROJECT="EmoPic.xcodeproj"
SCHEME="EmoPic"
TEAM_ID="MLT7DK5FRB"
NOTARY_PROFILE="${NOTARY_PROFILE:-EmoPic}"

DRY=0 SKIP_NOTARIZE=0 ALLOW_PRIVATE=0 ANY_BRANCH=0 NOTES_LINK_ONLY=0
NOTES_FILE=""
VERSION="${1:-}"; BUILD="${2:-}"
if [[ $# -gt 2 ]]; then shift 2; else set --; fi
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --skip-notarize) SKIP_NOTARIZE=1 ;;
    --allow-private) ALLOW_PRIVATE=1 ;;
    --allow-any-branch) ANY_BRANCH=1 ;;
    --notes) shift; NOTES_FILE="${1:?--notes needs a file}" ;;
    --generate-notes) NOTES_LINK_ONLY=1 ;;
    *) printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

step()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
info()  { printf '    %s\n' "$*"; }
warn()  { printf '\033[1;33mWARNING: %s\033[0m\n' "$*" >&2; }
fail()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

run() {
  if (( DRY )); then
    printf '    [dry-run] %s\n' "$*"
  else
    info "\$ $*"
    "$@"
  fi
}

# ---------------------------------------------------------------- preflight ----

step "Preflight"

[[ -n "$VERSION" && -n "$BUILD" ]] || fail "usage: scripts/release.sh <version> <build> [options]  e.g. scripts/release.sh 1.0.4 5"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || fail "version must look like 1.0.4 (got '$VERSION')"
[[ "$BUILD" =~ ^[0-9]+$ ]] || fail "build must be an integer (got '$BUILD')"

command -v xcodebuild >/dev/null || fail "xcodebuild not found"
command -v gh >/dev/null || fail "gh CLI not found"
command -v hdiutil >/dev/null || fail "hdiutil not found"

OWNER="$(gh repo view --json owner -q .owner.login)"
REPO="$(gh repo view --json name -q .name)"
VISIBILITY="$(gh repo view --json visibility -q .visibility)"
info "remote: $OWNER/$REPO ($VISIBILITY)"

BRANCH="$(git branch --show-current)"
if [[ "$BRANCH" != "main" ]]; then
  if (( ANY_BRANCH || DRY )); then
    warn "on branch '$BRANCH', not main — the appcast must be committed to main, since SUFeedURL points at /main/"
    (( ANY_BRANCH )) || fail "re-run with --allow-any-branch if this is intentional"
  else
    fail "must be on main to release (currently '$BRANCH')"
  fi
fi

if [[ -n "$(git status --porcelain)" ]]; then
  fail "working tree has uncommitted changes; commit or stash them first"
fi

# The feed-vs-remote guard: SUFeedURL is compiled into the binary. If it ever
# names an owner other than this repo's, updates 404 for every user and nobody
# notices until they are months behind. Catch it here, not in the wild.
FEED="$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$INFO_PLIST" 2>/dev/null || true)"
[[ -n "$FEED" ]] || fail "SUFeedURL missing from $INFO_PLIST"
EXPECTED_FEED="https://raw.githubusercontent.com/$OWNER/$REPO/main/appcast.xml"
if [[ "$FEED" != "$EXPECTED_FEED" ]]; then
  fail "SUFeedURL is stale.
      plist: $FEED
      remote: $EXPECTED_FEED
    Fix Info.plist before releasing (the feed URL cannot be changed after the
    binaries are in users' hands)."
fi
info "feed URL matches remote: $FEED"

if [[ "$VISIBILITY" == "PRIVATE" ]] && (( ! ALLOW_PRIVATE )); then
  fail "repo is private — anonymous users cannot read the appcast, so Sparkle cannot work. Use --allow-private for plumbing tests."
elif [[ "$VISIBILITY" == "PRIVATE" ]]; then
  warn "repo is private: this release will NOT be auto-updatable yet"
fi

PUBKEY="$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$INFO_PLIST" 2>/dev/null || true)"
[[ -n "$PUBKEY" ]] || fail "SUPublicEDKey missing from $INFO_PLIST — clients could not verify any update"
security find-identity -p codesigning -v 2>/dev/null | grep -q "Developer ID Application.*($TEAM_ID)" \
  || fail "no 'Developer ID Application' certificate for team $TEAM_ID in the keychain"
info "signing identity present, SUPublicEDKey set"

SPARKLE_BIN="${SPARKLE_BIN:-$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/EmoPic-*/SourcePackages/artifacts/sparkle/Sparkle/bin 2>/dev/null | head -1 || true)}"
[[ -n "$SPARKLE_BIN" && -x "$SPARKLE_BIN/generate_appcast" ]] \
  || fail "Sparkle CLI tools not found. Build once (xcodebuild -resolvePackageDependencies) or set SPARKLE_BIN."
info "sparkle tools: $SPARKLE_BIN"

# ---- which Sparkle signing key to use ---------------------------------------
# Sparkle keeps its EdDSA key in ONE Keychain item per machine: service
# https://sparkle-project.org, account ed25519. It is not per project, so
# generating a key for a second Sparkle app overwrites the first one's — which
# is what happened on 2026-11-07, when a Canionotes keygen replaced EmoPic's
# key. generate_appcast did not fail: it warned on stderr and wrote an UNSIGNED
# appcast entry that every installed copy would reject. So name the key here,
# and when falling back to the shared Keychain item, prove it is ours first.
ED_KEYS=()
if [[ -n "${SPARKLE_ED_KEY_FILE:-}" ]]; then
  [[ -r "$SPARKLE_ED_KEY_FILE" ]] || fail "SPARKLE_ED_KEY_FILE is not readable: $SPARKLE_ED_KEY_FILE"
  ED_KEYS=(--ed-key-file "$SPARKLE_ED_KEY_FILE")
  info "appcast key: key file $SPARKLE_ED_KEY_FILE (Keychain is not used)"
else
  # Own account first, shared account second. `-p` on a missing account only
  # errors out, so probing costs nothing and creates nothing.
  for account in "${SPARKLE_KEYCHAIN_ACCOUNT:-emopic}" ed25519; do
    pub="$($SPARKLE_BIN/generate_keys --account "$account" -p 2>/dev/null | tail -1)"
    if [[ -n "$pub" && "$pub" == "$PUBKEY" ]]; then
      ED_KEYS=(--account "$account")
      info "appcast key: Keychain account '$account' matches SUPublicEDKey"
      break
    fi
  done
  if [[ ${#ED_KEYS[@]} -eq 0 ]]; then
    fail "no Sparkle key in the Keychain matches SUPublicEDKey ($PUBKEY).
    Repair, once, from this project's export — under its OWN account, so no
    other app's keygen can replace it:
      $SPARKLE_BIN/generate_keys --account emopic -f ~/Sparkle-backups/<emopic-ed25519.txt>
    or sign straight from the file for a single run:
      SPARKLE_ED_KEY_FILE=<path> scripts/release.sh …
    Inventory, history and the backup drill: docs/RELEASE_PROCESS.md."
  fi
fi

# ---- release notes = the changelog in the update dialog ----------------------
# One file feeds two things: the GitHub release body, and the changelog Sparkle
# shows in "an update is available". generate_appcast embeds markdown as CDATA
# in the item's <description>, so the user reads the changelog out of the same
# feed file Sparkle already fetched — no extra request (see PRIVACY.md), no
# extra hosting, and it is covered by the appcast's EdDSA signature.
#
# generate_appcast finds the notes by matching the *archive's* basename, so it
# is copied to EmoPic-<version>.md next to the zip below; a misnamed file is
# silently ignored and the dialog comes up with no changelog, hence the guards.
NOTES_SRC="${NOTES_FILE:-docs/release-notes-$VERSION.md}"
NOTES_EMBED=""          # the file embedded as the in-app changelog; empty = stub
if (( NOTES_LINK_ONLY )); then
  warn "--generate-notes: the update dialog will show only a link to the release page"
elif [[ -r "$NOTES_SRC" ]]; then
  NOTES_EMBED="$NOTES_SRC"
  info "changelog: $NOTES_SRC (embedded in the appcast)"
else
  fail "no release notes at $NOTES_SRC.
    Since 1.3 these are not just release prose — they are the changelog every
    user sees in the update dialog. Write that file, pass --notes FILE, or
    accept a link-only changelog with --generate-notes."
fi
if [[ -n "$NOTES_EMBED" ]]; then
  grep -q '[^[:space:]]' "$NOTES_EMBED" || fail "release notes are blank: $NOTES_EMBED"
  # ']]>' closes the CDATA section early and writes a malformed appcast, which
  # every client rejects — and generate_appcast does not complain about it.
  grep -qF ']]>' "$NOTES_EMBED" \
    && fail "release notes contain ']]>', which cannot be embedded in the appcast's CDATA section — reword it"
fi

if (( ! SKIP_NOTARIZE )); then
  if [[ -n "${APPLE_ID:-}" ]]; then
    NOTARY=(--apple-id "$APPLE_ID" --password "${APP_SPECIFIC_PASSWORD:?APP_SPECIFIC_PASSWORD required with APPLE_ID}" --team-id "$TEAM_ID")
    info "notarizing with APPLE_ID from the environment"
  elif xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    NOTARY=(--keychain-profile "$NOTARY_PROFILE")
    info "notarizing with keychain profile '$NOTARY_PROFILE'"
  else
    fail "no notarization credentials. One-time setup:
    xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id YOU@example.com --team-id $TEAM_ID
  (needs an App Store Connect API key or an app-specific password)"
  fi
else
  warn "--skip-notarize: the artifact will be blocked by Gatekeeper. Never ship it."
fi

OUT="build/release-$VERSION"
ARCHIVE="build/EmoPic-$VERSION.xcarchive"
APP="$OUT/EmoPic.app"
DMG="EmoPic-$VERSION.dmg"
ZIP="EmoPic-$VERSION.zip"
TAG="v$VERSION"

step "Plan for $VERSION (build $BUILD)"
info "archive   $ARCHIVE"
info "artifact  $OUT/EmoPic.app  ->  $DMG + $ZIP"
info "tag       $TAG with $(basename "$DMG") + $(basename "$ZIP")"
info "feed      $EXPECTED_FEED"
if [[ -n "$NOTES_EMBED" ]]; then
  info "changelog $NOTES_EMBED  ->  <description> in the appcast (update dialog)"
else
  info "changelog link-only stub (GitHub writes the release body)"
fi
if (( DRY )); then
  printf '\n\033[1;33m--dry-run: nothing executed.\033[0m\n'
  exit 0
fi

# ------------------------------------------------------------------- bump ------

step "Bump versions to $VERSION (build $BUILD)"
ruby -e '
  require "xcodeproj"
  version, build = ARGV[0], ARGV[1]
  project = Xcodeproj::Project.open(ARGV[2])
  project.targets.each do |t|
    t.build_configurations.each do |c|
      c.build_settings["MARKETING_VERSION"] = version
      c.build_settings["CURRENT_PROJECT_VERSION"] = build
    end
  end
  project.save
  puts "  #{ARGV[2]}: MARKETING_VERSION=#{version} CURRENT_PROJECT_VERSION=#{build}"
' "$VERSION" "$BUILD" "$PROJECT"
# Idempotent: a release re-run after a mid-flight failure lands here with the
# bump already committed, and `git commit` with nothing staged would abort.
if git diff --quiet -- "$PROJECT"; then
  info "version already at $VERSION (build $BUILD) — nothing to commit"
else
  run git commit -am "chore: bump version to $VERSION (build $BUILD)"
fi

# ----------------------------------------------------------------- archive -----

step "Archive (Release, universal)"
rm -rf "$ARCHIVE" "$OUT"
run xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" archive -quiet

cat > "$ROOT/build/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
        <key>method</key><string>developer-id</string>
        <key>teamID</key><string>$TEAM_ID</string>
        <key>signingStyle</key><string>manual</string>
        <key>destination</key><string>export</string>
</dict>
</plist>
PLIST

step "Export Developer ID build"
run xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT" \
  -exportOptionsPlist "$ROOT/build/ExportOptions.plist" -quiet
[[ -d "$APP" ]] || fail "export produced no $APP"

step "Verify nested code signatures"
# Sparkle contributes Autoupdate, Updater.app and XPC services inside
# Sparkle.framework; all of it must carry the same team identity.
run codesign --verify --deep --strict --verbose=2 "$APP"
plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist" | grep -q "^$VERSION$" \
  || fail "built app reports the wrong version"

# ----------------------------------------------------------- notarize app ------

if (( ! SKIP_NOTARIZE )); then
  step "Notarize the app (then staple it, before packaging)"
  run ditto -c -k --keepParent "$APP" "$OUT/EmoPic-$VERSION-for-notary.zip"
  run xcrun notarytool submit "$OUT/EmoPic-$VERSION-for-notary.zip" "${NOTARY[@]}" --wait
  run xcrun stapler staple "$APP"
fi

# ------------------------------------------------------------- DMG + zip -------

step "Build DMG (staged with an Applications shortcut)"
STAGE="$OUT/dmg"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
run hdiutil create -volname "EmoPic $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"

if (( ! SKIP_NOTARIZE )); then
  step "Notarize + staple the DMG"
  run xcrun notarytool submit "$DMG" "${NOTARY[@]}" --wait
  run xcrun stapler staple "$DMG"
fi

step "Sparkle artifact (zip of the already-stapled app)"
# ditto --keepParent keeps EmoPic.app at the archive root, which is what
# generate_appcast and Sparkle's installer expect.
run ditto -c -k --keepParent "$STAGE/EmoPic.app" "$ZIP"

# --------------------------------------------------------------- appcast -------

step "Sign for Sparkle + regenerate appcast.xml"
APPCAST_DIR="$OUT/appcast"
rm -rf "$APPCAST_DIR"; mkdir -p "$APPCAST_DIR"
cp "$ZIP" "$APPCAST_DIR/"

# Notes are matched to the archive by basename: EmoPic-<ver>.zip + EmoPic-<ver>.md.
NOTES_BASENAME="${ZIP##*/}"; NOTES_BASENAME="${NOTES_BASENAME%.*}"
APPCAST_NOTES="$APPCAST_DIR/$NOTES_BASENAME.md"
if [[ -n "$NOTES_EMBED" ]]; then
  cp "$NOTES_EMBED" "$APPCAST_NOTES"
else
  # The release body is generated by GitHub *after* this step, so there is
  # nothing real to embed yet. Say so, and hand the user the release page.
  cat > "$APPCAST_NOTES" <<NOTE
## EmoPic $VERSION

The full release notes are written when the release is published.

[View release $TAG on GitHub](https://github.com/$OWNER/$REPO/releases/tag/$TAG)
NOTE
fi

# --embed-release-notes is what makes the changelog show up without a second
# network round trip. Left off, generate_appcast writes a
# <sparkle:releaseNotesLink> to a file beside the feed instead — and
# raw.githubusercontent.com serves it as text/plain with nosniff, so a stray
# .html would not even render.
run "$SPARKLE_BIN/generate_appcast" "${ED_KEYS[@]}" \
  --embed-release-notes \
  --download-url-prefix "https://github.com/$OWNER/$REPO/releases/download/$TAG/" \
  --link "https://github.com/$OWNER/$REPO/releases/tag/$TAG" \
  --full-release-notes-url "https://github.com/$OWNER/$REPO/releases" \
  "$APPCAST_DIR" 2>&1 | tee "$OUT/appcast.log"
APPCAST="$APPCAST_DIR/appcast.xml"
if (( ! DRY )); then
  grep -q "$ZIP" "$APPCAST" || fail "appcast does not reference $ZIP"
  # A changelog is not optional any more: no <description> means a dialog with
  # nothing in it. Check for *this* release's text rather than any item's.
  NOTES_FIRST_LINE="$( { grep -m1 '[^[:space:]]' "$APPCAST_NOTES" || true; } | sed 's/[[:space:]]*$//')"
  [[ -n "$NOTES_FIRST_LINE" ]] || fail "the changelog has no text to embed: $APPCAST_NOTES"
  grep -qF -- "$NOTES_FIRST_LINE" "$APPCAST" \
    || fail "the changelog did not make it into the appcast — is the notes file named $(basename "$APPCAST_NOTES") so it matches $(basename "$ZIP")?"
  grep -q 'sparkle:format="markdown"' "$APPCAST" \
    || fail "the embedded changelog is not tagged sparkle:format=\"markdown\" — Sparkle would show the raw markdown source"
  # The key-mismatch warning is only a warning, and the feed it produces is
  # unsigned — invisible here, fatal on every client. Refuse it.
  if grep -q "does not match key" "$OUT/appcast.log"; then
    fail "the Sparkle signing key does not match SUPublicEDKey — the appcast would be unsigned and rejected by every client. See the appcast-key note above and docs/RELEASE_PROCESS.md."
  fi
  grep -q 'sparkle:edSignature' "$APPCAST" || fail "appcast entry is missing an EdDSA signature"
fi

# --------------------------------------------------------------- release -------

# Commit the feed and push FIRST, then publish. Two hard-won lessons:
#  1. gh anchors the release tag at the commit remote main is on. If the bump
#     isn't pushed yet, the tag silently lands on the *previous* release's
#     commit (the v1.1 drift) — or, with an explicit --target, gh rejects an
#     unpushed SHA outright. Push first so the target exists on the remote.
#  2. Never delete-and-recreate a release tag to "fix" it: deleting the tag
#     GitHub is using flips the release to DRAFT, and re-pushing the tag does
#     not un-draft it. Getting the tag right the first time (below) avoids it.
step "Commit appcast.xml to main (this IS the feed)"
run cp "$APPCAST" "$ROOT/appcast.xml"
run git add appcast.xml
run git commit -m "release: $VERSION appcast (issue #2 feed)"
run git push origin main

step "Publish GitHub release $TAG"
# --target pins the tag to the bump+appcast commit we just pushed, so it can
# never drift onto an older commit.
RELEASE_TARGET="$(git rev-parse HEAD)"
if [[ -n "$NOTES_EMBED" ]]; then
  # Same bytes the update dialog shows, so the two can never disagree.
  run gh release create "$TAG" "$DMG" "$ZIP" --target "$RELEASE_TARGET" --title "EmoPic $VERSION" --notes-file "$NOTES_EMBED"
else
  run gh release create "$TAG" "$DMG" "$ZIP" --target "$RELEASE_TARGET" --title "EmoPic $VERSION" --generate-notes
fi

# ------------------------------------------------------------- verify ----------

if [[ "$VISIBILITY" != "PRIVATE" ]] && (( ! DRY )); then
  step "Post-release feed check"
  LIVE_FEED="$(curl -fsSL "$EXPECTED_FEED" || true)"
  if printf '%s' "$LIVE_FEED" | grep -q "$TAG"; then
    info "appcast is live and lists $TAG"
  else
    warn "appcast at $EXPECTED_FEED does not list $TAG yet — raw.githubusercontent.com caches for ~5 min, retry shortly"
  fi
  if printf '%s' "$LIVE_FEED" | grep -q '<description'; then
    info "changelog is embedded in the live feed"
  else
    warn "the live appcast has no <description> — the update dialog will show no changelog"
  fi
  # The asset users actually download must be the artifact we signed and
  # notarized, byte for byte — a truncated or mis-uploaded asset is otherwise
  # invisible until someone's update fails.
  ENC_URL="$(grep -o 'url="[^"]*\.zip"' "$APPCAST" | sed -n '1p' | sed 's/^url="//; s/"$//')"
  if [[ -n "$ENC_URL" ]]; then
    remote_sha="$(curl -fsSL "$ENC_URL" | shasum -a 256 | cut -d' ' -f1)"
    local_sha="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
    if [[ -n "$remote_sha" && "$remote_sha" == "$local_sha" ]]; then
      info "downloaded zip is byte-identical to the signed local build"
    else
      fail "downloaded zip differs from local build (remote=${remote_sha:-none} local=$local_sha)"
    fi
  fi

  # sign_update --verify needs the signature passed explicitly (it does not read
  # the appcast), and prints nothing on success — exit status is the signal.
  SIG="$(grep -o 'sparkle:edSignature="[^"]*"' "$APPCAST" | sed -n '1p' | sed 's/^[^"]*"//; s/"$//')"
  [[ -n "$SIG" ]] || fail "no sparkle:edSignature found in the generated appcast"
  if "$SPARKLE_BIN/sign_update" --verify "${ED_KEYS[@]}" "$ZIP" "$SIG" >/dev/null 2>&1; then
    info "EdDSA signature verifies on $(basename "$ZIP")"
  else
    fail "EdDSA verification FAILED — every client would reject this update. Do not ship it."
  fi

  # spctl cannot assess a bare .dmg ("Insufficient Context"); the definitive
  # Gatekeeper check is the app inside it.
  # Mount on the boot volume: hdiutil refuses with "Permission denied" for a
  # mountpoint under a repository on an external volume (TCC removable-volumes),
  # which silently disabled this check on the 1.0.5 run.
  MNT="$(mktemp -d "${TMPDIR:-/tmp}/emopic-gatekeeper.XXXXXX")"
  if hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MNT" >/dev/null 2>&1; then
    # Two traps here. (1) Do not pipe spctl into `grep -q`: grep exits on the
    # first match, spctl can die of SIGPIPE, and `pipefail` then reports a
    # rejection for an app that was accepted. Capture and test the text. (2) The
    # staple was written seconds ago and assessment needs an OCSP round trip, so
    # a first pass that comes back empty has been a false alarm before — give it
    # one retry before it is allowed to warn.
    GK=""
    for attempt in 1 2; do
      GK="$(spctl --assess --type execute -vvv "$MNT/EmoPic.app" 2>&1 || true)"
      if printf '%s\n' "$GK" | grep -q "accepted"; then
        break
      fi
      if (( attempt < 2 )); then
        info "Gatekeeper did not answer yet, retrying in 3s…"
        sleep 3
      fi
    done
    if printf '%s\n' "$GK" | grep -q "accepted"; then
      info "Gatekeeper accepts the app inside the DMG (notarized + stapled)"
    else
      warn "Gatekeeper did not accept the app inside the DMG — check before announcing"
      printf '%s\n' "$GK" | sed 's/^/        /' >&2
    fi
    built="$(plutil -extract CFBundleShortVersionString raw "$MNT/EmoPic.app/Contents/Info.plist")"
    [[ "$built" == "$VERSION" ]] || fail "DMG contains EmoPic $built, not $VERSION"
    hdiutil detach "$MNT" -quiet
    rm -rf "$MNT"
  else
    warn "could not mount $DMG for the Gatekeeper check"
    rm -rf "$MNT"
  fi
fi

step "Done"
info "tag $TAG  ·  $DMG  ·  $ZIP  ·  appcast.xml pushed to main"
info "manual follow-ups: check the release page assets, and (on a clean Mac)"
info "update → download → install → relaunch, then confirm the Accessibility"
info "grant and login item survived. See docs/RELEASE_PROCESS.md."
