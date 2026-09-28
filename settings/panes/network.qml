import QtQuick
import Quickshell
import Quickshell.Networking
import "../components"

// Wired connection and DNS (omarchy-dns).
Column {
  id: pane
  spacing: 22

  readonly property var devices: Networking.devices ? Networking.devices.values : []
  readonly property var wired: devices.filter(function(d) { return d && d.type === DeviceType.Wired })

  Group {
    title: "Connections"
    Repeater {
      model: pane.wired
      InfoRow {
        required property var modelData
        label: "Ethernet (" + modelData.name + ")"
        value: modelData.connected ? "Connected" + (modelData.linkSpeed ? " · " + modelData.linkSpeed + " Mb/s" : "") : (modelData.hasLink ? "Cable plugged in" : "Not connected")
      }
    }
    InfoRow {
      label: "Wi-Fi"
      value: Networking.wifiEnabled ? "On" : "Off"
    }
  }

  Group {
    title: "DNS"
    ChoiceRow {
      label: "DNS servers"
      options: [
        { value: "DHCP", label: "Automatic (from the network)" },
        { value: "Cloudflare", label: "Cloudflare" },
        { value: "Google", label: "Google" },
        { value: "Custom", label: "Custom…" }
      ]
      current: App.status.dns || "DHCP"
      onChosen: function(v) {
        if (v === "Custom") App.terminal("omarchy-dns Custom")
        else App.apply(["omarchy-dns", v], "DNS set to " + v)
      }
    }
  }
}
