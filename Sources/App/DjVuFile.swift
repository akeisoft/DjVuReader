import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Two identifiers are in use for DjVu files on macOS; Info.plist declares
    /// both (UTImportedTypeDeclarations), whichever one the system picks works.
    static let djvu = UTType(importedAs: "com.lizardtech.djvu")
    static let djvuAlternative = UTType(importedAs: "org.djvu.djvu")
}

/// The document type SwiftUI opens. It reads nothing itself: DjVuLibre reads
/// the file straight from its URL, page by page, so big books open instantly
/// and indirect (multi-file) documents find their companion files.
struct DjVuFile: FileDocument {
    static var readableContentTypes: [UTType] {
        // Also accept whatever type another installed app has registered for
        // these extensions, so .djvu files are never greyed out in Open dialogs.
        var types: [UTType] = [.djvu, .djvuAlternative]
        for ext in ["djvu", "djv"] {
            if let type = UTType(filenameExtension: ext), !types.contains(type) {
                types.append(type)
            }
        }
        return types
    }

    static var writableContentTypes: [UTType] { [] }

    init(configuration: ReadConfiguration) throws {}

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.featureUnsupported)
    }
}
