import QtQuick

// A rounded card of rows, with an optional heading above and a note below,
// like a macOS Settings group. Rows draw the lines between them.
Column {
  id: group
  property string title: ""
  property string note: ""
  default property alias rows: rowsColumn.data
  width: parent ? parent.width : 600
  spacing: 6

  Text {
    visible: group.title !== ""
    text: group.title
    textFormat: Text.PlainText
    color: App.fg
    font.family: App.font
    font.pixelSize: App.body
    font.bold: true
    leftPadding: 4
  }

  Rectangle {
    width: parent.width
    height: rowsColumn.implicitHeight
    radius: App.radius
    color: App.card
    border.width: 1
    border.color: App.line

    Column {
      id: rowsColumn
      width: parent.width
    }
  }

  Text {
    visible: group.note !== ""
    width: parent.width
    text: group.note
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    color: App.subtle
    font.family: App.font
    font.pixelSize: App.small
    leftPadding: 4
    rightPadding: 4
  }
}
