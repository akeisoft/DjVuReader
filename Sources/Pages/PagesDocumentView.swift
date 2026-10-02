import AppKit

/// The long scrolling column of pages.
///
/// Layout is computed once for all pages (in points at 100 % zoom), but only
/// the pages near the visible area have a PageView, so a 2000-page book costs
/// as much as a 20-page one.
///
/// Margins and gaps are a share of the page width, not fixed points: the page
/// size comes from the file's dpi, which is often far off (a book stored at
/// "600 dpi" with small images comes out 2.5 inches wide). Fixed 24-point margins
/// then grew to a hundred points on screen at fit-width zoom.
final class PagesDocumentView: NSView {
    /// Side and top/bottom margins, as a share of the widest page.
    private static let marginRatio: CGFloat = 0.025
    /// Gap between pages, as a share of the widest page.
    private static let spacingRatio: CGFloat = 0.02

    weak var controller: PagesController?

    private let document: DjVuDocument?
    private let settings: RenderSettings
    private(set) var pageFrames: [CGRect] = []
    /// Width of the column including side margins, in points at 100 %.
    private(set) var contentWidth: CGFloat = 0
    /// Side margin and gap between pages, in points at 100 %.
    private(set) var margin: CGFloat = 0
    private(set) var pageSpacing: CGFloat = 0
    private var pageViews: [Int: PageView] = [:]

    var pageCount: Int { pageFrames.count }

    init(document: DjVuDocument?, geometries: [PageGeometry], settings: RenderSettings) {
        self.document = document
        self.settings = settings
        super.init(frame: .zero)
        layoutPages(geometries)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    private func layoutPages(_ geometries: [PageGeometry]) {
        let widest = geometries.map(\.size.width).max() ?? 595
        margin = (widest * Self.marginRatio).rounded(.up)
        pageSpacing = (widest * Self.spacingRatio).rounded(.up)
        contentWidth = widest + 2 * margin
        var y = margin
        var frames: [CGRect] = []
        frames.reserveCapacity(geometries.count)
        for geometry in geometries {
            let x = ((contentWidth - geometry.size.width) / 2).rounded()
            frames.append(CGRect(x: x, y: y, width: geometry.size.width, height: geometry.size.height))
            y += geometry.size.height + pageSpacing
        }
        pageFrames = frames
        let height = max(y - pageSpacing + margin, 1)
        setFrameSize(NSSize(width: contentWidth, height: height))
    }

    func pageFrame(_ index: Int) -> CGRect {
        guard !pageFrames.isEmpty else { return .zero }
        return pageFrames[min(max(index, 0), pageFrames.count - 1)]
    }

    /// The page whose slot (page plus half the gap above it) contains y.
    func pageIndex(atY y: CGFloat) -> Int {
        guard !pageFrames.isEmpty else { return 0 }
        var low = 0
        var high = pageFrames.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if pageFrames[mid].minY - pageSpacing / 2 <= y {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }

    /// Creates page views around the visible rect and drops the far ones.
    func updateVisiblePages(around visible: CGRect) {
        guard !pageFrames.isEmpty else { return }
        let first = pageIndex(atY: visible.minY - visible.height)
        let last = pageIndex(atY: visible.maxY + visible.height)
        let keep = max(0, first - 2)...min(pageFrames.count - 1, last + 2)

        for (index, view) in pageViews where !keep.contains(index) {
            view.removeFromSuperview()
            pageViews[index] = nil
        }
        for index in first...last where pageViews[index] == nil {
            let view = PageView(frame: pageFrames[index], pageIndex: index, document: document, settings: settings)
            addSubview(view)
            pageViews[index] = view
        }
    }

    func restyle() {
        for view in pageViews.values {
            view.restyle()
        }
    }

    // MARK: - Input

    override func keyDown(with event: NSEvent) {
        if controller?.handleKey(event) != true {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    /// Two-finger double tap: zoom to the width of the page under the pointer
    /// (AppKit zooms back out on the next double tap).
    override func rectForSmartMagnification(at location: NSPoint, in visibleRect: NSRect) -> NSRect {
        pageFrame(pageIndex(atY: location.y)).insetBy(dx: -margin / 2, dy: 0)
    }
}

/// Keeps the page column centered when it is narrower or shorter than the window.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }
        let content = documentView.frame
        if rect.width > content.width {
            rect.origin.x = content.minX - (rect.width - content.width) / 2
        }
        if rect.height > content.height {
            rect.origin.y = content.minY - (rect.height - content.height) / 2
        }
        return rect
    }
}
