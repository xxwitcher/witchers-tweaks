import QtQuick

// A row with a slider and its value; `format` turns the value into text.
SettingRow {
  id: row
  property alias from: slider.from
  property alias to: slider.to
  property alias step: slider.step
  property alias value: slider.value
  property alias live: slider.live
  property var format: function(v) { return String(Math.round(v)) }
  property string minLabel: ""
  property string maxLabel: ""
  signal moved(real value)
  signal changed(real value)

  Row {
    spacing: 10
    Text {
      visible: row.minLabel !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: row.minLabel
      color: App.subtle
      font.family: App.font
      font.pixelSize: App.small
    }
    Slider {
      id: slider
      width: 220
      onMoved: function(v) { row.moved(v) }
      onChanged: function(v) { row.changed(v) }
    }
    Text {
      visible: row.maxLabel !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: row.maxLabel
      color: App.subtle
      font.family: App.font
      font.pixelSize: App.small
    }
    Text {
      visible: row.minLabel === ""
      anchors.verticalCenter: parent.verticalCenter
      width: 52
      horizontalAlignment: Text.AlignRight
      text: row.format(slider.shown)
      color: App.subtle
      font.family: App.font
      font.pixelSize: App.body
    }
  }
}
