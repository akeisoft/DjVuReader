import AppKit
import Observation
import SwiftUI

enum SidebarTab: String, CaseIterable {
    case thumbnails
    case outline
}

/// State of one reader window. SwiftUI views observe it; the AppKit page view
/// (PagesController) receives commands from it and reports scrolling back.
@MainActor
@Observable
final class ReaderModel {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
        /// A message in the interface language and optional technical details.
        case failed(String, String?)
    }

    var phase: Phase = .idle
    var title = ""
    var pageCount = 0
    /// 0-based page at the top of the view.
    var currentPage = 0
    var zoomMode: ZoomMode = .fitWidth
    /// 1.0 is the physical size of the page.
    var magnification: CGFloat = 1
    var nightMode = false
    var renderMode: RenderMode = .color
    var sidebarTab: SidebarTab = .thumbnails
    var outline: [OutlineNode] = []
    var isGoToPagePresented = false
    var statusMessage: String?

    @ObservationIgnored private(set) var document: DjVuDocument?
    @ObservationIgnored private(set) var geometries: [PageGeometry] = []
    @ObservationIgnored private(set) var pageTitles: [String?] = []
    @ObservationIgnored let renderSettings = RenderSettings()
    @ObservationIgnored weak var pagesController: PagesController?

    @ObservationIgnored private var thumbnailDocument: DjVuDocument?
    @ObservationIgnored private let thumbnailCache = NSCache<NSNumber, NSImage>()
    @ObservationIgnored private var fileURL: URL?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var statusTask: Task<Void, Never>?

    init() {
        thumbnailCache.countLimit = 400
    }

    // MARK: - Loading

    func open(_ url: URL) async {
        guard phase == .idle else { return }
        phase = .loading
        fileURL = url
        title = url.deletingPathExtension().lastPathComponent

        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                try LoadedDocument.load(url)
            }.value
            document = loaded.pages
            thumbnailDocument = loaded.thumbnails
            geometries = loaded.geometries
            pageTitles = loaded.titles
            outline = OutlineNode.tree(from: loaded.outline)
            pageCount = loaded.geometries.count
            applyInitialState(for: url)
            phase = .ready
        } catch let error as DjVuOpenError {
            phase = .failed(error.localizedDescription, error.details)
        } catch {
            phase = .failed(error.localizedDescription, nil)
        }
    }

    private func applyInitialState(for url: URL) {
        let defaults = UserDefaults.standard
        if let state = ReadingStateStore.load(for: url) {
            currentPage = min(max(state.page, 0), pageCount - 1)
            zoomMode = state.zoomMode
            magnification = CGFloat(state.magnification)
            nightMode = state.night
            renderMode = RenderMode(rawValue: state.renderMode) ?? .color
        } else {
            currentPage = 0
            zoomMode = ZoomMode(rawValue: defaults.string(forKey: SettingsKey.defaultZoom) ?? "") ?? .fitWidth
            if zoomMode == .custom { zoomMode = .fitWidth }
            nightMode = defaults.bool(forKey: SettingsKey.nightByDefault)
            renderMode = .color
        }
        renderSettings.update { style in
            style.night = nightMode
            style.mode = renderMode
        }
        sidebarTab = outline.isEmpty ? .thumbnails : sidebarTab
    }

    // MARK: - Navigation

    func goTo(page: Int) {
        guard pageCount > 0 else { return }
        let target = min(max(page, 0), pageCount - 1)
        currentPage = target
        pagesController?.scroll(toPage: target)
        scheduleSave()
    }

    func nextPage() { goTo(page: currentPage + 1) }
    func previousPage() { goTo(page: currentPage - 1) }
    func firstPage() { goTo(page: 0) }
    func lastPage() { goTo(page: pageCount - 1) }

    // MARK: - Zoom

    func zoomIn() { pagesController?.zoom(by: 1.25) }
    func zoomOut() { pagesController?.zoom(by: 0.8) }
    func actualSize() { setZoom(percent: 100) }

    func setZoom(percent: Int) {
        zoomMode = .custom
        pagesController?.setMagnification(CGFloat(percent) / 100)
    }

    func setZoomMode(_ mode: ZoomMode) {
        zoomMode = mode
        pagesController?.applyZoomMode()
    }

    var zoomDescription: LocalizedStringKey {
        switch zoomMode {
        case .fitWidth: return "Fit Width"
        case .fitPage: return "Fit Page"
        case .custom: return "\(Int((magnification * 100).rounded())) %"
        }
    }

    // MARK: - Appearance of pages

    func toggleNightMode() { setNightMode(!nightMode) }

    func setNightMode(_ on: Bool) {
        nightMode = on
        renderSettings.update { $0.night = on }
        pagesController?.restyle()
        scheduleSave()
    }

    func setRenderMode(_ mode: RenderMode) {
        renderMode = mode
        renderSettings.update { $0.mode = mode }
        pagesController?.restyle()
        scheduleSave()
    }

    // MARK: - Reports from the page view

    func pagesDidScroll(to page: Int) {
        guard page != currentPage else { return }
        currentPage = page
        scheduleSave()
    }

    func pagesDidZoom(to value: CGFloat, mode: ZoomMode? = nil) {
        magnification = value
        if let mode { zoomMode = mode }
        scheduleSave()
    }

    // MARK: - Text

    func copyCurrentPageText() {
        guard let document else { return }
        let page = currentPage
        Task {
            let text = await Task.detached(priority: .userInitiated) {
                document.text(page: page)?.string
            }.value
            if let text, !text.isEmpty {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                showStatus(String(localized: "Page text copied"))
            } else {
                showStatus(String(localized: "This page has no text layer"))
            }
        }
    }

    func showStatus(_ message: String) {
        statusTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) { statusMessage = message }
        statusTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.3)) { self?.statusMessage = nil }
        }
    }

    // MARK: - Thumbnails and labels

    func thumbnail(for page: Int) async -> NSImage? {
        let key = NSNumber(value: page)
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        guard let source = thumbnailDocument ?? document else { return nil }
        let rendered = await Task.detached(priority: .utility) { () -> RenderedImage? in
            source.thumbnail(page: page, maxPixels: 256).map(RenderedImage.init(cgImage:))
        }.value
        guard let image = rendered?.cgImage else { return nil }
        let thumbnail = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        thumbnailCache.setObject(thumbnail, forKey: key)
        return thumbnail
    }

    func aspectRatio(of page: Int) -> CGFloat {
        geometries.indices.contains(page) ? geometries[page].aspectRatio : 0.707
    }

    /// "12", or "iv (12)" when the document gives the page a title of its own,
    /// such as the roman numerals of a preface.
    func pageLabel(_ page: Int) -> String {
        let number = String(page + 1)
        guard pageTitles.indices.contains(page), let title = pageTitles[page], title != number else { return number }
        return "\(title) (\(number))"
    }

    // MARK: - Reading position

    func saveReadingState() {
        saveTask?.cancel()
        guard phase == .ready, let fileURL else { return }
        let state = ReadingState(
            page: currentPage,
            zoomMode: zoomMode,
            magnification: Double(magnification),
            night: nightMode,
            renderMode: renderMode.rawValue,
            updated: Date()
        )
        ReadingStateStore.save(state, for: fileURL)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveReadingState()
        }
    }
}
