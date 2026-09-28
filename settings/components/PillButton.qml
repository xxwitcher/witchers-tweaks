import QtQuick

// A button. `danger` paints it red; `prominent` fills it with the tint.
Rectangle {
  id: btn
  property string text: ""
  property bool danger: false
  property bool prominent: false
  property bool enabled2: true
  signal clicked()
  width: Math.max(80, label.implicitWidth + 28)
  height: 28
  radius: 7
  opacity: enabled2 ? 1 : 0.45
  color: prominent ? (danger ? App.danger : App.tint) : (ma.containsMouse ? App.hover : App.control)
  Text {
    id: label
    anchors.centerIn: parent
    text: btn.text
    textFormat: Text.PlainText
    color: btn.prominent ? (btn.danger ? "#ffffff" : App.onTint) : (btn.danger ? App.danger : App.fg)
    font.family: App.font
    font.pixelSize: App.body
  }
  MouseArea {
    id: ma
    anchors.fill: parent
    enabled: btn.enabled2
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: btn.clicked()
  }
}
