import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Color picker for the looks module's borders: the three colors of the
// active window gradient (light, main, accent) and the inactive border.
// Every change previews live on the real windows (bin/border-colors preview);
// Save keeps it (config, shell theme, lock screen), Cancel or Esc goes back
// to the saved colors.
//
// Pick a slot, then drag in the square (saturation/brightness) and the strip
// (hue), type a hex value, grab a color off the screen with the eyedropper,
// or start from a preset.
//
// Opened with `omarchy-shell shell summon witcher.border-colors '{}'`, which
// Setup > Witcher's Tweaks > Configure > Borders runs.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  // The eyedropper hides the window while it runs.
  property bool picking: false

  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string script: pluginDir + "/bin/border-colors"

  readonly property var defaults: ["c4b5fd", "a855f7", "da70d6", "5b3a7a"]
  readonly property var slotNames: ["Light", "Main", "Accent", "Inactive"]
  readonly property var presets: [
    { name: "Purple", colors: ["c4b5fd", "a855f7", "da70d6", "5b3a7a"] },
    { name: "Ocean", colors: ["7dd3fc", "0ea5e9", "6366f1", "1e3a5f"] },
    { name: "Sunset", colors: ["fde68a", "fb923c", "e11d48", "5c2a2a"] },
    { name: "Forest", colors: ["bbf7d0", "22c55e", "15803d", "1f3b2c"] },
    { name: "Rose", colors: ["fecdd3", "f43f5e", "be185d", "5a2a3a"] },
    { name: "Mono", colors: ["f5f5f5", "a3a3a3", "525252", "3a3a3a"] }
  ]

  property var saved: defaults.slice()
  property var colors: defaults.slice()
  property int slot: 0
  // The slot's color as HSV; hue survives greys, where it has none of its own.
  property real hue: 0
  property real sat: 0
  property real val: 0

  readonly property color foreground: Color.menu.text
  readonly property color background: Color.menu.background
  readonly property color accent: Color.accent
  readonly property color quiet: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.3)
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
  readonly property string fontFamily: Style.font.menuFamily
  readonly property int radius: Style.cornerRadius

  // --------------------------------------------------------------- open/close

  function open(payloadJson) {
    picking = false
    getProc.running = true
    opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    opened = false
  }

  function dismiss() {
    opened = false
    if (shell && typeof shell.hide === "function") shell.hide((manifest && manifest.id) || "witcher.border-colors")
  }

  // Closing without saving puts the saved colors back on the windows.
  function cancel() {
    if (colors.join(" ") !== saved.join(" ")) Quickshell.execDetached([script, "revert"])
    dismiss()
  }

  function save() {
    Quickshell.execDetached([script, "set"].concat(colors))
    saved = colors.slice()
    dismiss()
  }

  function toggle() {
    if (opened) cancel()
    else open("{}")
  }

  // --------------------------------------------------------------- colors

  function hex2(n) {
    var s = Math.round(Math.max(0, Math.min(1, n)) * 255).toString(16)
    return s.length < 2 ? "0" + s : s
  }

  function hexOf(c) {
    return hex2(c.r) + hex2(c.g) + hex2(c.b)
  }

  function colorOf(hex) {
    return Qt.color("#" + hex)
  }

  function selectSlot(index) {
    slot = index
    var c = colorOf(colors[slot])
    if (c.hsvHue >= 0) hue = c.hsvHue
    sat = c.hsvSaturation
    val = c.hsvValue
  }

  function setSlotColor(hex) {
    var next = colors.slice()
    next[slot] = hex
    colors = next
    previewTimer.restart()
  }

  function setFromHsv() {
    setSlotColor(hexOf(Qt.hsva(hue, sat, val, 1)))
  }

  function setHex(text) {
    var value = String(text || "").trim().replace(/^#/, "")
    if (!/^[0-9a-fA-F]{6}$/.test(value)) return false
    setSlotColor(value.toLowerCase())
    selectSlot(slot)
    return true
  }

  function usePreset(preset) {
    colors = preset.colors.slice()
    selectSlot(slot)
    previewTimer.restart()
  }

  // The gradient as Hyprland spreads it: 3 parts light, 3 main, 2 accent.
  function gradientColor(position) {
    var index = [0, 0, 0, 1, 1, 1, 2, 2][Math.min(7, Math.floor(position * 8))]
    return colorOf(colors[index])
  }

  // --------------------------------------------------------------- processes

  Process {
    id: getProc
    command: [root.script, "get"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text || "").trim().split(/\s+/)
        root.saved = parts.length === 4 ? parts : root.defaults.slice()
        root.colors = root.saved.slice()
        root.selectSlot(0)
      }
    }
  }

  // Previews are coalesced: one hyprctl call per pause in the dragging.
  Timer {
    id: previewTimer
    interval: 60
    onTriggered: {
      if (previewProc.running) { previewTimer.restart(); return }
      previewProc.command = [root.script, "preview"].concat(root.colors)
      previewProc.running = true
    }
  }

  Process { id: previewProc }

  Process {
    id: eyedropper
    command: ["hyprpicker", "--format=hex", "--no-fancy"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var match = String(text || "").match(/#?([0-9a-fA-F]{6})/)
        if (match) root.setHex(match[1])
      }
    }
    onRunningChanged: if (!running) {
      root.picking = false
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }

  function pickFromScreen() {
    picking = true
    // Let the window go before the picker grabs the screen.
    Qt.callLater(function() { eyedropper.running = true })
  }

  // --------------------------------------------------------------- window

  PanelWindow {
    id: window
    visible: root.opened && !root.picking
    screen: {
      var name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
      for (var i = 0; i < Quickshell.screens.length; i++)
        if (Quickshell.screens[i].name === name) return Quickshell.screens[i]
      return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    }
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "witcher-border-colors"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // No dimming: the point is to see the borders change behind the card.
    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) root.cancel()
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.save()
        else if (event.key === Qt.Key_Tab) root.selectSlot((root.slot + 1) % 4)
        else if (event.key === Qt.Key_Backtab) root.selectSlot((root.slot + 3) % 4)
        else return
        event.accepted = true
      }
    }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.min(Style.space(440), parent.width - Style.gapsOut * 2)
      height: content.implicitHeight + contentTopInset + contentBottomInset
      radius: root.radius
      color: root.background
      borderSpec: root.borderSpec
      padding: Style.spacing.panelPadding

      Column {
        id: content
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.space(14)

        // ---------- Title ----------
        Column {
          width: parent.width
          spacing: Style.space(2)
          Text {
            textFormat: Text.PlainText
            text: "Border colors"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
          }
          Text {
            textFormat: Text.PlainText
            text: "Previewing live on your windows. Enter saves, Esc cancels."
            color: root.foreground
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // ---------- The gradient as it will look ----------
        Rectangle {
          width: parent.width
          height: Style.space(18)
          radius: height / 2
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: root.gradientColor(0.0) }
            GradientStop { position: 0.3; color: root.gradientColor(0.3) }
            GradientStop { position: 0.45; color: root.gradientColor(0.45) }
            GradientStop { position: 0.7; color: root.gradientColor(0.7) }
            GradientStop { position: 0.8; color: root.gradientColor(0.8) }
            GradientStop { position: 1.0; color: root.gradientColor(0.99) }
          }
        }

        // ---------- Slots ----------
        Row {
          width: parent.width
          spacing: Style.space(10)

          Repeater {
            model: 4

            Item {
              id: slotItem
              required property int index
              readonly property bool selected: root.slot === index
              width: (parent.width - 3 * Style.space(10)) / 4
              height: swatch.height + slotLabel.implicitHeight + Style.space(4)

              Rectangle {
                id: swatch
                width: parent.width
                height: Style.space(34)
                radius: root.radius
                color: root.colorOf(root.colors[slotItem.index])
                border.width: slotItem.selected ? Style.space(3) : 1
                border.color: slotItem.selected ? root.foreground : root.quiet
              }

              Text {
                id: slotLabel
                anchors.top: swatch.bottom
                anchors.topMargin: Style.space(4)
                anchors.horizontalCenter: parent.horizontalCenter
                textFormat: Text.PlainText
                text: root.slotNames[slotItem.index]
                color: root.foreground
                opacity: slotItem.selected ? 1 : 0.6
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selectSlot(slotItem.index)
              }
            }
          }
        }

        // ---------- Saturation/brightness square and hue strip ----------
        Row {
          width: parent.width
          spacing: Style.space(12)

          Item {
            id: square
            width: parent.width - hueStrip.width - parent.spacing
            height: Style.space(170)

            Rectangle {
              anchors.fill: parent
              radius: Style.space(4)
              color: Qt.hsva(root.hue, 1, 1, 1)
            }
            Rectangle {
              anchors.fill: parent
              radius: Style.space(4)
              gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "#ffffffff" }
                GradientStop { position: 1.0; color: "#00ffffff" }
              }
            }
            Rectangle {
              anchors.fill: parent
              radius: Style.space(4)
              gradient: Gradient {
                GradientStop { position: 0.0; color: "#00000000" }
                GradientStop { position: 1.0; color: "#ff000000" }
              }
            }

            Rectangle {
              width: Style.space(14)
              height: width
              radius: width / 2
              x: root.sat * square.width - width / 2
              y: (1 - root.val) * square.height - height / 2
              color: root.colorOf(root.colors[root.slot])
              border.width: Style.space(2)
              border.color: root.val > 0.5 ? "black" : "white"
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.CrossCursor
              function pick(mouse) {
                root.sat = Math.max(0, Math.min(1, mouse.x / width))
                root.val = Math.max(0, Math.min(1, 1 - mouse.y / height))
                root.setFromHsv()
              }
              onPressed: function(mouse) { pick(mouse) }
              onPositionChanged: function(mouse) { if (pressed) pick(mouse) }
            }
          }

          Item {
            id: hueStrip
            width: Style.space(22)
            height: square.height

            Rectangle {
              anchors.fill: parent
              radius: Style.space(4)
              gradient: Gradient {
                GradientStop { position: 0 / 6; color: "#ff0000" }
                GradientStop { position: 1 / 6; color: "#ffff00" }
                GradientStop { position: 2 / 6; color: "#00ff00" }
                GradientStop { position: 3 / 6; color: "#00ffff" }
                GradientStop { position: 4 / 6; color: "#0000ff" }
                GradientStop { position: 5 / 6; color: "#ff00ff" }
                GradientStop { position: 6 / 6; color: "#ff0000" }
              }
            }

            Rectangle {
              width: parent.width + Style.space(6)
              height: Style.space(6)
              x: -Style.space(3)
              y: root.hue * hueStrip.height - height / 2
              radius: height / 2
              color: "transparent"
              border.width: Style.space(2)
              border.color: root.foreground
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              function pick(mouse) {
                root.hue = Math.max(0, Math.min(0.999, mouse.y / height))
                root.setFromHsv()
              }
              onPressed: function(mouse) { pick(mouse) }
              onPositionChanged: function(mouse) { if (pressed) pick(mouse) }
            }
          }
        }

        // ---------- Hex value and eyedropper ----------
        Row {
          width: parent.width
          spacing: Style.space(10)

          Rectangle {
            width: parent.width - eyedropperButton.width - parent.spacing
            height: eyedropperButton.height
            radius: Style.space(4)
            color: "transparent"
            border.width: 1
            border.color: hexInput.activeFocus ? root.accent : root.quiet

            Text {
              id: hashSign
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "#"
              color: root.foreground
              opacity: 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            TextInput {
              id: hexInput
              anchors.left: hashSign.right
              anchors.leftMargin: Style.space(2)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: root.colors[root.slot]
              maximumLength: 7
              color: root.foreground
              selectionColor: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              validator: RegularExpressionValidator { regularExpression: /#?[0-9a-fA-F]{0,6}/ }
              onTextEdited: if (/^#?[0-9a-fA-F]{6}$/.test(text)) root.setHex(text)
              Keys.onEscapePressed: keyCatcher.forceActiveFocus()
              onAccepted: keyCatcher.forceActiveFocus()
            }
          }

          Button {
            id: eyedropperButton
            text: "Pick from screen"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            onClicked: root.pickFromScreen()
          }
        }

        // ---------- Presets ----------
        Column {
          width: parent.width
          spacing: Style.space(6)

          Text {
            textFormat: Text.PlainText
            text: "Presets"
            color: root.foreground
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Flow {
            width: parent.width
            spacing: Style.space(8)

            Repeater {
              model: root.presets

              Rectangle {
                id: chip
                required property var modelData
                width: chipLabel.implicitWidth + Style.space(34)
                height: Style.space(26)
                radius: height / 2
                color: "transparent"
                border.width: 1
                border.color: chipArea.containsMouse ? root.foreground : root.quiet

                Rectangle {
                  id: chipDot
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(16)
                  height: width
                  radius: width / 2
                  gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#" + chip.modelData.colors[0] }
                    GradientStop { position: 0.5; color: "#" + chip.modelData.colors[1] }
                    GradientStop { position: 1.0; color: "#" + chip.modelData.colors[2] }
                  }
                }

                Text {
                  id: chipLabel
                  anchors.left: chipDot.right
                  anchors.leftMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: chip.modelData.name
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                MouseArea {
                  id: chipArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.usePreset(chip.modelData)
                }
              }
            }
          }
        }

        // ---------- Actions ----------
        Item {
          width: parent.width
          height: saveButton.implicitHeight

          Button {
            anchors.left: parent.left
            text: "Reset to purple"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            onClicked: root.usePreset(root.presets[0])
          }

          Row {
            anchors.right: parent.right
            spacing: Style.space(8)

            Button {
              text: "Cancel"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              onClicked: root.cancel()
            }

            Button {
              id: saveButton
              text: "Save"
              bordered: true
              foreground: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              onClicked: root.save()
            }
          }
        }
      }
    }
  }
}
