# lichbook state table

**v0.2.0.** What lichbook does in every configuration worth naming, what
the code actually does about it today, and what is promised. (§1–§13 were
written against v0.1.4 and their `lich:NN` line references predate the roam
feature; the facts they record still hold. §14–§15 are v0.2.0.)

This is written from the code, not from the README. Where the code and the
README disagree, the disagreement is called out. Where the code cannot answer
the question — because the answer lives in launchd, in macOS, or in a machine
nobody has tested on — the row says **Unknown** rather than guessing.

Line references are to `lich` at v0.1.4 (`lich:NN`). This revision merges a
research pass dated 2026-08-02 (power / sessions / launchd); everything it
settled is folded into the rows below, and everything it left open is either an
**Unknown** row or a question in §13.

---

## 0. How to read this

### The one-sentence policy

`disablesleep` is `1` — and lid-close therefore does not sleep the Mac — **only
when** the risen flag reads exactly `on` **and** the machine is on AC power
**and** a per-user `lich watch` LaunchAgent is alive to say so. Everything below
is a consequence of that sentence or a way it can fail.

Two properties of `disablesleep` do most of the damage in this document, and
both were measured rather than assumed:

- **It is a single system-wide boolean.** It prints under *System-wide power
  settings* in `pmset -g` and does **not** appear in `pmset -g custom`
  (observed). `pmset -a` is therefore cosmetic for this key: macOS has no notion
  of "disable sleep only on AC". The entire AC condition in the README's rules
  table is lich's 5-second poll and nothing else.
- **It persists across reboots.** It is stored as
  `SystemPowerSettings => { SleepDisabled => true }` in
  `/Library/Preferences/com.apple.PowerManagement.plist` (observed; note this is
  *not* the `SystemConfiguration/` subpath older write-ups cite — that file does
  not exist on Tahoe) and powerd applies it at boot. See §2.

### Column meanings

| Column | Meaning |
|---|---|
| **Configuration** | A named, meaningful state — not a cross-product row. |
| **Expected behavior** | Awake or asleep, locked or not, and what the user sees. |
| **Code handles it?** | Verified by reading v0.1.4. See values below. |
| **Support** | The promise, per the project's support policy. |

**"Code handles it?" values**

- **Yes** — there is code that deliberately covers this case; cited.
- **Partial** — covered, but with a gap in reporting, timing, or messaging.
- **No** — the code does not consider this case at all.
- **Unknown** — the code's behavior here depends on launchd/macOS semantics
  that reading the script cannot settle. Needs an experiment.
- **N/A** — the outcome is not lich's code to handle (physics, another
  subsystem, a different mechanism entirely). Listed because users will still
  attribute it to lichbook.

**"Support" values** — these four and no others.

- **Tested** — exercised on macOS 26 on the maintainer's machine.
  ⚠️ *Every "Tested" in this document is inferred from README claims and commit
  messages; the maintainer must confirm the real list (see **Q11**).*
- **Should-work** — mechanism is sound and the code path is deliberate, but
  nobody has run it.
- **Untested** — plausible, unexercised, no promise.
- **Known-gap** — the code does the wrong or incomplete thing here, and we know.

### Evidence markers used inside cells

- *(code)* — read from the v0.1.4 source.
- *(observed)* — a read-only measurement taken on the maintainer's Mac
  (macOS 26.5.2, build 25F84, 2026-08-02). **An observation of current state is
  not an exercised test** and never promotes a row to Tested.
- *(source)* — external documentation or reporting; cited in §14.
- *(unverified)* — looked for, nothing authoritative found.

### Dimensions enumerated

Power source · lid · risen flag (`on` / `off` / missing / malformed / racing
writer) · watcher (running / not loaded / disabled in System Settings /
crash-looping / SIGKILLed) · console session (console / login window /
fast-user-switched / ssh-only / Screen Sharing / Guest) · boot path (graceful
logout / graceful restart / forced or auto-update restart / panic / thermal
shutdown) · lock setting (immediate / delayed / off) · install completeness
(brew / clone / sudoers missing / stale pre-rename install / symlink missing /
stale plist path) · optional components (CLI / +menu bar / +Control Center) ·
login-item permission (launchd disable vs. BTM) · user privilege (admin /
standard) · macOS version (26 tested, earlier fail-open) · multi-user (second
user agreeing / disagreeing / installing / uninstalling) · thermal envelope
(fanless Air / fan-equipped Pro / bag) · battery policy (permanent AC).

They are grouped into sections below; a full cross-product would be ~10^7 rows
and would say nothing.

**Coverage: 141 configuration rows across 11 sections** — core power contract 20,
boot/login-window 9, session/login 15, lid-close locking 15, watcher lifecycle
17, install completeness 16, privilege 9, optional components 13, macOS version
9, multi-user 12, thermal/battery 6 — **plus 13 code fragilities (§12), 12 open
questions (§13) and 23 macOS quirks (§14).**

---

## 1. The core power contract

Assumes: single admin user, full install, watcher alive, macOS 26. Everything
else in this document is a deviation from this table.

