import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "lib/contrast.js" as Contrast

// System Check — a bar icon for pending updates and post-update health problems.
//
// One heartbeat glyph, always in the same place; the colour carries the state:
//   green -> checked and clean
//   amber -> deferred, or a half of the check was skipped
//   red   -> findings, tooltip carries them
// The colour is contrast-guarded against the bar background, so a red, green or
// yellow bar cannot hide the matching state.
//
// Clicking runs bin/omarchy-cleanup-popup: the exact repair commands, selectable
// with the mouse, plus Copy and Defer. Everything is read-only; nothing is
// installed or run without the user pasting it into a terminal.
BarWidget {
  id: root
  moduleName: "ssearles.system-check"

  // Resolve the bundled scripts relative to this QML file, so the plugin works
  // from wherever `omarchy plugin add` cloned it.
  readonly property string binDir: Qt.resolvedUrl("bin").toString().replace(/^file:\/\//, "")
  readonly property string checkScript: root.binDir + "/omarchy-system-check"
  readonly property string popupScript: root.binDir + "/omarchy-cleanup-popup"

  property bool known: false
  property bool hasIssues: false
  // Deferred from the popup: visible as its own state, never as "all clear".
  property bool deferred: false
  property string lastChecked: ""
  // Set when the user clicks a clean icon: confirm with an OSD after the recheck.
  property bool confirmOnFinish: false
  property bool healthIssue: false
  property string summary: ""
  property string detail: ""
  // When the last full upgrade completed. Context, not a verdict: whether an
  // update is *needed* comes from checkupdates against the mirrors, and the
  // amber "could not check" state exists because that answer can be unknown.
  property string lastUpdate: ""
  property string lastUpdateHuman: ""
  // Synchronous guard: Process.running is not yet true in the same tick, so a
  // timer tick plus an IPC refresh could otherwise start two checks.
  property bool busy: false

  function refresh() {
    if (root.busy) return
    root.busy = true
    checkProc.running = true
  }

  function openCleanup() {
    if (root.hasIssues) {
      if (root.bar) root.bar.run(Util.shellQuote(root.popupScript))
      return
    }

    // Clean or deferred: a click still has to do something visible. Re-check and
    // confirm in the OSD, so the click is acknowledged without opening a window.
    root.confirmOnFinish = true
    root.refresh()
  }

  // Fixed semantic colours, not theme slots: theme palettes do not map to
  // meanings (Lupine's "red" is magenta, its "yellow" is blue, its "green" is
  // purple), so Commons.Color.urgent would not read as an error.
  readonly property color baseStateColor: root.hasIssues
    ? "#e05252"
    : ((!root.known || root.deferred) ? "#e5c07b" : "#8ec07c")

  // The colour alone is not enough: a theme whose bar background is red, green
  // or yellow would swallow the matching state colour. lib/contrast.js keeps
  // the hue - that is the meaning - and moves only the lightness until the
  // glyph separates from what is behind it.
  //
  // A transparent bar has no known backdrop (the wallpaper shows through), so
  // there is nothing to measure against and the colour is left alone.
  readonly property color barBackground: (root.bar && !root.bar.transparent)
    ? root.bar.background : "transparent"

  readonly property color stateColor: Contrast.readableOn(root.baseStateColor, root.barBackground)

  // A different hue is not enough for a thin glyph: green on a light blue bar
  // is a different colour but the same lightness, so it reads as a smudge.
  // Draw a slightly larger copy of the glyph underneath in the bar's own
  // foreground - the colour the theme already promises is readable on this
  // backdrop - and the edge survives any background, including a wallpaper
  // behind a transparent bar.
  readonly property color outlineColor: {
    var base = root.bar && root.bar.barForeground ? root.bar.barForeground : "#000000"
    return Qt.rgba(base.r, base.g, base.b, 0.65)
  }

  // The whole tooltip in one place: the button binds to it, and the IPC
  // `tooltip` method returns it, so the wording can be checked without a mouse.
  readonly property string statusTooltip: (root.hasIssues
    ? (root.detail !== "" ? root.detail : root.summary)
      + (root.lastChecked !== "" ? " — checked " + root.lastChecked : "")
    : (!root.known
        ? "System check: " + (root.detail !== "" ? root.detail : "could not check")
        : (root.deferred
            ? "System check: deferred until next boot"
            : "System check: all clear"
              + (root.lastChecked !== "" ? " — checked " + root.lastChecked : ""))))
    + (root.lastUpdateHuman !== "" ? " · last update: " + root.lastUpdateHuman : "")

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  IpcHandler {
    target: "ssearles.system-check"

    function refresh(): void {
      root.refresh()
    }

    // Same path a click takes, so the popup can be exercised from a terminal:
    //   omarchy-shell ssearles.system-check open
    function open(): void {
      root.openCleanup()
    }

    function tooltip(): string {
      return root.statusTooltip
    }

    function state(): string {
      return JSON.stringify({
        known: root.known,
        deferred: root.deferred,
        checked: root.lastChecked,
        issues: root.hasIssues,
        summary: root.summary,
        detail: root.detail,
        lastUpdate: root.lastUpdate,
        lastUpdateHuman: root.lastUpdateHuman
      })
    }
  }

  Process {
    id: checkProc
    command: [root.checkScript, "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed
        try {
          parsed = JSON.parse(text || "{}")
        } catch (e) {
          return
        }

        root.lastUpdate = parsed.lastUpdate || ""
        root.lastUpdateHuman = parsed.lastUpdateHuman || ""

        // Deferred from the popup: show clean until the next boot.
        if (parsed.deferred) {
          root.known = true
          root.deferred = true
          root.hasIssues = false
          root.healthIssue = false
          root.summary = ""
          root.detail = ""
          return
        }

        root.known = parsed.known !== false
        root.deferred = false
        root.lastChecked = Qt.formatTime(new Date(), "h:mm AP")
        root.hasIssues = (parsed.summary || "") !== ""
        root.healthIssue = (parsed.health || 0) > 0
        root.summary = parsed.summary || ""
        root.detail = parsed.detail || ""

        if (root.confirmOnFinish) {
          root.confirmOnFinish = false
          if (!root.hasIssues && root.known && root.bar) {
            // A notification, not the OSD: the OSD is pinned to bottom-center
            // by the shell and renders icons with its own font (a raw Nerd
            // Font codepoint came out as a muted speaker there). A toast lands
            // in the notification corner and takes a freedesktop icon name.
            root.bar.run("notify-send --app-name=" + Util.shellQuote("System Check")
              + " -i " + Util.shellQuote("dialog-information")
              + " " + Util.shellQuote(root.deferred ? "Deferred to next boot" : "All clear")
              + " " + Util.shellQuote(root.deferred
                  ? "The icon stays hidden until the machine restarts."
                  : "No pending updates or repairs."))
          }
        }
      }
    }
    onExited: function(exitCode) {
      root.busy = false
      root.confirmOnFinish = false
    }
    // A failed run keeps the previous state rather than pretending all is well.
  }

  Timer {
    interval: 3600000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // One glyph, always in the same place; the colour carries the state:
    // green = checked and clean, amber = deferred or could not check,
    // red = findings. The tooltip spells it out in words.
    //
    // Drawn as iconComponent rather than `text` so the outline can sit behind
    // the fill: a 2 px larger copy in the bar foreground, then the state
    // colour on top.
    text: ""
    iconComponent: Component {
      Item {
        OpticalGlyph {
          anchors.centerIn: parent
          text: "\uf21e"
          fontSize: Style.font.caption + 2
          color: root.outlineColor
        }
        OpticalGlyph {
          anchors.centerIn: parent
          text: "\uf21e"
          fontSize: Style.font.caption
          color: root.stateColor
        }
      }
    }
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    foreground: root.stateColor
    tooltipText: root.statusTooltip
    onPressed: root.openCleanup()
  }
}
