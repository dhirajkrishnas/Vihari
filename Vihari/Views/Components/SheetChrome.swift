import SwiftUI

/// A sheet's navigation container: a navigation stack on iPhone, iPad and Apple Vision Pro.
///
/// On the Mac a navigation stack puts a sheet's title and its buttons in grey bars that clash
/// with the sheet's gradient. There the sheet draws them itself instead, on its own background,
/// with `macSheetHeader` and `macSheetFooter`.
struct SheetNavigationStack<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        #if os(macOS)
        content
        #else
        NavigationStack { content }
        #endif
    }
}

#if os(macOS)
extension View {
    /// The sheet's title, and its subtitle, in a bar along the top.
    func macSheetHeader(_ title: Text, subtitle: Text? = nil) -> some View {
        macSheetHeader(title, subtitle: subtitle) { EmptyView() }
    }

    /// The sheet's title, its subtitle and an accessory under them (a search field, say) in a bar
    /// along the top. Content scrolls under it and fades out behind it.
    func macSheetHeader<Accessory: View>(
        _ title: Text,
        subtitle: Text? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        let accessory = accessory()
        return scrollEdgeEffectStyle(.soft, for: .top).safeAreaBar(edge: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    title
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        subtitle
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                accessory
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)
        }
    }

    /// The sheet's buttons in a bar along the bottom, at the trailing edge, the default one last.
    func macSheetFooter<Trailing: View>(@ViewBuilder trailing: () -> Trailing) -> some View {
        macSheetFooter(leading: { EmptyView() }, trailing: trailing)
    }

    /// The sheet's buttons in a bar along the bottom: `leading` ones (a destructive or secondary
    /// action) at the leading edge, `trailing` ones at the trailing edge, the default one last.
    func macSheetFooter<Leading: View, Trailing: View>(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        let leading = leading()
        let trailing = trailing()
        return scrollEdgeEffectStyle(.soft, for: .bottom).safeAreaBar(edge: .bottom, spacing: 0) {
            HStack(spacing: 10) {
                leading
                Spacer(minLength: 12)
                trailing
            }
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }
}

/// A search field for a Mac sheet's header: glass, with a magnifying glass and a clear button.
struct MacSearchField: View {
    @Binding var text: String
    let prompt: Text
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(text: $text, prompt: prompt) { prompt }
                .textFieldStyle(.plain)
                .focused(isFocused)
            if !text.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .adaptiveGlass(in: Capsule())
    }
}

/// Closes a sheet that has nothing to save. Escape presses it too.
struct MacSheetDoneButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("Done") { dismiss() }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.cancelAction)
    }
}
#endif
