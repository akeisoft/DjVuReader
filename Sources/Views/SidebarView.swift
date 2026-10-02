import SwiftUI

struct SidebarView: View {
    @Bindable var model: ReaderModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            Picker("Sidebar", selection: $model.sidebarTab) {
                Text("Thumbnails").tag(SidebarTab.thumbnails)
                Text("Contents").tag(SidebarTab.outline)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Group {
                switch model.phase {
                case .ready:
                    switch model.sidebarTab {
                    case .thumbnails: ThumbnailList(model: model)
                    case .outline: OutlineList(model: model)
                    }
                default:
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // A row of its own under the list (not an inset over it): thumbnails are
            // tall pictures and scrolled underneath the transparent footer, covering ⓘ.
            SidebarFooter(openAbout: { openWindow(id: AboutView.windowID) })
        }
    }
}

/// Settings and About, always at hand at the bottom of the sidebar (not only in
/// the menu bar), the same way as in MAC64.
private struct SidebarFooter: View {
    let openAbout: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 2) {
                SettingsLink {
                    FooterIcon(symbol: "gearshape")
                }
                .help(Text("Settings"))
                .accessibilityLabel(Text("Settings"))
                Button(action: openAbout) {
                    FooterIcon(symbol: "info.circle")
                }
                .help(Text("About DjVu Reader"))
                .accessibilityLabel(Text("About DjVu Reader"))
                Spacer(minLength: 0)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }
}

private struct FooterIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 30, height: 26)
            .contentShape(Rectangle())
    }
}

// MARK: - Thumbnails

private struct ThumbnailList: View {
    let model: ReaderModel

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: Binding<Int?>(
                get: { model.currentPage },
                set: { page in if let page { model.goTo(page: page) } }
            )) {
                ForEach(0..<model.pageCount, id: \.self) { page in
                    ThumbnailCell(model: model, page: page)
                        .tag(page)
                }
            }
            .listStyle(.sidebar)
            .onAppear { proxy.scrollTo(model.currentPage, anchor: .center) }
            .onChange(of: model.currentPage) { _, page in
                proxy.scrollTo(page, anchor: .center)
            }
        }
    }
}

private struct ThumbnailCell: View {
    let model: ReaderModel
    let page: Int
    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 5) {
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.12))
                        .aspectRatio(model.aspectRatio(of: page), contentMode: .fit)
                }
            }
            .frame(maxWidth: 132, maxHeight: 176)
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)

            Text(model.pageLabel(page))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .task(id: page) {
            // Rows flying past during a fast scroll are cancelled before any decoding starts.
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            image = await model.thumbnail(for: page)
        }
    }
}

// MARK: - Contents

private struct OutlineList: View {
    let model: ReaderModel

    var body: some View {
        if model.outline.isEmpty {
            ContentUnavailableView(
                "No Table of Contents",
                systemImage: "list.bullet.indent",
                description: Text("This document has no outline.")
            )
        } else {
            List {
                OutlineGroup(model.outline, children: \.children) { node in
                    Button {
                        if node.page >= 0 { model.goTo(page: node.page) }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(node.title)
                                .lineLimit(2)
                            Spacer(minLength: 4)
                            if node.page >= 0 {
                                Text(model.pageLabel(node.page))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.sidebar)
        }
    }
}
