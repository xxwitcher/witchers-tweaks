import QtQuick
import QtQuick.Effects
import Quickshell

// A symbolic icon from the icon theme (Adwaita's are drawn centered in
// their frame), tinted to `color`.
Item {
  id: icon
  property string name: ""
  property int size: 16
  property color color: App.fg

  implicitWidth: size
  implicitHeight: size

  Image {
    id: image
    anchors.fill: parent
    source: icon.name !== "" ? Quickshell.iconPath(icon.name, true) : ""
    sourceSize.width: icon.size * 2
    sourceSize.height: icon.size * 2
    fillMode: Image.PreserveAspectFit
    smooth: true
    visible: false
  }

  // Symbolic icons are drawn in one dark color: brighten to white, then
  // tint.
  MultiEffect {
    anchors.fill: image
    source: image
    brightness: 1.0
    colorization: 1.0
    colorizationColor: icon.color
  }
}
