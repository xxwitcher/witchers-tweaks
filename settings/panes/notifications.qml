import QtQuick
import Quickshell
import "../components"

Column {
  id: pane
  spacing: 22

  readonly property var timeout: App.pluginEntry("witcher.notify-timeout")

  Group {
    SwitchRow {
      label: "Do Not Disturb"
      icon: "weather-clear-night-symbolic"
      iconColor: "#5e5ce6"
      checked: App.status.dnd === true
      onToggled: function(wanted) { App.apply(["omarchy-shell", "notifications", "setDnd", wanted ? "true" : "false"]) }
    }
  }

  Group {
    title: "How long they stay"
    TweakRow { tweak: "notifytimeout"; label: "Dismiss automatically" }
    ChoiceRow {
      visible: App.tweakOn("notifytimeout")
      label: "Leave the screen after"
      options: [3, 5, 8, 10, 15].map(function(n) { return { value: n, label: n + " seconds" } })
      current: pane.timeout && pane.timeout.seconds ? pane.timeout.seconds : 5
      onChosen: function(v) { App.apply([App.helperPath, "notify-seconds", String(v)]) }
    }
  }

  Group {
    title: "Menu bar"
    TweakRow { tweak: "bell"; label: "Notification bell" }
  }
}
