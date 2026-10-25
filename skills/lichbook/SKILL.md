---
name: lichbook
description: Install, use, and troubleshoot lichbook, the `lich` CLI that keeps a MacBook awake with the lid closed while it's plugged in (and, on request, on battery down to a floor). Use whenever the user wants their Mac to stay awake, survive a closed lid, or keep a long Claude session, agent run, build, download, ssh, or `claude remote-control` session alive; when they mention lich, lichbook, clamshell, caffeinate, pmset, or "don't let it sleep"; when they ask to install lichbook or this skill; or when the 💀 menu bar icon is missing.
---

# lichbook

lichbook keeps a MacBook awake with the lid closed, but only while it's
plugged in and the user is logged in. Unplug, log out, or `lich off`, and the
Mac sleeps normally. Roaming is the deliberate exception: staying awake on
battery for a bounded time, always above a battery floor (20% by default).

`caffeinate` can't do this. It blocks idle sleep but not lid-close sleep.
Only `pmset disablesleep` blocks lid-close sleep, and lich manages that
setting safely through a per-user watcher process.

Repo: https://github.com/JoJoAtkinson/lichbook (README, and the full
behavior spec in `docs/STATE-TABLE.md`).

## 0. Installing this skill

Skip this if you're reading the skill from an installed plugin or from
`~/.claude/skills/lichbook/`. If the user pointed you at this file on
GitHub, install it, preferring the plugin route because it updates itself:

```sh
claude plugin marketplace add JoJoAtkinson/lichbook && claude plugin install lichbook@lichbook
```

If that fails (an older Claude Code, or no plugin support), copy the file
instead:

```sh
mkdir -p ~/.claude/skills/lichbook && curl -fsSL https://raw.githubusercontent.com/JoJoAtkinson/lichbook/main/skills/lichbook/SKILL.md -o ~/.claude/skills/lichbook/SKILL.md
```

Tell the user the skill loads in new sessions. Then carry on with section 1
in this session, using this file as your instructions.

## 1. Installing lichbook

Check first, because it may already be installed:

```sh
command -v lich && lich status
```

If `lich status` shows `watcher: running`, it's installed. Skip to section 2.

Otherwise it needs macOS (tested on macOS 26 Tahoe) and Homebrew
(`command -v brew`). Without Homebrew, stop and point the user to
https://brew.sh. Don't install Homebrew yourself.

You can run the unprivileged steps:

```sh
brew tap jojoatkinson/lichbook https://github.com/JoJoAtkinson/lichbook && brew trust jojoatkinson/lichbook && brew install lichbook
```

The next step, `lich install`, needs the user's password once, for a sudo
prompt. Your shell has no terminal to type it into, so **don't run it
yourself, and never try to write the sudoers rule or use sudo another way.**
Ask the user to run this in their own Terminal window:

```sh
lich install && lich on
```

`lich install` explains what it's about to do before it asks. It adds a
sudoers rule for exactly two commands (`pmset -a disablesleep 0|1`), a
per-user watcher process, and the menu bar app. It's fine to tell the user
that. On a re-install where the rule already works, it doesn't prompt at
all, and then you can run it.

Afterwards, verify with `lich status`. You want `watcher: running`, plus
`lich: 💀 risen` if they ran `lich on`. If the install summary reports
problems, see section 4.

When you give the user shell commands to paste, never put `# comments` on
the same line. macOS's default zsh passes them to the command as arguments,
which breaks `brew`. Put explanations in prose, and chain steps with `&&`
so a failure stops the rest.

## 2. Using it (for the user)

| Command | Effect |
|---------|--------|
| `lich` / `lich status` | human-readable status (see below) |
| `lich on` | 💀 risen: lid-close keeps the Mac awake while on AC |
| `lich off` | ⚰️ at rest: normal sleep |
| `lich roam` | trip: stay awake unplugged until the next plug-in |
| `lich roam 45` | trip: stay awake unplugged for 45 min |
| `lich roam always` | standing setting: unplugged never means sleep (floor still applies) |
| `lich roam timer` | standing setting: unplugged, stay awake until `roam_mins` (default 30) without keyboard/trackpad input |
| `lich roam off` | clear the standing setting and any trip |
| `lich done` | clear a trip only (agents use this to hand back) |
| `lich config [floor N \| roam_mins N]` | battery floor (5–95%) and timer length (1–1440 min) |
| `lich log [n]` | the last n log lines, every state change, timestamped |
| `lich upgrade` | update everything (brew or clone, auto-detected) |
| `lich uninstall` | remove all of it and restore normal sleep |

