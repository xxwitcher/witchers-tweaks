import QtQuick

// One row in a Group: a label (and a smaller note under it) on the left and
// its control on the right. The first visible row in a group draws no line
// above it.
Item {
  id: row
  property string label: ""
  property string sublabel: ""
  // A symbolic icon name, shown white on a colored square.
  property string icon: ""
  property color iconColor: App.tint
  property bool dimmed: false
  default property alias control: slot.data
  property real controlWidth: slot.childrenRect.width

  width: parent ? parent.width : 600
  implicitHeight: Math.max(46, texts.implicitHeight + 20, slot.childrenRect.height + 16)
  height: visible ? implicitHeight : 0
  opacity: dimmed ? 0.5 : 1

  readonly property bool firstVisible: {
    var kids = parent ? parent.children : []
    for (var i = 0; i < kids.length; i++) if (kids[i].visible) return kids[i] === row
    return true
  }

  Rectangle {
    visible: !row.firstVisible
    x: 14
    width: parent.width - 28
    height: 1
    color: App.line
  }

  Rectangle {
    id: icon
    visible: row.icon !== ""
    x: 14
    anchors.verticalCenter: parent.verticalCenter
    width: 26
    height: 26
    radius: 7
    color: row.iconColor
    Icon {
      anchors.centerIn: parent
      name: row.icon
      size: 16
      color: "#ffffff"
    }
  }

  Column {
    id: texts
    x: icon.visible ? icon.x + icon.width + 12 : 16
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width - x - slot.childrenRect.width - 36
    spacing: 2

    Text {
      width: parent.width
      text: row.label
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: App.fg
      font.family: App.font
      font.pixelSize: App.body
    }
    Text {
      visible: row.sublabel !== ""
      width: parent.width
      text: row.sublabel
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: App.subtle
      font.family: App.font
      font.pixelSize: App.small
    }
  }

  Item {
    id: slot
    anchors.right: parent.right
    anchors.rightMargin: 16
    anchors.verticalCenter: parent.verticalCenter
    width: childrenRect.width
    height: childrenRect.height
  }
}
