---
name: sketch
description: "Open a minimal Windows sketch canvas so the user can draw one or more sketches and use the finished PNGs as visual context. Use when the user invokes $sketch or says they want to personally draw first, including phrases such as \u753b\u8349\u56fe, \u6253\u5f00\u753b\u677f, \u8ba9\u6211\u753b\u4e00\u4e0b, \u5148\u753b\u4e2a\u793a\u610f\u56fe, or asks to draw a quick wireframe, diagram, or layout before Codex continues. Do not use when the user wants Codex to generate the image for them."
metadata:
  short-description: Draw a quick visual prompt
---

# Sketch

Open the bundled sketch canvas, wait for the user, inspect the exported PNG or PNGs, and continue the current request with those drawings as user-provided visual context.

Natural-language requests that clearly ask to open a canvas for the user should run this workflow directly; do not require the user to retype `$sketch`.

## Run

1. Tell the user the canvas is opening and this turn will wait for completion or cancellation.
2. Resolve this skill directory and run its bundled script with Windows PowerShell in STA mode:

   ```powershell
   powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File <skill-directory>\scripts\sketchpad.ps1
   ```

   A desktop window may require approval. Request only the permission needed to launch this bundled local script. Never launch a second canvas while the first process is still running.
3. Wait for the single JSON result from the process:
   - `completed`: use `paths` in order when present, otherwise fall back to the legacy `path`. Inspect every returned image, treat the images and optional returned `note` as user-provided context for the current request, and continue without asking the user to attach them again. Embed every PNG in the final response with Markdown image syntax and its absolute local path, converting backslashes to forward slashes.
   - `cancelled`: stop sketch-dependent work and say that no sketch was added.
   - `error`: report the returned message and do not claim that an image was created.

The exported sketches are temporary current-conversation artifacts. Never copy them into the skill directory or another workspace, never stage, commit, or push them with Git, and never upload them to GitHub or another external storage service.

## Canvas controls

- Left drag: draw in black
- Right drag: draw in red
- Hold `Shift` and drag with either mouse button: draw a black or red rectangle
- Hold `Alt` and drag with either mouse button: draw a black or red circle
- Mouse wheel: change pen size
- `1`: pen
- `2`: eraser
- `3`: toggle automatic line/circle/ellipse/rectangle correction
- `4`: show or hide the built-in shortcut guide
- Click the top buttons: switch pen, eraser, or automatic correction; the selected states stay visible
- Click the bottom arrows or press `PageUp` / `PageDown`: move between editable pages
- `Ctrl+N`: append a new page after drawing on the current page; up to six pages
- `Ctrl+Delete`: confirm and delete the current page; when only one page remains, clear it
- `Ctrl+Z`: undo; after automatic correction, the first undo restores the original stroke and the second removes it
- `Ctrl+Y` or `Ctrl+Shift+Z`: redo
- `Ctrl+Backspace`: ask for confirmation, then clear
- `Ctrl+Enter`: open the optional note field; press it again to finish with the note
- `Ctrl+Shift+Enter`: finish immediately without opening the note field
- `Esc`: close help or the note field, otherwise cancel; unsent content requires confirmation

If the user asks how to operate the canvas, answer from this list. The canvas is intentionally limited: do not imply that it supports placed text, selection, arbitrary colors, paste, layers, or editing placed objects.

This skill is Windows-only and uses local WPF components included with Windows PowerShell 5.1. It does not use the network, an API key, cloud storage, or clipboard data. The local temporary PNGs exist only so Codex can read and display them in the current conversation; they are not repository artifacts. Do not substitute AI-generated images for the user's sketches, and do not claim the drawings are visible unless the response actually embeds them.
