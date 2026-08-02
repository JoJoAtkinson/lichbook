// LichMenuBar — a menu bar toggle for the `lich` CLI.
//
// Left-click the icon: toggle risen (💀) / at rest (⚰️).
// Right-click (or option-click): status details, roaming, Start at Login, Quit.
//
// Why it exists: `lich on|off|status` is the whole product, but a docked
// machine deserves a one-click way to raise and lay it to rest without
// finding a terminal. This app therefore holds *no* logic of its own —
// every action shells out to the `lich` CLI, which stays the single source
// of truth for the risen flag, the power contract, and the privileged
// pmset call. If the two ever disagree, the CLI is right.
//
// Things that are not obvious:
//   * Unlike the Control Center control (../controlcenter), this app is NOT
//     sandboxed — that is the only reason it can spawn a subprocess at all.
//     Keep it that way or it degrades to flag-file poking.
//   * The Makefile ad-hoc signs the bundle ("-"), so Lich.app is a local
//     build. It is not notarized and will not survive being handed to
//     someone else's Mac via Gatekeeper.
//   * Whole app is one file, built by `make install` — no Xcode project.

import AppKit
import ServiceManagement

// Probe the two Homebrew prefixes in order — Apple Silicon (/opt/homebrew)
// first, then Intel/`lich install`'s symlink (/usr/local/bin). The fallback
// is deliberately a path that may not exist: lich() turns the failed spawn
// into a readable "run install first" message rather than a crash.
let cliPath = ["/opt/homebrew/bin/lich", "/usr/local/bin/lich"]
    .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/local/bin/lich"

// Run the CLI and capture both streams. Synchronous on the main thread on
// purpose: every call here is a sub-100ms bash invocation, and serializing
// them keeps the icon from disagreeing with the flag file mid-toggle.
@discardableResult
func lich(_ args: [String]) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: cliPath)
    process.arguments = args
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do { try process.run() } catch { return (127, "lich CLI not found at \(cliPath) — run install first") }
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

// Roaming — staying risen without the phylactery (i.e. on battery). The CLI
// owns the whole feature, including the battery floor that overrules every
// mode; this app only arms and disarms it. `lich roam status` prints exactly
// one machine-readable line, which is the only shape parsed here.
enum RoamMode: Equatable {
    case off
    case once
    case always
    case until(Int)   // epoch seconds
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var refreshTimer: Timer?

    // `lich status --quiet` prints nothing and exits 0 when risen, non-zero
    // when at rest — the CLI's machine-readable contract for exactly this.
    var risen: Bool { lich(["status", "--quiet"]).status == 0 }

    // Read live, never cached: the CLI clears roam on its own (floor breach,
    // timer expiry, one-shot spent), so a remembered value would show stale
    // checkmarks. Anything unexpected — a parse miss, or a `lich` too old to
    // know the command — reads as .off, which degrades the menu to the
    // pre-roam behaviour instead of claiming a mode that isn't armed.
    var roamMode: RoamMode {
        let result = lich(["roam", "status"])
        guard result.status == 0 else { return .off }
        let fields = result.output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
        switch fields.first.map(String.init) ?? "" {
        case "once": return .once
        case "always": return .always
        case "until":
            guard fields.count > 1, let epoch = Int(fields[1]) else { return .off }
            return .until(epoch)
        default: return .off
        }
    }

    // The timer item's label has to name the real number of minutes, so read
    // it from `lich config` ("key=value" lines, defaults included) rather than
    // hardcoding one that quietly disagrees with the CLI. The 30 here is only
    // the last resort for a CLI that cannot answer at all.
    var roamMins: Int {
        let result = lich(["config"])
        guard result.status == 0 else { return 30 }
        for line in result.output.split(separator: "\n") {
            let pair = line.split(separator: "=", maxSplits: 1)
            guard pair.count == 2,
                  pair[0].trimmingCharacters(in: .whitespaces) == "roam_mins",
                  let mins = Int(pair[1].trimmingCharacters(in: .whitespaces))
            else { continue }
            return mins
        }
        return 30
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        refresh()
        // Nothing notifies us when the flag file changes, and four things can
        // change it (CLI, Control Center control, ssh, Shortcuts). Poll so the
        // icon stays honest; 15s is cheap and well under noticing-it latency.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        autoRegisterLoginItemOnce()
    }

