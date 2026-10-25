# System Check — Omarchy bar widget

One bar icon for the two things that quietly rot an Arch/Omarchy machine:
**pending package updates** and **damage left behind by an interrupted update**
(orphans, broken pacman DB entries, stale `db.lck`, unmerged `.pacnew` files,
failed units, failed initramfs generation).

Click the icon and you get the exact commands for *this* machine in a window you
can select with the mouse, with **Copy**, **Run in terminal**, **Defer to next
boot**, and **Close** buttons.

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

### Installing on another machine (agent instructions)

Everything below runs as your user. There is no `sudo` step and no service,
timer or file outside the plugin directory; the checks are read-only.

```bash
# 1. install and enable
omarchy plugin add https://github.com/ssearles/omarchy-system-check.git --enable

# 2. reload the shell - required, and not optional
omarchy restart shell

# 3. wait for the first poll, then read the verdict without a mouse
sleep 20
omarchy-shell ssearles.system-check state
omarchy-shell ssearles.system-check tooltip
```

A healthy machine prints something like:

```
{"known":true,"deferred":false,"checked":"8:46 PM","issues":false,"summary":"",
 "detail":"","lastUpdate":"2026-10-24T13:41:06-0700",
 "lastUpdateHuman":"today 1:41 PM","omarchy":"up to date"}

System check: all clear — checked 8:46 PM · last update: today 1:41 PM · Omarchy up to date
```

`omarchy restart shell` is the step that catches people out: the plugin is
instantiated once, and neither `rescanPlugins` nor the "Local plugin changed,
reloading" log line re-reads a widget that already exists. Without the restart
the IPC target does not exist and the bar shows nothing.

`"known":false` right after install is normal for the first ~20 seconds — the
first poll runs at shell start and may still be waiting on the mirrors. If it
is still false after a minute, run `omarchy-shell ssearles.system-check refresh`
and read the `detail` field for the reason.

To confirm it is wired into the bar at all:

```bash
omarchy bar list | grep system-check     # present
omarchy-shell ssearles.system-check open # opens the same popup a click does
```

Removal is one command (see [Removal](#removal)).

## Use

Click the icon. The popup lists the commands to paste into a terminal:

Clicking the icon again does not stack more windows: the popup is a single
application, so the click brings the open window forward instead.

- **Copy commands** — puts the block on the clipboard.
- **Run in terminal** — opens a floating terminal that shows the commands and
  asks before running anything. Repairs and the update are asked for
  **separately** (`Run these repairs now?` then `Run omarchy update now?`), so
  agreeing to a repair never drags the update — and its reboot prompt — along.
  Both prompts read `[y/N] (Enter = no)`: pressing Enter, or answering anything
  other than `y`/`yes`, skips that job.
- **Defer to next boot** — hides the icon until the machine restarts. The flag
  lives in `$XDG_RUNTIME_DIR`, so it disappears on reboot with no cleanup.
- **Close** — dismisses the window without deferring, so the icon keeps showing
  the finding. Closing the window with the titlebar × does the same; only
  **Defer to next boot** sets the flag.

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
| `pacman -Dk` | dependency sanity (broken or missing dependency links) |
| `systemctl --failed` | failed units |
| `find /etc -name '*.pacnew'` | unmerged config files from an update |
| `tail`/`grep` on `/var/log/pacman.log` | aborted transactions (started vs completed) |
| `/var/lib/pacman/local/*/desc` | local DB entries cut short by an interrupted write |
| `/tmp/omarchy-update.log` | initramfs or hook failure from the last update |

`pacman -Qkk` (verify every installed file against its mtree) is deliberately
not part of the check: it is slow, it is noisy on a healthy Arch install, and it
answers "are these files intact" rather than "did an update stop halfway". Run
it by hand if you want that answer.

Suggested repairs are printed, never executed. Judgement calls carry a
`# review:` note next to the command — the orphan sweep, for instance, says to
check `pacman -Qi <pkg>` first, because "nothing depends on it" is not the same
as "you did not install it on purpose". Comments are inert, so they travel with
the command without ever running.

## Tests

```bash
tests/run-tests.sh      # 161 assertions, no sudo, no real pacman
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

## Marketplace listing (not yet submitted)

This plugin is deliberately **unlisted**. When it is submitted, everything the
marketplace asks for is already in this repository:

| Requirement | Here |
|---|---|
| Public repo, one plugin, `manifest.json` at the root | yes |
| README with install *and* removal instructions | `## Install`, `## Removal` |
| Root license, dependencies documented | `LICENSE`, `## Requirements` |
| Plugin ID outside the reserved `omarchy.*` namespace | `ssearles.system-check` |
| Optional root `preview.png` | not present |

Submission goes through the issue form:

<https://github.com/omacom/omarchy-plugin-marketplace/issues/new?template=submit-plugin.yml>

or, for an agent, a `submission`-labelled issue whose body follows
[SUBMISSION.md](https://github.com/omacom/omarchy-plugin-marketplace/blob/main/SUBMISSION.md):

```
### Repository URL
https://github.com/ssearles/omarchy-system-check

### Category
System

### Tags
bar, quickshell, system

### Submission checklist
- [x] The repository is public and contains installation and removal instructions.
- [x] I have documented the plugin license and any external dependencies.
- [x] I confirm that I own or have permission to submit this plugin and its preview assets.
- [x] The plugin does not overwrite user configuration without explicit consent.
- [x] I understand that approval is for listing and is not a security review.
```

Category is case-sensitive (`System`); one to three tags from the marketplace's
fixed list. A listing requires a fresh scan of an **exact commit**, so tag or
record the SHA being submitted rather than pointing at a moving `main`:

```bash
git rev-parse HEAD
```

The marketplace's automated baseline is structural and compatibility checking,
not a security review — which is also why this plugin only ever prints repair
commands and asks before running them.

## License

MIT — see [LICENSE](LICENSE).
