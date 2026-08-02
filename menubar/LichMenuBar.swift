// LichMenuBar — a menu bar toggle for the `lich` CLI.
//
// Left-click the icon: toggle risen (💀) / at rest (⚰️).
// Right-click (or option-click): status details + Quit.
//
// This app holds no logic of its own — every action shells out to
// /usr/local/bin/lich, so the CLI stays the single source of truth.

import AppKit

let cliPath = ["/opt/homebrew/bin/lich", "/usr/local/bin/lich"]
    .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/local/bin/lich"

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

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var refreshTimer: Timer?

    var risen: Bool { lich(["status", "--quiet"]).status == 0 }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        refresh()
        // Keep the icon honest if the CLI is used directly in a terminal.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        statusItem.button?.title = risen ? "💀" : "⚰️"
        statusItem.button?.toolTip = risen
            ? "lich: risen — stays awake with lid closed while on AC"
            : "lich: at rest — normal sleep"
    }

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

    func showMenu() {
        let menu = NSMenu()
        let status = lich(["status"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        for line in status.split(separator: "\n") {
            menu.addItem(withTitle: String(line), action: nil, keyEquivalent: "")
        }
        menu.addItem(.separator())
        let toggleItem = menu.addItem(
            withTitle: risen ? "Lay to rest (off)" : "Raise the lich (on)",
            action: #selector(toggle), keyEquivalent: "")
        toggleItem.target = self
        let quitItem = menu.addItem(
            withTitle: "Quit Lich",
            action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        DispatchQueue.main.async { self.statusItem.menu = nil }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
