import QtQuick
import Quickshell
import "../components"

Column {
  id: pane
  spacing: 22

  readonly property var suspendEntry: App.pluginEntry("witcher.idle-suspend")
  readonly property var profiles: String(App.status.powerProfiles || "").split(",").filter(function(p) { return p !== "" })

  function profileLabel(p) {
    return p === "power-saver" ? "Power saver" : p === "performance" ? "Performance" : p === "balanced" ? "Balanced" : p
  }

  Group {
    visible: pane.profiles.length > 0
    SegmentedRow {
      label: "Power mode"
      options: pane.profiles.map(function(p) { return { value: p, label: pane.profileLabel(p) } })
      current: App.status.powerProfile || ""
      onChosen: function(v) { App.apply(["powerprofilesctl", "set", v]) }
    }
  }

  Group {
    title: "When idle"
    SwitchRow {
      label: "Stay awake"
      checked: App.status.stayAwake === true
      onToggled: function(wanted) { App.apply(["omarchy-toggle-idle", wanted ? "stay-awake" : "allow-idle"]) }
    }
    SwitchRow {
      label: "Screensaver"
      sublabel: App.tweakOn("suspend") ? "Off while suspend is on" : ""
      checked: App.status.screensaverOff !== true
      switchEnabled: !App.tweakOn("suspend")
      onToggled: function(wanted) { if (wanted === (App.status.screensaverOff === true)) App.apply(["omarchy-toggle-screensaver"]) }
    }
    TweakRow { tweak: "suspend"; label: "Suspend when idle" }
    ChoiceRow {
      visible: App.tweakOn("suspend")
      label: "Suspend after"
      options: [1, 5, 10, 15, 30, 60].map(function(n) { return { value: n, label: n === 1 ? "1 minute" : n + " minutes" } })
      current: pane.suspendEntry && pane.suspendEntry.minutes ? pane.suspendEntry.minutes : 5
      onChosen: function(v) { App.apply([App.helperPath, "suspend-minutes", String(v)]) }
    }
  }

  Group {
    title: "Battery"
    visible: App.status.laptop === true
    TweakRow { tweak: "battery"; label: "Show battery percentage in the top bar" }
  }

  Group {
    title: "Hibernation"
    SettingRow {
      label: App.status.hibernation ? "Hibernation is set up" : "Hibernation"
      PillButton {
        text: App.status.hibernation ? "Remove" : "Set Up…"
        danger: App.status.hibernation === true
        onClicked: App.terminal(App.status.hibernation ? "omarchy-hibernation-remove" : "omarchy-hibernation-setup")
      }
    }
  }

}
