// LichMenuBar — a menu bar control panel for the `lich` CLI.
//
// The icon is a status light: 💀 risen / ⚰️ at rest. Any click opens the
// menu: live status lines, then checkboxes — Awake (the tool), the three
// roam modes, Start at Login — and Quit. Numbers (battery floor, timer
// minutes) are deliberately CLI-only (`lich config`); the menu reflects them.
//
// Why it exists: `lich on|off|status` is the whole product, but a docked
// machine deserves a one-click way to raise and lay it to rest without
// finding a terminal. This app therefore holds *no* logic of its own —
// every action shells out to the `lich` CLI, which stays the single source
// of truth for the risen flag, the power contract, and the privileged
// pmset call. If the two ever disagree, the CLI is right.
//
// Performance model — open from cache, verify async: every CLI call is a
// bash spawn (~50-100ms), and the menu needs several. Paying them on the
// click path made opening feel sluggish, so the menu now presents INSTANTLY
// from the last-known snapshot and a background fetch repaints checkmarks,
// status lines, and the icon in place a beat later (the stay-open custom
// views make live repainting possible). The CLI remains the single source
// of truth — the menu just stops making the user wait to hear it.
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

// Run the CLI and capture both streams. Called only from cliQueue (below),
// never from the main thread — the UI must not wait on a bash spawn.
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

// One serial queue for every CLI interaction. Serializing means an action
// and a refresh can never interleave their subprocesses, so the snapshot
// that follows an action always reflects that action.
let cliQueue = DispatchQueue(label: "com.lichbook.menubar.cli", qos: .userInitiated)

// Roaming — staying risen without the phylactery (i.e. on battery). The CLI
// owns the whole feature, including the battery floor that overrules every
// mode; this app only arms and disarms it. `lich roam status` prints exactly
// one machine-readable line of two tokens — "<standing> <trip>" where
// standing is off|always|timer and trip is -|once|until:<epoch>. Standing =
// the owner's persistent setting; trip = a temporary overlay that evaporates
// without touching the setting.
struct RoamState: Equatable {
    enum Standing: String { case off, always, timer }
    var standing: Standing = .off
    var hasTrip: Bool = false
}

// Everything the UI shows, captured in one read. Fetched off-main; painted
// on main. `statusLines` is `lich status` verbatim, so the menu never
// drifts from the CLI's wording.
struct Snapshot {
    var risen = false
    var roam = RoamState()
    var mins = 30
    var statusLines: [String] = ["lich: reading…"]
}

