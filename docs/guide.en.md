# GDC Metadata — User guide

## Folder → inspector → Media Pool

1. **Open a folder** (toolbar folder button). The app scans it read-only and lists clips: camera, timecode and more.
2. **Inspector.** Select a clip to see camera, lens, white balance, exposure and image profile. Each value shows its source (embedded tag, derived, unavailable). Search by field or value; the banner explains why a clip matches.
3. **Send to Resolve.** Open a project in Resolve first. The sheet previews, per clip, what will be written, kept and identical.
4. **Apply to Media Pool** writes the values.

## Input gamut and transfer curve

The two values at the top of the inspector tell you which input to choose in colour management: e.g. a Canon C50 clip shows **Cinema Gamut** + **Canon Log 2** (read from the file's `cndm` track) — in Resolve pick *Canon Cinema Gamut / Canon Log 2*; a Canon Log 3 clip shows **Canon Log 3**. Each value has its source; with no evidence the row says **Unavailable** and nothing is assigned. Resolve detects many Canon clips by itself at import. **Apply to Media Pool** only writes informational notes (Gamma Notes / Color Space Notes); **Set input colour space…** is a separate confirmed action that changes colour processing, works in DaVinci YRGB Color Managed projects and never overwrites an existing choice. Manual path: Project Settings ▸ Color Management ▸ DaVinci YRGB Color Managed, then Media Pool ▸ right-click clip ▸ Input Color Space.

## What Apply does (verified in Resolve, after closing and reopening the project)

- Empty field → written.
- Field that already has a value → kept (not overwritten).
- Same clip present in more than one bin → ambiguous, not applied.
- Clips are matched by real file path, so folders reached through links still match.

## CSV as an alternative

- Save the CSV from the sheet, then in Resolve: File → Import Metadata To → Media Pool…
- Options verified: tick **Match using filename**; leave **Match using clip start and end Timecode** unticked (with it ticked Resolve reported no matching entries for our CSV); leave Reel Name unticked; merge option **Only update metadata items with entries in the source file**.
- **Warning:** the import overwrites existing values.
- **Duplicate file names:** Resolve matches by file name, so every clip with that name (in any bin, even from different folders) receives the same values. Use Apply to Media Pool to avoid this.

## Motion & stabilization

- The inspector lists detected motion data (in-clip telemetry, external logs, .gyroflow projects) with where each was found.
- Sources are shown as **Gyroflow compatibility unverified**. Stabilization is not offered: no before/after route has been demonstrated in Resolve yet.

## Several clips, folders, second batch

- **Drag clips or a folder** onto the window, in one gesture and in any number. Or use **Choose folder…** (⌘O) and select several files and folders at once.
- A new import is **added** to the list; the first batch is kept. **File → Clear list** starts over.
- The bottom bar says how many clips were imported; if any file was refused, click “imported · rejected” to see the reason for each.
- Same-name clips from different folders stay separate.

## Wide window, narrow window, large frame

In a wide window the list is a table: Clip (with thumbnail), Gamut / curve, Camera, Lens, White balance, Exposure, Timecode. In a narrow window Clip, Gamut / curve and the full Timecode stay. **Enlarge frame** (or double-click the preview) opens a large static frame; **Esc** closes it and the selection, active clip, filter and table position are kept.

## Example: a Sony batch to Resolve

1. Select two clips (click, ⌘-click; or Tab to the table and Shift+↓). The bar reads “2 selected of 3”.
2. **Send 2 to Resolve** → see per row how many fields are written and kept → **Apply to Media Pool** (informative metadata only).
3. Separately: **Set input colour space…** → confirm for the 2 clips (changes colour processing).
4. Save and reopen the project in Resolve and compare.

## Version and updates

- The installed version is in the bottom bar and in **About GDC Metadata** (version and build).
- **Check for Updates…** (app menu) always answers: new version, “You're up to date”, or “Could not check” with the reason. **Update Now** downloads, verifies and installs, then restarts the app.
- Coming from 0.1.0 (no updater): install the new DMG once; later updates are done from the app.

## Full manual

- Complete PDF manual: Help button / menu **Help**, or https://gordas.dev/gdc-metadata/GDC-Metadata-Manual-en.pdf


**Batches (0.3.0).** Select with click/Shift/⌘/⌘A, press **Accept for export** (each clip keeps its own pair; reversible), then **Export N clips** or **Send N to Resolve** — exactly on the selection. **Remove from list** (⌘⌫) and **Clear list** (⇧⌘⌫) only affect the list. Values the readers did not find show as **Not detected**, not as “missing”. Sony: curve and gamut are read from the embedded metadata; S-Gamut3.Cine ≠ S-Gamut3.
