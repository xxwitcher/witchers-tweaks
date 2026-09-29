import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons

// Close, minimize and maximize buttons for floating windows (the titlebars
// tweak). Hovering a floating window's top-left corner grows a tab out of
// its top edge, /‾‾‾\ shaped, with the three buttons in it: filled like the
// window, and outlined with the window's own border gradient, which the tab
// takes over where it sits, so the border seems to run up and around it.
//
// Each visible floating window gets a small surface of its own over that
// corner (just above the window, so its content stays clickable). A window
// whose corner is covered by a window focused more recently gets none.
Item {
  id: root
  visible: false

  property var shell: null

  // The invisible drag strip's height (bar_height in witchers-tweaks.lua).
  readonly property int stripHeight: 14
  property int borderSize: 2
  property int rounding: 0

  // ---------- the border, as Hyprland draws it ----------

  // Colors (8 for the gradient border, 1 for a flat one), and the angle it
  // points at, read from Hyprland; between readings the angle turns at the
  // border tweak's speed, so the tab keeps up with the spinning border.
  property var activeColors: ["#eec4b5fd"]
  property var inactiveColors: ["#aa5b3a7a"]
  property real angleBase: 45
  property real angleAt: 0
  property bool spinning: false
  property real now: 0
  readonly property real angle: spinning ? (angleBase + (now - angleAt) / 1000 * 360 / 13.33) % 360 : angleBase

  function parseColors(text) {
    var parts = String(text || "").trim().split(/\s+/)
    var colors = []
    var angle = null
    for (var i = 0; i < parts.length; i++) {
      var p = parts[i]
      if (/deg$/.test(p)) angle = Number(p.replace("deg", ""))
      else if (/^[0-9a-fA-F]{8}$/.test(p)) colors.push("#" + p)
    }
    return { colors: colors, angle: angle }
  }

  function readBorder() { borderReader.running = true }
  Process {
    id: borderReader
    command: ["bash", "-c", "hyprctl getoption general:col.active_border -j; echo; hyprctl getoption general:col.inactive_border -j; echo; hyprctl getoption general:border_size -j; echo; hyprctl getoption decoration:rounding -j; echo; grep -qsx gradient-border \"$HOME/.config/witchers-tweaks/tweaks.conf\" && echo spin"]
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = text.split("\n").filter(function(l) { return l.trim() !== "" })
        try {
          var a = JSON.parse(lines[0])
          var parsed = root.parseColors(a.gradient || (a.color ? a.color : ""))
          if (parsed.colors.length > 0) root.activeColors = parsed.colors
          root.angleBase = parsed.angle !== null ? parsed.angle : 0
          root.angleAt = Date.now()
          root.now = root.angleAt
          var i = JSON.parse(lines[1])
          var ip = root.parseColors(i.gradient || (i.color ? i.color : ""))
          if (ip.colors.length > 0) root.inactiveColors = ip.colors
          root.borderSize = JSON.parse(lines[2]).int || 2
          root.rounding = JSON.parse(lines[3]).int || 0
          root.spinning = lines.length > 4 && lines[4].trim() === "spin"
        } catch (e) {}
      }
    }
  }
  Component.onCompleted: { readBorder(); poll() }

  // While a tab shows, the clock runs for the spin and the angle is read
  // again now and then, so the two can't drift apart.
  property int showing: 0
  FrameAnimation {
    running: root.showing > 0 && root.spinning
    onTriggered: root.now = Date.now()
  }
  Timer {
    interval: 2000
    repeat: true
    running: root.showing > 0
    onTriggered: root.readBorder()
  }

  // Hyprland's border gradient: over the window's border box, progress runs
  // along x and y weighted by the angle's sine (mirrored per quadrant), and
  // the colors are spread evenly along it. It's linear, so it's a
  // LinearGradient from where progress is 0 to where it's 1.
  function gradientLine(box, angleDeg) {
    var a = angleDeg * Math.PI / 180
    var fx = false, fy = false, ang = a
    if (a > 4.71) { fy = true; ang = 6.28 - a }
    else if (a > 3.14) { fx = true; fy = true; ang = a - 3.14 }
    else if (a > 1.57) { fx = true; ang = 3.14 - a }
    var s = Math.sin(ang)
    // progress = u * (1 - s) + v * s, u and v the (mirrored) 0..1 coordinates.
    var gx = (1 - s) / box.w * (fx ? -1 : 1)
    var gy = s / box.h * (fy ? -1 : 1)
    var ox = fx ? box.x + box.w : box.x
    var oy = fy ? box.y + box.h : box.y
    var len2 = gx * gx + gy * gy
    if (len2 === 0) return { x1: ox, y1: oy, x2: ox + 1, y2: oy }
    return { x1: ox, y1: oy, x2: ox + gx / len2, y2: oy + gy / len2 }
  }

  // ---------- the windows ----------

  // Where the floating windows are, read straight from Hyprland's request
  // socket ("j/clients") rather than through Quickshell's window list, whose
  // refresh would make everything else watching windows (the dock) redo its
  // work too. Hyprland's events (opened, closed, floated, focused,
  // fullscreen, workspace changes) ask again; floating windows can also move
  // without an event, so while any is on screen their places are asked for a
  // few times a second. Nothing updates unless one actually changed, and
  // with none on screen nothing runs.

  // Visible floating windows by address: { x, y, w, h, history }.
  property var windowInfo: ({})
  property string snapshot: ""
  property string reply: ""

  function addressKey(value) { return String(value || "").replace(/^0x/, "").toLowerCase() }

  Socket {
    id: query
    path: Hyprland.requestSocketPath
    parser: SplitParser {
      splitMarker: ""
      // Hyprland closes the connection after its reply; hanging up as soon
      // as the reply is whole keeps that from being logged as an error.
      onRead: data => {
        root.reply += data
        if (/\]\s*$/.test(root.reply) && root.take(root.reply)) { root.reply = ""; query.connected = false }
      }
    }
    onConnectedChanged: {
      if (connected) {
        root.reply = ""
        write("j/clients")
        flush()
      } else {
        if (root.reply !== "") root.take(root.reply)
        root.reply = ""
      }
    }
  }

  function poll() { if (!query.connected) query.connected = true }

  function take(text) {
    var list
    try { list = JSON.parse(text) } catch (e) { return false }
    // The workspace each monitor shows.
    var shown = ({})
    var monitors = Hyprland.monitors ? Hyprland.monitors.values : []
    for (var m = 0; m < monitors.length; m++)
      if (monitors[m].activeWorkspace) shown[monitors[m].id] = monitors[m].activeWorkspace.id
    var info = ({})
    for (var i = 0; i < list.length; i++) {
      var c = list[i]
      if (!c.floating || c.fullscreen || !c.workspace || c.workspace.id < 0 || shown[c.monitor] !== c.workspace.id) continue
      info[addressKey(c.address)] = { x: c.at[0], y: c.at[1], w: c.size[0], h: c.size[1], history: c.focusHistoryID }
    }
    var next = JSON.stringify(info)
    if (next === snapshot) return true
    snapshot = next
    windowInfo = info
    return true
  }

  readonly property bool anyFloating: snapshot !== "" && snapshot !== "{}"
  Timer {
    interval: 400
    repeat: true
    running: root.anyFloating
    onTriggered: root.poll()
  }
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      if (/^(openwindow|closewindow|movewindowv2|changefloatingmode|fullscreen|workspacev2|activewindowv2|focusedmonv2)$/.test(name))
        eventPoll.restart()
    }
  }
  Timer { id: eventPoll; interval: 60; onTriggered: root.poll() }

  // The windows themselves are the model (so each keeps its surface while it
  // moves). A corner covered by a more recently focused window gets no tab.
  readonly property var floating: {
    var info = windowInfo
    var tops = Hyprland.toplevels ? Hyprland.toplevels.values : []
    var list = []
    for (var i = 0; i < tops.length; i++) {
      var w = tops[i] ? info[addressKey(tops[i].address)] : null
      if (w) list.push({ top: tops[i], x: w.x, y: w.y, w: w.w, h: w.h, history: w.history })
    }
    return list.filter(function(a) {
      var zx = a.x, zy = a.y - root.stripHeight - 30
      return !list.some(function(b) {
        return b !== a && b.history < a.history
          && b.x < zx + 150 && b.x + b.w > zx && b.y < a.y && b.y + b.h > zy
      })
    }).map(function(a) { return a.top })
  }

  function dispatch(lua) { Quickshell.execDetached(["hyprctl", "dispatch", lua]) }

  Variants {
    model: root.floating

    PanelWindow {
      id: area
      required property var modelData
      readonly property var info: root.windowInfo[root.addressKey(modelData.address)] || ({ x: 0, y: 0, w: 1, h: 1 })
      readonly property var mon: modelData.monitor || ({ name: "", x: 0, y: 0 })
      readonly property string address: "0x" + String(modelData.address).replace(/^0x/, "")
      readonly property bool focused: Hyprland.activeToplevel === modelData

      // Window geometry (layout coordinates); the border box is around it.
      readonly property real wx: info.x
      readonly property real wy: info.y
      readonly property real ww: info.w
      readonly property real wh: info.h
      readonly property int bw: root.borderSize

      // The tab: the window's left side carried straight up, its top then
      // bending down into the window's top edge. Every corner uses the
      // window rounding. In this surface's coordinates, the window's border
      // box starts at x 0 and its top border line at y edge.
      readonly property int tabHeight: 24
      readonly property real radius: root.rounding + bw                 // the border's outer rounding
      readonly property real edge: tabHeight + 2
      readonly property real buttonsX: bw + Math.max(10, root.rounding * 0.6)
      readonly property real stepAt: buttonsX + 55 + 14                  // where the top starts to bend down
      readonly property real stepWidth: tabHeight * 1.2
      readonly property real endX: stepAt + stepWidth + radius + 10       // where the tab's border rejoins the window's
      readonly property real cornerEnd: edge + bw + root.rounding         // where the window's left side stops curving

      screen: {
        for (var i = 0; i < Quickshell.screens.length; i++)
          if (Quickshell.screens[i].name === area.mon.name) return Quickshell.screens[i]
        return null
      }
      anchors { top: true; left: true }
      margins.left: wx - bw - mon.x
      margins.top: Math.max(0, wy - bw - mon.y - edge)
      implicitWidth: endX + 4
      implicitHeight: cornerEnd + 1
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "witcher-titlebars"
      WlrLayershell.layer: WlrLayer.Top

      // Only the space above the window takes the pointer (and the tab,
      // once it shows); the window's own corner stays clickable.
      mask: Region { item: area.shown ? tabArea : aboveWindow }
      Item { id: tabArea; width: area.endX; height: area.edge + area.bw }
      Item { id: aboveWindow; width: area.endX; height: area.edge }

      // Growing out of the window on hover, back in after a moment.
      // Opens when the pointer rests on the corner of a window that isn't
      // moving: while a window is dragged its surface trails behind it, and
      // the pointer sweeping over that spot mustn't open a tab there.
      property bool shown: false
      property real grow: shown ? 1 : 0
      Behavior on grow { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
      onShownChanged: root.showing += shown ? 1 : -1
      Component.onDestruction: if (shown) root.showing--

      property double movedAt: 0
      onWxChanged: windowMoved()
      onWyChanged: windowMoved()
      function windowMoved() {
        movedAt = Date.now()
        if (shown) shown = false
      }

      HoverHandler {
        id: hover
        onHoveredChanged: {
          if (hovered) {
            hideDelay.stop()
            if (!area.shown) rest.restart()
          } else {
            rest.stop()
            hideDelay.restart()
          }
        }
      }
      Timer {
        id: rest
        interval: 120
        onTriggered: {
          if (!hover.hovered) return
          if (Date.now() - area.movedAt < 500) { rest.restart(); return }
          sampler.running = true
        }
      }
      Timer { id: hideDelay; interval: 450; onTriggered: if (!hover.hovered) area.shown = false }

      // The app's own color at its top-left corner, for the tab's fill (the
      // theme's background when it can't be read): one pixel, read with grim
      // just before the tab opens.
      property color fill: Color.background
      Process {
        id: sampler
        command: ["bash", "-c", "grim -g \"" + Math.round(area.wx + Math.max(3, root.rounding * 0.35)) + ","
          + Math.round(area.wy + Math.max(3, root.rounding * 0.35)) + " 1x1\" -t ppm - 2>/dev/null | tail -c 3 | od -An -tu1"]
        stdout: StdioCollector {
          onStreamFinished: {
            var rgb = text.trim().split(/\s+/).map(Number)
            area.fill = rgb.length === 3 && rgb.every(function(n) { return isFinite(n) })
              ? Qt.rgba(rgb[0] / 255, rgb[1] / 255, rgb[2] / 255, 1) : Color.background
            if (hover.hovered && Date.now() - area.movedAt >= 500) area.shown = true
          }
        }
      }

      readonly property real tabTop: edge - tabHeight * grow
      // The border box, in this surface's coordinates.
      readonly property var box: ({ x: 0, y: edge, w: ww + 2 * bw, h: wh + 2 * bw })
      readonly property var gradLine: root.gradientLine(box, root.angle)
      readonly property var colors: focused ? root.activeColors : root.inactiveColors

      // A path through the points (not closed), each corner rounded by its r
      // (clamped to half the shorter side next to it).
      function rounded(points) {
        var n = points.length
        var p = ""
        for (var k = 0; k < n; k++) {
          var v = points[k], a = points[(k - 1 + n) % n], b = points[(k + 1) % n]
          var r = v.r || 0
          if (r <= 0) { p += (k === 0 ? "M " : " L ") + v.x + " " + v.y; continue }
          if (k === 0 || k === n - 1) { p += (k === 0 ? "M " : " L ") + v.x + " " + v.y; continue }
          var la = Math.hypot(a.x - v.x, a.y - v.y), lb = Math.hypot(b.x - v.x, b.y - v.y)
          var d = Math.min(r, la / 2, lb / 2)
          var inX = v.x + (a.x - v.x) / la * d, inY = v.y + (a.y - v.y) / la * d
          var outX = v.x + (b.x - v.x) / lb * d, outY = v.y + (b.y - v.y) / lb * d
          p += (k === 0 ? "M " : " L ") + inX + " " + inY + " Q " + v.x + " " + v.y + " " + outX + " " + outY
        }
        return p
      }

      // The silhouette (inset 0: the border's outer edge; inset bw: the
      // inside). The bend's slant is offset along its normal, so the border
      // keeps its width there too. At the bottom it follows the window's own
      // rounded corner, so it only fills the sliver the window doesn't draw
      // (between that curve and the tab's straight left side) and never
      // covers the app.
      function outline(inset) {
        var i = inset
        var h = edge - tabTop, w = stepWidth
        var len = Math.hypot(w, h)
        var nx = -h / len * i, ny = w / len * i
        var topY = tabTop + i, lowY = edge + i
        var bendX = h > 0 ? stepAt + nx + (i - ny) / h * w : stepAt
        var footX = h > 0 ? stepAt + nx + (h + i - ny) / h * w : stepAt + w
        var r = Math.max(0, radius - i)
        var R = root.rounding
        var p = rounded([
          { x: i, y: cornerEnd },
          { x: i, y: topY, r: r },
          { x: bendX, y: topY, r: r },
          { x: footX, y: lowY, r: r },
          { x: endX, y: lowY },
          { x: endX, y: edge + bw },
          { x: bw + R, y: edge + bw }
        ])
        // The inside (inset > 0) goes back down along the window's corner
        // (the edge of its content), on the same center but a little inside
        // it, so none of the window's own softened border edge shows. The
        // gradient under it (inset 0) turns at the corner square instead,
        // so it ends well inside the fill and nothing of it shows at the
        // fill's softened curved edge.
        if (i === 0) p += " L " + bw + " " + (edge + bw) + " L " + bw + " " + cornerEnd
        else {
          var d = Math.min(1.5, R)
          if (R > 0) p += " L " + (bw + R) + " " + (edge + bw + d)
            + " A " + (R - d) + " " + (R - d) + " 0 0 0 " + (bw + d) + " " + cornerEnd
          p += " L " + bw + " " + cornerEnd
        }
        return p + " L " + i + " " + cornerEnd + " Z"
      }

      Shape {
        anchors.fill: parent
        visible: area.grow > 0.02
        preferredRendererType: Shape.CurveRenderer

        // The outline: the border gradient, continuing the window's.
        ShapePath {
          strokeWidth: 0
          strokeColor: "transparent"
          fillGradient: LinearGradient {
            x1: area.gradLine.x1; y1: area.gradLine.y1
            x2: area.gradLine.x2; y2: area.gradLine.y2
            GradientStop { position: 0 / 7; color: area.colors[Math.min(0, area.colors.length - 1)] }
            GradientStop { position: 1 / 7; color: area.colors[Math.min(1, area.colors.length - 1)] }
            GradientStop { position: 2 / 7; color: area.colors[Math.min(2, area.colors.length - 1)] }
            GradientStop { position: 3 / 7; color: area.colors[Math.min(3, area.colors.length - 1)] }
            GradientStop { position: 4 / 7; color: area.colors[Math.min(4, area.colors.length - 1)] }
            GradientStop { position: 5 / 7; color: area.colors[Math.min(5, area.colors.length - 1)] }
            GradientStop { position: 6 / 7; color: area.colors[Math.min(6, area.colors.length - 1)] }
            GradientStop { position: 7 / 7; color: area.colors[Math.min(7, area.colors.length - 1)] }
          }
          PathSvg { path: area.outline(0) }
        }
        // The inside, like the window: it covers the window's border under
        // the tab and its rounded top-left corner.
        ShapePath {
          strokeWidth: 0
          strokeColor: "transparent"
          fillColor: area.fill
          PathSvg { path: area.outline(area.bw) }
        }
      }

      // The buttons.
      Row {
        id: buttons
        x: area.buttonsX + 4
        y: area.tabTop + (area.edge - area.tabTop - height) / 2 + 1
        spacing: 8
        opacity: area.grow
        Repeater {
          // The same colors as the buttons in the top bar: dots in the bar's
          // icon color, symbols in its background color.
          model: [
            { symbol: "×", action: "close" },
            { symbol: "−", action: "minimize" },
            { symbol: "+", action: "maximize" }
          ]
          Rectangle {
            id: button
            required property var modelData
            width: 13
            height: 13
            radius: 6.5
            color: Color.bar.text
            Text {
              anchors.centerIn: parent
              anchors.verticalCenterOffset: -1
              text: button.modelData.symbol
              color: Color.bar.background
              font.pixelSize: 11
              font.bold: true
            }
            MouseArea {
              anchors.fill: parent
              enabled: area.shown
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                var a = "address:" + area.address
                if (button.modelData.action === "close")
                  root.dispatch("hl.dsp.window.close({ window = \"" + a + "\" })")
                else if (button.modelData.action === "minimize")
                  // Through the dock (it animates it without a blink), else straight away.
                  Quickshell.execDetached(["bash", "-c", "omarchy-shell witcher.dock minimize " + a.replace("address:", "") + " >/dev/null 2>&1 || hyprctl dispatch 'hl.dsp.window.move({ window = \"" + a + "\", workspace = \"special:minimized\", follow = false })'"])
                else
                  Quickshell.execDetached(["bash", "-c", "hyprctl dispatch 'hl.dsp.focus({ window = \"" + a + "\" })' >/dev/null && hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = \"maximized\" })' >/dev/null"])
              }
            }
          }
        }
      }
    }
  }
}
