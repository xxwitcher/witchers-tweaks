import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// The window buttons in the top bar, between the Omarchy menu and the
// workspaces, while the focused window is maximized (it has no strip or tab
// then, and fills the screen): close, minimize, and green to restore it.
BarWidget {
  id: root
  moduleName: "witcher.titlebars"

  readonly property var window: Hyprland.activeToplevel
  property bool maximized: false

  // Whether the focused window is maximized, asked from Hyprland's request
  // socket ("j/activewindow") when its events say something changed, rather
  // than refreshing Quickshell's window list (which makes everything that
  // watches windows redo its work).
  property string reply: ""
  Socket {
    id: query
    path: Hyprland.requestSocketPath
    parser: SplitParser {
      splitMarker: ""
      // Hyprland closes the connection after its reply; hanging up as soon
      // as the reply is whole keeps that from being logged as an error.
      onRead: data => {
        root.reply += data
        if (/\}\s*$/.test(root.reply) && root.take(root.reply)) { root.reply = ""; query.connected = false }
      }
    }
    onConnectedChanged: {
      if (connected) {
        root.reply = ""
        write("j/activewindow")
        flush()
      } else {
        if (root.reply !== "") root.take(root.reply)
        root.reply = ""
      }
    }
  }
  function take(text) {
    var w
    try { w = JSON.parse(text) } catch (e) { return false }
    var now = !!(w && w.fullscreen > 0)
    if (maximized !== now) maximized = now
    return true
  }
  function poll() { if (!query.connected) query.connected = true }
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      if (/^(fullscreen|activewindowv2|closewindow|openwindow|movewindowv2|workspacev2|focusedmonv2)$/.test(name))
        pollTimer.restart()
    }
  }
  Timer { id: pollTimer; interval: 40; onTriggered: root.poll() }
  Component.onCompleted: poll()
  readonly property string address: window ? "0x" + String(window.address).replace(/^0x/, "") : ""

  readonly property int dot: 13
  readonly property int gap: 8
  readonly property real full: dot * 3 + gap * 2 + Style.space(12)
  property real reveal: maximized ? 1 : 0
  Behavior on reveal { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

  implicitWidth: vertical ? barSize : full * reveal
  implicitHeight: vertical ? full * reveal : barSize
  visible: reveal > 0.01
  clip: true

  function dispatch(lua) { Quickshell.execDetached(["hyprctl", "dispatch", lua]) }

  // The tab's buttons: dots in the bar's icon color with their symbols in
  // the bar's background color (the same colors as the tab's).
  readonly property color ink: bar ? bar.foreground : Color.bar.text
  readonly property color paper: Color.bar.background

  Grid {
    id: buttons
    anchors.centerIn: parent
    columns: root.vertical ? 1 : 3
    spacing: root.gap
    opacity: root.reveal
    Repeater {
      model: [
        { symbol: "×", action: "close" },
        { symbol: "−", action: "minimize" },
        { symbol: "+", action: "restore" }
      ]
      Rectangle {
        id: button
        required property var modelData
        width: root.dot
        height: root.dot
        radius: root.dot / 2
        color: root.ink
        Text {
          anchors.centerIn: parent
          anchors.verticalCenterOffset: -1
          text: button.modelData.symbol
          color: root.paper
          font.pixelSize: 11
          font.bold: true
        }
        MouseArea {
          anchors.fill: parent
          enabled: root.maximized
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            var a = "address:" + root.address
            if (button.modelData.action === "close")
              root.dispatch("hl.dsp.window.close({ window = \"" + a + "\" })")
            else if (button.modelData.action === "minimize")
              // Through the dock (it animates it without a blink), else straight away.
                  Quickshell.execDetached(["bash", "-c", "omarchy-shell witcher.dock minimize " + a.replace("address:", "") + " >/dev/null 2>&1 || hyprctl dispatch 'hl.dsp.window.move({ window = \"" + a + "\", workspace = \"special:minimized\", follow = false })'"])
            else
              root.dispatch("hl.dsp.window.fullscreen({ mode = \"maximized\" })")
          }
        }
      }
    }
  }
}
