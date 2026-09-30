import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Suspends the machine after `minutes` of inactivity, set on this plugin's
// entry in ~/.config/omarchy/shell.json:
//
//   "plugins": [{ "id": "witcher.idle-suspend", "minutes": 5 }]
//
// Omarchy's idle service only runs the screensaver and the lock, so this sits
// next to it. It suspends the way Omarchy's menu does (systemctl suspend),
// which locks the screen first through omarchy-sleep-lock. Idle inhibitors
// (a playing video) hold it off, and so does Omarchy's "stay awake" toggle.
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
      try { root.fileConfig = JSON.parse(text()) } catch (e) { console.warn("witcher.idle-suspend: bad shell.json", e) }
    }
    onFileChanged: reload()
  }
  readonly property var shellConfig: shell && shell.shellConfig ? shell.shellConfig : fileConfig

  readonly property int defaultMinutes: 5
  readonly property var entry: {
    var plugins = shellConfig && Array.isArray(shellConfig.plugins) ? shellConfig.plugins : []
    for (var i = 0; i < plugins.length; i++)
      if (plugins[i] && plugins[i].id === "witcher.idle-suspend") return plugins[i]
    return ({})
  }
  readonly property int minutes: {
    var n = Number(entry.minutes)
    return isFinite(n) && n >= 1 ? Math.floor(n) : defaultMinutes
  }

  IdleMonitor {
    id: idleMonitor
    enabled: true
    timeout: root.minutes * 60
    respectInhibitors: true
    onIsIdleChanged: {
      if (!isIdle) return
      console.log("witcher.idle-suspend: idle for " + root.minutes + "m, suspending")
      Quickshell.execDetached(["bash", "-c",
        "[[ -f \"$HOME/.local/state/omarchy/indicators/stay-awake\" ]] || systemctl suspend"])
    }
  }
}
