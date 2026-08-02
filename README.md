# lichbook 💀

**Close your lid. Your prompts, agents, and remote sessions keep running.**
Only while it's plugged in and you're logged in — unplug it, log out, or lay
it to rest, and it sleeps like any mortal machine.

## Install

```sh
brew tap jojoatkinson/lichbook https://github.com/JoJoAtkinson/lichbook
brew install lichbook   # if brew asks: brew trust jojoatkinson/lichbook
lich install            # one-time privileged setup; sudo prompts once
lich on                 # 💀 risen
```

That's it. Close the lid on a docked Mac and Claude Code sessions, `claude
remote-control`, ssh sessions, and long jobs keep going.

## Use

```sh
lich          # status: risen or at rest, power source, sleep setting, watcher health
lich on       # 💀 risen — lid-close keeps the Mac awake while on AC
lich off      # ⚰️ at rest — normal sleep
```

Both states persist across logins. Upgrade with:

```sh
brew upgrade lichbook && lich reload
```

---

## The rules it enforces

| Plugged in | Logged in | Risen | Lid closed → |
|------------|-----------|-------|--------------|
| ✅ | ✅ | ✅ | **stays awake** |
| ❌ | — | — | sleeps |
| — | ❌ | — | sleeps |
| — | — | ❌ | sleeps |

The power cord is the phylactery: while it feeds the machine, the lich stays
risen. Sever it and the body returns to rest — within ~5 seconds, even with
the lid already closed. That's not flavor text, it's the actual power
contract, which is why you'll never cook the battery in a bag.

## How it works

One bash script (`lich`, ~330 lines, half of them comments — read it before
you grant it sudo) plus one per-user LaunchAgent,
`com.lichbook.watcher`:

- The agent runs `lich watch`, which every 5 seconds reads the risen flag and
  the power source and flips the hidden `pmset disablesleep` setting: `1` when
  risen **and** on AC power, `0` otherwise. `disablesleep` is the only
  mechanism that blocks clamshell (lid-close) sleep — `caffeinate` cannot.
  Plain polling is deliberate: `pmset -g pslog` doesn't stream reliably under
  launchd (it exits after its header), and an event stream that can die takes
  `disablesleep` down with it.
- **The logged-in condition is free.** Per-user LaunchAgents only run while
  you're logged in; at logout launchd sends SIGTERM and the cleanup trap
  restores `disablesleep 0` before the process dies.
- `KeepAlive` restarts the watcher if it ever dies, and the cleanup trap
  restores normal sleep on any exit.

The risen state is just a flag file, `~/.lich/desired-state`, containing `on`
or `off`. The CLI, the menu bar app, and the Control Center toggle all flip
the same flag; the watcher applies it within ~5 seconds. Anything else that
can write a file — Shortcuts, ssh, cron — controls it the same way.

### What install does

1. Writes `/etc/sudoers.d/lichbook` — passwordless sudo scoped to **exactly
   two commands**: `pmset -a disablesleep 0` and `pmset -a disablesleep 1`
   (validated with `visudo -cf` before going live).
2. Puts `lich` on your PATH by symlinking `/usr/local/bin/lich` — skipped when
   `lich` is already on PATH, as it is after `brew install`.
3. Creates `~/.lich/desired-state` (starts at rest).
4. Writes and loads `~/Library/LaunchAgents/com.lichbook.watcher.plist`. On a
   Homebrew install the agent points at brew's stable `opt` path, not the
   versioned Cellar path, so upgrades don't break it.

`lich uninstall` removes all of it and restores normal sleep (only the log at
`~/Library/Logs/lich.log` is left behind, as the audit trail).

Running from a clone works the same: `./lich install`, then `lich on`.

## Optional: menu bar app

Left-click toggles 💀 risen / ⚰️ at rest; right-click gives status lines, a
toggle, a "Start at Login" checkbox, and Quit. It shells out to the `lich`
CLI, so the CLI stays the single source of truth.

```sh
cd menubar && make install
open /Applications/Lich.app
```

It registers itself as a login item on first launch (SMAppService); uncheck
"Start at Login" in the right-click menu if you'd rather it didn't.

## Optional: Control Center toggle

macOS 26+. Requires full Xcode (not just Command Line Tools) and
`brew install xcodegen`.

```sh
cd controlcenter && ./build.sh
```

Then, first time only: right-click the Desktop → "Edit Widgets…" and close it
again (forces the control gallery to re-scan — known Tahoe quirk), then
Control Center → customize → add "Lich". Optionally drag the control onto the
menu bar.

The widget is sandboxed and can do exactly one thing: read and write
`~/.lich/desired-state`.

## Caveats

- While awake with the lid closed, the machine vents less well. Fine on a
  desk; don't leave it running in a bag or on a couch cushion.
- While `disablesleep` is `1` (risen **and** on AC), manual sleep
  (Apple menu → Sleep) is also blocked. `lich off` first if you want that.
- A hard kill (SIGKILL, kernel panic) skips the cleanup trap. The watcher
  re-reconciles at next login; worst case is one session of "won't sleep"
  after a crash, visible in `lich status`.
- Control Center shows power glyphs, not a skull — it only renders SF Symbols
  and Apple ships no skull or coffin. The 💀/⚰️ live in the CLI and menu bar.
- Log: `~/Library/Logs/lich.log`.

## Credits

Mechanism and hygiene borrowed from
[tmad4000/nosleep](https://github.com/tmad4000/nosleep) (scoped sudoers,
cleanup traps), [Moarram/wake](https://github.com/Moarram/wake) (minimal
`pmset` wrapping), and
[hizzt/mac-sleep-tool](https://github.com/hizzt/mac-sleep-tool)
(power-event-driven LaunchAgent — with its missing logout reset fixed here).

MIT licensed.
