# lichbook 💀

[![Release](https://img.shields.io/github/v/release/JoJoAtkinson/lichbook?color=6e40c9)](https://github.com/JoJoAtkinson/lichbook/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B%20Tahoe-black)
![Install](https://img.shields.io/badge/install-homebrew-orange)

**Close your lid. Your prompts, agents, and remote sessions keep running.**
Only while it's plugged in and you're logged in — unplug it, log out, or lay
it to rest, and it sleeps like any mortal machine. (Need it awake off the
cord for a while? That's [roaming](#roaming-staying-awake-on-battery), and
it has a battery floor.)

## Install

```sh
brew tap jojoatkinson/lichbook https://github.com/JoJoAtkinson/lichbook
brew trust jojoatkinson/lichbook   # third-party taps need explicit trust
brew install lichbook              # builds the menu bar app on your machine
lich install                       # one-time privileged setup; sudo prompts once
lich on                            # 💀 risen
```

That's it. Close the lid on a docked Mac and Claude Code sessions, `claude
remote-control`, ssh sessions, and long jobs keep going.

## Use

```sh
lich          # status: risen or at rest, power source, sleep setting,
              #         watcher health, roam mode, battery vs. floor
lich on       # 💀 risen — lid-close keeps the Mac awake while on AC
lich off      # ⚰️ at rest — normal sleep
```

Both states persist across logins. Updating is one word — it detects whether
you installed via brew or a clone, updates accordingly, refreshes the menu
bar app, and reloads the watcher:

```sh
lich upgrade
```

## What happens when… (the everyday cases)

No sleep/wake theory required — while the lich is risen 💀:

| You… | Your Mac… |
|------|-----------|
| leave it plugged in, lid closed | stays awake indefinitely — Claude sessions, ssh, automations all keep running, screen locked behind the closed lid |
| finish up, close the lid, walk it over to the charger | wakes within seconds of the cord going in and *stays* awake — hours later, ask it something from your phone and it answers. The plug is the on-switch; the lid never needs to open |
| use it plugged in, lid open | never dozes off mid-task — idle sleep is off while risen |
| lock the screen (Ctrl+Cmd+Q, or just close the lid) | keeps working behind the password screen — **locked and asleep are different things**; your session and its work continue |
| unplug it | goes back to being a normal laptop: sleeps shortly after you stop using it (unless you asked it to [roam](#roaming-staying-awake-on-battery)) |
| log out, or run `lich off` | fully mortal — sleeps like lich was never installed |

All of these are field-tested. Every state beyond them — crashes, battery
floors, multiple users, the works — lives in the full
[state table](docs/STATE-TABLE.md).

## Roaming: staying awake on battery

Sometimes the work has to leave the desk — an agent mid-run you carry to the
couch, a build you'd rather not babysit next to an outlet. **Roaming is the
lich risen without its phylactery**: awake on battery, deliberately, with a
floor that ends it before your battery pays for it.

Roaming has two layers, so a one-off never costs you your default:

- **Standing settings** persist until you change them: `always` (unplugged
  never means sleep) or `timer` (**every** unplug gets `roam_mins` of grace —
  30 min out of the box — then sleep; the next unplug gets a fresh window).
- **Trips** are temporary overlays: `roam` (until you next plug in) or
  `roam 45` (a bounded window). When a trip is spent or expires, it
  evaporates — and your standing setting is simply back, untouched.

```sh
lich roam           # TRIP: stay awake unplugged until you plug back in
lich roam 45        # TRIP: for 45 minutes (45m works too)
lich roam always    # STANDING: every unplug, from now on
lich roam timer     # STANDING: roam_mins of grace at every unplug, forever
lich roam off       # clear the standing setting (and any trip)
lich roam status    # machine-readable: "<standing> <trip>", e.g. "timer -",
                    # "off once", "timer until:<epoch>"
```

Every arming form also raises the lich, so one command is enough from a cold
start.

| You run | Lasts | Your standing setting |
|---------|-------|----------------------|
| `roam` / `roam 45` | this trip / this window | **kept** — returns when the trip ends |
| `roam always` | until `roam off` | *is* the setting |
| `roam timer` | 30 min per unplug, every unplug | *is* the setting |

`lich roam status` is what the menu bar app parses — one bare line, no
decoration. `lich status` says the same thing in English, plus the battery
line described below.

### The battery floor

**Below the floor — 20% by default — roaming stops. No exceptions, no
override flag.** Not even `always` outranks it; that's the whole point of
having it, and a machine that will run itself flat in a bag is a worse tool
than one that sleeps.

- A `once` or timed roam that hits the floor is **canceled** — the setting
  goes back to `off` and the log says why. Plug in, and re-arm it if you
  still want it.
- `always` is **suspended**, not cleared: your standing preference survives
  the low battery and takes effect again once you're back above the floor.

The floor is checked every tick, alongside everything else, so a roam ends
within ~5 seconds of crossing it — lid open or closed.

### Config

```sh
lich config                 # print the effective config, defaults included
lich config floor 15        # battery floor, percent (5–95)
lich config roam_mins 45    # what `lich roam timer` means, minutes (1–1440)
```

Values live in `~/.lich/config` as plain `key=value` lines. No file, or a
missing key, means the default (`floor=20`, `roam_mins=30`); anything else in
there is ignored.

### For AI agents

If you're an agent — or you're writing the prompt for one — and you were told
to keep this Mac awake, hand the machine back when you're done:

```sh
lich done
```

That clears a **trip** (a `once` or bounded roam) so an unplugged Mac is
free to sleep again. It deliberately does **not** touch the standing setting
(`always` or `timer` — the owner's preference, not yours to spend) and does
**not** lay the lich to rest — `lich off` stays a human decision.

---

## The rules it enforces

| Plugged in | Logged in | Risen | Lid closed → |
|------------|-----------|-------|--------------|
| ✅ | ✅ | ✅ | **stays awake** |
| ❌ | — | — | sleeps — *unless roaming* ⁺ |
| — | ❌ | — | sleeps |
| — | — | ❌ | sleeps |

⁺ Roaming is the one exception to the battery row, and only when you asked
for it: risen **and** a roam armed **and** the battery above the floor. See
[Roaming](#roaming-staying-awake-on-battery). Logged out and at rest have no
exceptions at all.

The power cord is the phylactery: while it feeds the machine, the lich stays
risen. Sever it and the body returns to rest — within ~5 seconds, even with
the lid already closed. That's not flavor text, it's the actual power
contract, which is why you'll never cook the battery in a bag; roaming
borrows against it on purpose, for a bounded time, and the floor calls the
loan.

## How it works

One bash script (`lich`, a few hundred lines, half of them comments — read it
before you grant it sudo) plus one per-user LaunchAgent,
`com.lichbook.watcher`:

- The watcher runs `lich watch`, which every 5 seconds reads the risen flag and
  the power source and flips the hidden `pmset disablesleep` setting: `1` when
  risen **and** (on AC power **or** roaming), `0` otherwise. The same tick
  reads the battery percentage, so an expired timer, a spent one-shot, or a
  floor breach ends a roam within ~5 seconds. `disablesleep` is the only
  mechanism that blocks clamshell (lid-close) sleep — `caffeinate` cannot.
  Plain polling is deliberate: `pmset -g pslog` doesn't stream reliably under
  launchd (it exits after its header), and an event stream that can die takes
  `disablesleep` down with it.
- **The logged-in condition is free.** Per-user LaunchAgents only run while
  you're logged in; at logout launchd sends SIGTERM and the cleanup trap
  restores `disablesleep 0` before the process dies.
- `KeepAlive` restarts the watcher if it ever dies, and the cleanup trap
  restores normal sleep on any exit.
- **Lid close locks the screen.** Normally the lock rides along with sleep;
  since lich prevents the sleep, macOS never locks. The watcher detects the
  lid closing while risen, locks the console itself, and then **verifies** the
  lock took (`IOConsoleLocked`), warning in the log if it didn't. The lock
  rides on your Lock Screen setting — keep "Require password after screen
  saver begins or display is turned off" at **Immediately** (System Settings →
  Lock Screen) or an opened lid can land on your desktop.

The risen state is just a flag file, `~/.lich/desired-state`, containing `on`
or `off`. The CLI, the menu bar app, and the Control Center toggle all flip
the same flag; the watcher applies it within ~5 seconds. Anything else that
can write a file — Shortcuts, ssh, cron — controls it the same way. Roaming
is the same idea: `~/.lich/roam` holds `off`, `once`, `always`, or
`until <epoch>`, and `~/.lich/config` holds the `floor` and `roam_mins`
settings. The watcher owns those files too — it's what clears a spent
one-shot, an expired timer, or a roam that hit the floor.

### What install does

1. Writes `/etc/sudoers.d/lichbook-<you>` — passwordless sudo scoped to
   **exactly two commands**: `pmset -a disablesleep 0` and
   `pmset -a disablesleep 1` (validated with `visudo -cf` before going
   live). Per-user filename, so multiple users' installs never clobber each
   other's rule. (This must live in root-owned `/etc/sudoers.d/`, not in
   `~/.lich` — a root grant in a user-writable folder would be a privilege
   escalation. Everything *else* lich remembers lives per-user in `~/.lich/`.)
2. Puts `lich` on your PATH by symlinking `/usr/local/bin/lich` — skipped when
   `lich` is already on PATH, as it is after `brew install`.
3. Creates `~/.lich/desired-state` (starts at rest).
4. Writes and loads `~/Library/LaunchAgents/com.lichbook.watcher.plist`. On a
   Homebrew install the watcher points at brew's stable `opt` path, not the
   versioned Cellar path, so upgrades don't break it.

`lich uninstall` removes all of it and restores normal sleep (only the log at
`~/Library/Logs/lich.log` is left behind, as the audit trail).

Running from a clone works the same: `./lich install`, then `lich on`.

## Menu bar app

Installed for you: the brew formula builds `Lich.app` on your machine during
`brew install` (ad-hoc signing only trusts locally-built code — this is why
there's no prebuilt download), and `lich install` copies it to /Applications
and launches it. From a clone, `make -C menubar` first, then `lich install`
picks it up the same way. If the build isn't there, install just says so and
everything else works — the app is optional.

**Prefer CLI only?** `lich install --no-app` skips the menu bar app — and
the choice is persisted, so `lich upgrade` never resurrects an interface
you declined. Change your mind later with `lich config no_app 0` and re-run
`lich install`.

The icon is a status light — 💀 risen, ⚰️ at rest — and any click opens the
menu: live status lines, then checkboxes for **Awake** (the tool itself),
the three roaming modes, and **Start at Login**, plus Quit. Numbers like the
battery floor and timer minutes stay in `lich config`; the menu just
reflects them. It shells out to the `lich` CLI, so the CLI stays the single
source of truth.

The roaming checkboxes, in plain English:

- **Stay awake unplugged — this once** — a trip; unticking it (or plugging
  back in) returns you to your standing setting below
- **Stay awake unplugged — always** — standing setting
- **Stay awake unplugged — N min each time** — standing setting: every
  unplug gets N minutes of grace (N is your configured `roam_mins`, read
  live, so the label shows the real number)

The two standing settings are mutually exclusive; the trip rides on top of
either. Durations are set with `lich config roam_mins` and nowhere else —
the menu stays a switch, not a settings panel. The battery floor applies
here exactly as it does from the CLI.

It registers itself as a login item on first launch (SMAppService); uncheck
"Start at Login" in its menu if you'd rather it didn't.

## Optional: Control Center toggle

macOS 26+, and the one piece with a heavyweight toolchain: **full Xcode**
(Command Line Tools are not enough) plus `brew install xcodegen`. It is never
installed unasked:

```sh
lich widget          # builds on your machine, installs, launches
lich widget remove   # takes it back out
```

Without the toolchain, `lich widget` warns you exactly what's missing and
does nothing. (From a clone, `controlcenter/build.sh` is the same build by
hand.)

Then, first time only: right-click the Desktop → "Edit Widgets…" and close it
again (forces the control gallery to re-scan — known Tahoe quirk), then
Control Center → customize → add "Lich". Optionally drag the control onto the
menu bar.

The widget is sandboxed and can do exactly one thing: read and write
`~/.lich/desired-state`. Roaming is not in the widget — use the CLI or the
menu bar app for that.

## Caveats

- While awake with the lid closed, the machine vents less well. Fine on a
  desk; don't leave it running in a bag or on a couch cushion. Roaming makes
  that easier to do by accident — the battery floor is a floor, not a
  thermostat.
- While `disablesleep` is `1` (risen **and** on AC or roaming), manual sleep
  (Apple menu → Sleep) is also blocked. `lich off` first if you want that.
- **`disablesleep` survives reboots** — it lives in
  `/Library/Preferences/com.apple.PowerManagement.plist` and powerd re-applies
  it at boot (measured, not assumed). So a crash, kernel panic, or hard reboot
  while risen leaves the Mac sleep-proof **at the login window**, where no
  watcher runs to fix it — during that window it won't sleep even on battery,
  lid open or closed. The first login repairs it within ~5 seconds. If a
  crashed machine has to sit unattended, log in once (or run
  `sudo pmset -a disablesleep 0`) before walking away.
- Control Center shows power glyphs, not a skull — it only renders SF Symbols
  and Apple ships no skull or coffin. The 💀/⚰️ live in the CLI and menu bar.
- Log: `~/Library/Logs/lich.log`.

## Support policy

Tested and supported on the **latest macOS only** (currently macOS 26,
"Tahoe" — the version this was built and verified on). Earlier versions:
you're welcome to install it — `lich install` fails open, meaning every piece
tries, warns if it can't, and the CLI keeps working with whatever succeeded —
but it's untested there, only loosely supported, and gets no version checks,
no gates, and no promises.

The formal behavior reference — every configuration worth naming, what the
code verifiably does about it, and what is merely promised — lives in
[docs/STATE-TABLE.md](docs/STATE-TABLE.md).

## Credits

All code here is original; these projects inspired the approach —
[tmad4000/nosleep](https://github.com/tmad4000/nosleep) (scoped sudoers,
cleanup traps), [Moarram/wake](https://github.com/Moarram/wake) (minimal
`pmset` wrapping), and
[hizzt/mac-sleep-tool](https://github.com/hizzt/mac-sleep-tool)
(power-event-driven LaunchAgent — with its missing logout reset fixed here).

MIT licensed.
