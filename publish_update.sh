#!/bin/bash
# One-command release flow:
#   bump version → archive → notarize → staple → EdDSA-sign the zip →
#   update appcast.xml → push GitHub Release → commit & push appcast.
#
# Usage:  ./publish_update.sh <new-version> "Release notes…"
# Example: ./publish_update.sh 1.0.1 "Adds margin formula auto-percent"
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $0 <new-version> <release-notes>"
  exit 1
fi

NEW_VERSION="$1"
NOTES="$2"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PBXPROJ="$PROJECT_DIR/Beam.xcodeproj/project.pbxproj"
APPCAST="$PROJECT_DIR/appcast.xml"
SPARKLE_BIN=/opt/homebrew/Caskroom/sparkle/2.9.2/bin

# 1. Bump versions in pbxproj (both Debug & Release configs)
CURRENT_BUILD=$(grep -E "^[[:space:]]*CURRENT_PROJECT_VERSION = " "$PBXPROJ" | head -1 | sed -E 's/.*= ([0-9]+);.*/\1/')
NEW_BUILD=$((CURRENT_BUILD + 1))
echo "▶ Bumping version → $NEW_VERSION (build $NEW_BUILD)"
sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $NEW_VERSION;/g" "$PBXPROJ"
sed -i '' -E "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = $NEW_BUILD;/g" "$PBXPROJ"

# 2. Archive + notarize + staple (existing pipeline)
echo "▶ Packaging…"
"$PROJECT_DIR/package.sh"

ZIP="$PROJECT_DIR/dist/Beam.zip"
[ -f "$ZIP" ] || { echo "✗ Missing $ZIP"; exit 1; }

# 3. EdDSA-sign the zip (private key lives in the Keychain from generate_keys)
echo "▶ Signing update with EdDSA…"
SIG_ATTRS=$("$SPARKLE_BIN/sign_update" "$ZIP")
# sign_update prints e.g.:  sparkle:edSignature="..." length="123456"
echo "  $SIG_ATTRS"

PUBDATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")
ENCLOSURE_URL="https://github.com/moshed/Beam/releases/download/v${NEW_VERSION}/Beam.zip"

# 4. Update / create appcast.xml
echo "▶ Updating appcast.xml…"
python3 - <<EOF
import os, re, sys
from xml.sax.saxutils import escape

appcast = "$APPCAST"
notes = """$NOTES"""
new_item = f'''    <item>
      <title>Version $NEW_VERSION</title>
      <pubDate>$PUBDATE</pubDate>
      <sparkle:version>$NEW_BUILD</sparkle:version>
      <sparkle:shortVersionString>$NEW_VERSION</sparkle:shortVersionString>
      <description><![CDATA[{notes}]]></description>
      <enclosure
        url="$ENCLOSURE_URL"
        type="application/octet-stream"
        $SIG_ATTRS/>
    </item>
'''

if not os.path.exists(appcast):
    with open(appcast, "w") as f:
        f.write(f'''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Beam</title>
    <link>https://github.com/moshed/Beam</link>
    <description>Beam release feed</description>
    <language>en</language>
{new_item}  </channel>
</rss>
''')
else:
    with open(appcast) as f: content = f.read()
    # Insert new item at the TOP (newest-first) — right after the <language> line.
    marker = "<language>en</language>\n"
    if marker in content:
        content = content.replace(marker, marker + new_item, 1)
    else:
        content = content.replace("</channel>", new_item + "  </channel>", 1)
    with open(appcast, "w") as f: f.write(content)
print("  appcast.xml updated")
EOF

# 5. Commit version bump + appcast and push (so GitHub Pages serves it)
echo "▶ Committing & pushing…"
git add "$PBXPROJ" "$APPCAST"
git commit -m "Release v$NEW_VERSION

$NOTES" || echo "  (nothing to commit — already at this version?)"
git push

# 6. Create the GitHub Release with the notarized zip attached
echo "▶ Publishing GitHub Release…"
gh release create "v$NEW_VERSION" "$ZIP" \
  --title "v$NEW_VERSION" \
  --notes "$NOTES"

echo ""
echo "✓ v$NEW_VERSION released."
echo "  Download:  $ENCLOSURE_URL"
echo "  Appcast:   https://moshed.github.io/Beam/appcast.xml"
