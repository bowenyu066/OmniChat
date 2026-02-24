#!/bin/bash
set -euo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "Usage: $0 <tag> <dmg-path> [sparkle-account]"
  echo "Example: $0 v0.4.0-beta ~/Downloads/OmniChat-v0.4.0-beta.dmg omnichat"
  exit 1
fi

TAG="$1"
DMG_PATH="$2"
ACCOUNT="${3:-omnichat}"

if [ ! -f "$DMG_PATH" ]; then
  echo "Error: DMG not found at $DMG_PATH"
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_PATH="$REPO_ROOT/appcast.xml"

find_sparkle_tool() {
  local tool_name="$1"
  find "$HOME/Library/Developer/Xcode/DerivedData" -path "*/SourcePackages/artifacts/sparkle/Sparkle/bin/$tool_name" | head -1
}

SIGN_TOOL="$(find_sparkle_tool sign_update)"
if [ -z "$SIGN_TOOL" ]; then
  echo "Sparkle tools not found. Resolving package dependencies..."
  xcodebuild -project "$REPO_ROOT/OmniChat.xcodeproj" -scheme OmniChat -resolvePackageDependencies >/dev/null
  SIGN_TOOL="$(find_sparkle_tool sign_update)"
fi

if [ -z "$SIGN_TOOL" ] || [ ! -x "$SIGN_TOOL" ]; then
  echo "Error: Sparkle sign_update tool not found. Build the project once in Xcode first."
  exit 1
fi

version_to_build() {
  local short_version="$1"
  local base suffix major minor patch rank prerelease_num

  base="${short_version%%-*}"
  suffix="${short_version#${base}}"
  suffix="${suffix#-}"

  IFS='.' read -r major minor patch <<< "$base"
  major="${major:-0}"
  minor="${minor:-0}"
  patch="${patch:-0}"

  rank=90
  if [ -n "$suffix" ]; then
    case "$suffix" in
      alpha* )
        prerelease_num="${suffix#alpha}"
        prerelease_num="${prerelease_num:-0}"
        rank=$((10 + prerelease_num))
        ;;
      beta* )
        prerelease_num="${suffix#beta}"
        prerelease_num="${prerelease_num:-0}"
        rank=$((30 + prerelease_num))
        ;;
      rc* )
        prerelease_num="${suffix#rc}"
        prerelease_num="${prerelease_num:-0}"
        rank=$((60 + prerelease_num))
        ;;
      * )
        rank=20
        ;;
    esac
  fi

  # Produces monotonic integer: MMmmppRR (major/minor/patch/pre-release-rank)
  echo $((10#$major * 1000000 + 10#$minor * 10000 + 10#$patch * 100 + rank))
}

SIGN_OUTPUT="$($SIGN_TOOL --account "$ACCOUNT" "$DMG_PATH")"
SIGNATURE="$(echo "$SIGN_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
LENGTH="$(echo "$SIGN_OUTPUT" | sed -n 's/.*length="\([0-9][0-9]*\)".*/\1/p')"

if [ -z "$SIGNATURE" ] || [ -z "$LENGTH" ]; then
  echo "Error: Failed to parse Sparkle signature output."
  echo "$SIGN_OUTPUT"
  exit 1
fi

SHORT_VERSION="${TAG#v}"
BUILD_VERSION="$(version_to_build "$SHORT_VERSION")"
DMG_NAME="$(basename "$DMG_PATH")"
DOWNLOAD_URL="https://github.com/bowenyu066/OmniChat/releases/download/${TAG}/${DMG_NAME}"
RELEASE_NOTES_URL="https://github.com/bowenyu066/OmniChat/releases/tag/${TAG}"
PUB_DATE="$(LC_ALL=C date -R)"

cat > "$OUTPUT_PATH" <<XML
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
        <title>OmniChat</title>
        <item>
            <title>${SHORT_VERSION}</title>
            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:fullReleaseNotesLink>${RELEASE_NOTES_URL}</sparkle:fullReleaseNotesLink>
            <sparkle:version>${BUILD_VERSION}</sparkle:version>
            <sparkle:shortVersionString>${SHORT_VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure url="${DOWNLOAD_URL}" sparkle:edSignature="${SIGNATURE}" length="${LENGTH}" type="application/octet-stream"/>
        </item>
    </channel>
</rss>
XML

echo "Updated $OUTPUT_PATH"
echo "  Tag: $TAG"
echo "  Short version: $SHORT_VERSION"
echo "  Sparkle version: $BUILD_VERSION"
echo "  DMG: $DMG_NAME"
