// LichToggle — stub container app for the Control Center control.
//
// The app itself does nothing and shows nothing (LSUIElement). It exists
// because macOS only discovers widget/control extensions inside an app
// bundle that has been launched at least once. All real logic lives in the
// `lich` CLI; the control in Widget/ just flips ~/.lich/desired-state.

import SwiftUI

@main
struct LichToggleApp: App {
    var body: some Scene {
        Settings { EmptyView() }
    }
}
