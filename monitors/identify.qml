// Big numbers in the top-left corner of each screen for monitor-setup.
// A layer-shell overlay, not a window: it never takes keyboard focus or moves
// the cursor. MONITOR_NUMBERS maps output names to numbers, e.g.
// {"eDP-1": 1, "DVI-I-2": 2}.
import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
  id: root
  readonly property var numbers: JSON.parse(Quickshell.env("MONITOR_NUMBERS") || "{}")

  Variants {
    model: Quickshell.screens.filter(s => root.numbers[s.name] !== undefined)

    PanelWindow {
      required property var modelData
      screen: modelData
      anchors { top: true; left: true }
      margins { top: 24; left: 24 }
      implicitWidth: 120
      implicitHeight: 120
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      WlrLayershell.namespace: "witchers-tweaks-monitor-number"
      // Clicks pass straight through to whatever is underneath.
      mask: Region {}

      Rectangle {
        anchors.fill: parent
        radius: 14
        color: "#1e1e2e"
        border.color: "#c4b5fd"
        border.width: 4

        Text {
          anchors.centerIn: parent
          text: root.numbers[modelData.name]
          color: "#a855f7"
          font.family: "JetBrainsMono Nerd Font"
          font.bold: true
          font.pixelSize: 84
        }
      }
    }
  }
}
