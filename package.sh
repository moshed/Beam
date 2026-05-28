#!/bin/bash
# Sign + notarize + staple Beam.app, then bundle as a zip ready to send.
# Uses the App Store Connect API key already stored at ~/.appstoreconnect/.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="$PROJECT_DIR/dist"
ARCHIVE_PATH="$DIST_DIR/Beam.xcarchive"
EXPORT_DIR="$DIST_DIR/export"
ZIP_PATH="$DIST_DIR/Beam.zip"

# App Store Connect API credentials — read from the Keychain entry the `asc` CLI
# stores, so no secrets live in this (now public) repo.
ASC_CRED=$(security find-generic-password -s "asc" -a "asc:credential:CLI Upload" -w)
ASC_KEY_ID=$(printf '%s' "$ASC_CRED" | python3 -c "import json,sys;print(json.load(sys.stdin)['key_id'])")
ASC_ISSUER_ID=$(printf '%s' "$ASC_CRED" | python3 -c "import json,sys;print(json.load(sys.stdin)['issuer_id'])")
ASC_KEY_PATH=$(printf '%s' "$ASC_CRED" | python3 -c "import json,sys;print(json.load(sys.stdin)['private_key_path'])")

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

echo "▶ Archiving Release build…"
xcodebuild -project "$PROJECT_DIR/Beam.xcodeproj" \
  -scheme Beam -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  archive

echo "▶ Exporting Developer ID-signed .app…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$PROJECT_DIR/ExportOptions.plist"

APP_PATH="$EXPORT_DIR/Beam.app"
if [ ! -d "$APP_PATH" ]; then
  echo "✗ Export failed — no Beam.app at $APP_PATH" >&2
  exit 1
fi

echo "▶ Zipping for notarization upload…"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "▶ Submitting to Apple notary service (waits for result)…"
xcrun notarytool submit "$ZIP_PATH" \
  --key "$ASC_KEY_PATH" \
  --key-id "$ASC_KEY_ID" \
  --issuer "$ASC_ISSUER_ID" \
  --wait

echo "▶ Stapling notary ticket to .app…"
xcrun stapler staple "$APP_PATH"

echo "▶ Re-zipping with stapled ticket…"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo ""
echo "✓ Done."
echo "  App:  $APP_PATH"
echo "  Zip:  $ZIP_PATH"
spctl --assess --verbose=2 --type execute "$APP_PATH" 2>&1 | head -3 || true
