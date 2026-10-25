# System Check — Omarchy bar widget

One bar icon for the two things that quietly rot an Arch/Omarchy machine:
**pending package updates** and **damage left behind by an interrupted update**
(orphans, broken pacman DB entries, stale `db.lck`, unmerged `.pacnew` files,
failed units, failed initramfs generation).

Click the icon and you get the exact commands for *this* machine in a window you
can select with the mouse, with **Copy**, **Run in terminal**, and **Defer**
buttons.

Nothing is ever run for you. Every check is read-only, no `sudo`, and the plugin
does not install services or timers.

## What the icon means

One heartbeat glyph, always in the same place; the colour carries the state.

| Colour | Meaning |
|---|---|
| green | checked, nothing pending |
| amber | deferred until next boot, or a half of the check was skipped |
| red | findings — hover for the details |

The tooltip shows the finding, e.g. `7 orphaned package(s) — checked 7:25 PM`, or
the reason a check could not run, plus when the last full upgrade finished:

```
System check: all clear — checked 8:34 PM · last update: today 1:41 PM · Omarchy up to date
```

Three separate facts, deliberately not merged: when the check last ran, when
this machine last upgraded, and what the mirrors currently say about Omarchy
itself.

The colour is contrast-guarded against the bar background. A theme with a red,
green or yellow bar would otherwise hide the matching state, so the icon keeps
its hue — that is the meaning — and shifts only its lightness, and only as far
as needed, until it is a clearly different colour from the bar behind it.
Distance is measured in Lab (`ΔE`), not luminance: the green glyph on a blue bar
has a contrast ratio of just 1.19 yet reads fine, because the hue carries it.
On a transparent bar the wallpaper is unknown, so the colour is left alone.

A different hue is not enough for a thin glyph: green on a light blue bar is a
different colour but the same lightness, so it reads as a smudge. The glyph is
therefore drawn twice — a slightly larger copy in the bar's own foreground
behind the state colour — so its edge survives a background of similar
lightness, including a wallpaper behind a transparent bar.

A skipped check is never shown as green: if `pacman` is busy, or `checkupdates`
cannot reach the mirrors, the icon stays amber with the reason in the tooltip.
Colour is the fast read and the tooltip is the accessible one, so the state never
depends on colour alone.

## Install

```bash
omarchy plugin add https://github.com/ssearles/omarchy-system-check.git --enable
```

If it is not on the bar yet:

```bash
omarchy bar move ssearles.system-check --section right
```

The widget is added to the right section by default.

## Use

Click the icon. The popup lists the commands to paste into a terminal:

- **Copy commands** — puts the block on the clipboard.
- **Run in terminal** — opens a floating terminal that shows the commands and
  asks before running anything. Repairs and the update are asked for
  **separately** (`Run these repairs now?` then `Run omarchy update now?`), so
  agreeing to a repair never drags the update — and its reboot prompt — along.
- **Defer to next boot** — hides the icon until the machine restarts. Closing
  the window has the same effect. The flag lives in `$XDG_RUNTIME_DIR`, so it
  disappears on reboot with no cleanup.

### What the popup shows

Only what applies, in a fixed order:

- **Health** repairs, when something is wrong.
- **Updates** with `omarchy update`, only when packages are actually pending.
  If the machine is up to date, that line is absent and the notes say so.
- **Health/Updates — could not check**, when a half of the check was skipped,
  instead of pretending there is nothing to do.

Health repairs come **first** when both apply, because a stale `db.lck` or a
damaged pacman DB makes `omarchy update` fail — and `omarchy update` ends by
offering a reboot, so anything that must happen on this boot goes before it.

The icon re-checks at shell start, hourly, and right after the popup closes.

From a terminal:

```bash
omarchy-shell ssearles.system-check state     # {"known":true,"issues":true,...}
omarchy-shell ssearles.system-check refresh   # re-run the checks now
omarchy-shell ssearles.system-check open      # same code path as clicking
```

### Last update vs update required

