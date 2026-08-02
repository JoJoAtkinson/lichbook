// LichControl — the Control Center toggle for lich.
//
// This extension is force-sandboxed by macOS, so it cannot run launchctl or
// pmset. All it does is read/write the risen flag at ~/.lich/desired-state
// (whitelisted in LichControl.entitlements); the lich watcher LaunchAgent
// notices the change within a few seconds and does the privileged work.
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

func readRisen() -> Bool {
    let raw = (try? String(contentsOf: stateFileURL, encoding: .utf8)) ?? "off"
    return raw.trimmingCharacters(in: .whitespacesAndNewlines) == "on"
}

struct ToggleLichIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Toggle Lich"

    @Parameter(title: "Risen")
    var value: Bool

    func perform() async throws -> some IntentResult {
        try (value ? "on" : "off").write(to: stateFileURL, atomically: true, encoding: .utf8)
        return .result()
    }
}

struct LichToggle: ControlWidget {
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

    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }
        func currentValue() async throws -> Bool { readRisen() }
    }
}

@main
struct LichWidgetBundle: WidgetBundle {
    var body: some Widget {
        LichToggle()
    }
}
