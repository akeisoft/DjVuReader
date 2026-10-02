import AppKit
import SwiftUI

/// Version, developer, decoder and license. Opened from the ⓘ button at the
/// bottom of the sidebar and from "About DjVu Reader" in the app menu.
/// Layout follows MAC64's About window.
struct AboutView: View {
    static let windowID = "about"

    private static let developer = "AKEISOFT"
    private static let website = URL(string: "https://akeisoft.com")
    /// Keep in sync with ThirdParty/DjVuLibre/VERSION.
    private static let decoder = "DjVuLibre 3.5.30"
    private static let license = "GPL-2.0-or-later"

    @State private var copied = false

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    /// "© 2026 AKEISOFT …", from Info.plist (localized in InfoPlist.strings).
    private var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "© \(Self.developer)"
    }

    /// For support requests: the app, macOS and the Mac model, one per line.
    private var versionInfo: String {
        [
            "DjVu Reader \(version) (\(build))",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            Self.sysctlString("hw.model") ?? "—",
        ].joined(separator: "\n")
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 96, height: 96)
                Text(verbatim: "DjVu Reader")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Version \(version) (\(build))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .textSelection(.enabled)
                Text("Reader for DjVu books and scanned documents.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }

            InfoCard {
                InfoRow("Developer") {
                    Text(verbatim: Self.developer)
                }
                InfoRow("Website") {
                    if let website = Self.website {
                        Link(destination: website) {
                            Text(verbatim: "akeisoft.com")
                        }
                    }
                }
                InfoRow("Requirements") {
                    Text("macOS 14 or later")
                }
                InfoRow("Languages") {
                    Text(verbatim: "Русский, Українська, English")
                }
            }

            InfoCard {
                Label {
                    Text("DjVu Reader works offline")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(.green)
                }
            }

            InfoCard {
                InfoRow("Decoder") {
                    Text(verbatim: Self.decoder)
                }
                InfoRow("License") {
                    Text(verbatim: Self.license)
                }
            }

            HStack {
                Text(verbatim: copyright)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(versionInfo, forType: .string)
                    copied = true
                } label: {
                    Label(copied ? LocalizedStringKey("Copied") : LocalizedStringKey("Copy version info"),
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                }
            }
        }
        .padding(24)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// A string sysctl such as "hw.model" ("Mac16,10").
    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix(while: { $0 != 0 }), as: UTF8.self)
    }
}

/// A rounded group, like the rows of a grouped form.
private struct InfoCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Title on the left, value on the right.
private struct InfoRow<Value: View>: View {
    let title: LocalizedStringKey
    let value: Value

    init(_ title: LocalizedStringKey, @ViewBuilder value: () -> Value) {
        self.title = title
        self.value = value()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            value
                .multilineTextAlignment(.trailing)
        }
    }
}
