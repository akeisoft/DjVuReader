import SwiftUI

struct ReaderToolbar: ToolbarContent {
    let model: ReaderModel

    private var isReady: Bool { model.phase == .ready }

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            PageField(model: model)
                .disabled(!isReady)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            ControlGroup {
                Button {
                    model.zoomOut()
                } label: {
                    Label("Zoom Out", systemImage: "minus.magnifyingglass")
                }
                .help("Zoom Out")

                Menu {
                    Button("Fit Width") { model.setZoomMode(.fitWidth) }
                    Button("Fit Page") { model.setZoomMode(.fitPage) }
                    Button("Actual Size") { model.actualSize() }
                    Divider()
                    ForEach([50, 75, 100, 125, 150, 200, 300, 400], id: \.self) { percent in
                        Button {
                            model.setZoom(percent: percent)
                        } label: {
                            Text(verbatim: "\(percent) %")
                        }
                    }
                } label: {
                    Text(model.zoomDescription)
                        .monospacedDigit()
                        .frame(minWidth: 72)
                }
                .help("Zoom")

                Button {
                    model.zoomIn()
                } label: {
                    Label("Zoom In", systemImage: "plus.magnifyingglass")
                }
                .help("Zoom In")
            }
            .disabled(!isReady)

            Toggle(isOn: Binding(get: { model.nightMode }, set: { model.setNightMode($0) })) {
                Label("Night Mode", systemImage: model.nightMode ? "moon.fill" : "moon")
            }
            .toggleStyle(.button)
            .help("Night Mode")
            .disabled(!isReady)

            Menu {
                Picker("Display Mode", selection: Binding(get: { model.renderMode }, set: { model.setRenderMode($0) })) {
                    ForEach(RenderMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Display Mode", systemImage: "circle.lefthalf.filled")
            }
            .help("Display Mode")
            .disabled(!isReady)
        }
    }
}

extension RenderMode {
    var title: LocalizedStringKey {
        switch self {
        case .color: return "Color"
        case .blackAndWhite: return "Black & White"
        case .background: return "Background Only"
        case .foreground: return "Foreground Only"
        }
    }
}

/// "[ 12 ] of 340": type a number and press Return to jump.
struct PageField: View {
    let model: ReaderModel
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField("Page number", text: $text)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 56)
                .focused($isFocused)
                .onSubmit(jump)
            // The toolbar sizes this item once, while the count is still 0; the hidden
            // "of 99999" reserves room for any real count in the current language.
            ZStack(alignment: .leading) {
                Text("of \(99999)").hidden()
                Text("of \(model.pageCount)")
            }
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .fixedSize()
        }
        .help("Page number")
        .onAppear { text = String(model.currentPage + 1) }
        .onChange(of: model.currentPage) { _, page in
            if !isFocused { text = String(page + 1) }
        }
        .onChange(of: model.pageCount) { _, _ in
            text = String(model.currentPage + 1)
        }
    }

    private func jump() {
        if let number = Int(text.trimmingCharacters(in: .whitespaces)) {
            model.goTo(page: number - 1)
        }
        text = String(model.currentPage + 1)
        isFocused = false
    }
}
