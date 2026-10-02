import AppKit
import Foundation

/// The language DjVu Reader runs in: Russian, Ukrainian or English.
///
/// Same rules as MAC64. macOS takes an app's language from the app's own
/// "AppleLanguages" default when it is set (System Settings writes the same key
/// for per-app languages), otherwise from the system list, where it would pick
/// the first language the app has: a German system with Russian second would
/// start in Russian. The rule here is stricter: the primary system language when
/// it is Russian, Ukrainian or English, else English. main.swift applies it
/// before anything is localized, so menus, system panels, formatters and our own
/// strings always agree.
enum AppLanguage: String, CaseIterable, Identifiable {
    /// Follow the system (the default until the user picks a language).
    case system
    case ru
    case uk
    case en

    var id: String { rawValue }

    private static let preferenceKey = "DjVuReader.appLanguage"
    private static let supported: Set<String> = ["ru", "uk", "en"]

    /// The choice in Settings. Setting it also writes AppleLanguages for the next start.
    static var selected: AppLanguage {
        get {
            UserDefaults.standard.string(forKey: preferenceKey).flatMap(AppLanguage.init(rawValue:)) ?? .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: preferenceKey)
            apply(newValue)
        }
    }

    /// Language code this choice resolves to right now.
    var code: String {
        self == .system ? Self.systemCode : rawValue
    }

    /// The primary system language mapped to ru / uk / en; any other language gives en.
    /// Read from the global domain: the app's own AppleLanguages would hide the system list.
    static var systemCode: String {
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        let primary = (global?["AppleLanguages"] as? [String])?.first ?? Locale.preferredLanguages.first ?? "en"
        let code = Locale(identifier: primary).language.languageCode?.identifier ?? String(primary.prefix(2))
        return supported.contains(code) ? code : "en"
    }

    /// The language this process started in (fixed until the next start).
    static var running: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        return supported.contains(code) ? code : "en"
    }

    /// Language names are shown in their own language.
    static func nativeName(of code: String) -> String {
        switch code {
        case "ru": return "Русский"
        case "uk": return "Українська"
        default: return "English"
        }
    }

    /// First call in main.swift, before any string is localized.
    static func applyAtLaunch() {
        apply(selected)
    }

    private static func apply(_ language: AppLanguage) {
        UserDefaults.standard.set([language.code], forKey: "AppleLanguages")
    }
}

/// A language change needs a new process: the running one resolved its strings at start.
enum AppRelaunch {
    /// Quits, then starts DjVu Reader again. Unlike MAC64 (one window, nothing to
    /// restore) the new copy starts only after this one has exited, so macOS
    /// reopens the documents that were open. Nothing happens if the helper fails.
    @MainActor
    static func now() {
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = [
            "-c",
            "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"",
            Bundle.main.bundlePath,
        ]
        do {
            try helper.run()
        } catch {
            NSSound.beep()
            return
        }
        NSApp.terminate(nil)
    }
}
