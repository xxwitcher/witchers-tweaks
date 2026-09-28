import QtQuick
import QtQuick.Controls

// A color swatch; clicking it opens a picker (saturation/brightness square,
// hue strip and hex field). It emits previewed while you pick and picked
// when you press Done (Esc or clicking away emits cancelled).
Item {
  id: well
  property color color: "#a855f7"
  signal previewed(color value)
  signal picked(color value)
  signal cancelled()

  width: 44
  height: 26

  property real hue: 0
  property real sat: 0
  property real val: 0
  property bool accepted: false
  readonly property color working: Qt.hsva(hue, sat, val, 1)

  function hex(c) {
    function h(x) { var s = Math.round(x * 255).toString(16); return s.length < 2 ? "0" + s : s }
    return "#" + h(c.r) + h(c.g) + h(c.b)
  }

  Rectangle {
    anchors.fill: parent
    radius: 7
    color: well.color
    border.width: 1
    border.color: App.line
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      well.hue = Math.max(0, well.color.hsvHue)
      well.sat = well.color.hsvSaturation
      well.val = well.color.hsvValue
      hexField.text = well.hex(well.color)
      well.accepted = false
      popup.open()
    }
  }

  onWorkingChanged: if (popup.opened) previewed(working)

  Popup {
    id: popup
    y: well.height + 6
    x: Math.min(0, well.width - width)
    width: 250
    padding: 12
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onClosed: if (!well.accepted) well.cancelled()
    background: Rectangle { radius: 10; color: App.bg; border.width: 1; border.color: App.line }

    contentItem: Column {
      spacing: 10

      // Saturation left to right, brightness bottom to top.
      Item {
        width: parent.width
        height: 150
        Rectangle {
          anchors.fill: parent
          radius: 6
          color: Qt.hsva(well.hue, 1, 1, 1)
          Rectangle {
            anchors.fill: parent
            radius: 6
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0; color: "#ffffffff" }
              GradientStop { position: 1; color: "#00ffffff" }
            }
          }
          Rectangle {
            anchors.fill: parent
            radius: 6
            gradient: Gradient {
              GradientStop { position: 0; color: "#00000000" }
              GradientStop { position: 1; color: "#ff000000" }
            }
          }
        }
        Rectangle {
          width: 14; height: 14; radius: 7
          x: well.sat * parent.width - 7
          y: (1 - well.val) * parent.height - 7
          color: "transparent"
          border.width: 2
          border.color: well.val > 0.5 ? "black" : "white"
        }
        MouseArea {
          anchors.fill: parent
          preventStealing: true
          function set(m) {
            well.sat = Math.max(0, Math.min(1, m.x / width))
            well.val = Math.max(0, Math.min(1, 1 - m.y / height))
            hexField.text = well.hex(well.working)
          }
          onPressed: function(m) { set(m) }
          onPositionChanged: function(m) { set(m) }
        }
      }

      // Hue.
      Item {
        width: parent.width
        height: 14
        Rectangle {
          anchors.fill: parent
          radius: 7
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0 / 6; color: "#ff0000" }
            GradientStop { position: 1 / 6; color: "#ffff00" }
            GradientStop { position: 2 / 6; color: "#00ff00" }
            GradientStop { position: 3 / 6; color: "#00ffff" }
            GradientStop { position: 4 / 6; color: "#0000ff" }
            GradientStop { position: 5 / 6; color: "#ff00ff" }
            GradientStop { position: 6 / 6; color: "#ff0000" }
          }
        }
        Rectangle {
          width: 6; height: parent.height + 4; y: -2; radius: 3
          x: well.hue * parent.width - 3
          color: "white"
          border.width: 1
          border.color: "black"
        }
        MouseArea {
          anchors.fill: parent
          preventStealing: true
          function set(m) { well.hue = Math.max(0, Math.min(0.999, m.x / width)); hexField.text = well.hex(well.working) }
          onPressed: function(m) { set(m) }
          onPositionChanged: function(m) { set(m) }
        }
      }

      Row {
        spacing: 8
        Rectangle { width: 30; height: 28; radius: 6; color: well.working; border.width: 1; border.color: App.line }
        Rectangle {
          width: 110
          height: 28
          radius: 6
          color: App.control
          TextInput {
            id: hexField
            x: 8
            width: parent.width - 16
            anchors.verticalCenter: parent.verticalCenter
            color: App.fg
            font.family: App.font
            font.pixelSize: App.body
            maximumLength: 7
            onTextEdited: {
              var t = text.replace(/^#/, "")
              if (/^[0-9a-fA-F]{6}$/.test(t)) {
                var c = Qt.color("#" + t)
                well.hue = Math.max(0, c.hsvHue)
                well.sat = c.hsvSaturation
                well.val = c.hsvValue
              }
            }
          }
        }
        PillButton {
          text: "Done"
          prominent: true
          width: 70
          onClicked: {
            well.accepted = true
            well.picked(well.working)
            popup.close()
          }
        }
      }
    }
  }
}
