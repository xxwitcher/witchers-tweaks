import QtQuick

SettingRow {
  id: row
  property alias options: dd.options
  property alias current: dd.current
  property alias searchable: dd.searchable
  property alias placeholder: dd.placeholder
  property alias buttonWidth: dd.buttonWidth
  signal chosen(var value)
  Dropdown {
    id: dd
    onChosen: function(v) { row.chosen(v) }
  }
}
