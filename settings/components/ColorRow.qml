import QtQuick

// A row of one or more color wells. colors: list of colors; each pick
// emits colorPicked(index, "#rrggbb") (and colorPreviewed while picking).
SettingRow {
  id: row
  property var colors: []
  signal colorPreviewed(int index, string hex)
  signal colorPicked(int index, string hex)
  signal cancelled()
  Row {
    spacing: 8
    Repeater {
      model: row.colors
      ColorWell {
        id: w
        required property var modelData
        required property int index
        color: modelData
        onPreviewed: function(c) { row.colorPreviewed(w.index, w.hex(c)) }
        onPicked: function(c) { row.colorPicked(w.index, w.hex(c)) }
        onCancelled: row.cancelled()
      }
    }
  }
}
