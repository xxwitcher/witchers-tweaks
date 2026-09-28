import QtQuick

// A vertical scroll area that moves with a touchpad and keeps gliding when
// the fingers lift (the compositor sends no momentum of its own); a mouse
// wheel notch pushes it into the same glide. Put content in `content`.
Item {
  id: scroller
  default property alias content: holder.data
  property alias contentHeight: flick.contentHeight
  property alias contentY: flick.contentY
  readonly property alias flickable: flick
  clip: true

  Flickable {
    id: flick
    anchors.fill: parent
    interactive: false
    contentWidth: width
    boundsBehavior: Flickable.StopAtBounds

    Item {
      id: holder
      width: flick.width
      height: flick.contentHeight
    }
  }

  // A sideways scroll: dx in pixels (positive moves content right), the
  // pointer in window coordinates, and the gesture phase.
  signal sideways(real dx, point at, int phase)
  property bool sidewaysGesture: false

  property real velocity: 0
  property double lastAt: 0
  readonly property real friction: 3.4
  readonly property real speed: 1.4

  function maxY() { return Math.max(0, flick.contentHeight - flick.height) }
  function moveBy(dy) {
    var y = Math.max(0, Math.min(maxY(), flick.contentY + dy))
    var moved = y !== flick.contentY
    flick.contentY = y
    return moved
  }
  function scrollToTop() { glide.running = false; flick.contentY = 0 }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.NoButton
    z: 100
    onWheel: function(event) {
      // Sideways scrolls go to whatever scrolls sideways under the pointer
      // (the theme strip), through the sideways signal; so does the end of
      // a sideways gesture.
      var dx = event.pixelDelta.x !== 0 ? event.pixelDelta.x : event.angleDelta.x / 3
      var dy = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 3
      var at = mapToItem(null, event.x, event.y)
      if (Math.abs(dx) > Math.abs(dy) || (dx === 0 && dy === 0 && scroller.sidewaysGesture)) {
        scroller.sidewaysGesture = !(dx === 0 && dy === 0 && event.phase === Qt.ScrollEnd)
        scroller.sideways(dx, at, event.phase)
        return
      }
      if (dx === 0 && dy === 0 && event.phase === Qt.ScrollBegin) scroller.sidewaysGesture = false
      var now = Date.now()
      if (event.pixelDelta.y === 0 && event.angleDelta.y === 0) {
        if (event.phase === Qt.ScrollEnd) {
          lift.stop()
          glide.running = Math.abs(scroller.velocity) > 60
        } else if (event.phase === Qt.ScrollBegin) {
          glide.running = false
          scroller.velocity = 0
        }
        return
      }
      if (event.pixelDelta.y !== 0 || event.angleDelta.y % 120 !== 0) {
        var dy = (event.pixelDelta.y !== 0 ? -event.pixelDelta.y : -event.angleDelta.y / 3) * scroller.speed
        var dt = Math.max(4, now - scroller.lastAt)
        var v = dy * 1000 / dt
        scroller.velocity = now - scroller.lastAt > 120 ? v : scroller.velocity * 0.5 + v * 0.5
        scroller.lastAt = now
        glide.running = false
        scroller.moveBy(dy)
        lift.restart()
      } else {
        var push = -event.angleDelta.y / 120 * 1400
        scroller.velocity = glide.running && Math.sign(push) === Math.sign(scroller.velocity) ? scroller.velocity + push : push
        glide.running = true
      }
    }
  }

  Timer {
    id: lift
    interval: 50
    onTriggered: glide.running = Math.abs(scroller.velocity) > 60
  }

  FrameAnimation {
    id: glide
    onTriggered: {
      if (!scroller.moveBy(scroller.velocity * frameTime)) { running = false; return }
      scroller.velocity *= Math.exp(-scroller.friction * frameTime)
      if (Math.abs(scroller.velocity) < 20) running = false
    }
  }
}
