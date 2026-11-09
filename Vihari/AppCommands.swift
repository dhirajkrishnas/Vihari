import SwiftUI

/// What the focused window can do from the menu bar (Mac and iPad) and keyboard shortcuts.
struct SceneActions {
    var addCity: () -> Void
    /// Nil while the introduction is showing.
    var openSettings: (() -> Void)?
    /// Nil while the introduction is showing.
    var showAlarms: (() -> Void)?
}

extension FocusedValues {
    @Entry var sceneActions: SceneActions?
}

/// File > Add City… (⌘N), View > Show Alarms (⇧⌘A) and, on iPad, Settings… (⌘,), acting on the
/// frontmost window.
/// The Mac's Settings… item comes with its Settings window.
struct VihariCommands: Commands {
    @FocusedValue(\.sceneActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add City…") { actions?.addCity() }
                .keyboardShortcut("n")
                .disabled(actions == nil)
        }
        CommandGroup(before: .toolbar) {
            Button("Show Alarms") { actions?.showAlarms?() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(actions?.showAlarms == nil)
        }
        #if !os(macOS)
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { actions?.openSettings?() }
                .keyboardShortcut(",")
                .disabled(actions?.openSettings == nil)
        }
        #endif
    }
}
