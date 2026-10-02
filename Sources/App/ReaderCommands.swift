import SwiftUI

/// Menu bar commands for the frontmost reader window.
struct ReaderCommands: Commands {
    @FocusedValue(\.reader) private var reader

    private var isReady: Bool { reader?.phase == .ready }

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copy Page Text") { reader?.copyCurrentPageText() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!isReady)
        }

        CommandGroup(after: .sidebar) {
            Divider()
            Button("Zoom In") { reader?.zoomIn() }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(!isReady)
            Button("Zoom Out") { reader?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!isReady)
            Button("Actual Size") { reader?.actualSize() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(!isReady)
            Button("Fit Width") { reader?.setZoomMode(.fitWidth) }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(!isReady)
            Button("Fit Page") { reader?.setZoomMode(.fitPage) }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(!isReady)
            Divider()
            Toggle("Night Mode", isOn: Binding(
                get: { reader?.nightMode ?? false },
                set: { reader?.setNightMode($0) }
            ))
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(!isReady)
            Menu("Display Mode") {
                ForEach(RenderMode.allCases, id: \.self) { mode in
                    Toggle(mode.title, isOn: Binding(
                        get: { reader?.renderMode == mode },
                        set: { if $0 { reader?.setRenderMode(mode) } }
                    ))
                }
            }
            .disabled(!isReady)
        }

        CommandMenu("Go") {
            Button("Next Page") { reader?.nextPage() }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(!isReady)
            Button("Previous Page") { reader?.previousPage() }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(!isReady)
            Divider()
            Button("First Page") { reader?.firstPage() }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(!isReady)
            Button("Last Page") { reader?.lastPage() }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(!isReady)
            Divider()
            Button("Go to Page…") { reader?.isGoToPagePresented = true }
                .keyboardShortcut("g", modifiers: [.command, .option])
                .disabled(!isReady)
        }
    }
}
