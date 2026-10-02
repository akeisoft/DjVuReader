import AppKit
import SwiftUI

/// Hosts the AppKit reading surface inside the SwiftUI window.
struct PagesView: NSViewRepresentable {
    let model: ReaderModel

    final class Coordinator {
        var controller: PagesController?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let controller = PagesController(model: model)
        context.coordinator.controller = controller
        return controller.scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // State flows through ReaderModel's commands; here we only make sure the
        // restored position is applied once SwiftUI has given the view its size.
        context.coordinator.controller?.applyInitialStateIfPossible()
    }
}
