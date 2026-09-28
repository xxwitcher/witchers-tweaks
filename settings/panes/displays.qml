import QtQuick
import Quickshell
import "../components"

// Monitors: arrangement, resolution, scale, rotation, mirroring and on/off.
// Changes apply live through monitors/monitor-setup and revert by themselves
// after 15 seconds unless you keep them (then they're saved to monitors.lua).
// Also brightness and night light.
Column {
  id: pane
  spacing: 22

  property var saved: []      // monitors as Hyprland had them
  property var edits: []      // the same, with your changes
  property int picked: 0
  property bool changed: false
  property int keepSeconds: 0

  function load() {
    App.helper(["monitors"], function(out) {
      try {
        var list = JSON.parse(out).map(function(m) {
          return {
            name: m.name,
            description: String(m.description || "").trim(),
            modes: (m.availableModes || []).map(function(x) { return String(x).replace(/Hz$/, "") }),
            mode: m.width + "x" + m.height + "@" + Number(m.refreshRate).toFixed(2),
            width: m.width, height: m.height,
            x: m.x, y: m.y,
            scale: m.scale,
            transform: m.transform,
            mirror: m.mirrorOf && m.mirrorOf !== "none" ? m.mirrorOf : "",
            disabled: m.disabled === true
          }
        })
        list.sort(function(a, b) { return a.x - b.x || a.y - b.y })
        pane.saved = JSON.parse(JSON.stringify(list))
        pane.edits = list
        pane.changed = false
        if (pane.picked >= list.length) pane.picked = 0
      } catch (e) {}
    })
  }
  Component.onCompleted: load()

  readonly property var current: picked < edits.length ? edits[picked] : null

  function edit(key, value) {
    var list = JSON.parse(JSON.stringify(edits))
    list[picked][key] = value
    edits = list
    changed = JSON.stringify(edits) !== JSON.stringify(saved)
  }

  // A monitor's size on the desktop (rotation and scale applied).
  function logical(m) {
    var parts = String(m.mode).split("@")[0].split("x")
    var w = Number(parts[0]) || m.width, h = Number(parts[1]) || m.height
    if (m.transform % 2 === 1) { var t = w; w = h; h = t }
    var s = Number(m.scale) || 1
    return { w: Math.round(w / s), h: Math.round(h / s) }
  }

  function payload(list) {
    return JSON.stringify(list.map(function(m) {
      return { name: m.name, mode: m.mode, x: m.x, y: m.y, scale: m.scale, transform: m.transform, mirror: m.mirror, disabled: m.disabled }
    }))
  }

  function applyEdits() {
    App.sh("printf '%s' " + shellQuote(payload(edits)) + " | \"$WITCHER_REPO/monitors/monitor-setup\" --apply", function() {
      pane.keepSeconds = 15
      countdown.restart()
    })
  }
  function keep() {
    countdown.stop()
    keepSeconds = 0
    App.sh("printf '%s' " + shellQuote(payload(edits)) + " | \"$WITCHER_REPO/monitors/monitor-setup\" --save", function(out, code) {
      App.toast(code === 0 ? "Display settings saved" : "Couldn't save: " + out.trim().split("\n").pop())
      pane.load()
    })
  }
  function revert() {
    countdown.stop()
    keepSeconds = 0
    App.sh("printf '%s' " + shellQuote(payload(saved)) + " | \"$WITCHER_REPO/monitors/monitor-setup\" --apply", function() { pane.load() })
  }
  function shellQuote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

  Timer {
    id: countdown
    interval: 1000
    repeat: true
    onTriggered: {
      pane.keepSeconds--
      if (pane.keepSeconds <= 0) pane.revert()
    }
  }

  // ---------- arrangement ----------
  Group {
    title: "Arrangement"
    Item {
      id: arrangement
      width: parent.width
      height: 200
      readonly property var bounds: {
        var minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9
        for (var i = 0; i < pane.edits.length; i++) {
          var m = pane.edits[i]
          if (m.disabled) continue
          var l = pane.logical(m)
          minX = Math.min(minX, m.x); minY = Math.min(minY, m.y)
          maxX = Math.max(maxX, m.x + l.w); maxY = Math.max(maxY, m.y + l.h)
        }
        if (minX > maxX) return { x: 0, y: 0, w: 1, h: 1 }
        return { x: minX, y: minY, w: maxX - minX, h: maxY - minY }
      }
      readonly property real ratio: Math.min((width - 40) / bounds.w, (height - 40) / bounds.h)
      readonly property real ox: (width - bounds.w * ratio) / 2
      readonly property real oy: (height - bounds.h * ratio) / 2

      Repeater {
        model: pane.edits
        Rectangle {
          id: screenBox
          required property var modelData
          required property int index
          readonly property var size: pane.logical(modelData)
          visible: !modelData.disabled
          // Placed from the monitor's position, except while it's dragged.
          Binding on x {
            when: !dragArea.drag.active
            value: arrangement.ox + (screenBox.modelData.x - arrangement.bounds.x) * arrangement.ratio
          }
          Binding on y {
            when: !dragArea.drag.active
            value: arrangement.oy + (screenBox.modelData.y - arrangement.bounds.y) * arrangement.ratio
          }
          width: size.w * arrangement.ratio
          height: size.h * arrangement.ratio
          radius: 6
          color: index === pane.picked ? App.tint : App.control
          border.width: 1
          border.color: App.line
          Text {
            anchors.centerIn: parent
            width: parent.width - 8
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: (screenBox.index + 1) + "  " + (screenBox.modelData.description || screenBox.modelData.name)
            color: screenBox.index === pane.picked ? App.onTint : App.fg
            font.family: App.font
            font.pixelSize: App.small
          }
          MouseArea {
            id: dragArea
            anchors.fill: parent
            cursorShape: Qt.OpenHandCursor
            drag.target: pane.edits.length > 1 ? screenBox : null
            onPressed: pane.picked = screenBox.index
            onReleased: {
              if (!drag.active && pane.edits.length <= 1) return
              // Back to desktop coordinates, snapped to the other screens' edges.
              var nx = Math.round((screenBox.x - arrangement.ox) / arrangement.ratio + arrangement.bounds.x)
              var ny = Math.round((screenBox.y - arrangement.oy) / arrangement.ratio + arrangement.bounds.y)
              var snap = 60
              for (var i = 0; i < pane.edits.length; i++) {
                if (i === screenBox.index || pane.edits[i].disabled) continue
                var o = pane.edits[i], ol = pane.logical(o)
                var edgesX = [o.x - screenBox.size.w, o.x + ol.w, o.x, o.x + ol.w - screenBox.size.w]
                var edgesY = [o.y - screenBox.size.h, o.y + ol.h, o.y, o.y + ol.h - screenBox.size.h]
                for (var a = 0; a < edgesX.length; a++) if (Math.abs(nx - edgesX[a]) < snap) nx = edgesX[a]
                for (var b = 0; b < edgesY.length; b++) if (Math.abs(ny - edgesY[b]) < snap) ny = edgesY[b]
              }
              var list = JSON.parse(JSON.stringify(pane.edits))
              list[screenBox.index].x = nx
              list[screenBox.index].y = ny
              pane.edits = list
              pane.changed = JSON.stringify(pane.edits) !== JSON.stringify(pane.saved)
            }
          }
        }
      }
    }
  }

  // ---------- keep or revert ----------
  Rectangle {
    visible: pane.keepSeconds > 0
    width: parent.width
    height: 56
    radius: App.radius
    color: App.tint
    Text {
      x: 16
      anchors.verticalCenter: parent.verticalCenter
      text: "Keep these display settings? Reverting in " + pane.keepSeconds + " s"
      color: App.onTint
      font.family: App.font
      font.pixelSize: App.body
    }
    Row {
      anchors.right: parent.right
      anchors.rightMargin: 12
      anchors.verticalCenter: parent.verticalCenter
      spacing: 8
      PillButton { text: "Revert"; onClicked: pane.revert() }
      PillButton { text: "Keep"; onClicked: pane.keep() }
    }
  }

  // ---------- the picked monitor ----------
  Group {
    visible: pane.current !== null
    title: pane.current ? (pane.picked + 1) + ". " + (pane.current.description || pane.current.name) : ""
    SwitchRow {
      visible: pane.edits.length > 1
      label: "Use this display"
      checked: pane.current ? !pane.current.disabled : true
      onToggled: function(wanted) { pane.edit("disabled", !wanted) }
    }
    ChoiceRow {
      label: "Resolution"
      options: pane.current ? pane.current.modes.map(function(m) {
        var p = m.split("@")
        return { value: p[0] + "@" + Number(p[1]).toFixed(2), label: p[0].replace("x", " × ") + "  ·  " + Number(p[1]).toFixed(0) + " Hz" }
      }) : []
      current: pane.current ? pane.current.mode : ""
      searchable: false
      buttonWidth: 260
      onChosen: function(v) { pane.edit("mode", v) }
    }
    ChoiceRow {
      label: "Scale"
      options: [1, 1.25, 1.333333, 1.5, 1.6, 1.666667, 1.75, 2, 2.5, 3].map(function(s) { return { value: s, label: Math.round(s * 100) + "%" } })
      current: pane.current ? Number(pane.current.scale) : 1
      onChosen: function(v) { pane.edit("scale", v) }
    }
    SegmentedRow {
      label: "Rotation"
      options: [{ value: 0, label: "Standard" }, { value: 1, label: "90°" }, { value: 2, label: "180°" }, { value: 3, label: "270°" }]
      current: pane.current ? pane.current.transform % 4 : 0
      onChosen: function(v) { pane.edit("transform", v) }
    }
    ChoiceRow {
      visible: pane.edits.length > 1
      label: "Mirror"
      options: [{ value: "", label: "Don't mirror" }].concat(pane.edits.filter(function(m, i) { return i !== pane.picked }).map(function(m) {
        return { value: m.name, label: "Mirror " + (m.description || m.name) }
      }))
      current: pane.current ? pane.current.mirror : ""
      onChosen: function(v) { pane.edit("mirror", v) }
    }
    SettingRow {
      label: "Changes"
      sublabel: pane.changed ? "Not applied" : ""
      Row {
        spacing: 8
        PillButton { text: "Undo"; enabled2: pane.changed; onClicked: pane.load() }
        PillButton { text: "Apply"; prominent: true; enabled2: pane.changed && pane.keepSeconds === 0; onClicked: pane.applyEdits() }
      }
    }
  }

  // ---------- brightness and color ----------
  Group {
    title: "Brightness and color"
    SliderRow {
      label: "Brightness"
      from: 1; to: 100; step: 1
      value: Number(App.status.brightness || 100)
      format: function(v) { return Math.round(v) + "%" }
      onChanged: function(v) { App.apply(["omarchy-brightness-display", "--no-osd", Math.round(v) + "%"]) }
    }
    SwitchRow {
      label: "Night light"
      checked: App.status.nightlight === true
      onToggled: function(wanted) { if (wanted !== (App.status.nightlight === true)) App.apply(["omarchy-toggle-nightlight"]) }
    }
    ButtonRow {
      label: "Night light schedule"
      buttonText: "Edit…"
      onClicked: App.shDetached("omarchy-launch-config-editor ~/.config/hypr/hyprsunset.conf && omarchy-restart-hyprsunset")
    }
  }

  Group {
    visible: App.status.laptop === true
    title: "Laptop screen"
    ButtonRow { label: "Turn the laptop screen on or off"; buttonText: "Toggle"; onClicked: App.detached(["omarchy-hyprland-monitor-internal", "toggle"]) }
    ButtonRow { label: "Mirror the laptop screen"; buttonText: "Toggle"; onClicked: App.detached(["omarchy-hyprland-monitor-internal-mirror", "toggle"]) }
  }
}
