import SwiftUI

/// What the focused window can do from the menu bar (Mac and iPad) and keyboard shortcuts.
struct SceneActions {
    var addCity: () -> Void
    /// Nil while the introduction is showing.
    var openSettings: (() -> Void)?
}

extension FocusedValues {
    @Entry var sceneActions: SceneActions?
}

/// File > Add City… (⌘N) and Settings… (⌘,), acting on the frontmost window.
struct WanderClockCommands: Commands {
    @FocusedValue(\.sceneActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add City…") { actions?.addCity() }
                .keyboardShortcut("n")
                .disabled(actions == nil)
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { actions?.openSettings?() }
                .keyboardShortcut(",")
                .disabled(actions?.openSettings == nil)
        }
    }
}
