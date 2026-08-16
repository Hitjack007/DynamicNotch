#!/bin/bash
set -euo pipefail

# Usage: ./release.sh <version> "<notes>"
# e.g.   ./release.sh 1.0.1 "Fixed CPU stats flickering, improved spectrogram performance"
VERSION="${1:?Usage: ./release.sh <version> \"<release notes>\"}"
NOTES="${2:?Please provide release notes as the second argument}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PBXPROJ="$SCRIPT_DIR/boringNotch.xcodeproj/project.pbxproj"
SCHEME="boringNotch"
APP_NAME="boringNotch"
DMG_NAME="DynamicNotch-${VERSION}.dmg"
ARCHIVE_PATH="/tmp/DynamicNotch-${VERSION}.xcarchive"
DMG_PATH="/tmp/${DMG_NAME}"
APPCAST="$SCRIPT_DIR/docs/appcast.xml"
BUILD_NUM=$(date +%Y%m%d%H%M)

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  DynamicNotch release script v${VERSION}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Preflight checks ────────────────────────────────────────────────────────

echo "→ Checking dependencies..."

if ! command -v gh &>/dev/null; then
    echo "Error: GitHub CLI (gh) not found. Install with: brew install gh"
    exit 1
fi

SPARKLE_BIN=$(find ~/Library/Developer/Xcode/DerivedData -name "sign_update" -path "*/sparkle/*" 2>/dev/null | head -1)
if [ -z "$SPARKLE_BIN" ]; then
    echo "Error: Sparkle sign_update not found. Open the project in Xcode once to resolve packages."
    exit 1
fi
echo "  sign_update: $SPARKLE_BIN"

if git -C "$SCRIPT_DIR" status --short | grep -q '^[MADRC]'; then
    echo "Error: You have staged changes. Commit or stash them before releasing."
    exit 1
fi

# ── Bump version in Xcode project ───────────────────────────────────────────

echo ""
echo "→ Bumping version to ${VERSION} (build ${BUILD_NUM})..."
python3 - "$PBXPROJ" "$VERSION" "$BUILD_NUM" <<'PYEOF'
import sys, re
path, version, build = sys.argv[1:]
content = open(path).read()
# Update MARKETING_VERSION for main app target (2.x.x pattern)
content = re.sub(r'(MARKETING_VERSION = )\d+\.\d+[\.\d]*;', rf'\g<1>{version};', content)
# Update CURRENT_PROJECT_VERSION for main app target (3-digit build numbers)
content = re.sub(r'(CURRENT_PROJECT_VERSION = )\d{3,};', rf'\g<1>{build};', content)
open(path, 'w').write(content)
print(f"  MARKETING_VERSION = {version}")
print(f"  CURRENT_PROJECT_VERSION = {build}")
PYEOF

# ── Commit version bump ──────────────────────────────────────────────────────

echo ""
echo "→ Committing version bump..."
cd "$SCRIPT_DIR"
git add boringNotch.xcodeproj/project.pbxproj
git commit -m "Bump version to ${VERSION}"

# ── Archive ──────────────────────────────────────────────────────────────────

echo ""
echo "→ Archiving (this takes a minute)..."
xcodebuild archive \
    -project "$SCRIPT_DIR/boringNotch.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    SKIP_INSTALL=NO \
    2>&1 | grep -E "^(error:|Build succeeded|** ARCHIVE)" || true

APP_PATH=$(find "$ARCHIVE_PATH/Products" -name "*.app" -maxdepth 3 | head -1)
if [ -z "$APP_PATH" ]; then
    echo "Error: No .app found in archive. Check Xcode signing settings."
    exit 1
fi
echo "  App: $APP_PATH"

# ── DMG ──────────────────────────────────────────────────────────────────────

echo ""
echo "→ Creating DMG..."
rm -f "$DMG_PATH"
STAGING="/tmp/DynamicNotch-staging-$$"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
hdiutil create \
    -volname "DynamicNotch" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH" 2>&1 | grep -v "^hdiutil:" || true
rm -rf "$STAGING"
echo "  Created: $DMG_PATH ($(du -sh "$DMG_PATH" | cut -f1))"

# ── Sparkle signing ───────────────────────────────────────────────────────────

echo ""
echo "→ Signing DMG with Sparkle..."
SIGN_OUTPUT=$("$SPARKLE_BIN" "$DMG_PATH" 2>&1)
ED_SIG=$(echo "$SIGN_OUTPUT" | grep -oE 'edSignature="[^"]+"' | head -1 | cut -d'"' -f2)
FILE_LEN=$(echo "$SIGN_OUTPUT" | grep -oE 'length="[0-9]+"' | head -1 | cut -d'"' -f2)

if [ -z "$ED_SIG" ] || [ -z "$FILE_LEN" ]; then
    echo "Error: Could not parse Sparkle signature. Output was:"
    echo "$SIGN_OUTPUT"
    exit 1
fi
echo "  edSignature: ${ED_SIG:0:20}..."
echo "  length: $FILE_LEN"

# ── Update appcast.xml ────────────────────────────────────────────────────────

echo ""
echo "→ Updating appcast.xml..."
RELEASE_DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
DOWNLOAD_URL="https://github.com/Hitjack007/DynamicNotch/releases/download/v${VERSION}/${DMG_NAME}"

python3 - "$APPCAST" "$VERSION" "$BUILD_NUM" "$RELEASE_DATE" "$DOWNLOAD_URL" "$ED_SIG" "$FILE_LEN" <<'PYEOF'
import sys
path, version, build, date, url, sig, length = sys.argv[1:]
new_item = (
    f"\n    <item>\n"
    f"      <title>Version {version}</title>\n"
    f"      <pubDate>{date}</pubDate>\n"
    f"      <sparkle:version>{build}</sparkle:version>\n"
    f"      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>\n"
    f"      <enclosure\n"
    f"        url=\"{url}\"\n"
    f"        sparkle:edSignature=\"{sig}\"\n"
    f"        length=\"{length}\"\n"
    f"        type=\"application/octet-stream\"/>\n"
    f"    </item>"
)
content = open(path).read()
content = content.replace('  </channel>', new_item + '\n\n  </channel>', 1)
open(path, 'w').write(content)
print(f"  Added v{version} entry")
PYEOF

# ── GitHub release ─────────────────────────────────────────────────────────

echo ""
echo "→ Creating GitHub release v${VERSION}..."
gh release create "v${VERSION}" "$DMG_PATH" \
    --title "DynamicNotch v${VERSION}" \
    --notes "$NOTES"

# ── Push everything ───────────────────────────────────────────────────────────

echo ""
echo "→ Pushing appcast and tagging..."
cd "$SCRIPT_DIR"
git add docs/appcast.xml
git commit -m "Release v${VERSION}"
git push

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  v${VERSION} shipped!"
echo "  https://github.com/Hitjack007/DynamicNotch/releases/tag/v${VERSION}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
