#!/bin/bash
set -euo pipefail

# Usage: ./release.sh <version> "<notes>"
# e.g.   ./release.sh 1.0.1 "Fixed CPU stats flickering, improved spectrogram performance"
VERSION="${1:?Usage: ./release.sh <version> \"<release notes>\"}"
NOTES="${2:?Please provide release notes as the second argument}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PBXPROJ="$SCRIPT_DIR/dynamicNotch.xcodeproj/project.pbxproj"
SCHEME="DynamicNotch"
APP_NAME="DynamicNotch"
DMG_NAME="DynamicNotch-${VERSION}.dmg"
ARCHIVE_PATH="/tmp/DynamicNotch-${VERSION}.xcarchive"
DMG_PATH="/tmp/${DMG_NAME}"
APPCAST="$SCRIPT_DIR/docs/appcast.xml"
BUILD_NUM=$(date +%Y%m%d%H%M)
TAP_REPO="Hitjack007/homebrew-dynamicnotch"
CASK_NAME="dynamicnotch"

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

if ! command -v create-dmg &>/dev/null; then
    echo "Error: create-dmg not found. Install with: brew install create-dmg"
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

WHATSNEW_CATALOG="$SCRIPT_DIR/DynamicNotch/components/WhatsNew/WhatsNewCatalog.swift"
if ! grep -q "version: \"${VERSION}\"" "$WHATSNEW_CATALOG"; then
    echo ""
    echo "⚠️  Warning: WhatsNewCatalog.swift has no entry for version \"${VERSION}\"."
    echo "   Patch releases legitimately have no highlights, but if this release ships"
    echo "   a feature, users won't be introduced to it in-app."
    read -p "   Continue anyway? [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
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
git add dynamicNotch.xcodeproj/project.pbxproj
git commit -m "Bump version to ${VERSION}"

# ── Resolve minimum supported macOS version ─────────────────────────────────

echo ""
echo "→ Resolving minimum macOS version from build settings..."
MIN_OS_VERSION=$(xcodebuild -showBuildSettings \
    -project "$SCRIPT_DIR/dynamicNotch.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release 2>/dev/null \
    | awk -F '= ' '$1 ~ /^[[:space:]]*MACOSX_DEPLOYMENT_TARGET[[:space:]]*$/ { print $2; exit }')

if [ -z "$MIN_OS_VERSION" ]; then
    echo "Error: Could not resolve MACOSX_DEPLOYMENT_TARGET from build settings."
    exit 1
fi
echo "  Minimum macOS version: $MIN_OS_VERSION"

# ── Archive ──────────────────────────────────────────────────────────────────

echo ""
echo "→ Archiving (this takes a minute)..."
xcodebuild archive \
    -project "$SCRIPT_DIR/dynamicNotch.xcodeproj" \
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

create-dmg \
    --volname "DynamicNotch" \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 128 \
    --icon "DynamicNotch.app" 180 185 \
    --hide-extension "DynamicNotch.app" \
    --app-drop-link 480 185 \
    --no-internet-enable \
    "$DMG_PATH" \
    "$STAGING/" 2>&1 | grep -v "^$" || true

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

python3 - "$APPCAST" "$VERSION" "$BUILD_NUM" "$RELEASE_DATE" "$DOWNLOAD_URL" "$ED_SIG" "$FILE_LEN" "$MIN_OS_VERSION" <<'PYEOF'
import sys
path, version, build, date, url, sig, length, min_os = sys.argv[1:]
new_item = (
    f"\n    <item>\n"
    f"      <title>Version {version}</title>\n"
    f"      <pubDate>{date}</pubDate>\n"
    f"      <sparkle:version>{build}</sparkle:version>\n"
    f"      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>\n"
    f"      <sparkle:minimumSystemVersion>{min_os}</sparkle:minimumSystemVersion>\n"
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

# ── Homebrew cask ────────────────────────────────────────────────────────────
# Homebrew's `depends_on macos:` only accepts codename symbols, not raw version
# numbers, so MIN_OS_VERSION (resolved above from MACOSX_DEPLOYMENT_TARGET) is
# mapped to the matching symbol here. This keeps the cask's OS gate in sync
# with Sparkle's sparkle:minimumSystemVersion instead of a hardcoded codename
# that could go stale and let brew install a build the Mac can't run.

echo ""
echo "→ Resolving Homebrew macOS codename for ${MIN_OS_VERSION}..."
MIN_OS_MAJOR="${MIN_OS_VERSION%%.*}"
case "$MIN_OS_MAJOR" in
    11) MACOS_CODENAME="big_sur" ;;
    12) MACOS_CODENAME="monterey" ;;
    13) MACOS_CODENAME="ventura" ;;
    14) MACOS_CODENAME="sonoma" ;;
    15) MACOS_CODENAME="sequoia" ;;
    26) MACOS_CODENAME="tahoe" ;;
    27) MACOS_CODENAME="golden_gate" ;;
    *)
        echo "Error: No Homebrew codename mapping for macOS major version ${MIN_OS_MAJOR}."
        echo "Add it to the case statement in release.sh (check Homebrew's macos_version.rb"
        echo "SYMBOLS table for the correct name) before releasing, so the cask doesn't"
        echo "advertise an install that macOS refuses to run."
        exit 1
        ;;
esac
echo "  depends_on macos: :${MACOS_CODENAME}"

echo ""
echo "→ Publishing Homebrew cask to ${TAP_REPO}..."
CASK_SHA256=$(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)
TAP_CLONE="/tmp/homebrew-dynamicnotch-$$"
rm -rf "$TAP_CLONE"
gh repo clone "$TAP_REPO" "$TAP_CLONE" -- -q
mkdir -p "$TAP_CLONE/Casks"

cat > "$TAP_CLONE/Casks/${CASK_NAME}.rb" <<CASKEOF
cask "${CASK_NAME}" do
  version "${VERSION}"
  sha256 "${CASK_SHA256}"

  url "${DOWNLOAD_URL}"
  name "DynamicNotch"
  desc "Turns the MacBook notch into a live system dashboard"
  homepage "https://github.com/Hitjack007/DynamicNotch"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :${MACOS_CODENAME}

  app "DynamicNotch.app"

  postflight_steps do
    if_path_exists "DynamicNotch.app", base: :appdir do
      run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/DynamicNotch.app"]
    end
  end

  uninstall quit: "com.mark.dynamicnotch"

  zap trash: [
    "~/Library/Application Scripts/com.mark.dynamicnotch/",
    "~/Library/Containers/com.mark.dynamicnotch/",
  ]
end
CASKEOF

cd "$TAP_CLONE"
git add "Casks/${CASK_NAME}.rb"
if git diff --cached --quiet; then
    echo "  No cask changes to publish"
else
    git commit -m "Update ${CASK_NAME} to v${VERSION}"
    git push
    echo "  Cask updated: v${VERSION}"
fi
cd "$SCRIPT_DIR"
rm -rf "$TAP_CLONE"

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
