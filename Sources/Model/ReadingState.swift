import Foundation
import SwiftUI

/// Keys of everything kept in UserDefaults.
enum SettingsKey {
    static let appearance = "appearance"
    static let defaultZoom = "defaultZoom"
    static let nightByDefault = "nightByDefault"
    static let restorePosition = "restorePosition"
    static let readingStates = "readingStates"
}

enum ZoomMode: String, Codable, Sendable {
    case fitWidth
    case fitPage
    case custom
}

enum AppearanceOption: String, CaseIterable {
    case dark
    case light
    case system

    var colorScheme: ColorScheme? {
        switch self {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }
}

/// Where the reader left a document, so it reopens at the same place.
struct ReadingState: Codable, Sendable {
    var page: Int
    var zoomMode: ZoomMode
    var magnification: Double
    var night: Bool
    var renderMode: Int
    var updated: Date
}

/// Reading states of recently opened documents, keyed by file path.
enum ReadingStateStore {
    private static let limit = 500

    static func load(for url: URL) -> ReadingState? {
        guard UserDefaults.standard.object(forKey: SettingsKey.restorePosition) as? Bool ?? true else { return nil }
        return all()[key(for: url)]
    }

    static func save(_ state: ReadingState, for url: URL) {
        var states = all()
        states[key(for: url)] = state
        if states.count > limit {
            // Forget the documents that were opened longest ago.
            let stale = states.sorted { $0.value.updated < $1.value.updated }.prefix(states.count - limit)
            for (key, _) in stale { states[key] = nil }
        }
        if let data = try? JSONEncoder().encode(states) {
            UserDefaults.standard.set(data, forKey: SettingsKey.readingStates)
        }
    }

    private static func all() -> [String: ReadingState] {
        guard let data = UserDefaults.standard.data(forKey: SettingsKey.readingStates),
              let states = try? JSONDecoder().decode([String: ReadingState].self, from: data) else { return [:] }
        return states
    }

    private static func key(for url: URL) -> String {
        url.standardizedFileURL.path(percentEncoded: false)
    }
}
