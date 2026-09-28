import QtQuick
import Quickshell
import Quickshell.Bluetooth
import "../components"

// Bluetooth (Quickshell.Bluetooth): on/off, your devices, and nearby ones to
// pair while this pane is open.
Column {
  id: pane
  spacing: 22

  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property var devices: adapter && adapter.devices ? adapter.devices.values : []
  readonly property var mine: devices.filter(function(d) { return d.paired || d.bonded || d.connected })
  readonly property var nearby: devices.filter(function(d) { return !(d.paired || d.bonded || d.connected) && hasHumanName(d) })

  // Devices that broadcast no name get their address (or a UUID) as one;
  // they're hidden like Omarchy's Bluetooth panel hides them.
  function hasHumanName(d) {
    var label = String(d.deviceName || d.name || "").trim()
    if (label === "") return false
    if (/^([0-9a-f]{2}[:-]){5}[0-9a-f]{2}$/i.test(label)) return false
    return !(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(label)
      || /^[0-9a-f]{32}$/i.test(label) || /^0x[0-9a-f]{4,32}$/i.test(label))
  }

  function stateText(d) {
    if (d.pairing) return "Pairing…"
    if (d.state === BluetoothDeviceState.Connecting) return "Connecting…"
    if (d.state === BluetoothDeviceState.Disconnecting) return "Disconnecting…"
    if (d.connected) return "Connected" + (d.batteryAvailable ? " · " + Math.round(d.battery * 100) + "%" : "")
    return "Not connected"
  }

  // Looks for nearby devices while this pane is open.
  Component.onCompleted: if (adapter && adapter.enabled) adapter.discovering = true
  Component.onDestruction: if (adapter) adapter.discovering = false

  Group {
    visible: pane.adapter === null
    SettingRow { label: "No Bluetooth adapter found" }
  }

  Group {
    visible: pane.adapter !== null
    SwitchRow {
      label: "Bluetooth"
      icon: "bluetooth-active-symbolic"
      iconColor: "#0a84ff"
      checked: pane.adapter ? pane.adapter.enabled : false
      onToggled: function(wanted) {
        pane.adapter.enabled = wanted
        if (wanted) pane.adapter.discovering = true
      }
    }
  }

  Group {
    visible: pane.adapter !== null && pane.adapter.enabled && pane.mine.length > 0
    title: "My devices"
    Repeater {
      model: pane.mine
      SettingRow {
        id: dev
        required property var modelData
        label: String(modelData.deviceName || modelData.name || modelData.address)
        sublabel: pane.stateText(modelData)
        Row {
          spacing: 8
          PillButton {
            text: dev.modelData.connected ? "Disconnect" : "Connect"
            onClicked: dev.modelData.connected ? dev.modelData.disconnect() : dev.modelData.connect()
          }
          PillButton {
            text: "Forget"
            danger: true
            onClicked: App.confirm({ title: "Forget “" + dev.modelData.name + "”?", text: "You'll need to pair it again to use it.",
              action: "Forget", danger: true, onAccept: function() { dev.modelData.forget() } })
          }
        }
      }
    }
  }

  Group {
    visible: pane.adapter !== null && pane.adapter.enabled
    title: "Nearby devices"
    note: pane.nearby.length > 0 ? "" : (pane.adapter && pane.adapter.discovering ? "Looking for devices…" : "No devices found")
    Repeater {
      model: pane.nearby
      SettingRow {
        id: near
        required property var modelData
        label: String(modelData.deviceName || modelData.name)
        sublabel: modelData.pairing ? "Pairing…" : ""
        PillButton {
          text: "Connect"
          onClicked: {
            if (near.modelData.paired) near.modelData.connect()
            else near.modelData.pair()
          }
        }
      }
    }
  }
}
