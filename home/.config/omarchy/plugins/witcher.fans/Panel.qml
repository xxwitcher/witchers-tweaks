import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Fan control for Apple Silicon Macs. Each fan is
// either left to the SMC (Auto), run flat out (Full Blast), held at a fixed
// speed (Constant), or driven by a temperature sensor (Range): minimum speed
// at or below "Quiet at", maximum at or above "Full blast at", in a straight
// line between. bin/fans reads and
// writes the kernel's macsmc_hwmon files; the choices live in this widget's
// shell.json entry and are applied again whenever the shell starts.
// Right-click the icon to show the speed in the bar.
Panel {
  id: root
  moduleName: "witcher.fans"
  ipcTarget: "witcher.fans"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string fansCommand: pluginDir + "/bin/fans"

  readonly property string fanIcon: "󰈐"
  readonly property bool showSpeed: setting("showSpeed", false) === true
  readonly property var fanSettings: setting("fans", ({}))

  // Last `fans read`.
  property bool present: false
  property bool control: false
  property var fans: []
  property var temps: []
  property string lastError: ""

  // What was last written to each fan: "auto" or a speed. A fan is only
  // written when its wanted value moves away from this.
  property var applied: ({})

  readonly property int speed: fans.length > 0 ? (fans[0].rpm || 0) : 0

  // Title bar text: every fan's speed, and the range they can run in.
  readonly property string speedText: fans.length === 0 ? ""
    : fans.map(function(f) { return f.rpm }).join(" · ") + " RPM"
  readonly property string rangeText: fans.length === 0 ? ""
    : fans[0].min + "–" + fans[0].max + " RPM"

  function fanConfig(n) {
    var c = fanSettings ? fanSettings[String(n)] : null
    return {
      // "sensor" is what Range was called at first.
      mode: c && c.mode ? (c.mode === "sensor" ? "range" : String(c.mode)) : "auto",
      rpm: c && isFinite(Number(c.rpm)) ? Number(c.rpm) : 0,
      sensor: c && c.sensor ? String(c.sensor) : "",
      from: c && isFinite(Number(c.from)) ? Number(c.from) : 50,
      to: c && isFinite(Number(c.to)) ? Number(c.to) : 80
    }
  }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setFanConfig(n, values) {
    var all = JSON.parse(JSON.stringify(fanSettings || {}))
    var c = fanConfig(n)
    for (var key in values) c[key] = values[key]
    all[String(n)] = c
    persistSettings({ fans: all })
    Qt.callLater(root.applyAll)
  }

  function temp(id) {
    for (var i = 0; i < temps.length; i++) if (temps[i].id === id) return temps[i]
    return null
  }

  function hottestTemp() {
    var best = null
    for (var i = 0; i < temps.length; i++) if (!best || temps[i].celsius > best.celsius) best = temps[i]
    return best
  }

  function sensorFor(c) {
    return temp(c.sensor) || hottestTemp()
  }

  function clampRpm(fan, rpm) {
    return Math.round(Math.max(fan.min, Math.min(fan.max, rpm)))
  }

  // "auto", or the speed this fan should run at now.
  function wanted(fan) {
    var c = fanConfig(fan.n)
    if (c.mode === "full") return fan.max
    if (c.mode === "constant") return clampRpm(fan, c.rpm > 0 ? c.rpm : fan.min)
    if (c.mode === "range") {
      var t = sensorFor(c)
      if (!t) return "auto"
      var span = Math.max(1, c.to - c.from)
      var f = Math.max(0, Math.min(1, (t.celsius - c.from) / span))
      return clampRpm(fan, fan.min + f * (fan.max - fan.min))
    }
    return "auto"
  }

  function applyAll() {
    if (!control) return
    for (var i = 0; i < fans.length; i++) {
      var fan = fans[i]
      if (!fan.writable) continue
      var want = wanted(fan)
      var last = applied[String(fan.n)]
      // Sensor speeds settle within 50 RPM so the fan doesn't hunt.
      if (last === want) continue
      if (want !== "auto" && last !== undefined && last !== "auto" && Math.abs(last - want) < 50) continue
      runSet(fan.n, want)
    }
  }

  // ---------------------------------------------------------------- bin/fans

  property var setQueue: []

  function runSet(n, value) {
    var next = applied
    next[String(n)] = value
    applied = next
    setQueue = setQueue.filter(function(a) { return a[0] !== n }).concat([[n, value]])
    runNextSet()
  }

  function runNextSet() {
    if (setProc.running || setQueue.length === 0) return
    var queue = setQueue.slice()
    var args = queue.shift()
    setQueue = queue
    setProc.command = [root.fansCommand, "set", String(args[0]), String(args[1])]
    setProc.running = true
  }

  Process {
    id: setProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var message = String(text || "").trim()
        if (message !== "") {
          root.lastError = message
          // Try again on the next read.
          root.applied = ({})
        }
      }
    }
    onRunningChanged: if (!running) Qt.callLater(root.runNextSet)
  }

  Process {
    id: readProc
    command: [root.fansCommand, "read"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(String(text || "{}"))
          root.present = data.present === true
          root.control = data.control === true
          root.fans = Array.isArray(data.fans) ? data.fans : []
          root.temps = Array.isArray(data.temps) ? data.temps : []
          root.applyAll()
        } catch (e) {
          console.warn("witcher.fans: bad read output", e)
        }
      }
    }
  }

  Timer {
    interval: root.opened ? 1000 : 3000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: if (!readProc.running) readProc.running = true
  }

  // ---------------------------------------------------------------- bar

  visible: present
  implicitWidth: present ? button.implicitWidth : 0
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.showSpeed && !vertical ? root.speed + " " + root.fanIcon : root.fanIcon
    slotSize: Style.bar.iconSlot * (root.showSpeed && !vertical ? 2.6 : 1)
    tooltipText: ""
    onPressed: function(b) {
      if (b === Qt.RightButton) root.persistSettings({ showSpeed: !root.showSpeed })
      else root.toggle()
    }
  }

  // ---------------------------------------------------------------- panel

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: column.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

        Column {
          id: column
          width: scrollArea.availableWidth
          spacing: Style.space(14)

          // ---------- Title: name · speed · range ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroTitle.implicitHeight)

            Text {
              id: heroIcon
              textFormat: Text.PlainText
              text: root.fanIcon
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: heroTitle
              textFormat: Text.PlainText
              text: "Fan Control"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              textFormat: Text.PlainText
              text: root.speedText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              textFormat: Text.PlainText
              text: root.rangeText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Text {
            visible: !root.control
            width: parent.width
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: "Fan control is off, so speeds can only be read. Reboot after installing the fans tweak (it adds macsmc_hwmon.fan_control=1 to the kernel options)."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            visible: root.lastError !== ""
            width: parent.width
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: root.lastError
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          // ---------- One block per fan ----------
          Repeater {
            // By count, so a new read updates the rows instead of rebuilding
            // them (which would drop a slider mid-drag).
            model: root.fans.length

            Column {
              id: fanBlock
              required property int index
              readonly property var fan: root.fans[index] || ({ n: 0, label: "", rpm: 0, min: 0, max: 1 })
              readonly property var config: root.fanConfig(fan.n)
              readonly property bool canSet: root.control && fan.writable
              width: column.width
              spacing: Style.space(8)

              PanelSeparator { width: parent.width; foreground: root.foreground }

              // Only needed to tell fans apart.
              PanelSectionHeader {
                visible: root.fans.length > 1
                text: (fanBlock.fan.label + " " + fanBlock.fan.n).toUpperCase()
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              ButtonGroup {
                enabled: fanBlock.canSet
                opacity: enabled ? 1 : 0.5
                focusable: false
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                options: [
                  { value: "auto", label: "Auto" },
                  { value: "full", label: "Full Blast" },
                  { value: "constant", label: "Constant" },
                  { value: "range", label: "Range" }
                ]
                value: fanBlock.config.mode
                onChanged: function(v) {
                  var values = { mode: v }
                  // Start a fixed speed from where the fan is now.
                  if (v === "constant" && fanBlock.config.rpm <= 0) values.rpm = root.clampRpm(fanBlock.fan, fanBlock.fan.rpm)
                  if (v === "range" && fanBlock.config.sensor === "") {
                    var hot = root.hottestTemp()
                    if (hot) values.sensor = hot.id
                  }
                  root.setFanConfig(fanBlock.fan.n, values)
                }
              }

              // Constant: one speed.
              Column {
                visible: fanBlock.config.mode === "constant"
                width: parent.width
                spacing: Style.space(4)

                Text {
                  textFormat: Text.PlainText
                  text: Math.round(rpmSlider.dragging ? rpmSlider.liveValue : rpmSlider.value) + " RPM"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                PanelSlider {
                  id: rpmSlider
                  bar: root.bar
                  width: parent.width
                  enabled: fanBlock.canSet
                  minimum: fanBlock.fan.min
                  maximum: fanBlock.fan.max
                  step: 100
                  integer: true
                  value: root.clampRpm(fanBlock.fan, fanBlock.config.rpm > 0 ? fanBlock.config.rpm : fanBlock.fan.min)
                  onReleased: function(v) { root.setFanConfig(fanBlock.fan.n, { rpm: Math.round(v) }) }
                }
              }

              // Range: follows a temperature, quiet at one end, full blast at
              // the other.
              Column {
                visible: fanBlock.config.mode === "range"
                width: parent.width
                spacing: Style.space(14)

                // Sensor label and dropdown on one line.
                Item {
                  width: parent.width
                  implicitHeight: sensorDropdown.implicitHeight

                  Text {
                    id: sensorLabel
                    textFormat: Text.PlainText
                    text: "Sensor"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Dropdown {
                    id: sensorDropdown
                    anchors.left: sensorLabel.right
                    anchors.leftMargin: Style.space(12)
                    anchors.right: parent.right
                    showLabel: false
                    fontFamily: root.fontFamily
                    enabled: fanBlock.canSet
                    options: root.temps.map(function(t) { return { value: t.id, label: t.label + "  " + t.celsius + "°C" } })
                    value: root.sensorFor(fanBlock.config) ? root.sensorFor(fanBlock.config).id : ""
                    onChanged: function(v) { root.setFanConfig(fanBlock.fan.n, { sensor: v }) }
                  }
                }

                // Quiet at | Full blast at, side by side.
                Row {
                  id: rangeRow
                  width: parent.width
                  spacing: Style.space(12)

                  Column {
                    width: (rangeRow.width - rangeRow.spacing) / 2
                    spacing: Style.space(4)

                    Text {
                      textFormat: Text.PlainText
                      text: "Quiet at " + Math.round(fromSlider.dragging ? fromSlider.liveValue : fromSlider.value) + "°C"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    PanelSlider {
                      id: fromSlider
                      bar: root.bar
                      width: parent.width
                      enabled: fanBlock.canSet
                      minimum: 20
                      maximum: 95
                      step: 1
                      integer: true
                      value: fanBlock.config.from
                      onReleased: function(v) {
                        var from = Math.round(v)
                        root.setFanConfig(fanBlock.fan.n, { from: from, to: Math.max(fanBlock.config.to, from + 5) })
                      }
                    }
                  }

                  Column {
                    width: (rangeRow.width - rangeRow.spacing) / 2
                    spacing: Style.space(4)

                    Text {
                      textFormat: Text.PlainText
                      text: "Full blast at " + Math.round(toSlider.dragging ? toSlider.liveValue : toSlider.value) + "°C"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    PanelSlider {
                      id: toSlider
                      bar: root.bar
                      width: parent.width
                      enabled: fanBlock.canSet
                      minimum: 25
                      maximum: 100
                      step: 1
                      integer: true
                      value: fanBlock.config.to
                      onReleased: function(v) {
                        var to = Math.round(v)
                        root.setFanConfig(fanBlock.fan.n, { to: to, from: Math.min(fanBlock.config.from, to - 5) })
                      }
                    }
                  }
                }
              }
            }
          }

          // ---------- Temperatures ----------
          PanelSeparator { width: parent.width; foreground: root.foreground; visible: root.temps.length > 0 }

          PanelSectionHeader {
            visible: root.temps.length > 0
            text: "TEMPERATURES"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Column {
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: root.temps.length

              Item {
                required property int index
                readonly property var modelData: root.temps[index] || ({ label: "", celsius: 0 })
                width: column.width
                implicitHeight: tempLabel.implicitHeight

                Text {
                  id: tempLabel
                  textFormat: Text.PlainText
                  text: modelData.label
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  anchors.left: parent.left
                  anchors.right: tempValue.left
                  anchors.rightMargin: Style.space(8)
                }

                Text {
                  id: tempValue
                  textFormat: Text.PlainText
                  text: modelData.celsius + "°C"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(6)
                }
              }
            }
          }
        }
      }
    }
  }
}
