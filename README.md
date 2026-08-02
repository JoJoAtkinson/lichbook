# lichbook 💀

**Your MacBook, undead.** Keep it awake with the lid closed — but **only**
while it's plugged in and you're logged in. Unplug it, log out, or lay it to
rest, and it sleeps like any mortal machine.

The power cord is the phylactery: while it feeds the machine, the lich stays
risen. Sever it and the body returns to rest. That's not flavor text — it's
the actual power contract, which is why you'll never cook the battery in a
bag.

Built for the age of agents: leave Claude Code, automations, or long jobs
running on a docked laptop, close the lid, and keep prompting.

## The rules it enforces

| Plugged in | Logged in | Risen | Lid closed → |
|------------|-----------|-------|--------------|
| ✅ | ✅ | ✅ | **stays awake** |
| ❌ | — | — | sleeps |
| — | ❌ | — | sleeps |
| — | — | ❌ | sleeps |

Unplugging while the lid is closed puts it to sleep within a second or two —
the watcher reacts to power events, it doesn't poll.

## Install

Homebrew:

```sh
brew tap jojoatkinson/lichbook https://github.com/JoJoAtkinson/lichbook
brew install lichbook
lich install      # one-time privileged setup; sudo prompts once
lich on           # 💀 risen
```

Upgrades: `brew upgrade lichbook && lich reload` (the watcher restarts onto
the new code; the LaunchAgent points at brew's stable `opt` path, so nothing
else needs touching).

Or from a clone:

```sh
./lich install    # sudo prompts once; see "What install does" below
lich on           # 💀 risen
```

Optional menu bar toggle (left-click toggles 💀/⚰️, right-click for status):

```sh
cd menubar && make install
open /Applications/Lich.app
# add it to System Settings → General → Login Items to start at login
```

Optional Control Center toggle (macOS 26+; requires full Xcode and
`brew install xcodegen`):

```sh
cd controlcenter && ./build.sh
# then: right-click Desktop → "Edit Widgets…" once (gallery-refresh quirk),
# Control Center → customize → add "Lich" — and optionally drag the
# control onto the menu bar.
```

## Use

```sh
lich on       # 💀 risen — survives lid close while on AC (persists across logins)
lich off      # ⚰️ at rest — normal sleep (persists across logins)
lich status   # risen state, power source, sleep setting, watcher health
lich          # bare command = status
```

The risen state is just a flag file, `~/.lich/desired-state` — the CLI, the
menu bar app, and the Control Center toggle all flip the same flag, and the
watcher applies it within ~5 seconds. Anything else that can write a file
(Shortcuts, ssh, cron) can control it the same way.

## How it works

One bash script (`lich`, ~200 lines — read it) plus one per-user
LaunchAgent:

- The agent runs `lich watch`, which streams macOS power-source events
  (`pmset -g pslog`), reads the risen flag, and flips the hidden
  `pmset disablesleep` setting: `1` when risen and on AC power, `0` otherwise.
  `disablesleep` is the only mechanism that blocks clamshell (lid-close)
  sleep — `caffeinate` cannot.
- **Logged-in condition is free:** per-user LaunchAgents only run while you're
  logged in. At logout launchd sends SIGTERM and the cleanup trap restores
  `disablesleep 0` before the process dies.
- A 5-second fallback reconcile catches anything the event stream misses, and
  `KeepAlive` restarts the watcher if it ever dies.

### What install does

1. Writes `/etc/sudoers.d/lichbook` — passwordless sudo scoped to **exactly
   two commands**: `pmset -a disablesleep 0` and `pmset -a disablesleep 1`
   (validated with `visudo -cf` before going live).
2. Symlinks `/usr/local/bin/lich` → this script.
3. Creates `~/.lich/desired-state` (starts at rest).
4. Writes and loads `~/Library/LaunchAgents/com.lichbook.watcher.plist`.

`./lich uninstall` removes all of it and restores normal sleep.

## Caveats

- While awake with the lid closed, the machine vents less well. Fine on a
  desk; don't leave it running in a bag or on a couch cushion.
- While `disablesleep` is `1` (i.e., risen **and** on AC), manual sleep
  (Apple menu → Sleep) is also blocked. `lich off` first if you want that.
- A hard kill (SIGKILL, kernel panic) skips the cleanup trap. The watcher
  re-reconciles at next login; worst case is one session of "won't sleep"
  after a crash, visible in `lich status`.
- The Control Center glyphs are power symbols, not a skull — Control Center
  only renders SF Symbols, and Apple ships no skull or coffin. The 💀/⚰️ live
  in the CLI and menu bar app.
- Log: `~/Library/Logs/lich.log`.

## Credits

Mechanism and hygiene borrowed from
[tmad4000/nosleep](https://github.com/tmad4000/nosleep) (scoped sudoers,
cleanup traps), [Moarram/wake](https://github.com/Moarram/wake) (minimal
`pmset` wrapping), and
[hizzt/mac-sleep-tool](https://github.com/hizzt/mac-sleep-tool)
(power-event-driven LaunchAgent — with its missing logout reset fixed here).

MIT licensed.