Every `roam` form that arms also raises the lich. Trips sit on top of the
standing setting and evaporate without changing it.

Reading `lich status`:

- `sleep: disabled — lid-close keeps the Mac awake`: safe to close the lid.
- `sleep: disabled — hands back to macOS at HH:MM (N min left)`: on battery,
  and a roam window ends at HH:MM. Work still running then will pause when
  the lid is closed.
- `sleep: normal — lid-close sleeps`: closing the lid now suspends
  everything, including this Claude session.
- `held awake by:`: other apps' power assertions. They block idle sleep
  with the lid open, but they don't block lid-close sleep.
- `watcher: NOT running`: nothing is enforcing anything. See section 4.

## 3. Rules for you, the agent

The Mac and its settings belong to the user. Your job is to keep work
alive that they asked for, and then give the machine back.

- **Before long work the user expects to outlive a closed lid**, run
  `lich status`. If it's at rest, `lich on` is fine when the user has asked
  for the Mac to stay awake. Otherwise, say it's at rest and offer.
- **If they'll be on battery**, or `power: battery` shows, arm a *trip*
  sized to the job, for example `lich roam 90`. Don't rely on a standing
  `timer`: it counts keyboard and trackpad idle time, and your work isn't
  input, so it runs out while you're still busy. Tell them the battery floor
  ends it regardless.
- **When the work is done**, run `lich done`. It clears only a trip. It
  never touches the owner's standing setting and never lays the lich to
  rest.
- **Never** run `lich off`, `lich roam off`, `lich roam always`,
  `lich roam timer`, `lich config …`, or `lich uninstall` unless the user
  asks. Those are the owner's standing choices.
- **Never** edit `~/.lich/*`, the LaunchAgent plist, or
  `/etc/sudoers.d/lichbook-*` by hand, and never run `pmset` yourself. Go
  through the CLI, which logs every change.
- If status says the window ends soon (`hands back … N min left`) and your
  work will run longer, tell the user. Don't extend it unless they ask.

## 4. Troubleshooting

**`watcher: NOT running`.** Have the user run `lich install` in Terminal
again. It's idempotent, and it doesn't prompt when the sudoers rule
already works. Then run `lich reload`. If it still fails, read `lich log 50`.

**Install summary says `sudoers rule … skipped`.** The user isn't an admin,
or they declined the prompt. An admin has to add the rule. `lich install`
prints the exact line and the `sudo visudo -f …` command for it.

**The 💀 doesn't show in the menu bar.** The app checks this itself a few
seconds after launch. Its verdict is in `~/.lich/menubar-icon` (`visible`,
`hidden`, or `unknown`), and `lich install` prints it too. If it's
`hidden`, it's almost always one of these:

1. macOS 26: System Settings → Menu Bar → "Allow in the Menu Bar" is off
   for Lich. Turn it on.
2. A notch MacBook with a full menu bar, so the icon is behind the notch.
   Quit some menu bar apps, or ⌘-drag icons out of the bar.
3. A menu bar manager (Bartender, Ice, Hidden Bar) is hiding it. Reveal it
   there.

Then `open /Applications/Lich.app`. If the app isn't running at all
(`pgrep -x lich-menubar` prints nothing), try `open /Applications/Lich.app`.
If macOS refuses it, rebuild it on this Mac with
`brew reinstall lichbook && lich install`. The icon is optional: the CLI
does everything the menu does.

**Mac slept anyway.** Check `lich log 50` around the time it happened. The
usual causes are: it was on battery with no roam, the standing timer saw
`roam_mins` without input (`standing timer: idle … handed back`; remote
work like ssh or Claude doesn't count as input, so arm a trip for that),
the battery hit the floor, or the user logged out.

**Mac won't sleep.** If lich is at rest and `lich status` shows
`sleep: normal`, look at the `held awake by:` lines. Another app (a video
in a browser, Zoom, `caffeinate`) is holding it awake, not lich. After a
crash or hard reboot while risen, the Mac won't sleep at the login window
until someone logs in. That's documented, and the first login fixes it.

**Screen didn't lock on lid close.** The lock depends on System Settings →
Lock Screen → "Require password after screen saver begins or display is
turned off" being set to **Immediately**. Lock failures are logged as
warnings in `lich log`.
