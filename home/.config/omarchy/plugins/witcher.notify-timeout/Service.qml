import QtQuick
import Quickshell
import Quickshell.Io

// Takes every notification off the screen a few seconds after it appears.
// Omarchy's own timer keeps normal toasts up for 8s (longer if the sender
// asks) and critical ones until they're clicked; this caps all of them. The
// time is the `seconds` setting on this plugin's entry in
// ~/.config/omarchy/shell.json (default 5):
//
//   "plugins": [{ "id": "witcher.notify-timeout", "seconds": 5 }]
//
// It doesn't replace omarchy.notifications (the DND indicator looks that
// service up by id). It drives the stock service instead, through the same
// expirePopup() its own timer calls, so an expired toast lands in history
// exactly as if it had run out on its own.
Item {
  id: root
  visible: false

  property var shell: null

  // Omarchy 4.0.3 and later hand plugins a scoped shell without shellConfig;
  // there the settings are read straight from shell.json.
  property var fileConfig: ({})
  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      try { root.fileConfig = JSON.parse(text()) } catch (e) { console.warn("witcher.notify-timeout: bad shell.json", e) }
    }
    onFileChanged: reload()
  }
  readonly property var shellConfig: shell && shell.shellConfig ? shell.shellConfig : fileConfig

  readonly property var entry: {
    var plugins = shellConfig && Array.isArray(shellConfig.plugins) ? shellConfig.plugins : []
    for (var i = 0; i < plugins.length; i++)
      if (plugins[i] && plugins[i].id === "witcher.notify-timeout") return plugins[i]
    return ({})
  }
  readonly property int lifetimeMs: {
    var seconds = Number(entry.seconds)
    return (isFinite(seconds) && seconds >= 1 ? seconds : 5) * 1000
  }

  // First time each on-screen popup was seen, keyed by its history file stem
  // (timestamp-id), with the text it had then.
  property var seen: ({})

  function notificationService() {
    return shell && typeof shell.firstPartyServiceFor === "function"
      ? shell.firstPartyServiceFor("omarchy.notifications") : null
  }

  // The scoped shell of Omarchy 4.0.3 and later has no way to the service,
  // so bin/expire-popups does the same from outside, through its IPC.
  Process {
    running: root.shell !== null && !("shellConfig" in root.shell)
    command: [String(Qt.resolvedUrl("bin/expire-popups")).replace(/^file:\/\//, "")]
  }

  function sweep() {
    var service = notificationService()
    var model = service ? service.popupModel : null
    if (!model) return

    var now = Date.now()
    var next = ({})
    var expired = []
    for (var i = 0; i < model.count; i++) {
      var row = model.get(i)
      if (!row) continue
      var key = String(row.timestamp || 0) + "-" + String(row.originalId || 0)
      var text = String(row.summary || "") + "\n" + String(row.body || "")
      var entry = seen[key]
      // A sender updating a toast in place gets a fresh countdown, like the
      // stock timer gives it.
      if (!entry || entry.text !== text) entry = { since: now, text: text }
      next[key] = entry
      if (now - entry.since >= lifetimeMs) expired.push(i)
    }
    seen = next

    // Highest index first so the earlier indexes stay valid.
    for (var j = expired.length - 1; j >= 0; j--) service.expirePopup(expired[j])
  }

  Timer {
    interval: 250
    repeat: true
    running: true
    onTriggered: root.sweep()
  }
}
