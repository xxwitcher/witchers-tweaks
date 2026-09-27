import QtQuick
import Quickshell
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

  readonly property int defaultMinutes: 5
  readonly property var entry: {
    var plugins = shell && shell.shellConfig && Array.isArray(shell.shellConfig.plugins) ? shell.shellConfig.plugins : []
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
