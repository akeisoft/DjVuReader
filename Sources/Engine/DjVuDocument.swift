import CoreGraphics
import Foundation

/// Why a file could not be opened, in the reader's language.
enum DjVuOpenError: LocalizedError, Equatable {
    case notFound
    case notReadable
    case notDjVu
    case noPages
    /// DjVuLibre rejected the file; carries its own explanation (English).
    case damaged(details: String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return String(localized: "The file can't be found. It may have been moved or deleted.")
        case .notReadable:
            return String(localized: "There is no permission to read this file.")
        case .notDjVu:
            return String(localized: "This file is not a DjVu document.")
        case .noPages:
            return String(localized: "The document has no pages.")
        case .damaged:
            return String(localized: "The file is damaged or uses a DjVu variant that can't be read.")
        }
    }

    /// Technical details from DjVuLibre, for small print under the message.
    var details: String? {
        if case .damaged(let details) = self, !details.isEmpty { return details }
        return nil
    }
}

/// Page size as stored in the file, already swapped for the initial rotation.
struct DjVuPageInfo: Sendable, Equatable {
    let pixelWidth: Int
    let pixelHeight: Int
    let dpi: Int
    let rotation: Int

    /// Used for pages whose header cannot be read: A4 at 300 dpi.
    static let fallback = DjVuPageInfo(pixelWidth: 2480, pixelHeight: 3508, dpi: 300, rotation: 0)
}

struct DjVuOutlineEntry: Sendable {
    let title: String
    /// 0-based target page; -1 for external or unresolved links.
    let page: Int
    let depth: Int
}

struct DjVuWord: Sendable {
    let text: String
    /// Box in unrotated page pixels, origin in the top-left corner.
    let rect: CGRect
    let line: Int
}

struct DjVuPageText: Sendable {
    /// Words separated by spaces, lines by newlines.
    let string: String
    let words: [DjVuWord]
    /// Coordinate space of the word boxes.
    let pageSize: CGSize
}

/// Hands a CGImage across concurrency domains. Safe: the image is immutable.
struct RenderedImage: @unchecked Sendable {
    let cgImage: CGImage
}

/// Which layers of a page are drawn. Raw values are stored in user settings.
enum RenderMode: Int, CaseIterable, Sendable {
    case color = 0
    case blackAndWhite = 1
    case background = 2
    case foreground = 3
}

/// One open DjVu file.
///
/// DjVuLibre is used from one thread at a time per document: every call takes
/// the lock. Open the same file twice (two instances) to work in parallel,
/// for example pages in one and thumbnails in the other.
final class DjVuDocument: @unchecked Sendable {
    let url: URL
    let pageCount: Int

    private let handle: OpaquePointer
    private let lock = NSLock()

    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private static let bitmapInfo = CGBitmapInfo(
        rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
    )

    /// Points DjVuLibre at the message catalogs inside the app bundle, so that
    /// its errors read "Failed to open …" instead of internal message ids.
    /// Call once at launch, before the first document is opened.
    static func configureLibrary() {
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent("osi", isDirectory: true),
              FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else { return }
        folder.withUnsafeFileSystemRepresentation { path in
            if let path { djv_set_resource_dir(path) }
        }
    }

    init(url: URL) throws {
        self.url = url
        try DjVuDocument.checkFile(at: url)
        var reason = [CChar](repeating: 0, count: 512)
        let opened: OpaquePointer? = url.withUnsafeFileSystemRepresentation { (path: UnsafePointer<CChar>?) -> OpaquePointer? in
            guard let path else { return nil }
            return reason.withUnsafeMutableBufferPointer { (buffer: inout UnsafeMutableBufferPointer<CChar>) -> OpaquePointer? in
                djv_open(path, buffer.baseAddress, buffer.count)
            }
        }
        guard let opened else {
            let text = reason.withUnsafeBufferPointer { buffer in
                buffer.baseAddress.map { String(cString: $0) } ?? ""
            }
            throw DjVuOpenError.damaged(details: text)
        }
        handle = opened
        pageCount = Int(djv_page_count(opened))
    }

    deinit {
        djv_close(handle)
    }

