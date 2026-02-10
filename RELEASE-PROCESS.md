# OmniChat Release Process

This document describes how to create a new release for OmniChat.

## Quick Reference (For Claude)

Just tell Claude:
> "Create a new release v0.3.X-beta with title 'Feature Name'"

Claude will:
1. Update version in Xcode project
2. Build Release app
3. Create DMG with proper Applications alias
4. Create source ZIP
5. Commit and push changes
6. Create GitHub release with assets

---

## Manual Release (Using Script)

### Prerequisites

```bash
# Install required tools (one-time)
brew install create-dmg gh

# Authenticate GitHub CLI (one-time)
gh auth login

# Ensure DMG background exists
ls ~/Downloads/dmg-background.png
```

### Run Release Script

```bash
cd /Users/flyfishyu/Documents/2026/claude/OmniChat
./scripts/release.sh v0.3.X-beta
```

The script will prompt for:
- Release title (e.g., "Auto-Update Notifications")
- Release notes (multi-line, press Ctrl+D when done)

---

## Step-by-Step Manual Process

If you prefer manual control, here are the steps:

### 1. Update Version Number

Edit `OmniChat.xcodeproj/project.pbxproj` and change:
```
MARKETING_VERSION = 0.3.X-beta;
```

### 2. Build Release App

```bash
xcodebuild -project OmniChat.xcodeproj -scheme OmniChat -configuration Release clean build
```

### 3. Create Initial DMG

```bash
VERSION="v0.3.X-beta"
APP_PATH=~/Library/Developer/Xcode/DerivedData/OmniChat-*/Build/Products/Release/OmniChat.app

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
  "$APP_PATH"
```

### 4. Fix Applications Alias

```bash
# Convert to writable
hdiutil convert ~/Downloads/OmniChat-${VERSION}-PREVIEW.dmg -format UDRW -o ~/Downloads/OmniChat-rw.dmg
hdiutil attach ~/Downloads/OmniChat-rw.dmg

# Get alias from previous release
gh release download v0.3.1-beta --pattern "*.dmg" --dir /tmp
hdiutil attach /tmp/OmniChat-v0.3.1-beta.dmg -readonly

# Replace symlink with alias
rm "/Volumes/OmniChat ${VERSION}/Applications"
cp "/Volumes/OmniChat v0.3.1-beta/Applications" "/Volumes/OmniChat ${VERSION}/"

# Cleanup and finalize
hdiutil detach "/Volumes/OmniChat ${VERSION}"
hdiutil detach "/Volumes/OmniChat v0.3.1-beta"
rm ~/Downloads/OmniChat-${VERSION}-PREVIEW.dmg
hdiutil convert ~/Downloads/OmniChat-rw.dmg -format UDZO -o ~/Downloads/OmniChat-${VERSION}.dmg
rm ~/Downloads/OmniChat-rw.dmg
```

### 5. Create Source ZIP

```bash
zip -r ~/Downloads/OmniChat-${VERSION}-source.zip . \
  -x "*.git*" -x "*.DS_Store" -x "*DerivedData*" -x "*.xcuserdata*"
```

### 6. Create GitHub Release

```bash
gh release create ${VERSION} \
  --repo bowenyu066/OmniChat \
  --title "${VERSION} - Feature Name" \
  --notes "Release notes here..." \
  --prerelease \
  ~/Downloads/OmniChat-${VERSION}.dmg \
  ~/Downloads/OmniChat-${VERSION}-source.zip
```

---

## Checklist Before Release

- [ ] All code changes committed and pushed
- [ ] CHANGELOG.md updated with new version
- [ ] Version number updated in Xcode project
- [ ] App builds successfully in Release mode
- [ ] DMG opens correctly with proper background
- [ ] Applications folder shows blue icon (not broken symlink)
- [ ] Drag-and-drop to Applications works
- [ ] GitHub release created with both DMG and source ZIP

---

## Files Involved

| File | Purpose |
|------|---------|
| `OmniChat.xcodeproj/project.pbxproj` | Contains `MARKETING_VERSION` |
| `CHANGELOG.md` | Version history and release notes |
| `~/Downloads/dmg-background.png` | DMG background image (640x480) |
| `scripts/release.sh` | Automated release script |

---

## Version Numbering

Format: `vX.Y.Z-beta` or `vX.Y.Z`

- **X** (Major): Breaking changes, major features
- **Y** (Minor): New features, enhancements
- **Z** (Patch): Bug fixes, small improvements
- **-beta**: Pre-release suffix

Examples:
- `v0.3.2-beta` → Beta release with auto-update feature
- `v1.0.0` → First stable release
- `v1.0.1` → Patch release for v1.0.0

---

**Last Updated:** 2026-02-09
