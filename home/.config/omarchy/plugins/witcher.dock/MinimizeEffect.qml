import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland

// The minimize animation: a live picture of the window, with its rounded
// corners and border, travelling between where the window was and its
// place in the dock, drawn over everything in the dock's full-screen layer.
// Hyprland can't bend a window, so this plays in place of the window.
//
//   genie   the window pours into the dock, bottom first, its sides bending (macOS)
//   scale   the window shrinks straight into the dock
//   fade    the window shrinks a little and fades out
//   slide   the window drops down and fades
//
// play(toplevel, from, targetFn, reverse, ready, done): from is the window's
// border box here; targetFn() returns the dock spot's rect (asked every
// frame, as the dock rearranges). Minimizing, the picture first covers the
// window exactly, then ready() hides the real one and it animates away, so
// nothing flashes. Restoring (reverse), it animates out of the dock, done()
// brings the window back, and the picture stays until holdWhile() is false,
// so the window never blinks out between the two.
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
  property var ready: null
  property var done: null
  property var holdWhile: null
  // 0 is the window, 1 is inside the dock.
  property real progress: 0
  readonly property bool active: toplevel !== null
  property bool holding: false

  // The window's look: border width, rounding, and its border gradient as
  // Hyprland draws it (colors and the line the gradient runs along).
  property int borderSize: 2
  property int rounding: 0
  property var borderColors: ["#ffffffff"]
  property var gradLine: ({ x1: 0, y1: 0, x2: 1, y2: 0 })
  property color backdrop: "#1a1b26"

  visible: active

  function play(top, rect, target, backwards, readyFn, finished, holdFn) {
    finish(false)
    from = rect
    targetFn = target
    reverse = backwards
    ready = readyFn || null
    done = finished || null
    holdWhile = holdFn || null
    progress = backwards ? 1 : 0
    to = targetFn ? targetFn() : Qt.rect(rect.x + rect.width / 2, height, 0, 0)
    toplevel = top
    // The picture needs a frame before anything is drawn.
    waitForPicture.restart()
  }

  function finish(callDone) {
    anim.stop()
    waitForPicture.stop()
    holdTimer.stop()
    var cb = done
    done = null
    ready = null
    if (callDone && cb) cb()
    if (callDone && holdWhile) {
      // Restoring: keep the picture up until the window shows again.
      holding = true
      holdTimer.restart()
      return
    }
    holding = false
    holdWhile = null
    toplevel = null
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
        // The picture now covers the window: hide the real one, then go.
        if (fx.ready) { fx.ready(); fx.ready = null; startDelay.restart() }
        else fx.start()
      } else if (++tries > 20) {
        stop()
        tries = 0
        if (fx.ready) { fx.ready(); fx.ready = null }
        fx.holdWhile = null
        fx.finish(true)
      }
    }
  }
  // Gives Hyprland a frame to take the window away under the picture.
  Timer { id: startDelay; interval: 40; onTriggered: fx.start() }

  function start() {
    anim.from = fx.reverse ? 1 : 0
    anim.to = fx.reverse ? 0 : 1
    anim.duration = (fx.effect === "genie" ? 520 : fx.effect === "fade" ? 260 : 340) * 100 / Math.max(10, fx.speed)
    anim.start()
  }

  Timer {
    id: holdTimer
    interval: 16
    repeat: true
    property int ticks: 0
    property int settle: 0
    onTriggered: {
      // Once the window is back, a few more frames, so it has drawn itself
      // under the picture before the picture goes.
      if (fx.holdWhile && fx.holdWhile() && ticks <= 60) { ticks++; return }
      if (++settle < 4 && ticks <= 60) return
      stop()
      ticks = 0
      settle = 0
      fx.holding = false
      fx.holdWhile = null
      fx.toplevel = null
    }
  }

  NumberAnimation {
    id: anim
    target: fx
    property: "progress"
    easing.type: Easing.InOutQuad
    onFinished: fx.finish(true)
  }

  // ---------- the picture: the window with its corners and border ----------
  Item {
    id: picture
    x: fx.from.x
    y: fx.from.y
    width: fx.from.width
    height: fx.from.height
    visible: false

    ScreencopyView {
      id: capture
      x: fx.borderSize
      y: fx.borderSize
      width: picture.width - 2 * fx.borderSize
      height: picture.height - 2 * fx.borderSize
      captureSource: fx.active && fx.toplevel ? fx.toplevel.wayland : null
      live: fx.active
    }
    // The window's picture as a texture, to fill a rounded shape with (its
    // corners rounded like the window's). It has to stay visible to keep
    // updating, so it sits outside the picture's area, where it's never seen.
    ShaderEffectSource {
      id: captureTexture
      x: -width - 16
      y: 0
      width: capture.width
      height: capture.height
      sourceItem: capture
      hideSource: true
      live: true
    }
    Shape {
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      // Behind see-through windows Hyprland blurs what's under them; the
      // picture can't carry that, so it gets the theme's background instead.
      ShapePath {
        strokeWidth: 0
        strokeColor: "transparent"
        fillColor: fx.backdrop
        PathSvg { path: fx.roundedRect(fx.borderSize, fx.borderSize, capture.width, capture.height, fx.rounding) }
      }
      ShapePath {
        strokeWidth: 0
        strokeColor: "transparent"
        fillItem: captureTexture
        fillTransform: PlanarTransform.fromTranslate(fx.borderSize, fx.borderSize)
        PathSvg { path: fx.roundedRect(fx.borderSize, fx.borderSize, capture.width, capture.height, fx.rounding) }
      }
    }

    // The border: a rounded ring filled with the window's gradient.
    Shape {
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        strokeWidth: 0
        strokeColor: "transparent"
        fillRule: ShapePath.OddEvenFill
        fillGradient: LinearGradient {
          x1: fx.gradLine.x1; y1: fx.gradLine.y1
          x2: fx.gradLine.x2; y2: fx.gradLine.y2
          GradientStop { position: 0 / 7; color: fx.borderColors[Math.min(0, fx.borderColors.length - 1)] }
          GradientStop { position: 1 / 7; color: fx.borderColors[Math.min(1, fx.borderColors.length - 1)] }
          GradientStop { position: 2 / 7; color: fx.borderColors[Math.min(2, fx.borderColors.length - 1)] }
          GradientStop { position: 3 / 7; color: fx.borderColors[Math.min(3, fx.borderColors.length - 1)] }
          GradientStop { position: 4 / 7; color: fx.borderColors[Math.min(4, fx.borderColors.length - 1)] }
          GradientStop { position: 5 / 7; color: fx.borderColors[Math.min(5, fx.borderColors.length - 1)] }
          GradientStop { position: 6 / 7; color: fx.borderColors[Math.min(6, fx.borderColors.length - 1)] }
          GradientStop { position: 7 / 7; color: fx.borderColors[Math.min(7, fx.borderColors.length - 1)] }
        }
        PathSvg { path: fx.roundedRect(0, 0, picture.width, picture.height, fx.rounding + fx.borderSize) }
        PathSvg { path: fx.roundedRect(fx.borderSize, fx.borderSize, picture.width - 2 * fx.borderSize, picture.height - 2 * fx.borderSize, fx.rounding) }
      }
    }
  }

  function roundedRect(x, y, w, h, r) {
    r = Math.max(0, Math.min(r, w / 2, h / 2))
    if (r === 0) return "M " + x + " " + y + " h " + w + " v " + h + " h " + (-w) + " Z"
    return "M " + (x + r) + " " + y + " L " + (x + w - r) + " " + y + " A " + r + " " + r + " 0 0 1 " + (x + w) + " " + (y + r)
      + " L " + (x + w) + " " + (y + h - r) + " A " + r + " " + r + " 0 0 1 " + (x + w - r) + " " + (y + h)
      + " L " + (x + r) + " " + (y + h) + " A " + r + " " + r + " 0 0 1 " + x + " " + (y + h - r)
      + " L " + x + " " + (y + r) + " A " + r + " " + r + " 0 0 1 " + (x + r) + " " + y + " Z"
  }

  function lerp(a, b, t) { return a + (b - a) * t }
  function clamp01(t) { return Math.max(0, Math.min(1, t)) }
  function smooth(t) { t = clamp01(t); return t * t * (3 - 2 * t) }

  // ---------- genie: one picture, warped ----------
  // shaders/genie.vert bends the picture as a mesh of rows: each row heads
  // for the dock on its own schedule (the bottom ones first) and narrows as
  // it goes down, so the sides bend smoothly and the picture stays whole.

  // Shown once the picture has a frame (never an empty one).
  readonly property bool pictureReady: capture.hasContent

  // The picture as a texture for the shader. It has to stay visible to keep
  // updating, so it sits off to the side, where it's never seen.
  ShaderEffectSource {
    id: pictureTexture
    x: -width - 16
    y: 0
    width: picture.width
    height: picture.height
    sourceItem: picture
    hideSource: true
    live: true
  }

  ShaderEffect {
    anchors.fill: parent
    visible: fx.active && fx.effect === "genie" && fx.pictureReady
    property var source: pictureTexture
    property real progress: fx.progress
    property vector4d fromRect: Qt.vector4d(fx.from.x, fx.from.y, fx.from.width, fx.from.height)
    property vector4d toRect: Qt.vector4d(fx.to.x, fx.to.y, fx.to.width, fx.to.height)
    mesh: GridMesh { resolution: Qt.size(4, 96) }
    vertexShader: "shaders/genie.vert.qsb"
    fragmentShader: "shaders/genie.frag.qsb"
  }

  // ---------- scale, fade and slide: the whole picture ----------
  ShaderEffectSource {
    visible: fx.active && fx.effect !== "genie" && fx.pictureReady
    sourceItem: picture
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
