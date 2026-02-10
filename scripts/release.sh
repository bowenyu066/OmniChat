#!/bin/bash
#
# OmniChat Release Script
# Usage: ./scripts/release.sh <version>
# Example: ./scripts/release.sh v0.3.3-beta
#
# This script automates the entire release process:
# 1. Updates version number in Xcode project
# 2. Builds the Release app
# 3. Creates the DMG with proper Applications alias
# 4. Creates source code ZIP
# 5. Creates GitHub release with assets
#
# Prerequisites:
# - brew install create-dmg gh
# - gh auth login (GitHub CLI authenticated)
# - ~/Downloads/dmg-background.png exists
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check arguments
if [ -z "$1" ]; then
    echo -e "${RED}Error: Version required${NC}"
    echo "Usage: ./scripts/release.sh <version>"
    echo "Example: ./scripts/release.sh v0.3.3-beta"
    exit 1
fi

VERSION="$1"
VERSION_NUMBER="${VERSION#v}"  # Remove 'v' prefix for Xcode

# Validate version format
if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9]+)?$ ]]; then
    echo -e "${RED}Error: Invalid version format${NC}"
    echo "Expected format: vX.Y.Z or vX.Y.Z-beta"
    exit 1
fi

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  OmniChat Release Script${NC}"
echo -e "${BLUE}  Version: ${VERSION}${NC}"
echo -e "${BLUE}========================================${NC}"

# Check prerequisites
echo -e "\n${YELLOW}[1/8] Checking prerequisites...${NC}"

if ! command -v create-dmg &> /dev/null; then
    echo -e "${RED}Error: create-dmg not installed. Run: brew install create-dmg${NC}"
    exit 1
fi

if ! command -v gh &> /dev/null; then
    echo -e "${RED}Error: GitHub CLI not installed. Run: brew install gh${NC}"
    exit 1
fi

if [ ! -f ~/Downloads/dmg-background.png ]; then
    echo -e "${RED}Error: DMG background not found at ~/Downloads/dmg-background.png${NC}"
    exit 1
fi

echo -e "${GREEN}✓ All prerequisites met${NC}"

# Update version in Xcode project
echo -e "\n${YELLOW}[2/8] Updating version to ${VERSION_NUMBER}...${NC}"
cd "$PROJECT_ROOT"
sed -i '' "s/MARKETING_VERSION = .*;/MARKETING_VERSION = ${VERSION_NUMBER};/g" OmniChat.xcodeproj/project.pbxproj
echo -e "${GREEN}✓ Version updated in Xcode project${NC}"

# Build Release version
echo -e "\n${YELLOW}[3/8] Building Release version...${NC}"
xcodebuild -project OmniChat.xcodeproj -scheme OmniChat -configuration Release clean build 2>&1 | tail -5
APP_PATH=$(ls -d ~/Library/Developer/Xcode/DerivedData/OmniChat-*/Build/Products/Release/OmniChat.app)
echo -e "${GREEN}✓ Build successful: $APP_PATH${NC}"

# Verify version in built app
BUILT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
echo -e "   Built app version: ${BUILT_VERSION}"

# Clean up old DMG files
echo -e "\n${YELLOW}[4/8] Creating DMG...${NC}"
rm -f ~/Downloads/OmniChat-${VERSION}-PREVIEW.dmg ~/Downloads/OmniChat-rw.dmg ~/Downloads/OmniChat-${VERSION}.dmg 2>/dev/null || true

# Create initial DMG
create-dmg \
  --volname "OmniChat ${VERSION}" \
  --background ~/Downloads/dmg-background.png \
  --window-pos 200 120 \
  --window-size 640 480 \
  --icon-size 128 \
  --icon "OmniChat.app" 190 240 \
  --hide-extension "OmniChat.app" \
  --app-drop-link 450 240 \
  ~/Downloads/OmniChat-${VERSION}-PREVIEW.dmg \
  "$APP_PATH" 2>&1 | tail -3