    /// Catches the common problems before DjVuLibre does, so they can be
    /// explained in the interface language instead of DjVuLibre's English.
    private static func checkFile(at url: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw DjVuOpenError.notFound
        }
        guard let file = try? FileHandle(forReadingFrom: url) else {
            throw DjVuOpenError.notReadable
        }
        defer { try? file.close() }
        // Every DjVu file is an IFF container: "AT&TFORM", or plain "FORM" in very old files.
        let head = Array((try? file.read(upToCount: 8)) ?? Data())
        guard head.starts(with: Array("AT&TFORM".utf8)) || head.starts(with: Array("FORM".utf8)) else {
            throw DjVuOpenError.notDjVu
        }
    }

    // MARK: - Pages

    func pageInfo(_ page: Int) -> DjVuPageInfo? {
        lock.lock()
        defer { lock.unlock() }
        var info = djv_page_info()
        guard djv_get_page_info(handle, Int32(page), &info) == 0 else { return nil }
        return DjVuPageInfo(
            pixelWidth: Int(info.width),
            pixelHeight: Int(info.height),
            dpi: Int(info.dpi),
            rotation: Int(info.rotation)
        )
    }

    /// All page titles stored in the document (for example "iv"); nil for pages without one.
    func pageTitles() -> [String?] {
        guard pageCount > 0 else { return [] }
        lock.lock()
        defer { lock.unlock() }
        var raw = [UnsafeMutablePointer<CChar>?](repeating: nil, count: pageCount)
        _ = raw.withUnsafeMutableBufferPointer { buffer in
            djv_copy_page_titles(handle, buffer.baseAddress, Int32(buffer.count))
        }
        return raw.map { (pointer: UnsafeMutablePointer<CChar>?) -> String? in
            guard let pointer else { return nil }
            defer { free(pointer) }
            return String(cString: pointer)
        }
    }

    /// Renders `region` (pixels, origin top-left) of the page scaled to `fullSize` pixels.
    /// Areas outside the page or without content come back white.
    func render(page: Int, mode: RenderMode, fullSize: CGSize, region: CGRect) -> CGImage? {
        let width = Int(region.width)
        let height = Int(region.height)
        let fullWidth = Int(fullSize.width)
        let fullHeight = Int(fullSize.height)
        guard width > 0, height > 0, fullWidth > 0, fullHeight > 0 else { return nil }

        let bytesPerRow = width * 4
        guard let buffer = malloc(bytesPerRow * height) else { return nil }
        lock.lock()
        _ = djv_render(
            handle, Int32(page), Int32(mode.rawValue),
            Int32(fullWidth), Int32(fullHeight),
            Int32(region.minX), Int32(region.minY), Int32(width), Int32(height),
            buffer.assumingMemoryBound(to: UInt8.self), bytesPerRow
        )
        lock.unlock()
        // Errors and empty layers still leave a white buffer, which is what the page should show.
        return Self.makeImage(buffer, width: width, height: height, bytesPerRow: bytesPerRow)
    }

    /// A thumbnail that fits into `maxPixels` x `maxPixels`.
    func thumbnail(page: Int, maxPixels: Int) -> CGImage? {
        guard maxPixels > 0 else { return nil }
        var width = Int32(maxPixels)
        var height = Int32(maxPixels)
        let bytesPerRow = maxPixels * 4
        guard let buffer = malloc(bytesPerRow * maxPixels) else { return nil }
        lock.lock()
        let status = djv_render_thumbnail(
            handle, Int32(page), &width, &height,
            buffer.assumingMemoryBound(to: UInt8.self), bytesPerRow
        )
        lock.unlock()
        guard status == 0, width > 0, height > 0 else {
            free(buffer)
            return nil
        }
        return Self.makeImage(buffer, width: Int(width), height: Int(height), bytesPerRow: bytesPerRow)
    }

    // MARK: - Text and structure

    /// The hidden text layer of a page, or nil when the page has none.
    func text(page: Int) -> DjVuPageText? {
        lock.lock()
        defer { lock.unlock() }
        guard let raw = djv_get_text(handle, Int32(page)) else { return nil }
        defer { djv_free_text(raw) }
        let text = raw.pointee
        guard let base = text.utf8 else { return nil }

        let string = String(decoding: UnsafeRawBufferPointer(start: base, count: text.utf8_length), as: UTF8.self)
        var words: [DjVuWord] = []
        words.reserveCapacity(Int(text.word_count))
        for index in 0..<Int(text.word_count) {
            let word = text.words[index]
            let bytes = UnsafeRawBufferPointer(start: base.advanced(by: Int(word.offset)), count: Int(word.length))
            words.append(DjVuWord(
                text: String(decoding: bytes, as: UTF8.self),
                rect: CGRect(
                    x: Int(word.x0), y: Int(word.y0),
                    width: Int(word.x1 - word.x0), height: Int(word.y1 - word.y0)
                ),
                line: Int(word.line)
            ))
        }
        return DjVuPageText(
            string: string,
            words: words,
            pageSize: CGSize(width: Int(text.page_width), height: Int(text.page_height))
        )
    }

    /// The table of contents, flattened in display order.
    func outline() -> [DjVuOutlineEntry] {
        lock.lock()
        defer { lock.unlock() }
        var count: Int32 = 0
        guard let items = djv_get_outline(handle, &count) else { return [] }
        defer { djv_free_outline(items, count) }
        return (0..<Int(count)).map { index in
            let item = items[index]
            return DjVuOutlineEntry(
                title: item.title.map { String(cString: $0) } ?? "",
                page: Int(item.page),
                depth: Int(item.depth)
            )
        }
    }

    // MARK: - Images

    /// Wraps a malloc'ed BGRA buffer into a CGImage without copying; the image frees it.
    private static func makeImage(_ buffer: UnsafeMutableRawPointer, width: Int, height: Int, bytesPerRow: Int) -> CGImage? {
        let release: CGDataProviderReleaseDataCallback = { _, data, _ in
            free(UnsafeMutableRawPointer(mutating: data))
        }
        guard let provider = CGDataProvider(
            dataInfo: nil, data: buffer, size: bytesPerRow * height, releaseData: release
        ) else {
            free(buffer)
            return nil
        }
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
            space: colorSpace, bitmapInfo: bitmapInfo, provider: provider,
            decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }
}
