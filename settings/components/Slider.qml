import QtQuick

// A slider: drag or click the track. `value` shows the state; while dragging
// it emits moved (for live previews) and, on release, changed with the final
// value (rounded to `step`).
Item {
  id: slider
  property real from: 0
  property real to: 100
  property real step: 1
  property real value: 0
  property bool live: true
  signal moved(real value)
  signal changed(real value)

  width: 200
  height: 24

  property real shown: value
  onValueChanged: if (!area.pressed) shown = value
  readonly property real fraction: to > from ? (shown - from) / (to - from) : 0

  function snap(v) {
    var s = Math.round((v - from) / step) * step + from
    return Math.max(from, Math.min(to, Number(s.toFixed(4))))
  }

  Rectangle {
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width
    height: 4
    radius: 2
    color: App.control
    Rectangle {
      width: Math.max(0, Math.min(1, slider.fraction)) * parent.width
      height: parent.height
      radius: 2
      color: App.tint
    }
  }

  Rectangle {
    width: 20
    height: 20
    radius: 10
    anchors.verticalCenter: parent.verticalCenter
    x: Math.max(0, Math.min(1, slider.fraction)) * (parent.width - width)
    color: "#ffffff"
    border.width: 1
    border.color: Qt.rgba(0, 0, 0, 0.15)
  }

  MouseArea {
    id: area
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    preventStealing: true
    function at(mx) { return slider.snap(slider.from + Math.max(0, Math.min(1, (mx - 10) / (width - 20))) * (slider.to - slider.from)) }
    onPressed: function(m) { slider.shown = at(m.x); if (slider.live) slider.moved(slider.shown) }
    onPositionChanged: function(m) {
      var v = at(m.x)
      if (v !== slider.shown) { slider.shown = v; if (slider.live) slider.moved(v) }
    }
    onReleased: slider.changed(slider.shown)
  }
}
