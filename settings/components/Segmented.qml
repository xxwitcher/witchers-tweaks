import QtQuick

// A segmented control. options: [{ value, label }].
Rectangle {
  id: seg
  property var options: []
  property var current: null
  signal chosen(var value)
  width: buttons.implicitWidth + 4
  height: 28
  radius: 7
  color: App.control

  Row {
    id: buttons
    x: 2
    y: 2
    Repeater {
      model: seg.options
      Rectangle {
        id: b
        required property var modelData
        readonly property bool on: modelData.value === seg.current
        width: Math.max(64, t.implicitWidth + 24)
        height: 24
        radius: 6
        color: on ? App.tint : (ma.containsMouse ? App.hover : "transparent")
        Text {
          id: t
          anchors.centerIn: parent
          text: b.modelData.label
          textFormat: Text.PlainText
          color: b.on ? App.onTint : App.fg
          font.family: App.font
          font.pixelSize: App.body
        }
        MouseArea {
          id: ma
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: if (!b.on) seg.chosen(b.modelData.value)
        }
      }
    }
  }
}
