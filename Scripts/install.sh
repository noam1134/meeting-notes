#!/bin/zsh
# Build MeetingNotes (Release) and install to /Applications, then relaunch.
set -e
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild -project MeetingNotes.xcodeproj -scheme MeetingNotes -configuration Release \
    -derivedDataPath /tmp/mn-release-dd build | grep -E "BUILD (SUCCEEDED|FAILED)"
pkill -x MeetingNotes 2>/dev/null || true
sleep 1
rm -rf /Applications/MeetingNotes.app
ditto /tmp/mn-release-dd/Build/Products/Release/MeetingNotes.app /Applications/MeetingNotes.app
open /Applications/MeetingNotes.app
echo "Installed and launched /Applications/MeetingNotes.app"
