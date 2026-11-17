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

## Version and updates

- The installed version is in the bottom bar and in **About GDC Metadata** (version and build).
- **Check for Updates…** (app menu) always answers: new version, “You're up to date”, or “Could not check” with the reason. **Update Now** downloads, verifies and installs, then restarts the app.
- Coming from 0.1.0 (no updater): install the new DMG once; later updates are done from the app.

## Full manual

- Complete PDF manual: Help button / menu **Help**, or https://gordas.dev/gdc-metadata/GDC-Metadata-Manual-en.pdf
