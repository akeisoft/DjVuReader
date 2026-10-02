import SwiftUI

/// One document window: sidebar with thumbnails and contents, pages on the right.
struct ReaderView: View {
    let fileURL: URL?

    @State private var model = ReaderModel()
    @State private var pageInput = ""

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 170, ideal: 210, max: 340)
        } detail: {
            detail
                .overlay(alignment: .bottom) { statusToast }
        }
        .navigationTitle(model.title)
        .toolbar { ReaderToolbar(model: model) }
        .focusedSceneValue(\.reader, model)
        .modifier(AppAppearance())
        .task {
            if let fileURL { await model.open(fileURL) }
        }
        .onDisappear { model.saveReadingState() }
        .alert("Go to Page", isPresented: $model.isGoToPagePresented) {
            TextField("Page number", text: $pageInput)
            Button("Jump") {
                if let number = Int(pageInput.trimmingCharacters(in: .whitespaces)) {
                    model.goTo(page: number - 1)
                }
                pageInput = ""
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { pageInput = "" }
        } message: {
            Text("Enter a number from 1 to \(model.pageCount).")
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.phase {
        case .idle, .loading:
            ProgressView("Opening…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let reason, let details):
            ContentUnavailableView {
                Label("This document can't be opened", systemImage: "exclamationmark.triangle")
            } description: {
                VStack(spacing: 8) {
                    Text(reason)
                    if let details {
                        Text(details)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        case .ready:
            PagesView(model: model)
        }
    }

    @ViewBuilder
    private var statusToast: some View {
        if let message = model.statusMessage {
            Text(message)
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 18)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }
}

/// Lets menu commands reach the model of the frontmost window.
struct ReaderModelFocusedKey: FocusedValueKey {
    typealias Value = ReaderModel
}

extension FocusedValues {
    var reader: ReaderModel? {
        get { self[ReaderModelFocusedKey.self] }
        set { self[ReaderModelFocusedKey.self] = newValue }
    }
}
