import SwiftUI

// Entry point, the same way MAC64 starts. The language is fixed before SwiftUI
// starts: strings, menus and system panels are resolved in the language of
// AppleLanguages at the moment they are first needed (see AppLanguage). With
// @main on the App type this ordering is not guaranteed.
AppLanguage.applyAtLaunch()

// Readable DjVuLibre errors: its message catalogs ship inside the app bundle.
// Must happen before any document is opened, while there is only one thread.
DjVuDocument.configureLibrary()

// Top-level code runs on the main thread; App.main() is main-actor isolated.
MainActor.assumeIsolated {
    DjVuReaderApp.main()
}