// The full truth, in four CLI calls. Runs on cliQueue only.
func fetchSnapshot() -> Snapshot {
    var snap = Snapshot()
    snap.risen = lich(["status", "--quiet"]).status == 0

    let roam = lich(["roam", "status"])
    if roam.status == 0 {
        let fields = roam.output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
        if let s = fields.first.flatMap({ RoamState.Standing(rawValue: String($0)) }) {
            snap.roam.standing = s
        }
        if fields.count > 1, fields[1] != "-" { snap.roam.hasTrip = true }
    }

    let config = lich(["config"])
    if config.status == 0 {
        for line in config.output.split(separator: "\n") {
            let pair = line.split(separator: "=", maxSplits: 1)
            if pair.count == 2,
               pair[0].trimmingCharacters(in: .whitespaces) == "roam_mins",
               let mins = Int(pair[1].trimmingCharacters(in: .whitespaces)) {
                snap.mins = mins
            }
        }
    }

    let status = lich(["status"])
    if status.status == 0 || !status.output.isEmpty {
        snap.statusLines = status.output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n").map(String.init)
    }
    return snap
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var refreshTimer: Timer?

    // Last-known truth; the menu opens from this instantly. Refreshed at
    // launch, every 15s, after every action, and on every menu open.
    var cache = Snapshot()

    // Live references into the currently-open menu, so an async snapshot can
    // repaint it in place. Rebuilt on each open.
    private var menuToggles: [(button: NSButton, isOn: (Snapshot) -> Bool)] = []
    private var statusLineItems: [NSMenuItem] = []

    var loginItemEnabled: Bool { SMAppService.mainApp.status == .enabled }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.title = "💀"   // provisional until the first snapshot lands
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        refreshAsync()
        // Nothing notifies us when the flag file changes, and four things can
        // change it (CLI, Control Center control, ssh, Shortcuts). Poll so the
        // icon stays honest; 15s is cheap and well under noticing-it latency.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.refreshAsync()
        }
        autoRegisterLoginItemOnce()
    }

    // Login-item handling, via SMAppService (the modern replacement for
    // login-item hacks — no helper bundle, no AppleScript).
    //
    // A menu bar toggle nobody restarts after a reboot is useless, so we
    // self-register on first launch. macOS notifies the user and lists us in
    // System Settings > Login Items, so this is visible, not sneaky. The
    // UserDefaults latch makes it *once*: after that the menu's "Start at
    // Login" checkbox owns the setting, and an unregister must stick.
    func autoRegisterLoginItemOnce() {
        let key = "didAutoRegisterLoginItem"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        try? SMAppService.mainApp.register()
        UserDefaults.standard.set(true, forKey: key)
    }

    // Fetch off-main, paint on main. The only path that touches the CLI for
    // display purposes.
    func refreshAsync() {
        cliQueue.async { [weak self] in
            let snap = fetchSnapshot()
            DispatchQueue.main.async { self?.apply(snap) }
        }
    }

    // Paint one snapshot everywhere: icon, tooltip, and — when the menu is
    // open — every checkbox and status line, in place.
    func apply(_ snap: Snapshot) {
        cache = snap
        statusItem.button?.title = snap.risen ? "💀" : "⚰️"
        statusItem.button?.toolTip = snap.risen
            ? "lich: risen — stays awake with lid closed while on AC"
            : "lich: at rest — normal sleep"
        for t in menuToggles { t.button.state = t.isOn(snap) ? .on : .off }
        if statusLineItems.count == snap.statusLines.count {
            for (item, line) in zip(statusLineItems, snap.statusLines) {
                item.title = line
            }
        }
    }

    // Any click opens the menu. A click-to-toggle icon looks like a mystery
    // button — nothing advertises that a menu exists — so the icon is a pure
    // status light (💀/⚰️) and every control lives one click away where it
    // can be read before it's flipped.
    @objc func clicked() {
        showMenu()
    }

    // ---- stay-open toggles -------------------------------------------------
    // The toggle rows are real checkbox controls inside CUSTOM VIEWS, not
    // plain menu items: a plain NSMenuItem dismisses the menu the instant
    // it's clicked, and a settings panel that vanishes the moment you use it
    // forces a reopen just to confirm. Menu items that carry a view do NOT
    // auto-dismiss — click, watch the checkmark (and the 💀/⚰️) change in
    // place, then click anywhere outside (or press Esc) to close. The trade:
    // these rows have no hover highlight. Quit stays a plain item and closes
    // the menu like a menu item should.
    private func addToggle(to menu: NSMenu, title: String,
                           isOn: @escaping (Snapshot) -> Bool, action: Selector) {
        let button = NSButton(checkboxWithTitle: title, target: self, action: action)
        button.font = NSFont.menuFont(ofSize: 0)
        button.state = isOn(cache) ? .on : .off
        button.sizeToFit()
        let pad: CGFloat = 14
        let view = NSView(frame: NSRect(x: 0, y: 0,
                                        width: button.frame.width + pad * 2,
                                        height: button.frame.height + 8))
        button.setFrameOrigin(NSPoint(x: pad, y: 4))
        view.addSubview(button)
        let item = NSMenuItem()
        item.view = view
        menu.addItem(item)
        menuToggles.append((button, isOn))
    }

    // Every action: fire the CLI off-main, then fetch the truth and repaint.
    // The checkbox flips optimistically the instant it's clicked (NSButton
    // does that itself); the snapshot that follows confirms it — or corrects
    // it, if the CLI disagreed. The user never waits on a bash spawn.
    private func act(_ args: [String]) {
        cliQueue.async { [weak self] in
            lich(args)
            let snap = fetchSnapshot()
            DispatchQueue.main.async { self?.apply(snap) }
        }
    }

    @objc func awakeToggled(_ sender: NSButton) {
        act([sender.state == .on ? "on" : "off"])
    }

    // The trip's off switch is `lich done` — which spares the standing
    // setting by contract — while the standing modes clear with `roam off`.
    @objc func tripToggled(_ sender: NSButton) {
        act(sender.state == .on ? ["roam"] : ["done"])
    }

    @objc func alwaysToggled(_ sender: NSButton) {
        act(sender.state == .on ? ["roam", "always"] : ["roam", "off"])
    }

    @objc func timerToggled(_ sender: NSButton) {
        act(sender.state == .on ? ["roam", "timer"] : ["roam", "off"])
    }

    @objc func loginToggled(_ sender: NSButton) {
        if sender.state == .on {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }

    func showMenu() {
        menuToggles.removeAll()
        statusLineItems.removeAll()
        let menu = NSMenu()

        // Status lines from the cached snapshot — repainted in place moments
        // later by the async refresh kicked below.
        for line in cache.statusLines {
            let item = menu.addItem(withTitle: line, action: nil, keyEquivalent: "")
            statusLineItems.append(item)
        }

        menu.addItem(.separator())
        // The tool itself — checked means risen, same state the icon shows.
        addToggle(to: menu, title: "Awake — lid closed, plugged in",
                  isOn: { $0.risen },
                  action: #selector(awakeToggled(_:)))

        // Roaming, in plain English — no lore in the labels, because the
        // thing being chosen is "don't sleep when I unplug". Durations are
        // deliberately not editable here: minutes live in `lich config`.
        menu.addItem(.separator())
        addToggle(to: menu, title: "Stay awake unplugged — this once",
                  isOn: { $0.roam.hasTrip },
                  action: #selector(tripToggled(_:)))
        addToggle(to: menu, title: "Stay awake unplugged — always",
                  isOn: { $0.roam.standing == .always },
                  action: #selector(alwaysToggled(_:)))
        addToggle(to: menu, title: "Stay awake unplugged — \(cache.mins) min each time",
                  isOn: { $0.roam.standing == .timer },
                  action: #selector(timerToggled(_:)))

        menu.addItem(.separator())
        addToggle(to: menu, title: "Start at Login",
                  isOn: { [weak self] _ in self?.loginItemEnabled ?? false },
                  action: #selector(loginToggled(_:)))
        let quitItem = menu.addItem(
            withTitle: "Quit Lich",
            action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp

        // Same width for every toggle row, so the menu doesn't ripple.
        let maxWidth = menuToggles.map { $0.button.frame.width + 28 }.max() ?? 0
        for item in menu.items where item.view != nil {
            item.view?.setFrameSize(NSSize(width: maxWidth,
                                           height: item.view?.frame.height ?? 0))
        }

        // Present NOW from cache, verify async — the whole point.
        refreshAsync()

        // Attach, click to pop it open, then detach on the next runloop turn.
        // The menu is rebuilt on every open, so it must not stay attached
        // between opens. Clearing it synchronously would cancel the menu we
        // just asked for; the async hop lands after it has been presented.
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
