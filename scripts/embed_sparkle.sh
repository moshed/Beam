#!/bin/sh
# Embed Sparkle.framework into the app bundle and deep-sign it inside-out with the
# build's signing identity. Run as the last build phase (after Resources, before the
# app's own CodeSign). Replicates Xcode's "Embed & Sign" for the SPM xcframework,
# which a hand-written Copy Files phase can't do (it mis-resolves the product path
# and doesn't sign Sparkle's nested XPC services / helper apps).
set -e

SRC="$BUILT_PRODUCTS_DIR/Sparkle.framework"
if [ ! -d "$SRC" ]; then
  echo "warning: Sparkle.framework not found at $SRC — skipping embed"
  exit 0
fi

DEST_DIR="$BUILT_PRODUCTS_DIR/$FRAMEWORKS_FOLDER_PATH"
mkdir -p "$DEST_DIR"
/usr/bin/rsync -a --delete "$SRC/" "$DEST_DIR/Sparkle.framework/"

FW="$DEST_DIR/Sparkle.framework"
V="$FW/Versions/B"
ID="${EXPANDED_CODE_SIGN_IDENTITY:--}"

# Secure timestamp only for release/distribution (notarization needs it; skip for
# fast local Debug builds).
if [ "$CONFIGURATION" = "Release" ]; then TS="--timestamp"; else TS="--timestamp=none"; fi

SIGN="codesign --force --options runtime --preserve-metadata=entitlements $TS --sign $ID"

# Inside-out: nested helpers first, framework bundle last.
$SIGN "$V/XPCServices/Downloader.xpc"
$SIGN "$V/XPCServices/Installer.xpc"
$SIGN "$V/Updater.app"
$SIGN "$V/Autoupdate"
$SIGN "$FW"

echo "✓ Embedded & signed Sparkle.framework with identity: $ID"
