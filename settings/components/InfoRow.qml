import QtQuick

SettingRow {
  id: row
  property string value: ""
  Text {
    text: row.value
    textFormat: Text.PlainText
    color: App.subtle
    font.family: App.font
    font.pixelSize: App.body
  }
}
