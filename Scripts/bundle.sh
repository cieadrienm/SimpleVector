#!/bin/bash
# Builds build/SimpleVector.app; a release build is also installed into /Applications (INSTALL=0 to skip).
# Usage: Scripts/bundle.sh [debug|release]   (default: release)
# NOTARIZE=1 Scripts/bundle.sh   also has Apple notarize the app and staples the ticket (Developer ID, notarytool profile "notary")
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
VERSION="0.2.3"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

if [ ! -f Resources/AppIcon.icns ]; then
    swift Scripts/make-icon.swift
fi

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"
APP="${APP:-build/SimpleVector.app}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/SimpleVector" "$APP/Contents/MacOS/SimpleVector"
cp "$BIN/simplevector-mcp" "$APP/Contents/MacOS/simplevector-mcp"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
for LPROJ in Resources/*.lproj; do
    [ -d "$LPROJ" ] && cp -R "$LPROJ" "$APP/Contents/Resources/"
done

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>SimpleVector</string>
    <key>CFBundleDisplayName</key><string>SimpleVector</string>
    <key>CFBundleIdentifier</key><string>net.cieadrienm.simplevector</string>
    <key>CFBundleExecutable</key><string>SimpleVector</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>@VERSION@</string>
    <key>CFBundleVersion</key><string>@BUILD@</string>
    <key>CFBundleDevelopmentRegion</key><string>fr</string>
    <key>CFBundleLocalizations</key><array><string>fr</string><string>en</string></array>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHumanReadableCopyright</key><string>cie Adrien M — Compagnie Adrien M</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.graphics-design</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>SimpleVector écoute les commandes OSC (port UDP 9160) et expose une API HTTP locale (127.0.0.1:17960) pour le pilotage de régie.</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Document PDF</string>
            <key>CFBundleTypeRole</key><string>Editor</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key><array><string>com.adobe.pdf</string></array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key><string>Graphique vectoriel SVG</string>
            <key>CFBundleTypeRole</key><string>Editor</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key><array><string>public.svg-image</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST
sed -i '' -e "s/@VERSION@/$VERSION/" -e "s/@BUILD@/$BUILD/" "$APP/Contents/Info.plist"

if [ -z "${SIGN_IDENTITY:-}" ]; then
    IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    DEV_ID_LINE="$(echo "$IDENTITIES" | grep '"Developer ID Application: ' | tail -1 || true)"
    if [ -n "$DEV_ID_LINE" ]; then
        SIGN_HASH="$(echo "$DEV_ID_LINE" | awk '{print $2}')"
        SIGN_IDENTITY="$(echo "$DEV_ID_LINE" | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p')"
    else
        APP_DEV_LINE="$(echo "$IDENTITIES" | grep '"Apple Development: ' | tail -1 || true)"
        SIGN_HASH="$(echo "$APP_DEV_LINE" | awk '{print $2}')"
        SIGN_IDENTITY="$(echo "$APP_DEV_LINE" | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p')"
    fi
    [ -n "${SIGN_IDENTITY:-}" ] || SIGN_IDENTITY="-"
    [ -n "${SIGN_HASH:-}" ] || SIGN_HASH="$SIGN_IDENTITY"
else
    SIGN_HASH="$SIGN_IDENTITY"
fi
case "$SIGN_IDENTITY" in
    "Developer ID Application:"*) SIGN_FLAGS="--timestamp --options runtime" ;;
    *) SIGN_FLAGS="--timestamp=none" ;;
esac
if ! codesign --force $SIGN_FLAGS --sign "$SIGN_HASH" "$APP/Contents/MacOS/simplevector-mcp" "$APP" 2>/tmp/simplevector-codesign.log; then
    echo "warning: signing with '$SIGN_IDENTITY' ($SIGN_HASH) failed; falling back to ad hoc" >&2
    SIGN_IDENTITY="-"
    codesign --force --sign - "$APP/Contents/MacOS/simplevector-mcp" "$APP"
fi
echo "signed: $SIGN_IDENTITY ($SIGN_HASH)" >&2

# NOTARIZE defaults to 1 on release builds signed with Developer ID Application (pass NOTARIZE=0 to skip)
if [ "${NOTARIZE:-$([ "$CONFIG" = release ] && echo 1 || echo 0)}" = "1" ]; then
    case "$SIGN_IDENTITY" in
        "Developer ID Application:"*)
            ditto -c -k --keepParent "$APP" "$APP.notarize.zip"
            xcrun notarytool submit "$APP.notarize.zip" --keychain-profile "${NOTARY_PROFILE:-notary}" --wait
            rm -f "$APP.notarize.zip"
            xcrun stapler staple "$APP"
            echo "notarized and stapled" >&2
            ;;
        *)
            if [ "${NOTARIZE:-}" = "1" ]; then
                echo "error: NOTARIZE=1 needs a Developer ID Application certificate" >&2
                exit 1
            fi
            ;;
    esac
fi

INSTALL_DIR="${INSTALL_DIR:-/Applications}"
if [ "${INSTALL:-$([ "$CONFIG" = release ] && echo 1 || echo 0)}" = 1 ]; then
    TARGET="$INSTALL_DIR/SimpleVector.app"
    if pgrep -f "$TARGET/Contents/MacOS/SimpleVector" >/dev/null; then
        echo "note: SimpleVector is running from $TARGET — quit and reopen it to get this build" >&2
    fi
    rm -rf "$TARGET.new"
    ditto "$APP" "$TARGET.new"
    rm -rf "$TARGET"
    mv "$TARGET.new" "$TARGET"
    echo "installed: $TARGET" >&2
fi
echo "$APP"
