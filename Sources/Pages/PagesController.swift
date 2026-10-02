import AppKit

/// Owns the scroll view with the pages. Receives commands from ReaderModel
/// (go to page, zoom, restyle) and reports the visible page and zoom back.
@MainActor
final class PagesController: NSObject {
    let scrollView = NSScrollView()

    private weak var model: ReaderModel?
    private let documentView: PagesDocumentView
    private var didApplyInitialState = false
    /// Above zero while the controller itself scrolls or zooms: such moves are not reported back.
    private var adjustingDepth = 0
    private var knownMagnification: CGFloat = 1
    private var lastReportedPage = -1

    init(model: ReaderModel) {
        self.model = model
        documentView = PagesDocumentView(
            document: model.document,
            geometries: model.geometries,
            settings: model.renderSettings
        )
        super.init()
        documentView.controller = self
        configureScrollView(night: model.nightMode)
        model.pagesController = self
        // In case the scroll view already has its final size and never reports a resize.
        Task { @MainActor [weak self] in
            self?.applyInitialStateIfPossible()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configureScrollView(night: Bool) {
        let clip = CenteringClipView()
        clip.drawsBackground = false
        scrollView.contentView = clip
        scrollView.documentView = documentView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = ReaderPalette.canvas(night: night)
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.1
        scrollView.maxMagnification = 8

        clip.postsBoundsChangedNotifications = true
        scrollView.postsFrameChangedNotifications = true
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(visibleAreaChanged(_:)),
                           name: NSView.boundsDidChangeNotification, object: clip)
        center.addObserver(self, selector: #selector(viewportResized(_:)),
                           name: NSView.frameDidChangeNotification, object: scrollView)
        center.addObserver(self, selector: #selector(liveMagnifyEnded(_:)),
                           name: NSScrollView.didEndLiveMagnifyNotification, object: scrollView)
    }

    // MARK: - Notifications

    @objc private func viewportResized(_ notification: Notification) {
        guard didApplyInitialState else {
            applyInitialStateIfPossible()
            return
        }
        if model?.zoomMode != ZoomMode.custom {
            applyZoomMode()
        } else {
            updateVisiblePages()
        }
    }

    @objc private func visibleAreaChanged(_ notification: Notification) {
        // Until the restored position is applied, scrolling reports would overwrite it.
        guard didApplyInitialState else {
            applyInitialStateIfPossible()
            return
        }
        updateVisiblePages()
        guard adjustingDepth == 0 else { return }
        // Pinch and smart zoom change the magnification without telling us.
        if abs(scrollView.magnification - knownMagnification) > 0.0001 {
            knownMagnification = scrollView.magnification
            model?.pagesDidZoom(to: knownMagnification, mode: .custom)
        }
        reportVisiblePage()
    }

    @objc private func liveMagnifyEnded(_ notification: Notification) {
        knownMagnification = scrollView.magnification
        model?.pagesDidZoom(to: knownMagnification, mode: .custom)
        updateVisiblePages()
    }

    /// Shows the document at its restored page and zoom once the view has a real size.
    func applyInitialStateIfPossible() {
        guard !didApplyInitialState,
              scrollView.contentSize.width > 10,
              scrollView.contentSize.height > 10 else { return }
        applyInitialState()
    }

    /// The area pages are fitted into. With "Show scroll bars: Always" (a mouse is
    /// connected) the vertical scroll bar takes width, and it may not be on screen
    /// yet when the zoom is computed; fitting into the full width then made the pages
    /// a scroll bar wider than the window, with a horizontal scroll bar under them.
    private var fittingSize: CGSize {
        NSScrollView.contentSize(
            forFrameSize: scrollView.frame.size,
            horizontalScrollerClass: nil,
            verticalScrollerClass: NSScroller.self,
            borderType: scrollView.borderType,
            controlSize: .regular,
            scrollerStyle: scrollView.scrollerStyle
        )
    }

    private func applyInitialState() {
        guard let model else { return }
        didApplyInitialState = true
        let page = model.currentPage
        adjusting {
            if model.zoomMode == .custom {
                setMagnification(model.magnification, anchorPage: page, alignTop: true)
            } else {
                applyZoomMode()
            }
            scroll(toPage: page)
        }
        scrollView.window?.makeFirstResponder(documentView)
    }

    /// Runs programmatic scrolling or zooming without reporting it as the reader's own movement.
    private func adjusting(_ body: () -> Void) {
        adjustingDepth += 1
        body()
        adjustingDepth -= 1
    }

    // MARK: - Zoom

    /// Re-fits the pages for fit-width and fit-page modes.
    func applyZoomMode() {
        guard let model, documentView.pageCount > 0 else { return }
        let available = fittingSize
        guard available.width > 10, available.height > 10 else { return }
        let page = model.currentPage
        switch model.zoomMode {
        case .fitWidth:
            // One point of slack keeps a horizontal scroller from flickering in.
            setMagnification((available.width - 1) / documentView.contentWidth, anchorPage: page, alignTop: false)
        case .fitPage:
            let size = documentView.pageFrame(page).size
            let byWidth = (available.width - 1) / (size.width + 2 * documentView.margin)
            let byHeight = available.height / (size.height + documentView.pageSpacing)
            setMagnification(min(byWidth, byHeight), anchorPage: page, alignTop: true)
        case .custom:
            break
        }
    }

    /// Sets the zoom keeping the same spot of the anchor page at the top of the view.
    func setMagnification(_ value: CGFloat, anchorPage: Int? = nil, alignTop: Bool = false) {
        let clamped = min(max(value, scrollView.minMagnification), scrollView.maxMagnification)
        let anchor = anchorPage ?? currentVisiblePage()
        let fraction = alignTop ? 0 : fractionScrolled(into: anchor)

        adjusting {
            scrollView.magnification = clamped
            knownMagnification = clamped
            scroll(toPage: anchor, fraction: fraction)
        }

        model?.pagesDidZoom(to: clamped)
        updateVisiblePages()
    }

    /// Zoom in or out around the center of the view.
    func zoom(by factor: CGFloat) {
        let target = min(max(scrollView.magnification * factor, scrollView.minMagnification), scrollView.maxMagnification)
        let visible = scrollView.contentView.bounds
        adjusting {
            scrollView.setMagnification(target, centeredAt: NSPoint(x: visible.midX, y: visible.midY))
            knownMagnification = target
        }
        model?.pagesDidZoom(to: target, mode: .custom)
        updateVisiblePages()
        reportVisiblePage()
    }

    // MARK: - Scrolling

    func scroll(toPage page: Int, fraction: CGFloat = 0) {
        guard documentView.pageCount > 0 else { return }
        let index = min(max(page, 0), documentView.pageCount - 1)
        let frame = documentView.pageFrame(index)
        let clip = scrollView.contentView
        var origin = clip.bounds.origin
        origin.y = fraction == 0
            ? frame.minY - documentView.pageSpacing / 2
            : frame.minY + frame.height * fraction
        let constrained = clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size))
        adjusting {
            clip.scroll(to: constrained.origin)
            scrollView.reflectScrolledClipView(clip)
        }
        updateVisiblePages()
        lastReportedPage = index
    }

    private func scroll(by delta: CGFloat) {
        let clip = scrollView.contentView
        var origin = clip.bounds.origin
        origin.y += delta
        let constrained = clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size))
        clip.scroll(to: constrained.origin)
        scrollView.reflectScrolledClipView(clip)
    }

    /// The page the reader is looking at: the one under a line near the top of the view.
    func currentVisiblePage() -> Int {
        let visible = scrollView.contentView.bounds
        let probe = visible.minY + min(visible.height * 0.25, 120 / max(scrollView.magnification, 0.01))
        return documentView.pageIndex(atY: probe)
    }

    /// How far the top of the view is into the page, as a fraction of its height.
    private func fractionScrolled(into page: Int) -> CGFloat {
        let frame = documentView.pageFrame(page)
        guard frame.height > 0 else { return 0 }
        let top = scrollView.contentView.bounds.minY
        return min(max((top - frame.minY) / frame.height, 0), 1)
    }

    private func updateVisiblePages() {
        documentView.updateVisiblePages(around: scrollView.contentView.bounds)
    }

    private func reportVisiblePage() {
        let page = currentVisiblePage()
        guard page != lastReportedPage else { return }
        lastReportedPage = page
        model?.pagesDidScroll(to: page)
    }

    // MARK: - Style

    func restyle() {
        scrollView.backgroundColor = ReaderPalette.canvas(night: model?.nightMode ?? false)
        documentView.restyle()
    }

    // MARK: - Keyboard

    /// Reading keys that are not menu shortcuts. Returns false to let AppKit handle the key.
    func handleKey(_ event: NSEvent) -> Bool {
        guard let model else { return false }
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return false }

        let visible = scrollView.contentView.bounds
        let line = 48 / max(scrollView.magnification, 0.01)
        let screen = max(visible.height - line, line)

        if let key = event.specialKey {
            switch key {
            case .upArrow: scroll(by: -line); return true
            case .downArrow: scroll(by: line); return true
            case .leftArrow: model.previousPage(); return true
            case .rightArrow: model.nextPage(); return true
            case .pageUp: scroll(by: -screen); return true
            case .pageDown: scroll(by: screen); return true
            case .home: model.firstPage(); return true
            case .end: model.lastPage(); return true
            default: break
            }
        }
        if event.charactersIgnoringModifiers == " " {
            scroll(by: event.modifierFlags.contains(.shift) ? -screen : screen)
            return true
        }
        return false
    }
}
