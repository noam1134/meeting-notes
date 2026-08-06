# Meeting Notes App — Design Spec

**Date:** 2026-08-06
**Status:** Approved by user

## Problem

Current workflow: during meetings, jot short notes in WhatsApp; after the meeting, expand them with Claude and manually create Trello tasks. Screenshots are captured separately and juggled by hand.

Replace this with a dedicated native Mac app: capture notes and annotated screenshots during the meeting with near-zero friction, then let Claude Code read the captured session and create the Trello tasks via the already-connected Trello MCP.

## Decisions Made

| Question | Decision |
|---|---|
| Platform | Native Mac app (Swift/SwiftUI), menu-bar app, no dock icon |
| Claude access to notes | Plain files on disk (parked: app-side MCP server — revisit later) |
| Note organization | Explicit meeting sessions (start/end) |
| Categories | Fixed user-editable set; defaults: Trello task, Decision, Question, FYI |
| Annotation tools (v1) | Rectangle box, arrow, text label |
| Global shortcuts | Screenshot-region hotkey + quick-text-note hotkey |
| Trello in app | None in v1 — Claude owns Trello via its MCP. App only tracks note status |

## Architecture

SwiftUI menu-bar app (`MenuBarExtra`). Components:

1. **Session store** — owns sessions and notes; persists to plain files (see Storage). Single source of truth; all UI reads through it.
2. **Hotkey manager** — global shortcuts via the `KeyboardShortcuts` SPM package. Defaults: ⌃⇧S (screenshot), ⌃⇧N (quick note); editable in settings.
3. **Screenshot capture** — ScreenCaptureKit. Region select via custom full-screen transparent overlay window with crosshair drag. Requires one-time Screen Recording permission.
4. **Capture window** — appears after region select: image preview, annotation toolbar (box / arrow / text via SwiftUI Canvas overlay), note text field beneath the image, category picker. Enter saves and dismisses.
5. **Quick-note panel** — Spotlight-style non-activating floating `NSPanel`: text field + category picker (keys 1–4). Enter saves and dismisses. Meeting app keeps focus.
6. **Main window** — session browser: active session, pending sessions, processed sessions. Opens from menu bar on demand.

## Session Lifecycle

- Menu bar → **Start meeting** (name optional, default `YYYY-MM-DD-HHmm`). One active session at a time.
- All hotkey captures land in the active session.
- Hotkey with no active session → inline prompt to start one (single keystroke to confirm).
- **End meeting** closes the session → status `pending`.
- After Claude processes it (creates Trello cards), notes/session flip to `processed`. Claude edits the JSON directly; app picks up changes on next read.

## Storage (the integration contract)

Plain files under `~/Documents/MeetingNotes/`:

```
~/Documents/MeetingNotes/
  2026-08-06-1030-sprint-planning/
    session.json
    img-001.png
    img-002.png
```

`session.json` shape:

```json
{
  "name": "sprint-planning",
  "startedAt": "2026-08-06T10:30:00+03:00",
  "endedAt": "2026-08-06T11:15:00+03:00",
  "status": "pending",
  "notes": [
    {
      "id": "uuid",
      "timestamp": "2026-08-06T10:42:11+03:00",
      "category": "Trello task",
      "text": "fix login redirect bug — see screenshot",
      "image": "img-001.png",
      "status": "pending"
    }
  ]
}
```

`image` is null for text-only notes. This file layout **is** the Claude integration: Claude Code reads the folder, expands the notes, creates Trello cards through the Trello MCP, and writes `status: "processed"` back. No API, no server.

The app must tolerate external edits to `session.json` (re-read before display; last-writer-wins is acceptable for v1 since the app only writes during an active session and Claude only writes after it ends).

## Categories

Stored in app settings (UserDefaults or a small config JSON). Defaults: `Trello task`, `Decision`, `Question`, `FYI`. Editable list in settings. Category is a plain string on each note — renaming a category does not rewrite old notes (v1).

## Error Handling

- Screen Recording permission missing → capture hotkey opens an explainer with a button to System Settings.
- Storage folder missing/unwritable → surface error in menu bar item; never silently drop a note.
- Malformed `session.json` (e.g. bad external edit) → keep the file untouched, show session as unreadable with a "reveal in Finder" action; never overwrite with empty data.

## Testing

- Unit tests: session store CRUD, JSON round-trip (schema stability matters — Claude depends on it), external-edit tolerance, category settings.
- Manual verification: hotkeys, region capture, annotation, permission flow (system permission dialogs can't run headless).

## Out of Scope (v1) / Parked

- App-side MCP server exposing sessions to Claude (parked; revisit if file reading shows friction).
- Trello API in the app (read-only card links or in-app card creation).
- Freehand pen and blur/redact annotation tools.
- Full-window capture hotkey.
- iPhone/web capture.