The `last update:` part of the tooltip is local history: the completion time of
the most recent `pacman -Syu` in `/var/log/pacman.log`. Other transactions are
deliberately ignored — the orphan sweep the popup offers is `pacman -Rns`, and
installing one package is `pacman -S`, neither of which is an update. If the log
has no completed `-Syu`, the line is simply omitted rather than guessed.

Whether an update is **required** is a separate question, and a remote one:
`checkupdates` compares the local database against the mirrors. If it cannot
reach them, the icon stays amber with `could not check` — it never infers "up to
date" from the last-update date. The date is context; the mirror check is the
verdict.

`bin/omarchy-last-update` prints it on its own: ISO 8601 by default, `--human`
for `today 1:41 PM`, `--days` for an integer.

### The Omarchy verdict

The `Omarchy` part of the tooltip answers the narrower question: **does
upstream have a new Omarchy release for this machine?** That is the same check
the first-party `omarchy.system-update` bar widget runs at login, via
`omarchy-update-available` — it looks for the `omarchy` package in
`checkupdates` output. `bin/omarchy-update-check --omarchy` exposes it:

```
$ omarchy-update-check --omarchy
up to date              # checked against the mirrors, nothing new
omarchy 4.1.0-1 -> 4.2.0-1   # an update is available
                        # (empty) could not check
```

It is a remote answer, so it is not derived from the local timestamp: a machine
that upgraded an hour ago can still have an Omarchy update waiting, and the
laptop that surprised you with an update prompt after a reboot is exactly that
case. When the check cannot run, the field is empty and the tooltip omits it
rather than claiming "up to date".

The JSON carries it as `omarchy` (`"up to date"`, `"update available"`, or
`""`), on every path including `deferred`.

## What it runs

Read-only commands, all as your user:

| Command | Purpose |
|---|---|
| `checkupdates` | pending package updates (temporary DB, never touches `/var/lib/pacman`) |
| `omarchy-update-available` | whether the mirrors have a new Omarchy release |
| `pacman -Qtdq` | orphaned packages |
| `pacman -Dk`, `pacman -Qkk` | pacman DB consistency |
| `pacman -Qm`, `pacman -Qn` | foreign/foreigner checks |
| `systemctl --failed` | failed units |
| `journalctl`, `/tmp/omarchy-update.log` | interrupted update / initramfs failures |

Suggested repairs are printed, never executed. Judgement calls carry a
`# review:` note next to the command — the orphan sweep, for instance, says to
check `pacman -Qi <pkg>` first, because "nothing depends on it" is not the same
as "you did not install it on purpose". Comments are inert, so they travel with
the command without ever running.

## Tests

```bash
tests/run-tests.sh      # 128 assertions, no sudo, no real pacman
node tests/contrast.test.js   # the 52 colour assertions on their own
```

Every external command is a stub in a throwaway `HOME`, and the health check's
system paths point at fixtures through `OMARCHY_PACMAN_DB`, `OMARCHY_PACMAN_LOG`,
`OMARCHY_ETC_DIR` and `OMARCHY_UPDATE_LOG`. The suite covers the exit-code
contracts (`checkupdates` 0/2/other, health check 0/1/2/3), the JSON key set on
every path, popup ordering, the `[y/N]` gate, and the state colour against a
sweep of same-hue bar backgrounds. The colour maths lives in `lib/contrast.js`
rather than inside the QML so those tests exercise the code the widget actually
runs.

## Requirements

- Omarchy with the Quattro shell (`omarchy-shell`)
- `pacman-contrib` for `checkupdates`
- `python-gobject` for the popup (part of Omarchy's base packages)
- `jq` for the widget's JSON mode
- `wl-clipboard` (`wl-copy`) for the Copy button — without it the text is still
  selectable with the mouse

`zenity` is **not** required and not used: it does not ship with Omarchy.

Arch-only by design: the checks are pacman and systemd specific.

## Removal

```bash
omarchy plugin remove ssearles.system-check
```

Nothing else is left behind: no services, no timers, no files outside the plugin
directory (the defer flag lives in `$XDG_RUNTIME_DIR`).

## License

MIT — see [LICENSE](LICENSE).
