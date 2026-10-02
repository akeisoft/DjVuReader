import SwiftUI

/// Started from main.swift, which chooses the language first.
struct DjVuReaderApp: App {
    var body: some Scene {
        DocumentGroup(viewing: DjVuFile.self) { file in
            ReaderView(fileURL: file.fileURL)
        }
        .defaultSize(width: 1180, height: 860)
        .commands {
            // "About DjVu Reader" in the app menu opens our window instead of the standard panel.
            CommandGroup(replacing: .appInfo) {
                AboutMenuButton()
            }
            ReaderCommands()
        }

        Window("About DjVu Reader", id: AboutView.windowID) {
            AboutView()
                .modifier(AppAppearance())
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commandsRemoved()  // no entry for it in the Window menu

        Settings {
            SettingsView()
                .modifier(AppAppearance())
        }
    }
}

private struct AboutMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About DjVu Reader") {
            openWindow(id: AboutView.windowID)
        }
    }
}

/// Dark, light or system look from Settings, for every window of the app.
struct AppAppearance: ViewModifier {
    @AppStorage(SettingsKey.appearance) private var appearance = AppearanceOption.dark.rawValue

    func body(content: Content) -> some View {
        content.preferredColorScheme(AppearanceOption(rawValue: appearance)?.colorScheme)
    }
}
