import QtQuick
import Quickshell
import Quickshell.Networking
import "../components"

// Wi-Fi through NetworkManager (Quickshell.Networking): on/off, the network
// you're on, and the others in range to join or forget.
Column {
  id: pane
  spacing: 22

  readonly property bool managed: Networking.backend === NetworkBackendType.NetworkManager
  readonly property var devices: Networking.devices ? Networking.devices.values : []
  readonly property var wifi: {
    for (var i = 0; i < devices.length; i++) if (devices[i] && devices[i].type === DeviceType.Wifi) return devices[i]
    return null
  }
  readonly property var networks: {
    var list = wifi && wifi.networks ? wifi.networks.values.slice() : []
    list.sort(function(a, b) {
      if (a.connected !== b.connected) return a.connected ? -1 : 1
      if (a.known !== b.known) return a.known ? -1 : 1
      return (b.signalStrength || 0) - (a.signalStrength || 0)
    })
    return list
  }
  readonly property var connected: networks.filter(function(n) { return n.connected })
  readonly property var known: networks.filter(function(n) { return n.known && !n.connected })
  readonly property var others: networks.filter(function(n) { return !n.known && !n.connected && String(n.name) !== "" })

  // The network waiting for its password.
  property string asking: ""

  function secured(n) {
    return n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe
  }
  function bars(n) {
    var s = n.signalStrength || 0
    return s > 0.75 ? "▂▄▆█" : s > 0.5 ? "▂▄▆" : s > 0.25 ? "▂▄" : "▂"
  }
  function join(n) {
    if (secured(n) && !n.known) { asking = String(n.name); return }
    n.connect()
  }

  // Scans for networks while this pane is open.
  Component.onCompleted: if (wifi) wifi.scannerEnabled = true
  Component.onDestruction: if (wifi) wifi.scannerEnabled = false

  Group {
    visible: !pane.managed
    SettingRow {
      label: "Wi-Fi settings need NetworkManager"
      PillButton { text: "Open Wi-Fi tool"; onClicked: App.shDetached("omarchy-launch-or-focus-tui impala") }
    }
  }

  Group {
    visible: pane.managed
    SwitchRow {
      label: "Wi-Fi"
      icon: "network-wireless-symbolic"
      iconColor: "#0a84ff"
      checked: Networking.wifiEnabled
      switchEnabled: Networking.wifiHardwareEnabled
      sublabel: Networking.wifiHardwareEnabled ? "" : "Turned off by a hardware switch"
      onToggled: function(wanted) { Networking.wifiEnabled = wanted }
    }
    Repeater {
      model: pane.connected
      SettingRow {
        id: connectedRow
        required property var modelData
        label: String(modelData.name)
        sublabel: "Connected"
        Row {
          spacing: 10
          Text { anchors.verticalCenter: parent.verticalCenter; text: pane.bars(connectedRow.modelData); color: App.subtle; font.pixelSize: App.body }
          PillButton { text: "Disconnect"; onClicked: connectedRow.modelData.disconnect() }
        }
      }
    }
  }

  Group {
    visible: pane.managed && Networking.wifiEnabled && pane.known.length > 0
    title: "Known networks"
    Repeater {
      model: pane.known
      SettingRow {
        id: knownRow
        required property var modelData
        label: String(modelData.name)
        sublabel: modelData.stateChanging ? "Connecting…" : ""
        Row {
          spacing: 8
          Icon { anchors.verticalCenter: parent.verticalCenter; visible: pane.secured(knownRow.modelData); name: "channel-secure-symbolic"; size: 14; color: App.subtle }
          Text { anchors.verticalCenter: parent.verticalCenter; text: pane.bars(knownRow.modelData); color: App.subtle; font.pixelSize: App.body }
          PillButton { text: "Join"; onClicked: knownRow.modelData.connect() }
          PillButton {
            text: "Forget"
            danger: true
            onClicked: App.confirm({ title: "Forget “" + knownRow.modelData.name + "”?", text: "You'll need its password to join again.",
              action: "Forget", danger: true, onAccept: function() { knownRow.modelData.forget() } })
          }
        }
      }
    }
  }

  Group {
    visible: pane.managed && Networking.wifiEnabled
    title: "Other networks"
    note: pane.others.length === 0 ? "Looking for networks…" : ""
    Repeater {
      model: pane.others
      Column {
        id: other
        required property var modelData
        width: parent.width
        SettingRow {
          label: String(other.modelData.name)
          sublabel: other.modelData.stateChanging ? "Connecting…" : ""
          Row {
            spacing: 8
            Icon { anchors.verticalCenter: parent.verticalCenter; visible: pane.secured(other.modelData); name: "channel-secure-symbolic"; size: 14; color: App.subtle }
          Text { anchors.verticalCenter: parent.verticalCenter; text: pane.bars(other.modelData); color: App.subtle; font.pixelSize: App.body }
            PillButton { text: "Join"; onClicked: pane.join(other.modelData) }
          }
        }
        // The password, asked in place.
        SettingRow {
          visible: pane.asking === String(other.modelData.name)
          label: "Password"
          Row {
            spacing: 8
            Rectangle {
              width: 200; height: 28; radius: 7; color: App.control
              TextInput {
                id: psk
                x: 8; width: parent.width - 16
                anchors.verticalCenter: parent.verticalCenter
                echoMode: TextInput.Password
                color: App.fg
                font.family: App.font
                font.pixelSize: App.body
                clip: true
                onVisibleChanged: if (visible) forceActiveFocus()
                Keys.onReturnPressed: joinButton.clicked()
                Keys.onEscapePressed: pane.asking = ""
              }
            }
            PillButton {
              id: joinButton
              text: "Join"
              prominent: true
              onClicked: {
                if (psk.text.length === 0) return
                other.modelData.connectWithPsk(psk.text)
                psk.text = ""
                pane.asking = ""
              }
            }
          }
        }
      }
    }
  }

  Group {
    visible: pane.managed
    ButtonRow {
      label: "Share this Wi-Fi"
      buttonText: "Show QR Code"
      onClicked: App.detached(["omarchy-shell", "shell", "summon", "omarchy.wifiqr"])
    }
  }
}
