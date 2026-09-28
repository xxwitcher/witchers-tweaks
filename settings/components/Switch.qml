import QtQuick

// A macOS-style switch. `checked` shows the state; clicking emits toggled
// with the wanted state (the owner decides and updates `checked`). `busy`
// shows a pending change.
Item {
  id: sw
  property bool checked: false
  property bool busy: false
  property bool enabled2: true
  signal toggled(bool wanted)

  width: 40
  height: 24
  opacity: enabled2 ? 1 : 0.4

  Rectangle {
    anchors.fill: parent
    radius: height / 2
    color: sw.checked ? App.tint : App.control
    Behavior on color { ColorAnimation { duration: 140 } }
  }

  Rectangle {
    width: 20
    height: 20
    radius: 10
    y: 2
    x: sw.checked ? parent.width - width - 2 : 2
    color: "#ffffff"
    Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    // A pending change: the knob pulses.
    SequentialAnimation on opacity {
      running: sw.busy
      loops: Animation.Infinite
      alwaysRunToEnd: true
      NumberAnimation { to: 0.4; duration: 400 }
      NumberAnimation { to: 1; duration: 400 }
    }
  }

  MouseArea {
    anchors.fill: parent
    enabled: sw.enabled2 && !sw.busy
    cursorShape: Qt.PointingHandCursor
    onClicked: sw.toggled(!sw.checked)
  }
}
