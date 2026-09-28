import QtQuick

SettingRow {
  id: row
  property alias buttonText: b.text
  property alias danger: b.danger
  property alias prominent: b.prominent
  signal clicked()
  PillButton {
    id: b
    onClicked: row.clicked()
  }
}
