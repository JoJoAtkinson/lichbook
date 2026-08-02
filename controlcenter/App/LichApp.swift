// LichToggle — stub container app for the Control Center control.
//
// The app itself does nothing and shows nothing: no window, no Dock tile
// (LSUIElement in project.yml). It exists purely as a delivery vehicle —
// macOS only discovers widget/control extensions inside an app bundle, and
// only after that bundle has been launched at least once, which is why
// build.sh ends with `open /Applications/LichToggle.app`.
//
// The real control lives in ../Widget; all real logic lives in the `lich`
// CLI. Between them, the only contract is the flag file
// ~/.lich/desired-state. Nothing needs to be added here — if you find
// yourself wanting app code, it probably belongs in the CLI instead.
//
// Settings/EmptyView() is the least-surprising empty Scene: an App must
// declare one, and a Settings scene stays closed until someone picks
// Settings from a menu this app never shows.

import SwiftUI

@main
struct LichToggleApp: App {
    var body: some Scene {
        Settings { EmptyView() }
    }
}
