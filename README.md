# DjVu Reader

A native DjVu reader for macOS 14+. Free, open source (GPL 2.0 or later).
Decoder — DjVuLibre 3.5.30: its source code is included in the project and is built along with the app.

## Version 0.3 — Features

- Opens .djvu and .djv files, single-file and multi-file (indirect): double-click, "File → Open," or drag-and-drop. Tabs, "Recent Documents," and window restoration are native.
- Continuous scrolling. Pages are drawn in tiles based on the screen resolution, so text is sharp at any zoom level. Only the pages closest to the screen are stored in memory: a 2,000-page book opens as quickly as a 20-page one.
- Zoom: Width ⌘1, Full Page ⌘2, Actual Size ⌘0, ⌘=, and ⌘−, pinch on the trackpad. Double-tap with two fingers to zoom to the page width under the cursor, double-tap to zoom back.
- Sidebar: Thumbnails (load as you scroll) and document table of contents. Custom page captions from the file are shown as "iv (12)".
- Navigation: page number field in the toolbar, ⌥⌘G, ⌥⌘↓, and ⌥⌘↑ — next and previous, ⌘↑ and ⌘↓ — first and last, ← and → — by page, spacebar and ⇧spacebar — up and down the screen, Home, End, Page Up, Page Down.
- Night mode ⇧⌘N: warm light gray text on graphite, not white on black.
- Display mode: color; black and white (text mask only — removes gray background and dirt from scans); background only; foreground only.
- ⇧⌘C — copy page text if the file contains a text layer.
- The page, zoom level, and modes are saved for each file.
- The interface is in Russian, Ukrainian, and English; the language is selected in the program settings.
- At the bottom of the sidebar, just like in MAC64: the gear icon for settings, ⓘ for the "About" window: version, developer, website, requirements, languages, decoder, license, and the "Copy version information" button for support requests. The same window can be opened from the program menu.

## Build

You need a Mac with macOS 14 or later and Xcode 16 or later.

Helpful:

- The default signature is "Sign to Run Locally," so the project runs immediately. For release, select your command in Signing & Capabilities.
- The 'Sources', 'Resources', and DjVuLibre source folders are synced to disk: new files placed in them appear in Xcode automatically.
- The Release build is universal (Apple Silicon and Intel), while the Debug build is specific to your Mac.
- `Scripts/test-bridge.sh` tests the connection with DjVuLibre without Xcode: it compiles the library with the compiler and runs a self-test on `Tests/Fixtures/sample.djvu`.
