# MeetingNotes

Menu-bar Mac app: capture meeting notes + annotated screenshots with global
hotkeys; Claude Code processes sessions into Trello cards afterward.

## Use

- Menu bar → Start Meeting (or just hit a hotkey — it offers to start one).
- **⌃⇧S** — region screenshot → annotate (box/arrow/text) → note + category → ⏎.
- **⌃⇧N** — quick text note → category via ⌘1–⌘4 → ⏎.
- Menu bar → End Meeting when done. Browse Sessions shows everything.
- Hotkeys + categories editable in Settings (⌘,).

## After the meeting (Claude workflow)

Open Claude Code and say e.g. "process today's meeting notes". Claude should:

1. Read `~/Documents/MeetingNotes/<newest pending folder>/session.json` + PNGs.
2. Expand each note (screenshots give context), create Trello cards via the
   Trello MCP for notes categorized `Trello task`.
3. Set each handled note's `status` to `"processed"`, and the session's
   `status` to `"processed"` when done. Keep the JSON schema intact.

## Build

    brew install xcodegen
    xcodegen generate
    xcodebuild -project MeetingNotes.xcodeproj -scheme MeetingNotes build

Core logic tests: `cd Core && swift test`.

First screenshot needs Screen Recording permission (System Settings →
Privacy & Security), then relaunch.
