import QtQuick

SettingRow {
  id: row
  property alias options: seg.options
  property alias current: seg.current
  signal chosen(var value)
  Segmented {
    id: seg
    onChosen: function(v) { row.chosen(v) }
  }
}
