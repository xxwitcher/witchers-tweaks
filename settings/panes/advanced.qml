import QtQuick
import Quickshell
import "../components"

// Config files, restarts and refreshes, for when something needs a nudge.
Column {
  id: pane
  spacing: 22

  Group {
    title: "Config files"
    ButtonRow { label: "Hyprland"; sublabel: "hyprland.lua"; buttonText: "Edit…"; onClicked: App.editConfig(App.home + "/.config/hypr/hyprland.lua") }
    ButtonRow { label: "Look and feel"; sublabel: "looknfeel.lua"; buttonText: "Edit…"; onClicked: App.editConfig(App.home + "/.config/hypr/looknfeel.lua") }
    ButtonRow { label: "Input"; sublabel: "input.lua"; buttonText: "Edit…"; onClicked: App.editConfig(App.home + "/.config/hypr/input.lua") }
    ButtonRow { label: "Keybindings"; sublabel: "bindings.lua"; buttonText: "Edit…"; onClicked: App.editConfig(App.home + "/.config/hypr/bindings.lua") }
    ButtonRow { label: "Monitors"; sublabel: "monitors.lua"; buttonText: "Edit…"; onClicked: App.editConfig(App.home + "/.config/hypr/monitors.lua") }
    ButtonRow { label: "Night light"; sublabel: "hyprsunset.conf"; buttonText: "Edit…"; onClicked: App.shDetached("omarchy-launch-config-editor ~/.config/hypr/hyprsunset.conf && omarchy-restart-hyprsunset") }
    ButtonRow { label: "Compose keys"; sublabel: ".XCompose"; buttonText: "Edit…"; onClicked: App.shDetached("omarchy-launch-config-editor ~/.XCompose && omarchy-restart-xcompose") }
  }

  Group {
    title: "Restart"
    ButtonRow { label: "Omarchy shell"; buttonText: "Restart"; onClicked: App.detached(["omarchy-restart-shell"]) }
    ButtonRow { label: "Night light"; buttonText: "Restart"; onClicked: App.detached(["omarchy-restart-hyprsunset"]) }
    ButtonRow { label: "Audio"; buttonText: "Restart"; onClicked: App.terminal("omarchy-restart-audio") }
    ButtonRow { label: "Wi-Fi"; buttonText: "Restart"; onClicked: App.terminal("omarchy-restart-wifi") }
    ButtonRow { label: "Bluetooth"; buttonText: "Restart"; onClicked: App.terminal("omarchy-restart-bluetooth") }
    ButtonRow { label: "Trackpad"; buttonText: "Restart"; onClicked: App.terminal("omarchy-restart-trackpad") }
  }

  Group {
    title: "Reset to Omarchy's defaults"
    ButtonRow { label: "Hyprland config"; buttonText: "Refresh…"; onClicked: App.terminal("omarchy-refresh-hyprland") }
    ButtonRow { label: "Night light config"; buttonText: "Refresh…"; onClicked: App.terminal("omarchy-refresh-hyprsunset") }
    ButtonRow { label: "Boot screen"; buttonText: "Refresh…"; onClicked: App.terminal("omarchy-refresh-plymouth") }
    ButtonRow { label: "tmux config"; buttonText: "Refresh…"; onClicked: App.terminal("omarchy-refresh-tmux") }
    ButtonRow { label: "Shell config"; buttonText: "Refresh…"; onClicked: App.terminal("omarchy-refresh-shell") }
  }
}