    // Login-item handling, via SMAppService (the modern replacement for
    // login-item hacks — no helper bundle, no AppleScript).
    //
    // A menu bar toggle nobody restarts after a reboot is useless, so we
    // self-register on first launch. macOS notifies the user and lists us in
    // System Settings > Login Items, so this is visible, not sneaky. The
    // UserDefaults latch makes it *once*: after that the right-click "Start
    // at Login" item owns the setting, and an unregister must stick.
    var loginItemEnabled: Bool { SMAppService.mainApp.status == .enabled }

    func autoRegisterLoginItemOnce() {
        let key = "didAutoRegisterLoginItem"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        try? SMAppService.mainApp.register()
        UserDefaults.standard.set(true, forKey: key)
    }

    @objc func toggleLoginItem() {
        if loginItemEnabled {
            try? SMAppService.mainApp.unregister()
        } else {
            try? SMAppService.mainApp.register()
        }
    }

    func refresh() {
        statusItem.button?.title = risen ? "💀" : "⚰️"
        statusItem.button?.toolTip = risen
            ? "lich: risen — stays awake with lid closed while on AC"
            : "lich: at rest — normal sleep"
    }

    // One button, two behaviours. Assigning a menu to the NSStatusItem would
    // make *every* click open the menu, so the button keeps its action and we
    // decide from the event which gesture we got.
    @objc func clicked() {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.option) == true
        wantsMenu ? showMenu() : toggle()
    }

    @objc func toggle() {
        lich([risen ? "off" : "on"])
        refresh()
    }

    // The three roam items are checkboxes, so each one is its own off switch:
    // clicking an armed mode disarms it. Arming never has to clear the other
    // two by hand — roam is a single value in the CLI, so writing one mode
    // replaces whatever was there. Arming also raises the lich (the CLI does
    // that too), hence the refresh for the icon.
    @objc func roamOnce(_ sender: NSMenuItem) {
        armRoam(sender.state == .on ? ["roam", "off"] : ["roam"])
    }

    @objc func roamAlways(_ sender: NSMenuItem) {
        armRoam(sender.state == .on ? ["roam", "off"] : ["roam", "always"])
    }

    @objc func roamTimer(_ sender: NSMenuItem) {
        armRoam(sender.state == .on ? ["roam", "off"] : ["roam", "timer"])
    }

    func armRoam(_ args: [String]) {
        lich(args)
        refresh()
    }

    func showMenu() {
        let menu = NSMenu()
        // Rendered as disabled header lines: whatever `lich status` prints
        // (risen state, power source, sleep setting, watcher health) shows up
        // here verbatim, so the menu never drifts from the CLI's wording.
        let status = lich(["status"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        for line in status.split(separator: "\n") {
            menu.addItem(withTitle: String(line), action: nil, keyEquivalent: "")
        }
        menu.addItem(.separator())
        let toggleItem = menu.addItem(
            withTitle: risen ? "Lay to rest (off)" : "Raise the lich (on)",
            action: #selector(toggle), keyEquivalent: "")
        toggleItem.target = self

        // Roaming, in plain English — no lore in the labels, because the thing
        // a user is choosing here is "don't sleep when I unplug". One read of
        // the CLI feeds all three checkmarks so they can't disagree with each
        // other mid-menu. Durations are deliberately not editable here: the
        // minutes live in `lich config`, and this menu just reflects them.
        menu.addItem(.separator())
        let mode = roamMode
        var isTimed = false
        if case .until = mode { isTimed = true }
        let roamItems: [(String, Selector, Bool)] = [
            ("Stay awake unplugged — once", #selector(roamOnce(_:)), mode == .once),
            ("Stay awake unplugged — always", #selector(roamAlways(_:)), mode == .always),
            ("Stay awake unplugged — for \(roamMins) min", #selector(roamTimer(_:)), isTimed),
        ]
        for (title, action, checked) in roamItems {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
            item.state = checked ? .on : .off
        }

        menu.addItem(.separator())
        let loginItem = menu.addItem(
            withTitle: "Start at Login",
            action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = loginItemEnabled ? .on : .off
        let quitItem = menu.addItem(
            withTitle: "Quit Lich",
            action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp

        // Attach, click to pop it open, then detach on the next runloop turn
        // so the *next* left-click toggles again instead of reopening the
        // menu. Clearing it synchronously would cancel the menu we just asked
        // for; the async hop lands after it has been presented.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        DispatchQueue.main.async { self.statusItem.menu = nil }
    }
}

// No main.swift, no @main: this is a script-style top-level entry point, which
// is what lets the whole app be a single file compiled by swiftc.
// .accessory = menu bar only — no Dock tile, no menu bar menus of its own.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
