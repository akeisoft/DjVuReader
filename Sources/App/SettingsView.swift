import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.appearance) private var appearance = AppearanceOption.dark.rawValue
    @AppStorage(SettingsKey.defaultZoom) private var defaultZoom = ZoomMode.fitWidth.rawValue
    @AppStorage(SettingsKey.nightByDefault) private var nightByDefault = false
    @AppStorage(SettingsKey.restorePosition) private var restorePosition = true
    @State private var language = AppLanguage.selected

    /// The choice differs from the language this process started in.
    private var needsRestart: Bool { language.code != AppLanguage.running }

    var body: some View {
        Form {
            Section("Language") {
                Picker("App language", selection: $language) {
                    Text("System (\(AppLanguage.nativeName(of: AppLanguage.systemCode)))")
                        .tag(AppLanguage.system)
                    Divider()
                    ForEach([AppLanguage.ru, .uk, .en]) { option in
                        Text(verbatim: AppLanguage.nativeName(of: option.rawValue))
                            .tag(option)
                    }
                }
                .onChange(of: language) { _, newValue in
                    AppLanguage.selected = newValue
                }
                Text("If the system language is not Russian, Ukrainian or English, DjVu Reader starts in English.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if needsRestart {
                    HStack(spacing: 12) {
                        Label("Restart DjVu Reader to switch the language.", systemImage: "arrow.clockwise.circle.fill")
                            .foregroundStyle(.orange)
                        Spacer(minLength: 8)
                        Button("Restart now") {
                            AppRelaunch.now()
                        }
                    }
                }
            }

            Section("Reading") {
                Picker("Appearance", selection: $appearance) {
                    Text("Dark").tag(AppearanceOption.dark.rawValue)
                    Text("Light").tag(AppearanceOption.light.rawValue)
                    Text("System").tag(AppearanceOption.system.rawValue)
                }
                Picker("Default Zoom", selection: $defaultZoom) {
                    Text("Fit Width").tag(ZoomMode.fitWidth.rawValue)
                    Text("Fit Page").tag(ZoomMode.fitPage.rawValue)
                }
                Toggle("Night mode for new documents", isOn: $nightByDefault)
                Toggle("Reopen documents where I left off", isOn: $restorePosition)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}
