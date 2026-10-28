import AppKit
import SwiftUI

/// One visual vocabulary for every settings page, including error/report states.
enum SettingsStyle {
    static let accent = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.94, green: 0.48, blue: 0.39, alpha: 1)
                : NSColor(srgbRed: 0.64, green: 0.20, blue: 0.16, alpha: 1)
        })
    static let canvas = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.12, green: 0.12, blue: 0.13, alpha: 1)
                : NSColor(srgbRed: 0.97, green: 0.96, blue: 0.94, alpha: 1)
        })
    static let card = Color(nsColor: .controlBackgroundColor)
    static let line = Color.primary.opacity(0.075)
}

struct SettingsHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 26, weight: .semibold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28).padding(.top, 25).padding(.bottom, 20)
        .accessibilityElement(children: .combine)
    }
}

struct SettingsScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18, content: content)
                .frame(maxWidth: 900, alignment: .leading)
                .padding(.horizontal, 28).padding(.top, 2).padding(.bottom, 24)
                .frame(maxWidth: .infinity)
        }
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !title.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    if let icon {
                        Image(systemName: icon).foregroundStyle(SettingsStyle.accent)
                            .font(.system(size: 16, weight: .medium)).frame(width: 22, height: 22)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.system(size: 14, weight: .semibold))
                        if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 14, content: content)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsStyle.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(SettingsStyle.line, lineWidth: 1))
    }
}

struct SettingsDisclosure<Content: View>: View {
    let title: String
    let subtitle: String
    @State private var expanded = false
    @ViewBuilder var content: () -> Content
    var body: some View {
        SettingsCard(title: "") {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 14, content: content).padding(.top, 14)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }
}

struct SettingsBadge: View {
    let title: String
    var accent = false
    var body: some View {
        Text(title).font(.system(size: 10, weight: .medium))
            .foregroundStyle(accent ? SettingsStyle.accent : Color.secondary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(accent ? SettingsStyle.accent.opacity(0.09) : Color.primary.opacity(0.05), in: Capsule())
    }
}

struct SettingsHint: View {
    let text: String
    var icon = "info.circle"
    var body: some View {
        Label(text, systemImage: icon).font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Unlike LabeledContent's form-specific layout, keeps labels at the leading
/// edge in a card and leaves the whole row available to assistive technology.
struct SettingsFieldRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
            Spacer(minLength: 12)
            content()
        }.frame(maxWidth: .infinity).accessibilityElement(children: .contain)
    }
}
