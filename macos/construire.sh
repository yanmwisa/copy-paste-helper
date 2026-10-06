#!/bin/bash
# ─────────────────────────────────────────────────────────────────
#  Builds, signs and (optionally) installs CopieRapide.
#
#  Usage:
#    ./construire.sh              build CopieRapide.app next to this script
#    ./construire.sh --installer  also install it in /Applications and relaunch
#
#  Signing:
#    SIGN_IDENTITY="My Certificate" ./construire.sh
#  signs with that code-signing certificate from your keychain. Without it,
#  the app is signed ad hoc, which is fine for trying it out. macOS then
#  recognises the app by the fingerprint of its binary, so the
#  Accessibility and Screen Recording permissions are asked again after
#  every rebuild. A stable certificate avoids that; see the README.
#
#  Requirements: macOS 13 or later, Xcode Command Line Tools (swiftc).
# ─────────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"

BUNDLE_ID="io.github.yanmwisa.copierapide"
APP="CopieRapide.app"
TARGET_APP="/Applications/CopieRapide.app"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"   # "-" means ad hoc
ARCH="$(uname -m)"                     # arm64 or x86_64

INSTALL=false
case "${1:-}" in
  "")           ;;
  --installer)  INSTALL=true ;;
  *)            echo "Usage: $0 [--installer]"; exit 2 ;;
esac

# 1. If a certificate was named, it must exist: signing ad hoc by surprise
#    would silently reset the permissions on every build.
if [ "$SIGN_IDENTITY" != "-" ] && ! security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
  echo "ERROR: code-signing certificate \"$SIGN_IDENTITY\" not found in the keychain."
  echo "List yours with:  security find-identity -v -p codesigning"
  exit 1
fi

# 2. Compile. The old binary is removed first: without that, a failed
#    compilation would leave it in place and look like a success.
echo "→ Compiling ($ARCH)"
rm -f CopieRapide
swiftc -O -target "${ARCH}-apple-macos13.0" -o CopieRapide main.swift

# 3. Assemble the bundle
echo "→ Assembling the bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist             "$APP/Contents/Info.plist"
cp CopieRapide            "$APP/Contents/MacOS/CopieRapide"
cp icone/CopieRapide.icns "$APP/Contents/Resources/CopieRapide.icns"

# 4. Sign
echo "→ Signing ($([ "$SIGN_IDENTITY" = "-" ] && echo "ad hoc" || echo "$SIGN_IDENTITY"))"
codesign --force --deep --sign "$SIGN_IDENTITY" \
         --identifier "$BUNDLE_ID" --options runtime --timestamp=none \
         --entitlements CopieRapide.entitlements "$APP"

# 5a. The hardened runtime forbids Apple Events without this entitlement.
#     Without it, reading the Finder selection fails silently: the bar only
#     shows "Paste" and nothing says why.
if ! codesign -d --entitlements - --xml "$APP" 2>/dev/null \
     | plutil -convert xml1 -o - - 2>/dev/null \
     | grep -q "com.apple.security.automation.apple-events"; then
  echo "ERROR: the Apple Events entitlement is missing from the signature."
  echo "Actions on Finder files would silently do nothing."
  exit 1
fi

# 5b. With a real certificate, the designated requirement must name it,
#     not a cdhash (a cdhash means the signature was ad hoc after all).
REQUIREMENT="$(codesign -d -r- "$APP" 2>&1 | tail -1)"
if [ "$SIGN_IDENTITY" != "-" ] && echo "$REQUIREMENT" | grep -q "cdhash"; then
  echo "ERROR: ad hoc signature detected although a certificate was requested."
  echo "$REQUIREMENT"
  exit 1
fi
codesign --verify --verbose=2 "$APP"

if ! $INSTALL; then
  echo
  echo "✓ Built: $(pwd)/$APP"
  echo "  Run it with:  open \"$APP\""
  echo "  Install it with:  $0 --installer"
  exit 0
fi

# 6. Install and relaunch
echo "→ Installing in /Applications"
osascript -e 'tell application "CopieRapide" to quit' 2>/dev/null || true
sleep 1
pkill -f "CopieRapide.app/Contents/MacOS" 2>/dev/null || true
sleep 1
rm -rf "$TARGET_APP"
cp -R "$APP" "$TARGET_APP"
open -a "$TARGET_APP"

echo
echo "✓ Installed and launched."
echo "  $REQUIREMENT"