| Configuration | Expected behavior | Code handles it? | Support |
|---|---|---|---|
| risen, AC, lid open | Never sleeps. Display may still sleep. `lich` shows `sleep: disabled` *(observed: `pmset -g` reports `SleepDisabled 1` under "System-wide power settings")* | Yes — `reconcile` sets `disablesleep 1` (lich:92-104) | Tested |
| risen, AC, lid closed | Stays awake; console locked once, on the closing transition — subject to §4 | Yes — lich:133-140 | Tested |
| risen, battery, lid open | Normal sleep. Status prints the "on battery — the lich rests" note | Yes — `want=0` (lich:94), note at lich:196-198 | Tested |
| risen, battery, lid closed | Sleeps like a normal Mac. lich does **not** lock — the lock rides along with macOS's own sleep | Yes — lock path is gated on `sleep_disabled == 1` (lich:133) | Tested |
| at rest, AC, lid open | Normal in every way | Yes | Tested |
| at rest, AC, lid closed | Sleeps | Yes | Tested |
| at rest, battery, either lid | Sleeps | Yes | Tested |
| Flag file missing entirely | Reads as at rest → normal sleep. Safe default | Yes — `risen()` swallows the read error (lich:65) | Tested |
| Flag contains `off`, empty, `ON`, or junk | At rest. Only the exact string `on` counts | Yes — exact `==` compare (lich:65) | Should-work |
| Flag contains `on` with a leading space (external writer) | **CLI reads at rest; Control Center widget reads risen** — `$(cat)` strips trailing whitespace only, the widget trims both ends (LichWidgets.swift:41) | Partial — two readers, two parsers | Known-gap (cosmetic; UI disagrees with reality) |
| Unplug while risen, lid closed, **watcher alive** | Within ≤5s `disablesleep` → 0, machine sleeps. Already locked from the lid-close | Yes — polling loop, lich:131-142 | Tested |
| Unplug while risen, lid closed, **watcher dead or never installed** | Nothing happens. `disablesleep` stays 1 on battery, because the setting is system-wide and macOS has no AC-only variant *(observed)*. The Mac stays awake in the bag until someone logs in or runs `lich off` | **No** — the AC rule exists only inside the watcher loop | Known-gap → **Q1** |
| Battery reaches critical charge with a stale `disablesleep 1` and no watcher | Unknown whether macOS's emergency low-battery sleep/hibernate is itself gated by `SleepDisabled` or overrides it *(unverified — no authoritative source)*. If gated: the Mac runs to a hard cut-off instead of hibernating (data loss). If it overrides: heat plus a flat battery | **Unknown** | Untested — **highest-value bench test in this document** (see §14, row 3) |
| Plug in while risen, lid closed, machine asleep | Wakes enough for the watcher to tick, re-arms, and stays awake | Yes — field-verified | **Tested** 2026-08-02: cord attached (by a third party, lid closed, machine idle-dark after an unplug release) → log shows `power=AC -> disablesleep=1` at 17:10:49, seconds after attach, and the machine then served a remote session lid-closed for 25+ min. *(Caveat: full-sleep depth at the attach moment wasn't independently confirmed; the tick-on-attach and stay-awake outcome were.)* |
| Apple menu → Sleep while risen + AC | Blocked. Documented caveat; `lich off` first | Yes — inherent to `disablesleep` | Tested |
| `pmset sleepnow` while risen + AC | Almost certainly blocked, same mechanism | Unknown (not exercised) | Untested |
| Sleep + DarkWake continuity: machine sleeps on battery with periodic maintenance DarkWakes | The watcher stays silent through the whole sleep (no ticks, no `disablesleep` flapping, no log lines), DarkWakes change nothing, and the first real wake resumes correct behavior immediately | Yes — field-verified twice | **Tested** twice: (a) 2026-08-02, ~3h sleep (17:48–20:38, 5 DarkWake blips); (b) 2026-08-02→03 **overnight**: asleep within **39 seconds** of session idle (last beat 20:51:21), ~13h with 10 isolated blips including one 3-hour silent stretch, zero lich log entries, battery **100% → 100%** |
| Sleep onset latency after the last wake-holder releases (battery, lid closed, roam off) | Sleeps as soon as the last assertion lapses — lich adds zero delay since it released `disablesleep` at unplug time | Yes | **Tested** 2026-08-02: lid closed 20:50:42, final heartbeat 20:51:21 — under a minute |
| Remote session (claude remote-control) reaches a Mac asleep on battery | The incoming message wakes the machine over the network, the session is served (lid still closed, on battery), and it returns to sleep when the session goes idle — sleep is interruptible, not a disconnection | N/A — macOS network-wake + session infrastructure, not lich's code; lich correctly stays released throughout | **Tested** twice (2026-08-02 20:38, 2026-08-03 10:05): both wakes served full working sessions from a phone against a battery-sleeping, lid-closed Mac |
| Flag flipped by any writer (CLI / menu bar / widget / ssh / Shortcuts) | Takes effect within ≤5s; `lich on\|off` additionally applies immediately | Yes — lich:150-169 | Tested |
| Flag rewritten non-atomically by `lich on` exactly as the watcher reads it | One tick could read an empty file → at rest → a transient `disablesleep 0`. If the lid is closed at that instant the Mac could sleep. Next tick corrects | Partial — widget writes atomically (LichWidgets.swift:58), the CLI's `echo on >` does not | Known-gap (very narrow race) |
| Live `SleepDisabled` changed to 0 by something that is not lich | Next tick notices the divergence and restores it; ≤5s exposure. **Observed once** on this machine: a reconcile log line at 11:56:38 with no watcher restart bracketing it and a matching plist mtime, i.e. the value had been cleared by something else between 11:41 and 11:56. Cause unattributed — a unified-log query returned nothing *(unverified)* | Yes — this is exactly what idempotent polling buys (lich:92-104, 120-124). A set-once design would have silently lost the setting | Untested (cause unknown; reproduce before drawing conclusions) |
| Another app holds `caffeinate`-style IOPMAssertions at the same time | Coexists. `sleep_disabled()` reads the `SleepDisabled` line, not assertions, so it is not confused by them *(observed: two unrelated `caffeinate` assertions alongside `SleepDisabled 1`)* | Yes — different mechanism (lich:69-73) | **Tested** 2026-08-02: a remote session's `caffeinate` assertions ran alongside lich all day with no interference in either direction — and when the session went idle on battery (lich released, `disablesleep 0`), the assertions lapsed and the Mac slept within ~1 min (heartbeat log) |

---

## 2. Boot, restart, and the unattended login window

**This section is new, and it is the sharpest gap in the product.**

`disablesleep` survives a reboot (see §0). Per-user LaunchAgents do not exist
before login. Therefore any exit path that skips the cleanup trap (lich:106-114)
leaves the Mac sleep-disabled *at the login window, with nothing running that
could fix it, for an unbounded time*.

Two consequences worth stating plainly:

- The code comment at **lich:67-68** offers "a reboot" as one of the reasons live
  state may differ from what lich last asked for. A reboot does not clear this
  setting; that comment is wrong.
- **README:47** ("which is why you'll never cook the battery in a bag") does not
  hold in this window, because `disablesleep` is system-wide and applies on
  battery too. **README:132-134** describes the crash case as "worst case is one
  session of 'won't sleep' after a crash, visible in `lich status`" — but the
  risky interval is *before* login, when `lich status` is not reachable.

| Configuration | Expected behavior | Code handles it? | Support |
|---|---|---|---|
| Graceful logout, restart, or shutdown while risen | launchd boots out the GUI domain → SIGTERM → trap restores `disablesleep 0`, and *that* 0 is what persists to the next boot | Yes — the central guarantee (lich:106-114) | Should-work |
| macOS **automatic update** restart, or an MDM/`shutdown`-driven restart, while risen | Unknown whether those paths grant LaunchAgents a full SIGTERM window; community reporting suggests some restart paths bypass graceful agent teardown *(unverified)*. If they do, the machine boots sleep-disabled. Note this is a **likely** event for lichbook users: risen machines are awake overnight precisely so updates can install | **Unknown** | Untested — the result decides how urgent **Q1** is |
| Kernel panic, hard power-off, or a SIGKILL that takes the session with it, while risen | Trap never runs. `SleepDisabled` stays `true` on disk through the reboot | **No** — nothing resets it at boot | Known-gap → **Q1** |
| Thermal shutdown while risen | Same as a panic: a hard stop that skips the trap. "Never sleeps" is not "never stops" (§11) | **No** | Known-gap → **Q1** |
| At the FileVault/login window after such a boot, **on AC** | Machine will not sleep. Closing the lid does nothing. No per-user agent exists yet, so nothing reconciles | **No** | Known-gap → **Q1** |
| At the login window after such a boot, **on battery** | Also will not sleep — one system-wide boolean, no per-power-source variant *(observed)*. Close the lid, put it in a bag, and it stays awake and warm on battery | **No** | Known-gap → **Q1/Q2** |
| Same, and nobody logs in (unattended / headless / overnight after an auto-update reboot) | The window is unbounded — it lasts until a login | **No** | Known-gap → **Q1** |
| First login after such a boot | Agent starts, `reconcile` compares live to desired and corrects within ~5s (immediately to `0` if the flag reads at rest) | Yes — lich:92-104, 131-132 | Should-work |
| `lich status` during the window | Unreachable: no session, no shell for that user, and the CLI is not what runs at the login window. The README's "visible in `lich status`" reassurance does not apply to the dangerous interval | **No** | Known-gap → **Q2** |

---

## 3. Console session and login state

The "only while logged in" guarantee lives entirely in the fact that the
watcher is a **per-user LaunchAgent** plus the `EXIT/INT/TERM` trap (lich:106-117).
Boot and crash paths moved to §2.

The research settled the load-bearing question here: **fast user switching does
not stop a switched-out user's agents.** Apple: *"Processes in a switched-out
login session continue running as before."* So "logged in" in the README's rules
table really means "has a login session", not "is at the console" — and a
grep across `lich`, `menubar/`, `controlcenter/` and the README confirms there
is **zero console-ownership detection anywhere in the repo** (no `/dev/console`,
no `kCGSSessionOnConsoleKey`, no `IOConsoleUsers`).

| Configuration | Expected behavior | Code handles it? | Support |
|---|---|---|---|
| Normal console login | Agent runs at login (`RunAtLoad`), full behavior | Yes — lich:270 | Tested |
| Log out to login window while risen | launchd SIGTERMs the watcher → trap restores `disablesleep 0` → Mac sleeps normally | Yes — the central guarantee (lich:106-114) | Tested |
| Log out **while the lid is already closed** and risen | Same: trap fires, sleep restored, Mac sleeps | Yes | Should-work |
| Screen locked (Ctrl-Cmd-Q) while risen | Session still logged in → watcher alive → stays awake. Correct, and the headline feature. *(observed: a session can report `kCGSSessionOnConsoleKey: true` and `CGSSessionScreenIsLocked: true` simultaneously — locked and on-console are independent, and lich consults neither)* | Yes | Should-work |
| Fast-user-switch away (user A risen, stays logged in; B is at the front) | A's agent keeps running, so the machine stays awake while B uses it. Settled, not speculative *(source: Apple FUS documentation)*. The README's "only while you're logged in" framing does not cover "logged in but switched away" | **No** — no notion of who owns the console | Known-gap → **Q4** |
| All users switched out — FUS login window — while a risen session exists | Machine sits at a password prompt, lid closed, pinned awake, with no indication to anyone. README's `\| — \| ❌ \| — \| sleeps \|` row overstates the guarantee | **No** | Known-gap → **Q4** |
| ssh in, user also has a live GUI session | Everything works: `lich on/off/status`, agent already loaded | Yes | Should-work |
| ssh only, user never logged in at the console | `gui/$UID` only exists while that user has an Aqua session; SSH gets `user/$UID` *(observed: `launchctl print gui/501/com.lichbook.watcher` resolves, `user/501/...` does not)*. `bootstrap` fails, `kickstart -k` fails, both are `\|\| true` → **install still prints "Installed."** This is the fail-open policy's "warns on what fails" half being violated outright | Partial — `lich status` does say `watcher: NOT running`, and the advice it gives is to re-run the command that just silently failed | Known-gap → **Q7** |
| ssh `lich on` with sudoers installed but no watcher | `disablesleep` is set to 1 immediately by `cmd_on`'s own reconcile, and **nothing will ever set it back** — not unplug, not ssh logout, not a reboot (§2) | Partial — prints `warning: watcher not running` to stderr (lich:159) and nothing more | Known-gap |
| Screen Sharing into an already-active session (same user) | Identical to sitting at the machine. This is the flagship path, and `disablesleep` is the documented, widely-used fix for keeping a lid-closed MacBook reachable *(source)* | Yes | Should-work |
| Screen Sharing **as a different user** | Creates a second Aqua session with its own LaunchAgents — the realistic real-world route into the multi-user flip-flop of §10, far more likely than deliberate fast user switching | **No** | Known-gap → **Q4** |
| Screen Sharing, user deliberately unlocks with the lid still down | Watcher does **not** re-lock — `LID_WAS_CLOSED` latches for the duration of the closure | Yes — deliberate, lich:129/134-137 | Should-work |
| ...and then the watcher restarts (`lich reload`, KeepAlive respawn) | `LID_WAS_CLOSED` resets to 0 → the console is locked again out from under the remote user | **No** — the latch is process-local | Known-gap (minor) |
| Screen Sharing to the **login window** (virtual display session) | A virtual session may create a `gui/$UID` domain and start the watcher. Tahoe reportedly behaves differently when the target is at a login prompt rather than a live session *(unverified — conflicting reports)*. Note lich locks the console on every lid close, so the first connect after a lid close always faces authentication | **Unknown** | Untested |
| Guest account | `lich install` aborts cleanly at `visudo -cf` (Guest cannot be admin) — no half state. Beyond that the Guest home is discarded at logout, so the flag, plist and log would vanish anyway; under FileVault the Guest account is Safari-only with no Terminal *(unverified — general macOS behavior, no authoritative source found)* | Yes, incidentally — validation runs before anything is written (lich:237) | Untested (effectively unsupported, for stated reasons) |

---

## 4. Lid-close locking vs. the system lock setting

The lock is not lich's own password prompt: `lock_console()` just runs
`open -a ScreenSaverEngine` (lich:84) and lets **System Settings → Lock Screen →
"Require password after screen saver begins or display is turned off"** decide
whether that means locked. That setting is load-bearing and lich never reads it.

Three things make this the one place where lichbook makes a **security** promise
it cannot keep:

1. When the setting is a delay or Never, starting the screensaver locks nothing —
   and because lich is holding the machine awake, macOS never performs the
   sleep that would normally have locked it. **lich actively removes a lock the
   user would otherwise have had.**
2. The watcher checks `console_locked` only *before* firing (lich:135), never
   after, and `LID_WAS_CLOSED=1` latches regardless — so a failed lock is never
   noticed and never retried.
3. `lock_console` is `|| true`, and the log line "lid closed while risen —
   screen locked" is printed unconditionally. **The log asserts a security
   property the code never verified.**

A probe exists and lich does not use it: `sysadminctl -screenLock status`
*(observed on this machine: "screenLock delay is immediate" — which is why the
mechanism appears to work here; that measures one machine's setting, not a
property of macOS)*. The user domain is no help: `defaults read
com.apple.screensaver` returns only `tokenRemovalAction`, with no
`askForPassword`/`askForPasswordDelay` key set at all *(observed)*.

| Configuration | Expected behavior | Code handles it? | Support |
|---|---|---|---|
| Require password **Immediately**, lid closes while risen | Screensaver starts, console locks; reopening the lid lands on the password screen | Yes — README says `IOConsoleLocked` was measured | Tested *(on a machine that reports "immediate" — observed; the row is about that configuration, not about the default)* |
| Require password after a **delay** (5s … 8h), lid closes while risen | Screensaver starts but the console is **not locked** until the delay elapses, and lich prevents the sleep that would have locked it. Reopening inside the grace window lands on an unlocked desktop | **No** — never verifies the lock took (lich:135) | Known-gap → **Q3** (README:67-71's "always lands on the password screen" is conditional) |
| Require password **Never / off**, lid closes while risen | Screensaver runs; machine never locks. Lid reopens straight into the live session | **No** | Known-gap → **Q3** |
| Lock does not take, for any reason | The log still says "screen locked", `LID_WAS_CLOSED` latches, and nothing retries for that closure | **No** — three compounding details, listed above | Known-gap → **Q3** |
| Tahoe 26 lock-screen regressions | Reported on 26.0.1: exiting the screensaver before the password grace period shows a lock-screen image without prompting; closing/reopening the lid inside a 5-minute "require password after display off" window lands on the live desktop *(source, unverified on this machine)*. Raises the odds that "screensaver started" ≠ "locked" even when set to Immediately | **Unknown** — an Apple bug lich cannot fix, but also cannot detect | Untested |
| Screensaver set to "Never start" | `open -a ScreenSaverEngine` starts the engine explicitly, so idle settings shouldn't matter | Unknown (untested against a disabled screensaver) | Untested |
| Console already locked when the lid closes | No second lock, no log line | Yes — `console_locked \|\|` guard (lich:135) | Should-work |
| ScreenSaverEngine fails to launch | Nothing locks, and the log still prints "lid closed while risen — screen locked" | Partial — `lock_console` is `\|\| true` (lich:84) and the log line is unconditional | Known-gap (log lies) |
| Lid closed with an external display attached (clamshell desk setup) | macOS keeps working on the external display; lich locks the console anyway. Security-correct, possibly unwanted | Yes — code makes no exception for external displays | Untested → **Q10** |
| Lid closed while risen but on **battery** | No lich lock; macOS sleeps and applies its own lock policy | Yes — gated on `sleep_disabled == 1` | **Tested** — field-verified 2026-08-02: lid closed on AC, then unplugged; log shows `power=battery roam=off -> disablesleep=0` at 17:04:18, machine slept (log gap), re-armed on AC return at 17:10:49 |
| Lid opened, then closed again | Locks again — the latch resets when the lid opens | Yes — lich:138-139 | Should-work |
| Desktop Mac / no clamshell sensor (Mac mini, Studio, iMac) | `lid_closed` never true → no lock path; `disablesleep` still applies, so lich becomes "never sleeps on AC" | Yes, incidentally — `ioreg` returns nothing (lich:77) | Untested (out of scope — MacBook tool) |
| Lid already closed when `lich on` runs (ssh) | First tick sees closed + risen → locks. Correct | Yes — `LID_WAS_CLOSED` starts at 0 | Should-work |
| Lid closes while this user is risen but **switched out** | `console_locked()` greps the root-level `IOConsoleLocked`, a single global reflecting the *front* session; `lock_console()` acts on the *calling* session. Under FUS those are different sessions, so: a false negative fires ScreenSaverEngine into an off-screen session (no-op, or contention — *unverified*), and a false positive means a switched-out risen user's own session is never locked at all | **No** — global read, per-session action | Untested → **Q4** |
| Several watchers, one lid closure | `LID_WAS_CLOSED` is per-process, so every running watcher fires its own lock attempt on the same closure | **No** | Known-gap (minor) |

---

## 5. Watcher lifecycle and health

| Configuration | Expected behavior | Code handles it? | Support |
|---|---|---|---|
| Agent loaded and running | 5s reconcile loop, silent until something changes | Yes | Tested |
| Agent never installed, sudoers absent | `lich on` writes the flag, reconcile fails silently, message still says "💀 lich risen" — with a stderr warning about the watcher only | Partial — nothing reports the failed `sudo` | Known-gap (misleading success) → **Q7** |
| Agent booted out (`launchctl bootout`) while risen | `bootout` sends SIGTERM (exit timeout 5s, *observed* via `launchctl print`) → trap restores `disablesleep 0` → Mac sleeps normally | Yes | Should-work |
| Agent disabled with `launchctl disable` | Won't start at login; `lich install` clears it with `launchctl enable` (lich:280) | Yes | Should-work |
| Toggled off in **System Settings → General → Login Items & Extensions** | A real launchd disable, not a deletion: the state lives in the per-uid override store `/var/db/com.apple.xpc.launchd/disabled.<uid>.plist` and is readable with `launchctl print-disabled gui/$UID` *(observed: `"com.lichbook.watcher" => enabled`, an explicit override written by `lich install`)*. lich sees only "not running" and prints **"run: lich install"** — wrong twice: the install is fine, and re-running it re-asserts `launchctl enable` over the user's explicit choice without saying so. **Fail-safe side is good:** the disable SIGTERMs the watcher, so the trap still restores sleep | Partial — detects absence, misdiagnoses cause, prescribes the wrong remedy | Known-gap → **Q6** |
| ...then `lich install` is re-run, then log out and back in | Whether `backgroundtaskmanagementd` re-asserts the BTM-side disable after `launchctl enable` clears the launchd override *(unverified; eclecticlight notes items being auto-re-enabled, implying BTM does assert state)*. If it does, install looks like it worked and quietly loses the race at next login | **Unknown** | Untested → **Q6** |
| How the watcher appears in Login Items & Extensions | `ProgramArguments[0]` is an unsigned bash script, so BTM attributes the item by filename with no developer identity, and macOS fires a "Background items added" notification right after install. The user gets an unexplained notification and a vendorless "lich" entry; every consumer Mac-security article tells them to switch exactly that off — which is the one action that breaks the product, and which lich then misdiagnoses (row above). README:78-93 mentions neither | **No** — not mentioned anywhere in the product | Known-gap → **Q6** |
| Sudoers rule missing while the watcher is loaded | `reconcile` returns 78 → `exit 78` (lich:132) on the first iteration → `KeepAlive` respawns → repeats forever. The generated plist sets no `ThrottleInterval`, so launchd's default applies *(observed: `minimum runtime = 10`)*: ~3 log lines per 10s ≈ 26k lines/day into an unrotated file, plus a process churned every 10 seconds indefinitely with no give-up | Partial — failing loudly is deliberate (lich:98-102), the unbounded cost is not | Known-gap (minor, but permanent) |
| ...and what `lich status` says during that crash loop | Almost certainly still `watcher: running` — `watcher_running()` asks whether the **label is loaded**, not whether a process is alive (lich:75), and launchd keeps the label loaded while throttling | **Unknown** (needs verification; the failure mode is structural) | Known-gap |
| Watcher SIGKILLed | No trap → `disablesleep` stuck at its last value until `KeepAlive` respawns (seconds) and reconciles | Yes — documented caveat | Should-work |
| `brew upgrade lichbook` without `lich reload` | Old code keeps running; new code is on disk. `reload` is the documented step | Yes — `cmd_reload` (lich:286-295) | Tested |
| `lich reload` with no agent loaded | `die "watcher not loaded — run: lich install"` | Yes | Should-work |
| Plist points at a clone path that was later moved or deleted | Agent can't spawn; launchd retries; `lich status` likely still claims "running" | **No** — nothing validates the recorded path | Known-gap |
| `lich install` run twice | `bootstrap` fails (already loaded) → falls through to `kickstart -k` | Yes — deliberate (lich:281) | Tested |
| Log file growth | `~/Library/Logs/lich.log` grows forever; no rotation, `uninstall` deliberately leaves it, and a crash loop fills it at ~26k lines/day | **No** | Known-gap (minor) |
| `lich off` while the watcher is running | Both `cmd_off` and the next tick set 0; idempotent | Yes | Tested |
| Launchctl override after `lich uninstall` | `uninstall` boots the job out and removes the plist, but never removes the `enable` override it wrote — it persists in `disabled.<uid>.plist` forever, per label *(observed: `launchctl print-disabled gui/501` still lists `"com.undeadmac.watcher" => enabled` from the pre-rename label)* | **No** | Known-gap (minor) → **Q5** |

---

## 6. Install completeness

| Configuration | Expected behavior | Code handles it? | Support |
|---|---|---|---|
| `brew install` + `lich install` (Apple Silicon) | Full function; plist points at `…/opt/lichbook/bin/lich`, stable across upgrades | Yes — Cellar-path rewrite (lich:212-214) | Tested |
| `brew install`, `lich install` never run | Flag writes work; nothing else does. `lich status` says watcher NOT running | Partial — no message about the missing sudoers rule | Known-gap (minor) |
| Clone + `./lich install` | Symlinks `/usr/local/bin/lich` → resolved clone path; agent points at the same | Yes (lich:206, 244-247) | Should-work |
| Clone directory moved/deleted after install | CLI symlink dangles and the watcher's program path is gone | **No** — nothing detects it | Known-gap |
| `lich` already on PATH (brew, or `~/bin`) | PATH step skipped, brew's own symlink never clobbered | Yes — deliberate (lich:243-247) | Tested |
| `/etc/sudoers.d/lichbook` deleted by hand | Watcher crash-loops (§5); `lich off` still works best-effort. Note the cleanup trap's `sudo -n … \|\| true` (lich:112) is now a no-op too, so that user's **logout guarantee is dead** until the rule returns | Partial — loud in the log, silent in the UI | Known-gap |
| Generated sudoers fails `visudo -cf` | Aborts with nothing installed — system sudo never at risk | Yes — validated in a temp file first (lich:237) | Should-work |
| `lich install` when `/etc/sudoers.d/lichbook` already exists naming **another user** | The file is replaced wholesale (`sudo install …` at lich:238), silently revoking the other user's rule. Nothing reads the existing file, nothing warns | **No** | Known-gap (major) → **Q4** |
| `lich install` over ssh with no console session | Prints "Installed." having loaded nothing — see §3 | Partial | Known-gap → **Q7** |
| Installed under the tool's **previous name**, then `lich uninstall` | `cmd_uninstall` removes only `$SUDOERS` = `/etc/sudoers.d/lichbook`. A pre-rename `undead-mac` rule is left behind as a **standing passwordless-root grant in a file the user won't recognize** *(observed on this machine: `/etc/sudoers.d/` contains both `lichbook` and `undead-mac`, and `sudo -l` lists the pmset grant twice)*. Blast radius is small (two exact pmset argv), but README:90's "removes all of it" is false for those users, and the trap re-arms on any future rename | **No** | Known-gap → **Q5** |
| Agent plist removed by hand instead of `lich uninstall`, while risen | No SIGTERM path, no watcher, and `disablesleep` persists across every subsequent reboot (§2) with nothing left that can reset it and nothing that reports it except `lich status`'s `sleep:` line | **No** | Known-gap |
| `lich uninstall` from a brew install on **Intel** (`/usr/local` is both) | Brew's own symlink is left alone — the readlink target is checked for `/Cellar/` | Yes — explicitly handled (lich:310-312) | Should-work |
| `lich uninstall` while risen | Flag → off, agent booted out (trap restores sleep), `disablesleep 0`, files removed in a safe order | Yes (lich:297-313) | Tested |
| `lich uninstall` with a Control Center widget installed | `rm -rf ~/.lich` removes the directory the sandboxed widget has an exception for. The widget's toggle then silently does nothing | **No** — uninstall doesn't know about the widget | Known-gap |
| Half-installed machine (any subset present) | Every uninstall step is `\|\| true`, so cleanup always completes | Yes — deliberate (lich:299-300) | Should-work |
| `lich install` as a **standard (non-admin) user** | `sudo` is refused → the `\|\|` branch fires → dies with *"generated sudoers failed validation"*, which is the wrong reason | Partial — it does abort with nothing installed | Known-gap (misleading error) |

---

## 7. Privilege and permissions

| Configuration | Expected behavior | Code handles it? | Support |
|---|---|---|---|
| Admin user, one password prompt at install | Standing privilege is exactly two pmset command lines; nothing runs as root | Yes (lich:232-238) | Tested |
| Standard user, self-install | Cannot install; see §6's misleading error. Correct outcome, wrong explanation | Partial | Known-gap |
| Standard user runs `lich on` on a Mac where an **admin** installed | The sudoers rule names one `$USER`, so this user has none. `cmd_on` does `reconcile \|\| true` (lich:156) — the refusal is swallowed — then unconditionally prints "💀 lich risen". **Nothing happened except a flag write.** Only signals: the stderr watcher warning, and `lich status`'s `sleep:` line contradicting the success message | **No** — exit 78 is indistinguishable from success at the call site | Known-gap → **Q7** |
| Standard user, admin hand-provisions the sudoers rule + plist | `sudo -n pmset` works for a standard user with a NOPASSWD rule, so the watcher should function | Unknown — never exercised | Untested |
| `sudo` timestamp expired / Touch ID configured | Irrelevant to the watcher: every background call is `sudo -n` and never prompts | Yes — deliberate (lich:29-30) | Tested |
| Menu bar app, login item granted | Registers once via `SMAppService`, appears in System Settings → Login Items | Yes (LichMenuBar.swift:84-89) | Should-work |
| Menu bar app, login-item registration **denied or failing** | Silently unregistered — and the `didAutoRegisterLoginItem` latch is set **regardless of whether `register()` threw**, so it is never retried | Partial — user can still tick "Start at Login" by hand | Known-gap |
| User unticks "Start at Login" later | Unregisters and stays unregistered; menu reflects `SMAppService.mainApp.status` | Yes | Should-work |
| TCC prompts (Accessibility / Automation / Full Disk Access) | None needed anywhere — screensaver locking was chosen precisely to avoid them | Yes — deliberate (lich:81-83) | Tested |

---

## 8. Optional components

| Configuration | Expected behavior | Code handles it? | Support |
|---|---|---|---|
| CLI only | Complete product. Everything else is a front end | Yes | Tested |
| CLI + menu bar app, brew on Apple Silicon | Icon reflects the flag within 15s; left-click toggles | Yes — probes `/opt/homebrew/bin/lich` first (LichMenuBar.swift:29-30) | Should-work |
| Menu bar app with the CLI at neither probed path (e.g. `~/bin/lich`) | Every call returns 127; icon shows ⚰️ forever and clicks do nothing visible | Partial — the error string exists but is never surfaced in the UI | Known-gap |
| Menu bar app, flag changed by something else | Icon catches up within 15s (poll; no file watcher) | Yes — deliberate (LichMenuBar.swift:66-70) | Should-work |
| Menu bar app copied to another Mac | Gatekeeper refuses it — ad-hoc signed, not notarized | Yes — documented, not prevented | Should-work |
| Menu bar app launched by a **second user** on the same Mac | Per-user-correct in itself (it shells out to the CLI and resolves the real home via `getpwuid`), but each user registers their own `SMAppService` login item and writes their own flag — another route into §10 | Yes for the app, No for the consequence | Untested → **Q4** |
| Control Center widget on macOS 26, built by the same user | Toggle writes the flag atomically; effect appears within ~5s | Yes (LichWidgets.swift:48-61) | Should-work |
| Widget built with `build.sh` steps reordered | Entitlements get truncated by xcodegen → sandboxed widget can't read the flag → silent no-op | Yes — order is enforced and documented in `build.sh` | Should-work |
| Widget used by a **second user** on the same Mac | The sandbox exception is baked to the *builder's* `$HOME` (`build.sh` generates it from `$HOME` at build time), while the code resolves the *running* user's home (LichWidgets.swift:28-34) → writes denied, silently. The second user must rebuild, which needs full Xcode + `xcodegen` | **No** | Known-gap |
| Generated entitlements file in the repo | **Correction to the research pass:** `controlcenter/Widget/LichControl.entitlements` is gitignored and untracked at v0.1.4 *(verified: `git ls-files` does not list it)*, so no username ships in the repo. The local build byproduct does contain `/Users/joe/.lich/`, which is expected and per-user by design | Yes — already handled in `.gitignore` | Should-work |
| Widget with no CLI or no live watcher | **The widget is structurally incapable of reporting this.** It is sandboxed to exactly one path (`~/.lich/`), so it cannot run `launchctl`, `pmset`, or `lich`; its whole side effect is writing the flag, and `ControlWidgetToggle` renders "Risen" afterwards regardless. In every watcher-down scenario in this document it shows confident success while the machine will sleep the moment the lid shuts — the exact failure the product exists to prevent. The CLI and menu bar both warn (lich:159); the widget cannot. Any fix must route through `~/.lich` (e.g. a watcher-touched heartbeat file) | **No** — and not fixable without expanding the flag-file API | Known-gap → **Q8** |
| Widget on the **Lock Screen** | A tap can raise or rest the lich while the machine is locked, without unlocking | Unknown — not verified whether macOS permits the intent while locked | Untested → **Q12** |
| Widget shows a stale state | No push from the flag file; refreshes when macOS asks | Yes — documented design | Should-work |

---

## 9. macOS version

The support policy is: **only the current latest macOS (26 / Tahoe) is tested.**
There are **no version checks anywhere in `lich`** (verified by grep) — earlier
systems fail open, attempting everything and warning on what fails.

| Configuration | Expected behavior | Code handles it? | Support |
|---|---|---|---|
| macOS 26 (this machine: 26.5.2, build 25F84) | Everything above | Yes | Tested |
| macOS 15 / 14 — CLI | `pmset disablesleep`, `ioreg`, `launchctl bootstrap`, `open -a ScreenSaverEngine` all long-standing; expected to work | Yes, incidentally — nothing is gated | Untested (fail-open) |
| macOS 15 / 14 — Control Center widget | Won't build: `MACOSX_DEPLOYMENT_TARGET: 26.0`, and Control Center controls are a 26 feature | Yes — build fails loudly, CLI unaffected | Untested |
| macOS 13 — menu bar app | `LSMinimumSystemVersion 13.0`; `SMAppService` is 13+ | Yes | Untested |
| macOS 12 and earlier — menu bar app | Refuses to launch | Yes | Untested |
| macOS 12.2 and earlier — `lich install` | `readlink -f` doesn't exist on old BSD readlink → falls back to `"$0"`, which may be **relative** → the plist records a path launchd cannot resolve | Partial — there is a fallback, but it can be wrong | Known-gap (accepted under fail-open) |
| Any earlier version, optional components failing | CLI must remain fully usable — and it is: components are independent, install is best-effort per step | Yes | Should-work |
| Tahoe 26's user-activity change that broke assertion-based keep-awake apps | **lich is unaffected, and this is a genuine differentiator.** Caffeine needed 1.1.4 for Tahoe (older versions launch, appear to work, and silently fail to prevent sleep); KeepingYouAwake shipped Tahoe fixes *(source)*. lich holds no `IOPMAssertion` and simulates no user activity — it flips the kernel-level `disablesleep` via powerd, which that change does not touch, and which is also the only mechanism that blocks clamshell sleep at all (README:58 is correct) | N/A — different mechanism, verified by reading (lich:69-73, 92-104) | Should-work |
| A future 26.x that emits a **second** line matching `/SleepDisabled/` | `sleep_disabled()` is an unanchored `awk` over all of `pmset -g` *(observed: exactly one matching line today)*. Two matches → `"1 1"` → the equality test in `reconcile` can never match → `sudo pmset` and a log line **every 5 seconds forever**, while the power behavior stays correct so nothing surfaces the problem | **No** — one-token hardening; see §12 #7 | Untested (latent; "untested future 26.x" is precisely this project's stated risk surface) |

---

## 10. Multi-user and fast user switching

This is the weakest area of the design, because the pieces of state that are
shared are shared and the flag is not.

- `/etc/sudoers.d/lichbook` is **one file at one fixed path** containing **one
  user's rule** (lich:43, 232-238), replaced wholesale on every install.
- `pmset -a disablesleep` is a **machine-wide** setting, but `~/.lich/desired-state`
  is **per-user**. Two logged-in users can want opposite things.
- Fast user switching keeps both users' agents running (§3), so both can want
  opposite things *at the same time*.

The no-privilege primitive a fix would need already exists and was confirmed on
this machine: `ioreg -n Root -d1 -a` → `IOConsoleUsers` is an array of
per-session dicts carrying `kCGSSessionUserIDKey`, `kCGSSessionOnConsoleKey` and
`CGSSessionScreenIsLocked` *(observed)*. That is strictly better than
`stat -f%Su /dev/console`, which cannot distinguish "at the FUS login window"
from "backgrounded user".

| Configuration | Expected behavior | Code handles it? | Support |
|---|---|---|---|
| One user on the machine | Everything in §1 | Yes | Tested |
| User B runs `lich install` after user A | B's rule **overwrites** A's — the file is replaced, not appended. A's watcher then crash-loops (§5), **and A's cleanup trap is dead too** (`sudo -n … \|\| true`, lich:112), so nothing in A's session can ever restore normal sleep again. From that point `disablesleep` is governed solely by B. A is never warned; `lich status` may still show "watcher: running" in the window between respawns | **No** — fixed filename, single-line rule | Known-gap (major) → **Q4** |
| User B runs `lich uninstall` | Removes `/etc/sudoers.d/lichbook` outright, disarming **every** other user's watcher the same way, plus removes `/usr/local/bin/lich` from everyone's PATH when it isn't a brew symlink. B is told "the Mac is mortal again" and has no way to know they broke someone else's session. The careful ordering comment at lich:298-300 suggests the cross-user blast radius is unintentional | **No** | Known-gap (major) → **Q4** |
| Standard-user B attempts install alongside admin A | Aborts before writing anything, so A survives | Yes, incidentally — validation runs before `install` (lich:237) | Untested |
| A and B both logged in (FUS), **both risen**, both with working sudo | They agree; `reconcile` is idempotent so both go quiet | Yes — desired-vs-live comparison (lich:95) | Untested |
| A risen, B at rest, both watchers alive | **Flip-flop war**: each tick one sets 1 and the other sets 0, roughly every 5s each, forever, with a log line on every flip in both homes (~12 lines/min each, unrotated). The kernel samples `disablesleep` at the instant the lid closes, so **whether the machine survives a lid close is decided by whichever watcher ticked last** — i.e. A's long-running session dies at random | **No** — no notion of another user's intent, and no console-ownership check anywhere in the repo | Known-gap (major) → **Q4** |
| B logs out while A is risen (FUS) | B's cleanup trap sets `disablesleep 0` machine-wide; A's next tick restores 1 — leaving a ≤5s window where a lid close would sleep the machine | **No** — the trap is unconditional by design | Known-gap → **Q4** |
| Lid closes while A is risen but B is the active console user | A's watcher may fire `lock_console` into its own off-screen session, locking nothing that matters — or contend for the console; and B's session state is what `IOConsoleLocked` reports. See §4's switched-out row | **Unknown** — cross-session `ScreenSaverEngine` behavior unverified | Untested → **Q4** |
| A risen, B has no lichbook at all | Works: only A's watcher exists. The machine-wide setting simply follows A | Yes, incidentally | Untested |
| A LaunchAgent plist present for a user with **no** sudoers rule (copied home, renamed short username, security tooling cleaning `/etc/sudoers.d`) | Permanent 10-second respawn loop appending an ERROR line forever (§5). `lich on` warns only about the watcher, never about sudo | Partial | Known-gap |
| Screen Sharing as a second user | The realistic trigger for every row above — it creates a second Aqua session with its own agents without anyone consciously "switching users" | **No** | Known-gap → **Q4** |
| Machine has a second real account but only one lich user (this machine: `joe` uid 501, `webs` uid 502, both admin) | Fine today, and one `lich install` by the other account away from the rows above | **No** — install does not look for other users' agents or rules | Untested → **Q4** |

---

## 11. Thermal and battery limits

Not code behavior — but users will attribute all of it to lichbook, and the
README currently understates the first row.

| Configuration | Expected behavior | Code handles it? | Support |
|---|---|---|---|
| **Fanless MacBook Air**, sustained load, lid closed, on a desk | Measured reporting: sustained GPU work in clamshell fell to ~52% of peak over 20 minutes purely from thermal throttling, versus roughly a 10% drop with a heat-shedding accessory *(source)*. The mechanism is specific: with the lid shut the keyboard deck — a primary dissipation surface on the Air — is covered. lichbook's entire use case is long-running lid-closed work, i.e. exactly this load profile. README:128-130's "Fine on a desk" is wrong for an Air | N/A — physics | Known-gap in the docs → **Q9** |
| **Fan-equipped MacBook Pro**, lid closed, on a desk | Expected to be mostly fine; the vents-less-well framing holds here | N/A | Untested |
| Any Mac risen in a bag or on a cushion | The existing README warning stands, and is the correct one | N/A — documented, not prevented | Untested |
| Extreme temperature while risen | macOS thermal protection shuts the machine down regardless of `disablesleep`. "Never sleeps while risen" is not "never stops" — and a thermal shutdown is a hard stop that skips the cleanup trap, feeding §2 | N/A | Untested → **Q9** |
| In a bag at the login window after a crash/forced reboot (§2) | The one case where the README's battery-safety promise genuinely fails: system-wide `disablesleep` still `1`, on battery, with no watcher and no way to reach `lich status` | **No** | Known-gap → **Q1/Q2** |
| Permanently docked (the state lichbook structurally encourages) | Apple's Optimized Battery Charging learns the pattern over ~a week and holds charge near 80%; Tahoe also exposes an explicit Charge Limit; the Mac still tops to 100% occasionally to keep the charge estimate calibrated *(source)*. **No interaction with `disablesleep` was found and none is expected** — powerd's charging policy and the `SystemPowerSettings` sleep boolean are separate subsystems. Looked for specifically; recorded so it is not re-investigated. *(observed: `/Library/Preferences/com.apple.powerd.charging.plist` currently holds `ChargeCtrlPolicy` with `soclimit: 100`, i.e. no limit active here)* | N/A — separate subsystem, investigated and clear | Untested (no promise; nothing for lich to do) |

---

## 12. Appendix: code fragilities found while reading (not state rows)

These are not configurations; they are places where the code could produce a
wrong answer in any of the rows above. Listed for the maintainer, not as
promises.

1. **`set -o pipefail` + early-exiting readers.** `on_ac` (lich:59),
   `lid_closed` (lich:77) and `console_locked` (lich:79) all pipe a producer
   into `head -1` / `grep -q`, which exit at the first match. If the producer
   is still writing it takes SIGPIPE (141), and `pipefail` turns that into a
   false negative — "on battery" while on AC, or "lid open" while closed.
   Outputs are small enough that this probably never fires; it is latent, not
   observed.
2. **`watcher_running()` proves the label is loaded, not that a process is
   alive** (lich:75). A crash-looping watcher likely reports `watcher: running`.
   Wants a `launchctl print | grep -E 'state = running'` or a PID check.
3. **The lock log line is unconditional** (lich:135). `lock_console` is
   `|| true`, so "screen locked" is logged even when nothing locked — the log
   asserts a security property that was never verified.
4. **`didAutoRegisterLoginItem` is latched even when `register()` threw**
   (LichMenuBar.swift:87-88), so a denied login item is never retried.
5. **`lich install` prints "Installed." after swallowing every launchctl
   failure** (lich:280-283).
6. **`cmd_on` swallows a failed `reconcile`** (lich:156) and still prints
   "💀 lich risen", warning only about the watcher, never about sudo. Exit 78 is
   distinguishable and currently discarded.
7. **`sleep_disabled()`'s match is unanchored** (lich:71):
   `awk '/SleepDisabled/ {print $2}'` over all of `pmset -g`. One matching line
   today; a second one silently breaks the equality test forever. Hardening is
   one token: `awk '$1=="SleepDisabled" {print $2; exit}'`. No behavior change
   today.
8. **`cleanup()`'s `sudo -n … || true`** (lich:112) means a revoked sudoers rule
   silently converts the logout guarantee into a no-op, with nothing logged
   about *why* sleep was not restored.
9. **The generated plist sets `KeepAlive` with no `ThrottleInterval`**
   (lich:271), so launchd's default governs a broken install
   *(observed: `minimum runtime = 10`)*.
10. **`lich install` re-asserts `launchctl enable`** (lich:280) over a user's
    explicit "off" in System Settings, silently.
11. **`lich uninstall` never removes the launchctl override it wrote**, so
    `disabled.<uid>.plist` accumulates one entry per label the tool has ever
    used *(observed)*.
12. **Fork cost of the healthy path.** The 5s loop spawns ~8 short-lived
    processes per tick (two `pmset`, `ioreg`, `plutil`, `grep`, `awk`, `head`,
    `cat`) *(observed: `runs = 51`, `forks = 5113` for one watcher)*. Not a bug;
    it is the kind of thing macOS energy accounting notices.
13. **The session primitive the code never uses.** `IOConsoleUsers` (per-session
    `kCGSSessionUserIDKey` / `kCGSSessionOnConsoleKey` /
    `CGSSessionScreenIsLocked`) is readable without privileges and would settle
    every "who owns the console?" question in §3, §4 and §10.

---

## 13. Open questions for the owner

Referenced as **Q1**…**Q12** above. Each is a decision a worker should not make.

- **Q1 — Boot-time reconciliation.** `disablesleep` survives a reboot, so any
  crash or forced restart leaves the Mac sleep-disabled at the login window with
  no watcher, indefinitely (§2). Accept and document, or fix with a root
  LaunchDaemon that forces `disablesleep 0` at boot — which breaks the "nothing
  runs as root" promise in lich:25-26 — or a middle path (`lich doctor`, status
  surfacing)?
- **Q2 — README power-contract claims.** README:47 ("you'll never cook the
  battery in a bag") and README:132-134 ("worst case is one session … visible in
  `lich status`") are both false for the pre-login window. Rewrite them to name
  that window explicitly? This is a promise change, not just wording.
- **Q3 — The lock-screen dependency.** In any configuration where "require
  password" is not Immediately, lich *removes* a lock the user would otherwise
  have had (§4). Should `lich install`/`lich status` probe
  `sysadminctl -screenLock status` and warn — or refuse to raise — and should
  README:67-71 be softened to state the dependency?
- **Q4 — Multi-user policy.** Declare lichbook single-user-per-Mac and document
  it, or fix it: per-user sudoers files (`/etc/sudoers.d/lichbook-$USER`, which
  also fixes cross-user uninstall) plus console-ownership gating via
  `IOConsoleUsers`? A cheap interim is an install-time warning when another
  user's rule or agent exists.
- **Q5 — Legacy `undead-mac` cleanup.** Should `uninstall` also remove the
  pre-rename sudoers file and launchctl override (a one-time migration for early
  adopters, guarded by a content check), or is that out of scope with a README
  note telling them to `sudo rm /etc/sudoers.d/undead-mac`?
- **Q6 — Login Items & Extensions.** When a user has toggled the watcher off
  there, should `lich install` silently re-enable it (today), refuse, or warn?
  Should `status`/`on` name the real cause and remedy? And is the unexplained
  "Background items added" notification worth a line in the README?
- **Q7 — Install/`on` honesty vs. the fail-open policy.** Should `lich install`
  exit non-zero when the watcher did not load, and should `lich on` print an error
  instead of "💀 lich risen" when `reconcile` returned 78? Today both report
  success they did not achieve, which contradicts the "warns on what fails" half
  of the stated support policy.
- **Q8 — Control Center API surface.** The widget cannot detect a dead watcher
  and will show "Risen" regardless (§8). Expand the documented flag-file
  contract from one file to two (a `~/.lich/heartbeat` the watcher touches, with
  the widget treating >30s as "watcher down"), or document the limitation and
  make `lich status` the only authoritative health check?
- **Q9 — Thermal wording.** Split the caveat into "fanless Airs: expect
  sustained throttling even on a desk (~half of peak reported)" vs
  "fan-equipped Pros: fine on a desk, never in a bag", and add that a thermal
  shutdown overrides `disablesleep`?
- **Q10 — External displays.** Should lich still lock the console on lid close
  when an external display is attached and the session is visibly in use?
- **Q11 — Which rows are genuinely Tested?** Every "Tested" in this document is
  inferred from README claims and commit messages. The maintainer must confirm
  the real list; anything unconfirmed should drop to Should-work.
- **Q12 — Lock Screen widget.** Is raising or resting the lich from the Lock
  Screen, without unlocking, acceptable? Needs both a test (does macOS permit
  the intent?) and a policy answer.

---

## 14. Known macOS quirks that affect lichbook

Behaviors of macOS — not of `lich` — that change what lichbook does or how it is
perceived. **Severity** is the research pass's own scale: `breaks-core` (defeats
the product's central promise), `degrades` (works, worse or noisier than
claimed), `info` (worth knowing or saying out loud), `unknown` (severity cannot
be assigned until someone tests it). Sources are abbreviated; *observed* means
measured read-only on the maintainer's Mac (26.5.2 / 25F84, 2026-08-02).

| Finding | Severity | Source | How lichbook behaves |
|---|---|---|---|
| `disablesleep` persists across reboots — `SystemPowerSettings => SleepDisabled` in `/Library/Preferences/com.apple.PowerManagement.plist`, applied by powerd at boot (**not** the `SystemConfiguration/` subpath older docs cite; that file does not exist on Tahoe) | breaks-core | observed (plist + mtime); dssw pmset reference; drpebcak; derflounder | Any panic, thermal shutdown or forced restart while risen boots the Mac sleep-disabled with no watcher until someone logs in (§2). lich:67-68's comment assumes a reboot may clear it — it does not |
| `disablesleep` is a single **system-wide** boolean, not per-power-source: it prints under "System-wide power settings" and is absent from `pmset -g custom`; `pmset -a` is cosmetic for this key | breaks-core | observed | The entire "AC only" rule is lich's 5s poll and nothing else. With no watcher, a stale `1` keeps the Mac awake **on battery** too (§1, §2) |
| Whether macOS's critical-battery emergency sleep/hibernate is gated by `SleepDisabled` or overrides it | unknown | nothing authoritative found | Unknown. If gated, a stale `1` with no watcher could run a MacBook to a hard cut-off rather than hibernating (data loss). **The single highest-value bench test:** set `disablesleep 1`, kill the watcher, unplug, drain |
| Starting ScreenSaverEngine locks nothing by itself — the lock comes from "Require password after screen saver begins or display is turned off" | breaks-core | Apple discussions 254918945; dev forums 778916; observed (`sysadminctl -screenLock status` → "immediate" here) | With a delay or Never, lid-close does not lock, and because lich blocks the sleep it also removes the lock macOS would have applied. lich logs "screen locked" regardless and never retries (§4) |
| Tahoe 26 lock-screen regressions: exiting the screensaver inside the password grace period shows a lock image without prompting; lid close/reopen inside a 5-minute grace window lands on the live desktop | degrades | discussions.apple.com 256165873; dev forums 787444; **field-confirmed 2026-08-02**: same machine, same "immediate" setting — lock verification failed at 17:04 and 17:10 but succeeded by 17:38 (IOConsoleLocked=true). Intermittent, not configuration | As of v0.2.0 lich re-checks on the next tick and logs "lock confirmed" or a loud WARNING — the intermittence is now visible in the log instead of silent (§4) |
| Tahoe moved Screen Saver settings into a modal inside Wallpaper | info | same thread cluster | Users are less likely to have ever seen the setting lich silently depends on (§4) |
| Fast user switching does not stop a switched-out user's LaunchAgents — *"Processes in a switched-out login session continue running as before"* | breaks-core | Apple, *Multiple User Environments* (FUS) | Two lich users with opposite intent write the one global setting every ~5s each; the lid-close outcome is decided by whichever ticked last (§10). Also: a switched-away risen user keeps the whole Mac awake (§3) |
| Screen Sharing **as a different user** opens a second Aqua session with its own LaunchAgents | degrades | Apple FUS doc; macworld; mac-forums | The realistic route into the flip-flop above — reached without anyone consciously switching users (§10) |
| `gui/<uid>` exists only while that user has an Aqua session; SSH gets `user/<uid>` | degrades | jamf; home-manager #4413; buildkite/docs #353; observed (`gui/501` resolves, `user/501` does not) | `lich install` over SSH with no console session loads nothing, swallows both failures, and still prints "Installed." (§3, §6) |
| Login Items & Extensions toggles are **real launchd disables**, stored per-uid in `/var/db/com.apple.xpc.launchd/disabled.<uid>.plist` and readable via `launchctl print-disabled gui/$UID` | breaks-core | eclecticlight; macblog; observed (`"com.lichbook.watcher" => enabled`) | lich sees only "not running", tells the user to re-run install, and install then silently re-asserts `enable` over their explicit choice (§5). Fail-safe: the disable SIGTERMs the watcher, so the trap still restores sleep |
| Whether `backgroundtaskmanagementd` re-asserts a user's BTM disable after `launchctl enable` clears the launchd override | unknown | eclecticlight (notes items being auto-re-enabled) | Unknown. If it does, `lich install` looks like it worked and quietly loses the race at the next login (§5) |
| launchd's default respawn throttle is a 10-second minimum runtime, and the generated plist sets no `ThrottleInterval` | degrades | Apple dev forums 133915; shirtpocket; observed (`minimum runtime = 10`) | A missing sudoers rule becomes a permanent respawn loop writing ~3 lines per 10s (~26k/day) to an unrotated log, forever (§5) |
| launchd jobs whose program is an unsigned script are attributed in Login Items by filename, with no developer identity; macOS also fires a "Background items added" notification | degrades | macblog; eclecticlight; inventivehq | After `lich install` the user gets an unexplained notification and a vendorless "lich" entry. Switching it off is the one action that breaks the product — and lich then misdiagnoses it (§5). README:78-93 mentions neither |
| `launchctl enable` writes a per-uid override that outlives the job it named | info | observed (`"com.undeadmac.watcher" => enabled` still listed, from the pre-rename label) | `lich uninstall` boots out and deletes the plist but never removes the override; one stale entry accumulates per label the tool has used (§5) |
| Tahoe 26 changed user-activity handling and broke assertion-based keep-awake apps — Caffeine needed 1.1.4 (older builds launch and silently fail); KeepingYouAwake shipped Tahoe fixes | info | intelliscapesolutions; KeepingYouAwake CHANGELOG; HN 45300616 | **Does not affect lich**, and is worth saying out loud: it holds no `IOPMAssertion` and simulates no user activity — it flips kernel `disablesleep` via powerd. *(observed: unrelated `caffeinate` assertions coexist with `SleepDisabled 1`, and `sleep_disabled()` is not confused by them)* (§9) |
| Widely reported Tahoe 26 sleep/wake regressions: lid close then no wake (backlight responds, screen black, restart needed); display not turning off on lid close; persisting for some into 26.1/26.2 | info | discussions.apple.com 256150505 / 256253675; macobserver; macrumors 2469257 | The opposite failure mode from lich's, with an overlapping symptom surface — users will blame lichbook. `lich status`'s live `sleep:` line already distinguishes "lich is holding it awake" from "macOS is broken" |
| NVRAM and SMC resets — the standard internet advice for those regressions — do not clear `SleepDisabled` | info | observed (`nvram -p` shows no power/sleep keys); Apple Silicon has no user-invokable SMC reset | The setting lives in a plist on the data volume. Only `lich off`, `sudo pmset -a disablesleep 0`, or `lich uninstall` clears it (§2) |
| Clamshell thermals on fanless Apple Silicon: sustained GPU work fell to ~52% of peak over 20 minutes in clamshell, versus ~10% with heat-shedding help; the covered keyboard deck is a primary dissipation surface on an Air | degrades | cultofmac; techradar; macrumors forums 2292473 | lichbook's whole use case is sustained lid-closed load. README:128-130's "Fine on a desk" holds for fan-equipped Macs, not for an Air (§11) |
| macOS thermal protection shuts the machine down at extreme temperature regardless of `disablesleep` | info | vendor/behavioral; specifics unverified | "Never sleeps while risen" is not "never stops" — and a thermal shutdown is a hard stop that skips the cleanup trap, feeding the first row of this table (§2, §11) |
| Optimized Battery Charging (and Tahoe's Charge Limit) handle permanent-AC operation, holding near 80% after ~a week of learning and topping to 100% occasionally for calibration | info | support.apple.com 102338; osxdaily; observed (`ChargeCtrlPolicy` `soclimit: 100` here, i.e. no limit active) | **No interaction with `disablesleep` found and none expected** — separate subsystems. Recorded as investigated and clear, so it is not re-opened (§11) |
| Tahoe Screen Sharing to a target sitting at a login prompt reportedly behaves differently than to a live session | unknown | conflicting community reports | Unknown. lich locks the console on every lid close, so the first connect after a lid close always faces an authentication step (§3) |
| Guest accounts: home directory discarded at logout, cannot be admin, Safari-only under FileVault | info | general macOS behavior; no authoritative source found (*unverified, high confidence*) | `lich install` aborts at `visudo -cf` with nothing written, and no lich state would survive a Guest logout anyway (§3) |
| `SleepDisabled` observed being cleared to `0` by something other than lich, with the next reconcile restoring it | info | observed (`~/Library/Logs/lich.log` 11:56:38 + plist mtime; cause unattributed, unified-log query returned nothing) | Direct evidence that idempotent polling (lich:120-124) is load-bearing rather than merely defensive: a set-once implementation would have silently lost the setting (§1). Reproduce before drawing conclusions |

---

## 14. Roaming (added in v0.2.0; **semantics revised in v0.3.0**)

> **v0.3.0 change:** roam became two layers — a persistent **standing**
> setting (`off`/`always`/`timer`, where `timer` grants a fresh
> `roam_mins` window at *every* unplug) plus a temporary **trip** overlay
> (`once` / bounded minutes) that evaporates without touching the standing
> setting. The rows below were tested against v0.2.x single-value semantics;
> their *mechanics* (floor, expiry precision, spend-on-AC) carry over to
> trips unchanged, but "cleared to off" now means "trip cleared, standing
> revealed". Standing-timer per-unplug renewal is new in v0.3.0 and
> **Untested** until it happens in the field.

Battery keep-awake ("roam") rows, authored by the review gate after the
feature landed. The AC-side paths were exercised live; the battery-side logic
is code-verified but **not yet field-tested on battery** — statuses say so.

| Configuration | Expected behavior | Code handles it? | Support |
|---|---|---|---|
| Risen, on battery, `once` armed, above floor | Awake, lid open or closed (lid-close still locks); next return to AC spends the one-shot, logged | Yes — `roam_active` / `roam_on_ac` | Should-work |
| Risen, on battery, `always`, above floor | Awake indefinitely while above the floor | Yes | Should-work |
| Timed roam expires on battery | Sleeps within ~5s; roam cleared to `off`, logged once (watcher is the only writer of expiry) | Yes | **Tested** 2026-08-03: 30-min roam armed 10:19:03, lid closed, no power; heartbeat = 29/29 consecutive minute-beats (fully available all window); `roam timer expired` + release at 10:49:05 (**+2s** past deadline); asleep before the next minute-beat; battery 100% → 100% |
| Risen + roam active on battery, lid closes | Held awake by the roam grant; the lid-close lock fires exactly as on AC | Yes — lock path gated on `sleep_disabled == 1`, which roam satisfies | **Tested** 2026-08-03: lock requested 10:22:21 while roaming on battery (verification failed — Tahoe intermittence, tally 3 fail / 1 success; availability unaffected) |
| `once`/timed roam hits the floor (default 20%) | Canceled outright; sleeps within ~5s; nothing silently resumes at 19% | Yes | Should-work |
| `always` roam hits the floor | **Suspended, not cleared** — sleeps below floor, standing preference survives to the next charge | Yes | Should-work |
| Roam armed but watcher dead | Nothing enforces the floor or timer — the flags are inert, and a stale `disablesleep 1` stays | No — the watcher *is* the enforcement | Known-gap |
| `lich done` (agent hand-back) | Clears `once`/timed only; `always` and the risen flag untouched | Yes | **Tested** (live) |
| Roam armed while still on AC | No effect until unplugged; plugging in before any battery use does **not** spend a one-shot (in-memory grant latch) | Yes | **Tested** (AC side) |
| Watcher restart mid-roam | `always`/timed survive (file-backed); an unused `once` can survive one extra plug-in cycle (in-memory latch lost — documented tradeoff, lich comment at top of file) | Partial | Should-work |
| Battery percentage unreadable (desktop Mac, format change) | Reads as 100% — floor never triggers; warned once in the log | Partial — fails toward awake | Untested |

## 15. Review-gate rulings (2026-08-02)

Decisions on the questions escalated by the research and build passes,
recorded so they are not accidentally relitigated.

| Question | Ruling | Rationale |
|---|---|---|
| Post-crash login-window exposure (§2): add a root LaunchDaemon clearing `disablesleep` at boot? | **No daemon; document honestly** (README caveat rewritten in v0.2.0) | Preserves the "nothing runs as root" audit story; first login self-heals within ~5s |
| Lock fired but never verified (§4) | **Fixed in v0.2.0** — lock *requested*, then *verified* next tick (`IOConsoleLocked`); one honest log line, loud warning if it never took | Cheap, truthful, and still never fights a deliberate Screen Sharing unlock |
| Two-user flip-flop (§10) | **Known-gap, documented; no console-ownership gating** | A switched-away session keeping the Mac awake is the product working as specified; dual conflicting installs are rare and now documented |
| Fail-open install | **Adopted in v0.2.0** — per-step attempt/warn/continue, sudoers *proven* via `sudo -k` + `sudo -n` probe, agent deliberately not loaded on a broken sudoers rule (respawn-loop guard), truth-telling summary | Matches the support policy: latest macOS tested, everything else fails open |
| Install exit status | `0` unless the sudoers step failed | Scripts need "nothing works" distinguishable from "optional parts missing" |
| Add `brew trust` to Formula caveats | **Rejected** | The trust error blocks before caveats ever print; brew's own error names the command; README covers it |
| Critical-battery emergency sleep vs `SleepDisabled` (§13) | **Left Unknown; bench test deferred** | The roam floor ends grants well before critical charge in supported use |
