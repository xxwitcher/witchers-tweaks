import QtQuick

SettingRow {
  id: row
  property alias checked: sw.checked
  property alias busy: sw.busy
  property bool switchEnabled: true
  signal toggled(bool wanted)

  Switch {
    id: sw
    enabled2: row.switchEnabled
    onToggled: function(wanted) { row.toggled(wanted) }
  }
}
