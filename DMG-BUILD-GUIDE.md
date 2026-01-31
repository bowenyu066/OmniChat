# DMG Build Guide for OmniChat

This guide documents the process for creating a properly formatted DMG installer for macOS distribution.

## DMG Structure

A proper macOS DMG installer should contain:

```
/Volumes/AppName vX.X.X/
├── YourApp.app                    # The application bundle
├── Applications                    # Alias (NOT symlink) to /Applications folder
├── .background/
│   └── background.png             # Background image (640x480 recommended)
├── .VolumeIcon.icns               # Custom volume icon (optional)
└── .DS_Store                      # Finder view settings (icon positions, background)
```

## Recommended Build Process (Hybrid Approach)

This is the **proven working method** that handles both background and Applications icon correctly.

### Prerequisites

```bash
# Install create-dmg tool (if not already installed)
brew install create-dmg

# Have a reference background image with arrow and instructions
# Located at: ~/Downloads/dmg-background.png (640x480, light gray background)
```

### Step 1: Build the App

```bash
# Build in Release configuration
xcodebuild -project OmniChat.xcodeproj -scheme OmniChat -configuration Release clean build

# Locate the built app
APP_PATH=~/Library/Developer/Xcode/DerivedData/OmniChat-*/Build/Products/Release/OmniChat.app
```

### Step 2: Create Initial DMG with create-dmg

The `create-dmg` tool properly sets up backgrounds using AppleScript, but creates symlinks (not aliases) for Applications.

```bash
create-dmg \
  --volname "OmniChat vX.X.X-beta" \
  --background ~/Downloads/dmg-background.png \
  --window-pos 200 120 \
  --window-size 640 480 \
  --icon-size 128 \
  --icon "OmniChat.app" 190 240 \
  --hide-extension "OmniChat.app" \
  --app-drop-link 450 240 \
  ~/Downloads/OmniChat-vX.X.X-beta-PREVIEW.dmg \
  "$APP_PATH"
```

### Step 3: Convert to Writable and Fix Applications Alias

The symlink created by `create-dmg` won't show the folder icon. Replace it with a proper alias.

```bash
# Convert to writable DMG
hdiutil convert ~/Downloads/OmniChat-vX.X.X-beta-PREVIEW.dmg \
  -format UDRW \
  -o ~/Downloads/OmniChat-rw.dmg

# Mount the writable DMG
hdiutil attach ~/Downloads/OmniChat-rw.dmg

# Download and mount previous release to get the Applications alias
gh release download v0.2.2-beta --pattern "*.dmg" --dir /tmp
hdiutil attach /tmp/OmniChat-v0.2.2-beta.dmg -readonly

# Replace symlink with proper alias
rm "/Volumes/OmniChat vX.X.X-beta/Applications"
cp "/Volumes/OmniChat v0.2.2-beta/Applications" "/Volumes/OmniChat vX.X.X-beta/"

# Unmount both
hdiutil detach "/Volumes/OmniChat vX.X.X-beta"
hdiutil detach "/Volumes/OmniChat v0.2.2-beta"
```

### Step 4: Convert Back to Compressed Format

```bash
# Remove the preview DMG
rm ~/Downloads/OmniChat-vX.X.X-beta-PREVIEW.dmg

# Convert to final compressed DMG
hdiutil convert ~/Downloads/OmniChat-rw.dmg \
  -format UDZO \
  -o ~/Downloads/OmniChat-vX.X.X-beta.dmg

# Clean up
rm ~/Downloads/OmniChat-rw.dmg /tmp/OmniChat-v0.2.2-beta.dmg
```

### Step 5: Preview Before Upload

**ALWAYS preview the DMG before uploading:**

```bash
open ~/Downloads/OmniChat-vX.X.X-beta.dmg
```

**Checklist:**
- [ ] Light background visible (works in both Light and Dark Mode)
- [ ] Arrow and "Drag to Applications to install" text visible
- [ ] Applications folder shows blue folder icon with App Store symbol
- [ ] OmniChat app icon displays correctly
- [ ] Icons properly positioned
- [ ] Window size correct, no toolbar/statusbar
- [ ] Drag-and-drop to Applications works

### Step 6: Upload to GitHub Release

```bash
# Delete old asset if exists
gh release delete-asset vX.X.X-beta "OmniChat-vX.X.X-beta.dmg" --yes

# Upload new DMG
gh release upload vX.X.X-beta ~/Downloads/OmniChat-vX.X.X-beta.dmg
```

---

## Background Image

### Current Background
The background image (`dmg-background.png`) should be:
- **Dimensions:** 640x480 pixels
- **Background color:** Light gray (#E8E8E8 to #F0F0F0)
- **Contains:** Arrow pointing from left to right, instruction text at bottom

### Location
Keep a copy of the working background at:
- `~/Downloads/dmg-background.png` (for builds)
- Or download from v0.2.2-beta DMG: `.background/background.png`

---

## Common Issues & Solutions

### Issue: Applications folder shows empty/dashed outline
**Cause:** `create-dmg` uses symlinks, which don't show folder icons
**Solution:** Replace symlink with proper macOS Alias from previous release (Step 3 above)

### Issue: Dark background despite light background.png
**Cause:** Old .DS_Store with cached dark background settings
**Solution:** Use `create-dmg` which creates fresh .DS_Store with AppleScript

### Issue: Background not showing at all
**Cause:** .DS_Store missing or corrupted
**Solution:** Use `create-dmg` to regenerate proper window settings

### Issue: Icons in wrong positions
**Cause:** .DS_Store has different icon coordinates
**Solution:** Adjust `--icon` and `--app-drop-link` coordinates in create-dmg command

---

## Quick Reference Commands

```bash
# Build app
xcodebuild -project OmniChat.xcodeproj -scheme OmniChat -configuration Release clean build

# Create DMG with create-dmg
create-dmg --volname "OmniChat vX.X.X" --background ~/Downloads/dmg-background.png \
  --window-size 640 480 --icon-size 128 --icon "OmniChat.app" 190 240 \
  --app-drop-link 450 240 ~/Downloads/output.dmg /path/to/OmniChat.app

# Convert DMG to writable
hdiutil convert input.dmg -format UDRW -o output-rw.dmg

# Convert DMG to compressed
hdiutil convert input-rw.dmg -format UDZO -o output.dmg

# Mount DMG
hdiutil attach file.dmg

# Unmount DMG
hdiutil detach "/Volumes/VolumeName"

# Upload to GitHub release
gh release upload vX.X.X-beta file.dmg
```

---

## Files to Keep

For future builds, keep these files accessible:
1. **`dmg-background.png`** - Background image with arrow and text (640x480)
2. **Previous release DMG** - Source for Applications alias

---

**Last Updated:** 2026-01-30
**Version:** 2.0 (Hybrid approach with create-dmg + alias fix)
