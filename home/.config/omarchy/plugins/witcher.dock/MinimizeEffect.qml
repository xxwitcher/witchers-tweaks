import QtQuick
import Quickshell
import Quickshell.Wayland

// The minimize animation: a live picture of the window travelling between
// where the window was and its place in the dock, drawn over everything in
// the dock's full-screen layer. Hyprland can't bend a window, so this plays
// in place of the window, which is already hidden (or not shown yet).
//
//   genie   strips of the window funnel into the dock, bottom first (macOS)
//   scale   the window shrinks straight into the dock
//   fade    the window shrinks a little and fades out
//   slide   the window drops down and fades
//
// play(toplevel, from, targetFn, reverse, done): from is the window's rect
// here, targetFn() returns the dock spot's rect (asked every frame, as the
// dock rearranges), reverse plays it back out of the dock.
Item {
  id: fx
  anchors.fill: parent

  property string effect: "genie"
  // Percent of the normal speed (100); 200 takes half as long.
  property real speed: 100
  property var toplevel: null
  property rect from: Qt.rect(0, 0, 1, 1)
  property rect to: Qt.rect(0, 0, 1, 1)
  property var targetFn: null
  property bool reverse: false
  property var done: null
  // 0 is the window, 1 is inside the dock.
  property real progress: 0
  readonly property bool active: toplevel !== null
  readonly property int strips: 40

  visible: active

  function play(top, rect, target, backwards, finished) {
    finish(false)
    effect = effect === "" ? "genie" : effect
    from = rect
    targetFn = target
    reverse = backwards
    done = finished || null
    progress = backwards ? 1 : 0
    to = targetFn ? targetFn() : Qt.rect(rect.x + rect.width / 2, height, 0, 0)
    toplevel = top
    // The picture needs a frame before anything is drawn.
    waitForPicture.restart()
  }

  function finish(callDone) {
    anim.stop()
    waitForPicture.stop()
    var cb = done
    done = null
    toplevel = null
    if (callDone && cb) cb()
  }

  onProgressChanged: if (targetFn) to = targetFn()

  Timer {
    id: waitForPicture
    interval: 16
    repeat: true
    property int tries: 0
    onTriggered: {
      if (capture.hasContent) {
        stop()
        tries = 0
        anim.from = fx.reverse ? 1 : 0
        anim.to = fx.reverse ? 0 : 1
        anim.duration = (fx.effect === "genie" ? 520 : fx.effect === "fade" ? 260 : 340) * 100 / Math.max(10, fx.speed)
        anim.start()
      } else if (++tries > 15) {
        // No picture (the window went away): skip the animation.
        stop()
        tries = 0
        fx.finish(true)
      }
    }
  }

  NumberAnimation {
    id: anim
    target: fx
    property: "progress"
    easing.type: Easing.InOutQuad
    onFinished: fx.finish(true)
  }

  ScreencopyView {
    id: capture
    x: fx.from.x
    y: fx.from.y
    width: fx.from.width
    height: fx.from.height
    captureSource: fx.active && fx.toplevel ? fx.toplevel.wayland : null
    live: fx.active
    visible: false
  }

  function lerp(a, b, t) { return a + (b - a) * t }
  function clamp01(t) { return Math.max(0, Math.min(1, t)) }
  function smooth(t) { t = clamp01(t); return t * t * (3 - 2 * t) }

  // ---------- genie: horizontal strips ----------
  // Each strip heads for the dock on its own schedule (the bottom ones
  // first) and narrows as it goes down, so the window pours into the icon.
  function strip(i) {
    var n = strips
    var t = n > 1 ? i / (n - 1) : 0
    var lag = 0.55
    var r = clamp01(progress * (1 + lag) - (1 - t) * lag)
    var e = r * r
    var h = lerp(from.height / n, Math.max(0.5, to.height / n), r)
    var y = lerp(from.y + t * from.height, to.y + t * to.height, e)
    var span = to.y - from.y
    var f = span !== 0 ? clamp01((y - from.y) / span) : 1
    var s = smooth(f) * smooth(progress / 0.35)
    var w = lerp(from.width, to.width, s)
    var cx = lerp(from.x + from.width / 2, to.x + to.width / 2, s)
    return { x: cx - w / 2, y: y, w: Math.max(1, w), h: h + 0.75 }
  }

  Repeater {
    model: fx.active && fx.effect === "genie" ? fx.strips : 0
    ShaderEffectSource {
      required property int index
      readonly property var g: fx.progress >= 0 ? fx.strip(index) : null
      sourceItem: capture
      hideSource: true
      sourceRect: Qt.rect(0, index * capture.height / fx.strips, capture.width, capture.height / fx.strips + 1)
      x: g.x
      y: g.y
      width: g.w
      height: g.h
      smooth: true
    }
  }

  // ---------- scale, fade and slide: the whole picture ----------
  ShaderEffectSource {
    visible: fx.active && fx.effect !== "genie"
    sourceItem: capture
    hideSource: true
    smooth: true
    readonly property real p: fx.progress
    readonly property real e: fx.smooth(p)
    x: fx.effect === "scale" ? fx.lerp(fx.from.x, fx.to.x, e)
      : fx.effect === "fade" ? fx.from.x + fx.from.width * 0.075 * e
      : fx.from.x + fx.from.width * 0.1 * e
    y: fx.effect === "scale" ? fx.lerp(fx.from.y, fx.to.y, e)
      : fx.effect === "fade" ? fx.from.y + fx.from.height * 0.075 * e
      : fx.lerp(fx.from.y, fx.to.y - fx.from.height * 0.4, e)
    width: fx.effect === "scale" ? Math.max(1, fx.lerp(fx.from.width, fx.to.width, e)) : fx.from.width * (1 - (fx.effect === "fade" ? 0.15 : 0.2) * e)
    height: fx.effect === "scale" ? Math.max(1, fx.lerp(fx.from.height, fx.to.height, e)) : fx.from.height * (1 - (fx.effect === "fade" ? 0.15 : 0.2) * e)
    opacity: fx.effect === "scale" ? 1 - 0.3 * e : 1 - e
  }
}
