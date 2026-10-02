import AppKit
import QuartzCore

/// One page on the reading surface. The page itself is drawn by PageTileLayer;
/// this view only provides the frame, the paper color and the shadow.
final class PageView: NSView {
    let pageIndex: Int
    private let tiles = PageTileLayer()
    private let settings: RenderSettings

    init(frame: CGRect, pageIndex: Int, document: DjVuDocument?, settings: RenderSettings) {
        self.pageIndex = pageIndex
        self.settings = settings
        super.init(frame: frame)

        tiles.pageIndex = pageIndex
        tiles.document = document
        tiles.settings = settings

        wantsLayer = true
        layerContentsRedrawPolicy = .never

        let pageShadow = NSShadow()
        pageShadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
        pageShadow.shadowBlurRadius = 5
        pageShadow.shadowOffset = NSSize(width: 0, height: -1.5)
        shadow = pageShadow

        installTilesIfNeeded()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        tiles.frame = bounds
        updateShadowPath()
    }

    /// An explicit shadow shape: without it Core Animation renders the shadow
    /// offscreen from the whole (possibly huge, zoomed) page every frame.
    private func updateShadowPath() {
        layer?.shadowPath = CGPath(rect: bounds, transform: nil)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installTilesIfNeeded()
    }

    /// The backing layer may only appear once the view is in a window.
    private func installTilesIfNeeded() {
        guard tiles.superlayer == nil, let layer else { return }
        tiles.frame = bounds
        tiles.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer.addSublayer(tiles)
        updateShadowPath()
        applyPaperColor()
        tiles.setNeedsDisplay()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        tiles.contentsScale = window?.backingScaleFactor ?? 2
        tiles.setNeedsDisplay()
    }

    /// Drops the cached tiles and draws them again with the current style.
    func restyle() {
        applyPaperColor()
        tiles.setNeedsDisplay()
    }

    private func applyPaperColor() {
        let paper = ReaderPalette.paper(night: settings.current.night).cgColor
        layer?.backgroundColor = paper
        tiles.backgroundColor = paper
    }
}

/// Draws a page in tiles on background threads, at the resolution the page is
/// shown with on screen: zooming in asks for finer tiles, so text stays sharp at
/// any magnification and only the visible part of the page is ever decoded.
final class PageTileLayer: CATiledLayer {
    // Set once before the layer is shown; read from drawing threads.
    var pageIndex = 0
    var document: DjVuDocument?
    var settings: RenderSettings?

    override class func fadeDuration() -> CFTimeInterval { 0 }

    override init() {
        super.init()
        tileSize = CGSize(width: 512, height: 512)
        // 10 levels, 5 of them magnified: from 32x the base resolution (zoomed in)
        // down to 1/16 (zoomed far out), so small pages are not decoded at full size.
        levelsOfDetail = 10
        levelsOfDetailBias = 5
        needsDisplayOnBoundsChange = true
        isOpaque = true
    }

    override init(layer: Any) {
        super.init(layer: layer)
        if let other = layer as? PageTileLayer {
            pageIndex = other.pageIndex
            document = other.document
            settings = other.settings
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func draw(in context: CGContext) {
        guard let document, let settings else { return }
        let page = bounds
        guard page.width > 0, page.height > 0 else { return }
        let tile = context.boundingBoxOfClipPath.intersection(page)
        guard !tile.isNull, tile.width > 0, tile.height > 0 else { return }

        // Device pixels per layer point for this tile (includes Retina and zoom).
        let ctm = context.ctm
        let scale = max((ctm.a * ctm.a + ctm.b * ctm.b).squareRoot(), 0.01)
        let flipped = contentsAreFlipped()

        let fullWidth = (page.width * scale).rounded()
        let fullHeight = (page.height * scale).rounded()

        // The tile in page pixels, y measured from the top edge of the page.
        let topInPoints = flipped ? tile.minY - page.minY : page.maxY - tile.maxY
        let x = ((tile.minX - page.minX) * scale).rounded(.down)
        let y = (topInPoints * scale).rounded(.down)
        let width = min((tile.width * scale).rounded(.up) + 1, fullWidth - x)
        let height = min((tile.height * scale).rounded(.up) + 1, fullHeight - y)
        guard width >= 1, height >= 1 else { return }

        let style = settings.current
        let image = document.render(
            page: pageIndex,
            mode: style.mode,
            fullSize: CGSize(width: fullWidth, height: fullHeight),
            region: CGRect(x: x, y: y, width: width, height: height)
        )

        // Where those pixels belong, in layer coordinates.
        let target = CGRect(
            x: page.minX + x / scale,
            y: flipped ? page.minY + y / scale : page.maxY - (y + height) / scale,
            width: width / scale,
            height: height / scale
        )

        context.saveGState()
        context.interpolationQuality = .high
        if let image {
            if flipped {
                context.translateBy(x: 0, y: target.minY + target.maxY)
                context.scaleBy(x: 1, y: -1)
            }
            context.draw(image, in: target)
        } else {
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(target)
        }
        context.restoreGState()

        if style.night {
            ReaderPalette.applyNight(to: context, in: target)
        }
    }
}
