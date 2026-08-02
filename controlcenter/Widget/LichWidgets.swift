// LichControl — the Control Center toggle for lich (macOS 26+).
//
// A ControlWidget: it shows up in Control Center, can be dragged to the menu
// bar, and is reachable from the Lock Screen — one tap to raise or lay the
// machine to rest without a terminal.
//
// The constraint that shapes this whole file: macOS force-sandboxes
// app extensions. No opting out. So unlike the menu bar app (../../menubar),
// this cannot spawn `lich`, launchctl, or pmset — it has no subprocess at
// all. Everything it does is read and write one file, the risen flag at
// ~/.lich/desired-state, reached through an absolute-path sandbox exception
// in LichControl.entitlements (generated per-user by ../build.sh, because
// the exception must name a literal $HOME). The `lich watch` LaunchAgent
// polls that flag every 5 seconds and performs the privileged pmset call,
// so the visible effect of a tap lags by up to ~5s. That is the design, not
// a bug: the flag file is the API, and the CLI stays the source of truth.
//
// Icon note: Control Center renders SF Symbols only (no emoji), and Apple
// ships no skull/coffin symbol — so the control uses power glyphs and the
// skull/coffin theme lives in the CLI and menu bar app.

import AppIntents
import SwiftUI
import WidgetKit

// NSHomeDirectory() inside a sandboxed extension returns the container home,
// not /Users/<you> — resolve the real home via the passwd database instead.
private var stateFileURL: URL {
    var home = NSHomeDirectory()
    if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
        home = String(cString: dir)
    }
    return URL(fileURLWithPath: home).appendingPathComponent(".lich/desired-state")
}

// Missing or unreadable file reads as at rest — the safe default, since it
// means "let the machine sleep normally". Anything that isn't exactly "on"
// (trimmed) is at rest, matching the CLI's own reading of the flag.
func readRisen() -> Bool {
    let raw = (try? String(contentsOf: stateFileURL, encoding: .utf8)) ?? "off"
    return raw.trimmingCharacters(in: .whitespacesAndNewlines) == "on"
}

// SetValueIntent (not AppIntent) is what ControlWidgetToggle requires: the
// system hands us the value it wants, rather than us flipping the current
// one. That keeps taps idempotent when the control's cached state is stale.
// It also makes the toggle a Shortcuts action for free.
struct ToggleLichIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Toggle Lich"

    @Parameter(title: "Risen")
    var value: Bool

    func perform() async throws -> some IntentResult {
        // atomically: true writes via a temp file + rename, so the watcher
        // never reads a half-written flag. Write is the entire side effect;
        // the LaunchAgent picks it up on its next 5-second pass.
        try (value ? "on" : "off").write(to: stateFileURL, atomically: true, encoding: .utf8)
        return .result()
    }
}

struct LichToggle: ControlWidget {
    // Stable identity for this control. Changing it makes the system treat
    // it as a brand-new control: anyone who added it to Control Center or
    // the menu bar loses their placement and has to add it again.
    static let kind = "com.lichbook.toggle"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: Provider()) { isOn in
            ControlWidgetToggle("Lich", isOn: isOn, action: ToggleLichIntent()) { on in
                Label(on ? "Risen" : "At rest",
                      systemImage: on ? "powerplug.portrait.fill" : "moon.zzz.fill")
            }
        }
        .displayName("Lich")
        .description("Stay awake with the lid closed while on AC power.")
    }

    // The system asks for currentValue when it refreshes the control; there
    // is no push from the flag file, so a change made by the CLI or the menu
    // bar app shows up here whenever macOS next asks. previewValue is what
    // the control gallery renders before any read happens — at rest, so the
    // gallery never advertises a state the machine isn't in.
    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }
        func currentValue() async throws -> Bool { readRisen() }
    }
}

// The extension's entry point. One control today; additional ControlWidgets
// would be listed here and would ship inside the same .appex.
@main
struct LichWidgetBundle: WidgetBundle {
    var body: some Widget {
        LichToggle()
    }
}
