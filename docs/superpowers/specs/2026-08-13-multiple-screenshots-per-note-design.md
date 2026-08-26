# Multiple screenshots per note

**Date:** 2026-08-13
**Status:** Approved

## Problem

A note holds at most one screenshot, fixed at the moment of capture. There is no way to
add a screenshot to a note that already exists. This surfaced while repairing the
image-filename collision bug (`fix(core): never reuse an image filename`): two notes lost
their screenshots permanently, and the only recovery path was re-capturing them — which
the app could not do without creating a new, duplicate note.

## Goals

- Attach a screenshot to an existing note.
- Hold several screenshots on one note.
- Preserve every existing session on disk without a migration step.

## Non-goals

- Pasting from the clipboard, or dragging image files onto a note. Considered and
  dropped: capture-from-note covers the actual need and reuses the existing annotate
  pipeline. Revisit only if the capture flow proves awkward in practice.
- Reordering a note's screenshots.

## Data model

`Note.image: String?` becomes `Note.images: [String]`.

Decoding accepts both shapes:

| on disk | decodes to |
|---|---|
| `"images": ["img-001.png", "img-004.png"]` | `["img-001.png", "img-004.png"]` |
| `"image": "img-001.png"` (legacy) | `["img-001.png"]` |
| `"image": null` (legacy) | `[]` |
| neither key | `[]` |

Encoding writes `images` only. Sessions migrate lazily, on the first write to each. The
legacy `image` key is deliberately **not** written alongside: two fields that must agree
is the same shape as the collision bug this feature grew out of.

Claude's processing prompt asks it to "read session.json and the PNG screenshots" without
naming fields, so the rename does not break processing. Only `trello` is named in the
prompt, and it is unchanged.

## Store API

All allocation goes through the existing `nextImageName(in:notes:)`, which probes
`img-001`, `img-002`, … until a name is free of both any note's reference and any file on
disk. `nextImageName` reads `notes.flatMap(\.images)` after this change.

- `attachImage(noteID:in:imageData:) throws -> String` — allocate, write
  `.withoutOverwriting`, append to the note's `images`. Throws `noteNotFound` for an
  unknown id.
- `detachImage(noteID:in:named:) throws` — drop the reference; trash the file only if no
  surviving note references it.
- `deleteNote` — trash *every* image the note holds, each guarded by the same
  reference check.

`addNote` keeps its signature; a captured screenshot becomes a one-element array.

Deletion trashes rather than removes, matching `deleteSession`.

## Attaching

Note context menu gains **Add Screenshot…**, which runs the existing capture pipeline:
region select → annotate → flatten to PNG.

`CaptureController.begin` gains a destination:

- `.newNote` — today's behavior, bound to ⌃⇧S.
- `.existingNote(id:folder:)` — `CaptureNoteView` hides the text/category composer and
  shows the annotation tools plus an **Attach** button; save calls `attachImage`.

The Sessions window hides during region select and is restored afterward, so it does not
appear in the capture. Consequence: the Sessions window cannot be captured this way.

## Card layout

Screenshots move from the right-hand column to a centered strip beneath the note text.
This applies to single-screenshot notes too, so every card has one consistent shape.

- Three thumbnails visible at a time.
- Chevrons and page dots appear only when the note holds more than three.
- Two-finger trackpad swipe pages the strip as well.
- Paging state is per note, local to the card.

`noteThumbnail` becomes `noteThumbnailStrip`.

## Preview window

`PreviewWindowController.show` takes the note's image list and a starting index. ← / →
page through; a counter shows position ("2 of 5"). Escape closes, unchanged.

## Copy and remove

`Copy Screenshot` moves off the note context menu — ambiguous once a note has several —
onto a right-click on the thumbnail itself, alongside `Remove Screenshot`.

## Testing

Core tests, written before implementation:

- Legacy `image` string decodes into `images`; legacy null and absent key decode to empty.
- `images` round-trips through encode/decode.
- `attachImage` never returns a name held by another note or present on disk.
- `attachImage` to an unknown note id throws `noteNotFound`.
- `detachImage` keeps a file that another note still references.
- `deleteNote` trashes every image the note holds.

The existing 43 tests must keep passing.

## Build order

Core (model, store, tests) first and fully green, then the App layer (capture destination,
card strip, preview paging, context menus). One branch.
