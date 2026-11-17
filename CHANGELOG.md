# Changelog

## 0.3.0
- Batches: native multi-selection (click, Shift, ⌘, ⌘A); **Export N clips** and **Send N to Resolve** act on exactly the selection (also when a filter hides part of it); **Remove from list** and **Clear list** next to the table.
- **Accept for export**: the detected gamut + curve pair is confirmed per clip (reversible); read, inferred and confirmed values are shown distinctly and exported with their provenance.
- Sony XAVC S MP4: curve, gamut, camera, exposure and timecode read from the embedded Sony metadata (or the card-structure XML); S-Gamut3.Cine and S-Gamut3 are told apart.
- Values the readers do not find show as "Not detected" instead of a claim about the file.
- Resolve: informative metadata and input space are separated in the sheet; input space names verified for Sony, Panasonic V-Log and Canon pairs.

## 0.2.0
- Inspector: **Input gamut** and **Transfer curve** at the top, each with its own source; "Unavailable" when the file carries nothing. Canon Cinema EOS / EOS R MP4 (`cndm` track): Canon Log 2 / Canon Log 3 with Cinema Gamut.
- Container labels and camera maker-note hints are shown separately and never assigned as the camera profile; conflicting sources show both values.
- Send to Resolve: separate, confirmed action to set Input Color Space (DaVinci YRGB Color Managed projects only, never overwrites an existing choice).
- Includes 0.1.1: multi-clip import, app icon, version and updates in the app, PDF manual (RO/EN/ES).

## 0.1.1 (not published separately)
- Import of several clips/folders at once, app icon, in-app updates, PDF manual.

## 0.1.0
- First public release.
