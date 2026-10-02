import AppKit

/// How pages are drawn right now.
struct RenderStyle: Equatable, Sendable {
    var mode: RenderMode = .color
    var night = false
}

/// The current style, readable from the background threads that draw tiles.
final class RenderSettings: @unchecked Sendable {
    private let lock = NSLock()
    private var style = RenderStyle()

    var current: RenderStyle {
        lock.lock()
        defer { lock.unlock() }
        return style
    }

    func update(_ change: (inout RenderStyle) -> Void) {
        lock.lock()
        change(&style)
        lock.unlock()
    }
}

/// Colors of the reading surface.
///
/// Night mode does not simply invert the page: white paper becomes dark graphite
/// and black ink becomes warm light grey, which is easier on the eyes than
/// pure white on pure black.
enum ReaderPalette {
    /// Background around the pages.
    static func canvas(night: Bool) -> NSColor {
        night ? NSColor(srgbRed: 0.075, green: 0.078, blue: 0.09, alpha: 1) : dayCanvas
    }

    /// Color of a page before its tiles arrive.
    static func paper(night: Bool) -> NSColor {
        night ? NSColor(cgColor: nightPaper) ?? .black : .white
    }

    static let nightPaper = CGColor(srgbRed: 0.118, green: 0.122, blue: 0.133, alpha: 1)
    static let nightInk = CGColor(srgbRed: 0.85, green: 0.83, blue: 0.79, alpha: 1)

    private static let dayCanvas = NSColor(name: "ReaderCanvas") { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark
            ? NSColor(srgbRed: 0.17, green: 0.173, blue: 0.188, alpha: 1)
            : NSColor(srgbRed: 0.86, green: 0.86, blue: 0.875, alpha: 1)
    }

    /// Turns an already drawn day-colored area into night colors.
    static func applyNight(to context: CGContext, in rect: CGRect) {
        context.saveGState()
        context.setBlendMode(.difference)          // white paper -> black, black ink -> white
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.setBlendMode(.multiply)            // white ink -> warm light grey
        context.setFillColor(nightInk)
        context.fill(rect)
        context.setBlendMode(.lighten)             // black paper -> graphite
        context.setFillColor(nightPaper)
        context.fill(rect)
        context.restoreGState()
    }
}
