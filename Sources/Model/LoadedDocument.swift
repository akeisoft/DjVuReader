import CoreGraphics
import Foundation

/// Page size in points at 100 % zoom, i.e. the physical size of the scanned page.
struct PageGeometry: Sendable {
    let info: DjVuPageInfo
    let size: CGSize

    init(info: DjVuPageInfo) {
        self.info = info
        // Some old files store 0 or nonsense; 300 dpi is the common scanning resolution.
        let dpi = (25...4800).contains(info.dpi) ? CGFloat(info.dpi) : 300
        size = CGSize(
            width: max(CGFloat(info.pixelWidth), 1) / dpi * 72,
            height: max(CGFloat(info.pixelHeight), 1) / dpi * 72
        )
    }

    var aspectRatio: CGFloat { size.width / size.height }
}

/// One entry of the table of contents, as a tree for the sidebar.
struct OutlineNode: Identifiable, Hashable {
    let id: Int
    let title: String
    /// 0-based target page, -1 when the entry points nowhere inside the document.
    let page: Int
    /// nil for leaves, so that the sidebar shows no disclosure triangle.
    var children: [OutlineNode]?

    static func tree(from entries: [DjVuOutlineEntry]) -> [OutlineNode] {
        var index = 0

        func build(depth: Int) -> [OutlineNode] {
            var nodes: [OutlineNode] = []
            while index < entries.count {
                let entry = entries[index]
                if entry.depth < depth { break }
                if entry.depth > depth {
                    // A level was skipped: hang the deeper entries under the previous node.
                    guard var last = nodes.popLast() else {
                        index += 1
                        continue
                    }
                    last.children = (last.children ?? []) + build(depth: entry.depth)
                    nodes.append(last)
                    continue
                }
                index += 1
                var node = OutlineNode(id: index, title: entry.title, page: entry.page, children: nil)
                if index < entries.count, entries[index].depth > depth {
                    node.children = build(depth: depth + 1)
                }
                nodes.append(node)
            }
            return nodes
        }

        return build(depth: 0)
    }
}

/// Everything read from a file before the window shows it. Built off the main thread.
struct LoadedDocument: Sendable {
    let pages: DjVuDocument
    /// A second instance of the same file, so thumbnails never wait for page rendering.
    let thumbnails: DjVuDocument?
    let geometries: [PageGeometry]
    let titles: [String?]
    let outline: [DjVuOutlineEntry]

    static func load(_ url: URL) throws -> LoadedDocument {
        let pages = try DjVuDocument(url: url)
        guard pages.pageCount > 0 else {
            throw DjVuOpenError.noPages
        }
        var geometries: [PageGeometry] = []
        geometries.reserveCapacity(pages.pageCount)
        var previous = DjVuPageInfo.fallback
        for page in 0..<pages.pageCount {
            let info = pages.pageInfo(page) ?? previous
            previous = info
            geometries.append(PageGeometry(info: info))
        }
        return LoadedDocument(
            pages: pages,
            thumbnails: try? DjVuDocument(url: url),
            geometries: geometries,
            titles: pages.pageTitles(),
            outline: pages.outline()
        )
    }
}
