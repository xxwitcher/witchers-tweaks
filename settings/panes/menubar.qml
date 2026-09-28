import QtQuick
import Quickshell
import "../components"

// Omarchy's menu bar (omarchy-bar) and the bar tweaks.
Column {
  id: pane
  spacing: 22

  readonly property var bar: App.shellConfig && App.shellConfig.bar ? App.shellConfig.bar : ({})

  Group {
    SwitchRow {
      label: "Show the top bar"
      icon: "open-menu-symbolic"
      iconColor: "#636366"
      // Autohide shows and hides it by itself.
      sublabel: App.tweakOn("autohide") ? "Managed by autohide" : ""
      checked: App.tweakOn("autohide") || App.status.barHidden !== true
      switchEnabled: !App.tweakOn("autohide")
      onToggled: function(wanted) { App.apply(["omarchy-toggle-bar", wanted ? "off" : "on"]) }
    }
    TweakRow { tweak: "autohide"; label: "Automatically hide and show the top bar" }
    SegmentedRow {
      label: "Position"
      options: [
        { value: "top", label: "Top" },
        { value: "bottom", label: "Bottom" },
        { value: "left", label: "Left" },
        { value: "right", label: "Right" }
      ]
      current: pane.bar.position || "top"
      onChosen: function(v) { App.apply([App.helperPath, "bar-set", "position", JSON.stringify(v)]) }
    }
    SwitchRow {
      label: "Transparent background"
      checked: pane.bar.transparent === true
      onToggled: function(wanted) { App.apply([App.helperPath, "bar-set", "transparent", JSON.stringify(wanted)]) }
    }
  }

  Group {
    title: "On the top bar"
    TweakRow { tweak: "clock"; label: "Clock in the middle" }
    TweakRow { tweak: "battery"; label: "Battery percentage" }
    TweakRow { tweak: "bell"; label: "Notification bell" }
    TweakRow { tweak: "agentchat"; label: "Agent widget" }
    ButtonRow {
      label: "Other widgets"
      buttonText: "Shell Plugins"
      onClicked: shellRoot.select("plugins")
    }
  }
}
