//@ pragma AppId org.witcher.installer
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "components"

// The Witcher's Tweaks setup wizard: install.sh's window. Steps on the left
// (Introduction, Choose, Settings, Install, Summary), like macOS's
// Installer. Picking and removing tweaks, and their settings, end up as one
// install.sh run with the same environment settings the terminal installer
// takes, so both ways do the same thing.
ShellRoot {
  id: wizard

  readonly property var steps: ["Introduction", "Choose Tweaks", "Settings", "Install", "Summary"]
  property int step: 0

  // Wanted state per tweak (name -> bool), from what's installed.
  property var wanted: ({})
  property bool loaded: false
  Connections {
    target: App
    function onTweakListChanged() {
      if (wizard.loaded) return
      var w = ({})
      for (var i = 0; i < App.tweakList.length; i++) w[App.tweakList[i].name] = App.tweakList[i].state !== "none"
      wizard.wanted = w
      wizard.loaded = true
    }
  }

  function isOn(name) { return wanted[name] === true }
  function setWanted(name, on) {
    var w = JSON.parse(JSON.stringify(wanted))
    w[name] = on
    wanted = w
  }
  readonly property var toAdd: App.tweakList.filter(function(t) { return wanted[t.name] === true && t.state !== "full" }).map(function(t) { return t.name })
  readonly property var toRemove: App.tweakList.filter(function(t) { return wanted[t.name] === false && t.state !== "none" }).map(function(t) { return t.name })
  readonly property var categories: {
    var seen = []
    for (var i = 0; i < App.tweakList.length; i++) if (seen.indexOf(App.tweakList[i].category) < 0) seen.push(App.tweakList[i].category)
    return seen
  }

  // Settings asked for tweaks being added.
  readonly property var configurable: ["dock", "suspend", "notifytimeout", "rounding", "border"]
  readonly property bool hasSettings: toAdd.some(function(n) { return configurable.indexOf(n) >= 0 })
  function adding(name) { return toAdd.indexOf(name) >= 0 }

  // The choices, with the installer's defaults.
  property var dock: ({
    size: 48, magnification: 0, position: "bottom", minimizeEffect: "genie", minimizeSpeed: 100,
    minimize: false, hide: "auto", animate: true, indicators: true, recents: true, click: "cycle",
    transparency: 0, appsTransparency: 0, roundness: 60, border: "windows", borderColors: ["#c4b5fd", "#a855f7", "#da70d6"]
  })
  function setDock(key, value) { var d = JSON.parse(JSON.stringify(dock)); d[key] = value; dock = d }
  property int suspendMinutes: 5
  property int notifySeconds: 5
  property int roundness: 60
  property var border: ["#c4b5fd", "#a855f7", "#da70d6", "#5b3a7a"]

  function next() {
    if (step === 1 && !hasSettings) step = 3
    else if (step < steps.length - 1) step++
  }
  function back() {
    if (step === 3 && !hasSettings) step = 1
    else if (step > 0) step--
  }

  // ---------- running install.sh ----------

  property bool running: false
  property bool finished: false
  property int exitCode: 0
  property string log: ""
  // Set when install.sh says a change needs a reboot ("reboot   needed to finish: ...").
  property string rebootReason: ""

  function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

  function script() {
    var env = ["SUDO=pkexec"]
    if (adding("dock")) {
      var d = dock
      env.push("DOCK_SIZE=" + d.size, "DOCK_MAGNIFICATION=" + d.magnification, "DOCK_POSITION=" + d.position,
        "DOCK_MINIMIZE_EFFECT=" + d.minimizeEffect, "DOCK_MINIMIZE_SPEED=" + d.minimizeSpeed, "DOCK_MINIMIZE=" + d.minimize,
        "DOCK_HIDE=" + d.hide, "DOCK_ANIMATE=" + d.animate, "DOCK_INDICATORS=" + d.indicators, "DOCK_RECENTS=" + d.recents,
        "DOCK_CLICK=" + d.click, "DOCK_TRANSPARENCY=" + d.transparency, "DOCK_APPS_TRANSPARENCY=" + d.appsTransparency,
        "DOCK_ROUNDNESS=" + d.roundness, "DOCK_BORDER=" + d.border)
      if (d.border === "custom") env.push("DOCK_BORDER_COLORS=" + q(d.borderColors.join(",")))
      if (d.border === "solid") env.push("DOCK_BORDER_COLORS=" + q(d.borderColors[1]))
    }
    if (adding("suspend")) env.push("SUSPEND_MINUTES=" + suspendMinutes)
    if (adding("notifytimeout")) env.push("NOTIFY_SECONDS=" + notifySeconds)
    if (adding("rounding")) env.push("WINDOW_ROUNDING=" + roundness)
    var parts = ["cd " + q(App.repo)]
    var failed = "status=0"
    if (toAdd.length > 0) parts.push(env.join(" ") + " ./install.sh --add " + toAdd.join(" ") + " </dev/null 2>&1 || status=1")
    if (toRemove.length > 0) parts.push("SUDO=pkexec ./install.sh --remove " + toRemove.join(" ") + " </dev/null 2>&1 || status=1")
    if (adding("border"))
      parts.push("settings/bin/settings-helper border set " + border.map(function(c) { return c.replace("#", "") }).join(" ") + " 2>&1 || status=1")
    parts.push("exit $status")
    return [failed].concat(parts).join("\n")
  }

  function install() {
    running = true
    finished = false
    log = ""
    rebootReason = ""
    installer.command = ["bash", "-c", script()]
    installer.running = true
  }

  Process {
    id: installer
    stdout: SplitParser {
      onRead: function(line) {
        var clean = line.replace(/\x1b\[[0-9;]*m/g, "")
        var reboot = clean.match(/^reboot +needed to finish: (.*)$/)
        if (reboot) wizard.rebootReason = reboot[1]
        wizard.log += clean + "\n"
        Qt.callLater(function() { logView.contentY = Math.max(0, logView.contentHeight - logView.height) })
      }
    }
    onExited: function(code) {
      wizard.exitCode = code
      wizard.running = false
      wizard.finished = true
      App.refreshTweaks()
      wizard.step = 4
    }
  }

  // ---------- window ----------

  FloatingWindow {
    id: window
    title: "Witcher's Tweaks Setup"
    implicitWidth: 900
    implicitHeight: 640
    minimumSize: Qt.size(760, 520)
    color: App.bg
    onVisibleChanged: if (!visible) Qt.quit()

    // Steps.
    Rectangle {
      id: side
      width: 210
      height: parent.height
      color: App.sidebar
      Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: App.line }

      Column {
        x: 22
        y: 30
        spacing: 16
        Text {
          text: "Witcher's Tweaks"
          color: App.fg
          font.family: App.font
          font.pixelSize: App.body + 3
          font.bold: true
        }
        Item { width: 1; height: 6 }
        Repeater {
          model: wizard.steps
          Row {
            required property var modelData
            required property int index
            spacing: 10
            readonly property bool done: index < wizard.step
            readonly property bool current: index === wizard.step
            readonly property bool skipped: index === 2 && !wizard.hasSettings
            opacity: skipped ? 0.35 : 1
            Rectangle {
              width: 12; height: 12; radius: 6
              anchors.verticalCenter: parent.verticalCenter
              color: parent.current || parent.done ? App.tint : "transparent"
              border.width: 1
              border.color: parent.current || parent.done ? App.tint : App.faint
            }
            Text {
              text: parent.modelData
              color: parent.current ? App.fg : App.subtle
              font.family: App.font
              font.pixelSize: App.body
              font.bold: parent.current
            }
          }
        }
      }
    }

    // Pages.
    Item {
      id: content
      anchors.left: side.right
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: buttons.top

      // ---------- 0: introduction ----------
      Column {
        visible: wizard.step === 0
        x: 40
        y: 40
        width: parent.width - 80
        spacing: 14
        Text {
          text: "Welcome"
          color: App.fg
          font.family: App.font
          font.pixelSize: App.body + 9
          font.bold: true
        }
        Text {
          width: parent.width
          wrapMode: Text.Wrap
          text: "Pick the tweaks you want and set them up. Installed tweaks start switched on; switch one off to remove it.\n\nYou can change all of this later from Setup > Witcher's Tweaks in the Omarchy menu, or from the Settings app."
          color: App.subtle
          font.family: App.font
          font.pixelSize: App.body
          lineHeight: 1.2
        }
      }

      // ---------- 1: choose ----------
      Scroller {
        visible: wizard.step === 1
        anchors.fill: parent
        contentHeight: chooseColumn.height + 60
        Column {
          id: chooseColumn
          x: 32
          y: 28
          width: parent.width - 64
          spacing: 22
          Repeater {
            model: wizard.categories
            Group {
              id: cat
              required property var modelData
              title: modelData
              Repeater {
                model: App.tweakList.filter(function(t) { return t.category === cat.modelData })
                SwitchRow {
                  required property var modelData
                  label: modelData.description
                  sublabel: modelData.state === "full" ? "Installed" : modelData.state === "partial" ? "Partly installed" : ""
                  checked: wizard.isOn(modelData.name)
                  onToggled: function(on) { wizard.setWanted(modelData.name, on) }
                }
              }
            }
          }
        }
      }

      // ---------- 2: settings ----------
      Scroller {
        visible: wizard.step === 2
        anchors.fill: parent
        contentHeight: settingsColumn.height + 60
        Column {
          id: settingsColumn
          x: 32
          y: 28
          width: parent.width - 64
          spacing: 22

          Group {
            visible: wizard.adding("dock")
            title: "Dock"
            ChoiceRow {
              label: "Size"
              options: [32, 40, 48, 56, 64, 80].map(function(n) { return { value: n, label: n + " px" } })
              current: wizard.dock.size
              onChosen: function(v) { wizard.setDock("size", v) }
            }
            ChoiceRow {
              label: "Magnification"
              options: [{ value: 0, label: "Off" }].concat([64, 80, 96, 128].map(function(n) { return { value: n, label: n + " px" } }))
              current: wizard.dock.magnification
              onChosen: function(v) { wizard.setDock("magnification", v) }
            }
            SegmentedRow {
              label: "Position on screen"
              options: [{ value: "left", label: "Left" }, { value: "bottom", label: "Bottom" }, { value: "right", label: "Right" }]
              current: wizard.dock.position
              onChosen: function(v) { wizard.setDock("position", v) }
            }
            ChoiceRow {
              label: "Minimize windows using"
              options: [{ value: "genie", label: "Genie effect" }, { value: "scale", label: "Scale effect" }, { value: "fade", label: "Fade" }, { value: "slide", label: "Slide down" }, { value: "none", label: "No animation" }]
              current: wizard.dock.minimizeEffect
              onChosen: function(v) { wizard.setDock("minimizeEffect", v) }
            }
            SliderRow {
              visible: wizard.dock.minimizeEffect !== "none"
              label: "Animation speed"
              from: 50; to: 200; step: 10
              value: wizard.dock.minimizeSpeed
              minLabel: "Slow"; maxLabel: "Fast"
              onChanged: function(v) { wizard.setDock("minimizeSpeed", Math.round(v)) }
            }
            SwitchRow {
              label: "Minimize windows into application icon"
              checked: wizard.dock.minimize
              onToggled: function(on) { wizard.setDock("minimize", on) }
            }
            ChoiceRow {
              label: "Automatically hide and show the Dock"
              options: [{ value: "auto", label: "Always" }, { value: "smart", label: "When a window is under it" }, { value: "never", label: "Never" }]
              current: wizard.dock.hide
              onChosen: function(v) { wizard.setDock("hide", v) }
            }
            SwitchRow { label: "Animate opening applications"; checked: wizard.dock.animate; onToggled: function(on) { wizard.setDock("animate", on) } }
            SwitchRow { label: "Show indicators for open applications"; checked: wizard.dock.indicators; onToggled: function(on) { wizard.setDock("indicators", on) } }
            SwitchRow { label: "Show suggested and recent apps in Dock"; checked: wizard.dock.recents; onToggled: function(on) { wizard.setDock("recents", on) } }
            ChoiceRow {
              label: "Clicking the app you're in"
              options: [{ value: "cycle", label: "Goes to its next window" }, { value: "focus", label: "Stays on its last window" }]
              current: wizard.dock.click
              onChosen: function(v) { wizard.setDock("click", v) }
            }
            SliderRow {
              label: "Dock transparency"
              from: 0; to: 90; step: 5
              value: wizard.dock.transparency
              format: function(v) { return Math.round(v) + "%" }
              onChanged: function(v) { wizard.setDock("transparency", Math.round(v)) }
            }
            SliderRow {
              label: "App drawer transparency"
              from: 0; to: 90; step: 5
              value: wizard.dock.appsTransparency
              format: function(v) { return Math.round(v) + "%" }
              onChanged: function(v) { wizard.setDock("appsTransparency", Math.round(v)) }
            }
            SliderRow {
              label: "Corner rounding"
              from: 0; to: 100; step: 5
              value: wizard.dock.roundness
              format: function(v) { return Math.round(v) + "%" }
              onChanged: function(v) { wizard.setDock("roundness", Math.round(v)) }
            }
            ChoiceRow {
              label: "Border"
              options: [{ value: "windows", label: "Same gradient as windows" }, { value: "custom", label: "Custom gradient" }, { value: "solid", label: "One solid color" }, { value: "none", label: "No border" }]
              current: wizard.dock.border
              onChosen: function(v) { wizard.setDock("border", v) }
            }
            ColorRow {
              visible: wizard.dock.border === "custom" || wizard.dock.border === "solid"
              label: wizard.dock.border === "solid" ? "Border color" : "Gradient colors"
              colors: wizard.dock.border === "solid" ? [wizard.dock.borderColors[1]] : wizard.dock.borderColors
              onColorPicked: function(i, hex) {
                var c = wizard.dock.borderColors.slice()
                c[wizard.dock.border === "solid" ? 1 : i] = hex
                wizard.setDock("borderColors", c)
              }
            }
          }

          Group {
            visible: wizard.adding("border")
            title: "Window border"
            ColorRow {
              label: "Gradient colors"
              colors: wizard.border.slice(0, 3)
              onColorPicked: function(i, hex) { var c = wizard.border.slice(); c[i] = hex; wizard.border = c }
            }
            ColorRow {
              label: "Inactive windows"
              colors: wizard.border.slice(3, 4)
              onColorPicked: function(i, hex) { var c = wizard.border.slice(); c[3] = hex; wizard.border = c }
            }
          }

          Group {
            visible: wizard.adding("rounding")
            title: "Window corners"
            SliderRow {
              label: "Corner rounding"
              from: 0; to: 100; step: 5
              value: wizard.roundness
              format: function(v) { return Math.round(v) + "%" }
              onChanged: function(v) { wizard.roundness = Math.round(v) }
            }
          }

          Group {
            visible: wizard.adding("suspend")
            title: "Suspend"
            ChoiceRow {
              label: "Suspend after"
              options: [1, 5, 10, 15, 30, 60].map(function(n) { return { value: n, label: n === 1 ? "1 minute" : n + " minutes" } })
              current: wizard.suspendMinutes
              onChosen: function(v) { wizard.suspendMinutes = v }
            }
          }

          Group {
            visible: wizard.adding("notifytimeout")
            title: "Notifications"
            ChoiceRow {
              label: "Leave the screen after"
              options: [3, 5, 8, 10, 15].map(function(n) { return { value: n, label: n + " seconds" } })
              current: wizard.notifySeconds
              onChosen: function(v) { wizard.notifySeconds = v }
            }
          }
        }
      }

      // ---------- 3: install ----------
      Column {
        visible: wizard.step === 3
        x: 40
        y: 40
        width: parent.width - 80
        spacing: 14
        Text {
          text: wizard.running ? "Installing…" : "Ready to install"
          color: App.fg
          font.family: App.font
          font.pixelSize: App.body + 9
          font.bold: true
        }
        Text {
          visible: !wizard.running
          width: parent.width
          wrapMode: Text.Wrap
          text: wizard.toAdd.length === 0 && wizard.toRemove.length === 0 ? "Nothing to change."
            : (wizard.toAdd.length > 0 ? "Add: " + wizard.toAdd.join(", ") : "")
              + (wizard.toAdd.length > 0 && wizard.toRemove.length > 0 ? "\n" : "")
              + (wizard.toRemove.length > 0 ? "Remove: " + wizard.toRemove.join(", ") : "")
          color: App.subtle
          font.family: App.font
          font.pixelSize: App.body
          lineHeight: 1.3
        }
        // Progress.
        Rectangle {
          visible: wizard.running
          width: parent.width
          height: 4
          radius: 2
          color: App.control
          clip: true
          Rectangle {
            width: parent.width * 0.3
            height: parent.height
            radius: 2
            color: App.tint
            SequentialAnimation on x {
              running: wizard.running
              loops: Animation.Infinite
              NumberAnimation { from: -120; to: 560; duration: 1200; easing.type: Easing.InOutQuad }
            }
          }
        }
      }

      // The installer's output.
      Rectangle {
        visible: wizard.step >= 3 && wizard.log !== ""
        x: 40
        y: 150
        width: parent.width - 80
        height: parent.height - y - 16
        radius: App.radius
        color: App.card
        border.width: 1
        border.color: App.line
        Flickable {
          id: logView
          anchors.fill: parent
          anchors.margins: 12
          clip: true
          contentWidth: width
          contentHeight: logText.implicitHeight
          boundsBehavior: Flickable.StopAtBounds
          Text {
            id: logText
            width: parent.width
            wrapMode: Text.WrapAnywhere
            text: wizard.log
            textFormat: Text.PlainText
            color: App.subtle
            font.family: Style.font.family
            font.pixelSize: App.small
          }
        }
      }

      // ---------- 4: summary ----------
      Column {
        visible: wizard.step === 4
        x: 40
        y: 40
        width: parent.width - 80
        spacing: 14
        Text {
          text: wizard.exitCode === 0 ? "Done" : "Finished with problems"
          color: App.fg
          font.family: App.font
          font.pixelSize: App.body + 9
          font.bold: true
        }
        Text {
          width: parent.width
          wrapMode: Text.Wrap
          text: wizard.exitCode === 0 ? "Everything is installed." : "Something didn't install; the output below says what."
          color: App.subtle
          font.family: App.font
          font.pixelSize: App.body
        }
        Text {
          visible: wizard.rebootReason !== ""
          width: parent.width
          wrapMode: Text.Wrap
          text: "A reboot is needed for some changes to apply (" + wizard.rebootReason + ")."
          color: App.fg
          font.family: App.font
          font.pixelSize: App.body
        }
      }
    }

    // Buttons.
    Item {
      id: buttons
      anchors.left: side.right
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: 64
      Rectangle { width: parent.width; height: 1; color: App.line }
      Row {
        anchors.right: parent.right
        anchors.rightMargin: 24
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10
        PillButton {
          visible: wizard.step > 0 && wizard.step < 4
          enabled2: !wizard.running
          text: "Go Back"
          onClicked: wizard.back()
        }
        PillButton {
          visible: wizard.step === 4 && wizard.rebootReason !== ""
          text: "Reboot Now"
          onClicked: App.detached(["omarchy", "system", "reboot"])
        }
        PillButton {
          visible: wizard.step === 4 && App.tweakOn("settings")
          text: "Open Settings"
          onClicked: { App.detached(["witcher-settings"]); Qt.quit() }
        }
        PillButton {
          prominent: true
          enabled2: !wizard.running && (wizard.step !== 1 || wizard.loaded)
            && (wizard.step !== 3 || wizard.toAdd.length > 0 || wizard.toRemove.length > 0)
          text: wizard.step === 3 ? "Install" : wizard.step === 4 ? "Close" : "Continue"
          onClicked: {
            if (wizard.step === 3) wizard.install()
            else if (wizard.step === 4) Qt.quit()
            else wizard.next()
          }
        }
      }
    }
  }
}
