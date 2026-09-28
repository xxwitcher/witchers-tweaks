import QtQuick
import Quickshell
import "../components"

// About this computer, software updates, date and time, passwords, startup
// and reset. Steps that need a password open in Omarchy's floating terminal.
Column {
  id: pane
  spacing: 22

  property var zones: []
  Component.onCompleted: App.helper(["timezones"], function(out) {
    try { pane.zones = JSON.parse(out) } catch (e) {}
  })

  Group {
    title: "About"
    InfoRow { label: "Computer"; value: App.status.machine || App.status.hostname || "" }
    InfoRow { label: "Name"; value: App.status.hostname || "" }
    InfoRow { label: "Processor"; value: App.status.cpu || "" }
    InfoRow { label: "Memory"; value: App.status.memory || "" }
    InfoRow { label: "Omarchy"; value: (App.status.version || "") + (App.status.channel ? " (" + App.status.channel + ")" : "") }
    InfoRow { label: "Kernel"; value: App.status.kernel || "" }
  }

  Group {
    title: "Software Update"
    ButtonRow {
      label: "Update Omarchy"
      buttonText: "Update Now"
      prominent: true
      onClicked: App.terminal("omarchy-update")
    }
    ChoiceRow {
      label: "Update channel"
      options: [
        { value: "stable", label: "Stable" },
        { value: "rc", label: "Release candidate" },
        { value: "edge", label: "Edge" },
        { value: "dev", label: "Development" }
      ]
      current: App.status.channel || "stable"
      onChosen: function(v) {
        App.confirm({ title: "Switch to the " + v + " channel?", text: "Omarchy will update from that channel from now on. A terminal opens to do it.",
          action: "Switch", onAccept: function() { App.terminal("omarchy-channel-set " + v) } })
      }
    }
    ButtonRow { label: "Update extra themes"; buttonText: "Update"; onClicked: App.terminal("omarchy-theme-update") }
    ButtonRow { label: "Update firmware"; buttonText: "Update"; onClicked: App.terminal("omarchy-update-firmware") }
  }

  Group {
    title: "Date & Time"
    ChoiceRow {
      label: "Time zone"
      options: pane.zones
      searchable: true
      buttonWidth: 260
      current: App.status.timezone || ""
      onChosen: function(v) {
        App.run(["timedatectl", "set-timezone", v], function(out, code) {
          if (code === 0) {
            App.detached(["omarchy-shell", "-q", "omarchy.clock", "refresh"])
            App.toast("Time zone set to " + v)
          } else {
            App.terminal("sudo timedatectl set-timezone " + v + " && omarchy-shell -q omarchy.clock refresh")
          }
          App.refresh()
        })
      }
    }
    ButtonRow { label: "Set the time from the internet"; buttonText: "Sync Now"; onClicked: App.terminal("omarchy-update-time") }
  }


  Group {
    title: "Startup"
    ButtonRow {
      label: "Direct boot"
      buttonText: "Set Up…"
      onClicked: App.terminal("omarchy-setup-direct-boot")
    }
  }

  Group {
    title: "Reset"
    ButtonRow {
      label: "Reset this computer"
      buttonText: "Reset…"
      danger: true
      onClicked: App.confirm({ title: "Reset this computer?", text: "This erases all your files and settings and reinstalls Omarchy. It can't be undone.",
        action: "Reset", danger: true, onAccept: function() { App.terminal("omarchy-system-factory-reset") } })
    }
  }
}