# Convert to writable and fix Applications alias
echo -e "\n${YELLOW}[5/8] Fixing Applications alias...${NC}"
hdiutil convert ~/Downloads/OmniChat-${VERSION}-PREVIEW.dmg -format UDRW -o ~/Downloads/OmniChat-rw.dmg 2>&1 | tail -1
hdiutil attach ~/Downloads/OmniChat-rw.dmg 2>&1 | tail -1

# Get previous release for Applications alias
PREV_VERSION=$(gh release list --repo bowenyu066/OmniChat --limit 1 | head -1 | awk '{print $3}')
echo "   Previous release: ${PREV_VERSION}"

gh release download "${PREV_VERSION}" --pattern "*.dmg" --dir /tmp --clobber 2>&1 | tail -1
hdiutil attach /tmp/OmniChat-${PREV_VERSION}.dmg -readonly 2>&1 | tail -1

# Replace symlink with alias
rm "/Volumes/OmniChat ${VERSION}/Applications" 2>/dev/null || true
cp "/Volumes/OmniChat ${PREV_VERSION}/Applications" "/Volumes/OmniChat ${VERSION}/"

# Unmount and finalize
hdiutil detach "/Volumes/OmniChat ${VERSION}" 2>&1 | tail -1
hdiutil detach "/Volumes/OmniChat ${PREV_VERSION}" 2>&1 | tail -1
rm ~/Downloads/OmniChat-${VERSION}-PREVIEW.dmg
hdiutil convert ~/Downloads/OmniChat-rw.dmg -format UDZO -o ~/Downloads/OmniChat-${VERSION}.dmg 2>&1 | tail -1
rm ~/Downloads/OmniChat-rw.dmg /tmp/OmniChat-${PREV_VERSION}.dmg 2>/dev/null || true

echo -e "${GREEN}✓ DMG created: ~/Downloads/OmniChat-${VERSION}.dmg${NC}"
ls -lh ~/Downloads/OmniChat-${VERSION}.dmg

# Create source ZIP
echo -e "\n${YELLOW}[6/8] Creating source ZIP...${NC}"
cd "$PROJECT_ROOT"
zip -r ~/Downloads/OmniChat-${VERSION}-source.zip . \
  -x "*.git*" \
  -x "*.DS_Store" \
  -x "*DerivedData*" \
  -x "*.xcuserdata*" \
  -x "*xcshareddata*" \
  -x "*.build*" \
  2>&1 | tail -1
echo -e "${GREEN}✓ Source ZIP created${NC}"
ls -lh ~/Downloads/OmniChat-${VERSION}-source.zip

# Prompt for release notes
echo -e "\n${YELLOW}[7/8] Creating GitHub release...${NC}"
echo -e "${BLUE}Enter release title (e.g., 'Auto-Update Notifications'):${NC}"
read -r RELEASE_TITLE

echo -e "${BLUE}Enter brief release notes (press Ctrl+D when done):${NC}"
RELEASE_NOTES=$(cat)

# Create release
gh release create ${VERSION} \
  --repo bowenyu066/OmniChat \
  --title "${VERSION} - ${RELEASE_TITLE}" \
  --notes "${RELEASE_NOTES}" \
  --prerelease \
  ~/Downloads/OmniChat-${VERSION}.dmg \
  ~/Downloads/OmniChat-${VERSION}-source.zip

echo -e "\n${YELLOW}[8/8] Committing version change...${NC}"
cd "$PROJECT_ROOT"
git add -A
git commit -m "Release ${VERSION}

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>" || echo "No changes to commit"
git push origin main

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}  Release ${VERSION} Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Release URL: https://github.com/bowenyu066/OmniChat/releases/tag/${VERSION}"
echo -e "\nAssets uploaded:"
echo -e "  - OmniChat-${VERSION}.dmg"
echo -e "  - OmniChat-${VERSION}-source.zip"
