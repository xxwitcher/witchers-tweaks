import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Mission Control-style overview on the focused screen. Along the top, a
// strip of every workspace as a miniature of the screen (scrolls sideways
// when there are more than fit). Below it, the windows of the workspace the
// pointer last hovered in the strip (the current one to start with), as big
// live thumbnails.
//
// Clicking a workspace goes to it; clicking a window goes to that window,
// raised above the others when it floats. Either way bin/focus-window then puts the cursor on the focused window, so
// Omarchy's focus-follows-mouse doesn't hand focus to another one.
// Keys: Left/Right pick a workspace, Tab/Shift+Tab a window, Enter goes to the
// picked window (or the workspace when it's empty), Esc closes. A click on
// the backdrop closes too.
//
// Opened with `omarchy-shell shell summon witcher.overview '{}'`; the 3-finger
// swipe up in hypr/input.lua does that (and swipe down hides it).
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  // Every workspace: { id, name, active, monitor, windows: [...] }
  property var workspaces: []
  property int selectedWorkspace: 0
  property int selectedWindow: 0

  readonly property var current: selectedWorkspace >= 0 && selectedWorkspace < workspaces.length
    ? workspaces[selectedWorkspace] : null
  readonly property var windows: current ? current.windows : []

  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")

  readonly property color foreground: Color.menu.text
  readonly property color accent: Color.accent
  // Dark enough that the windows behind don't compete with the thumbnails.
  readonly property color scrim: Qt.rgba(Color.menu.background.r, Color.menu.background.g, Color.menu.background.b, 0.96)
  readonly property color cardBackground: Color.menu.background
  readonly property color quiet: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.25)
  readonly property string fontFamily: Style.font.menuFamily
  readonly property int radius: Style.cornerRadius

  // The picked workspace and window wear the window border: the theme's
  // active-border gradient (the border tweak's colors when it's on, flat
  // accent otherwise), turning at the same speed as on the windows.
  property real borderTurn: 0
  readonly property var activeBorder: Border.withWidth(Border.hyprlandActiveSpec(accent, 0), Style.space(3))
  readonly property var pickedBorder: activeBorder.gradient.enabled
    ? {
        color: activeBorder.color,
        widths: activeBorder.widths,
        gradient: {
          colors: activeBorder.gradient.colors,
          angle: (activeBorder.gradient.angle + borderTurn) % 360,
          enabled: true
        }
      }
    : activeBorder

  NumberAnimation on borderTurn {
    from: 0
    to: 360
    duration: 13330
    loops: Animation.Infinite
    running: root.opened && root.activeBorder.gradient.enabled
  }

  readonly property int margin: Style.space(40)
  readonly property int cardGap: Style.space(22)
  readonly property int titleHeight: Style.font.caption + Style.space(10)
  readonly property int stripCardWidth: Style.space(190)
  readonly property int stripGap: Style.space(16)

  // --------------------------------------------------------------- open/close

  function open(payloadJson) {
    Hyprland.refreshMonitors()
    Hyprland.refreshWorkspaces()
    Hyprland.refreshToplevels()
    rebuild()
    var focused = Hyprland.focusedWorkspace
    selectedWorkspace = 0
    for (var i = 0; i < workspaces.length; i++)
      if (focused && workspaces[i].id === focused.id) selectedWorkspace = i
    selectedWindow = activeWindowIndex()
    opened = true
    Qt.callLater(function() {
      keyCatcher.forceActiveFocus()
      strip.positionViewAtIndex(root.selectedWorkspace, ListView.Contain)
    })
  }

  function close() {
    opened = false
  }

  function dismiss() {
    opened = false
    if (shell && typeof shell.hide === "function") shell.hide((manifest && manifest.id) || "witcher.overview")
  }

  function toggle() {
    if (opened) dismiss()
    else open("{}")
  }

  function goWindow(entry) {
    if (!entry) return
    dismiss()
    Quickshell.execDetached([pluginDir + "/bin/focus-window", entry.address])
  }

  function goWorkspace(workspace) {
    if (!workspace) return
    dismiss()
    Quickshell.execDetached([pluginDir + "/bin/focus-window", "--workspace", String(workspace.id)])
  }

  // --------------------------------------------------------------- model

  function hexAddress(value) {
    var text = String(value || "").replace(/^0x/, "")
    return text === "" ? "" : "0x" + text
  }

  // A monitor's origin and size in layout coordinates (window positions are
  // in those; the monitor reports physical pixels and a scale).
  function monitorBox(monitor) {
    var scale = monitor && monitor.scale > 0 ? monitor.scale : 1
    return {
      x: monitor ? monitor.x : 0,
      y: monitor ? monitor.y : 0,
      width: monitor && monitor.width > 0 ? monitor.width / scale : 1920,
      height: monitor && monitor.height > 0 ? monitor.height / scale : 1080
    }
  }

  function rebuild() {
    var byId = ({})
    var list = []
    var spaces = Hyprland.workspaces ? Hyprland.workspaces.values : []
    for (var i = 0; i < spaces.length; i++) {
      var ws = spaces[i]
      // Named special workspaces (the scratchpad) stay out, like on screen.
      if (!ws || ws.id < 0) continue
      var entry = {
        id: ws.id,
        name: String(ws.name || ws.id),
        active: Hyprland.focusedWorkspace === ws,
        box: monitorBox(ws.monitor),
        windows: []
      }
      byId[String(ws.id)] = entry
      list.push(entry)
    }

    var toplevels = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (var t = 0; t < toplevels.length; t++) {
      var top = toplevels[t]
      var owner = top && top.workspace ? byId[String(top.workspace.id)] : null
      if (!owner) continue
      var ipc = top.lastIpcObject || ({})
      var size = ipc.size || [16, 10]
      var at = ipc.at || [0, 0]
      owner.windows.push({
        toplevel: top,
        address: hexAddress(top.address),
        title: String(top.title || ipc.title || ""),
        appClass: String(ipc.class || ""),
        x: Number(at[0]),
        y: Number(at[1]),
        width: Math.max(1, Number(size[0])),
        height: Math.max(1, Number(size[1])),
        aspect: Math.max(0.2, Math.min(5, Number(size[0]) / Math.max(1, Number(size[1]))))
      })
    }

    list.sort(function(a, b) { return a.id - b.id })
    for (var w = 0; w < list.length; w++)
      list[w].windows.sort(function(a, b) { return a.x - b.x || a.y - b.y })
    workspaces = list
  }

  function activeWindowIndex() {
    var active = Hyprland.activeToplevel
    for (var i = 0; i < windows.length; i++)
      if (windows[i].toplevel === active) return i
    return 0
  }

  function selectWorkspace(index) {
    if (index < 0 || index >= workspaces.length || index === selectedWorkspace) return
    selectedWorkspace = index
    selectedWindow = activeWindowIndex()
    strip.positionViewAtIndex(index, ListView.Contain)
  }

  // --------------------------------------------------------------- layout

  // Lay the hovered workspace's windows out in however many rows makes them
  // biggest, keeping their order and aspect ratios; each row is centered.
  // Returns { height, rows: [[window index...]] }.
  function windowGrid(windowList, width, height) {
    var n = windowList.length
    if (n === 0 || width <= 0 || height <= 0) return { height: 0, rows: [] }
    var best = { height: 0, rows: [] }
    for (var rowCount = 1; rowCount <= n; rowCount++) {
      var rows = []
      var perRow = Math.ceil(n / rowCount)
      for (var start = 0; start < n; start += perRow) {
        var row = []
        for (var i = start; i < Math.min(n, start + perRow); i++) row.push(i)
        rows.push(row)
      }
      var h = (height - rows.length * titleHeight - (rows.length - 1) * cardGap) / rows.length
      for (var r = 0; r < rows.length; r++) {
        var aspects = 0
        for (var k = 0; k < rows[r].length; k++) aspects += windowList[rows[r][k]].aspect
        h = Math.min(h, (width - (rows[r].length - 1) * cardGap) / aspects)
      }
      if (h > best.height) best = { height: h, rows: rows }
    }
    best.height = Math.floor(Math.min(best.height, height * 0.8))
    return best
  }

  // --------------------------------------------------------------- window

  PanelWindow {
    id: window
    visible: root.opened
    screen: {
      var name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
      for (var i = 0; i < Quickshell.screens.length; i++)
        if (Quickshell.screens[i].name === name) return Quickshell.screens[i]
      return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    }
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "witcher-overview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle {
      anchors.fill: parent
      color: root.scrim
      opacity: root.opened ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) root.dismiss()
        else if (event.key === Qt.Key_Left) root.selectWorkspace(root.selectedWorkspace - 1)
        else if (event.key === Qt.Key_Right) root.selectWorkspace(root.selectedWorkspace + 1)
        else if (event.key === Qt.Key_Tab && root.windows.length > 0)
          root.selectedWindow = (root.selectedWindow + 1) % root.windows.length
        else if (event.key === Qt.Key_Backtab && root.windows.length > 0)
          root.selectedWindow = (root.selectedWindow - 1 + root.windows.length) % root.windows.length
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          if (root.windows.length > 0) root.goWindow(root.windows[root.selectedWindow])
          else root.goWorkspace(root.current)
        }
        else return
        event.accepted = true
      }
    }

    Item {
      id: content
      anchors.fill: parent
      anchors.margins: root.margin
      opacity: root.opened ? 1 : 0
      scale: root.opened ? 1 : 0.96
      Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }

      // ---------- Workspaces strip ----------
      ListView {
        id: strip
        readonly property real cardHeight: {
          var box = root.workspaces.length > 0 ? root.workspaces[0].box : null
          return box ? root.stripCardWidth * box.height / box.width : root.stripCardWidth * 0.625
        }
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        // Room for the picked card to grow without being clipped.
        leftMargin: Style.space(8)
        rightMargin: Style.space(8)
        width: Math.min(parent.width, contentWidth + leftMargin + rightMargin)
        height: cardHeight + root.titleHeight + Style.space(8)
        orientation: ListView.Horizontal
        spacing: root.stripGap
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.workspaces

        // A mouse wheel scrolls the strip sideways; touchpads already do.
        WheelHandler {
          acceptedDevices: PointerDevice.Mouse
          onWheel: function(event) {
            var min = -strip.leftMargin
            var max = Math.max(min, strip.contentWidth + strip.rightMargin - strip.width)
            strip.contentX = Math.max(min, Math.min(max, strip.contentX - event.angleDelta.y))
          }
        }

        delegate: Item {
          id: space
          required property var modelData
          required property int index
          readonly property bool selected: root.selectedWorkspace === index
          width: root.stripCardWidth
          height: strip.height

          Rectangle {
            id: miniature
            y: Style.space(4)
            width: parent.width
            height: strip.cardHeight
            radius: root.radius
            color: root.cardBackground
            clip: true
            scale: space.selected ? 1.04 : 1
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

            readonly property real ratio: width / space.modelData.box.width

            // The workspace's windows where they sit on its screen.
            Repeater {
              model: space.modelData.windows

              ScreencopyView {
                required property var modelData
                x: (modelData.x - space.modelData.box.x) * miniature.ratio
                y: (modelData.y - space.modelData.box.y) * miniature.ratio
                width: modelData.width * miniature.ratio
                height: modelData.height * miniature.ratio
                captureSource: root.opened && modelData.toplevel ? modelData.toplevel.wayland : null
                // Live, not a single frame: a one-off capture of a window
                // that isn't redrawing (an idle terminal, a file manager)
                // can come back empty. Small buffers keep it cheap.
                live: root.opened
                constraintSize: Qt.size(width * 2, height * 2)
              }
            }

            Rectangle {
              visible: !space.selected
              anchors.fill: parent
              radius: root.radius
              color: "transparent"
              border.width: 1
              border.color: root.quiet
            }

            BorderOverlay {
              visible: space.selected
              radius: root.radius
              borderSpec: root.pickedBorder
            }
          }

          Text {
            anchors.top: miniature.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: root.titleHeight
            verticalAlignment: Text.AlignBottom
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            textFormat: Text.PlainText
            // The workspace you're on is marked with a dot.
            text: (space.modelData.active ? "● " : "") + "Workspace " + space.modelData.name
            color: root.foreground
            opacity: space.selected ? 1 : 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          HoverHandler {
            onHoveredChanged: if (hovered) root.selectWorkspace(space.index)
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.goWorkspace(space.modelData)
          }
        }
      }

      // ---------- The picked workspace's windows ----------
      Item {
        id: windowsArea
        anchors.top: strip.bottom
        anchors.topMargin: root.margin
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        readonly property var grid: root.windowGrid(root.windows, width, height)

        Text {
          visible: root.windows.length === 0
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: root.current ? "No windows on Workspace " + root.current.name : "No workspaces"
          color: root.foreground
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
        }

        Column {
          anchors.centerIn: parent
          spacing: root.cardGap

          Repeater {
            model: windowsArea.grid.rows

            Row {
              id: gridRow
              required property var modelData
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: root.cardGap

              Repeater {
                model: gridRow.modelData

                Item {
                  id: card
                  required property var modelData
                  readonly property var entry: root.windows[modelData]
                  readonly property bool selected: root.selectedWindow === modelData
                  width: Math.round(windowsArea.grid.height * (entry ? entry.aspect : 1))
                  height: windowsArea.grid.height + root.titleHeight

                  HoverHandler {
                    onHoveredChanged: if (hovered) root.selectedWindow = card.modelData
                  }

                  Rectangle {
                    id: frame
                    width: parent.width
                    height: windowsArea.grid.height
                    radius: root.radius
                    color: root.cardBackground
                    scale: card.selected ? 1.03 : 1
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                    ScreencopyView {
                      id: capture
                      anchors.fill: parent
                      anchors.margins: Style.space(2)
                      captureSource: root.opened && card.entry && card.entry.toplevel ? card.entry.toplevel.wayland : null
                      live: root.opened
                      constraintSize: Qt.size(width, height)
                    }

                    // A window the compositor won't hand over (or hasn't yet)
                    // shows its app icon instead.
                    Image {
                      visible: !capture.hasContent
                      anchors.centerIn: parent
                      width: Math.min(parent.width, parent.height) * 0.4
                      height: width
                      sourceSize.width: width * 2
                      sourceSize.height: height * 2
                      fillMode: Image.PreserveAspectFit
                      source: {
                        var cls = card.entry ? card.entry.appClass : ""
                        var desktop = DesktopEntries.heuristicLookup(cls)
                        return Quickshell.iconPath(desktop && desktop.icon ? desktop.icon : cls, true)
                      }
                    }

                    Rectangle {
                      visible: !card.selected
                      anchors.fill: parent
                      radius: root.radius
                      color: "transparent"
                      border.width: 1
                      border.color: root.quiet
                    }

                    BorderOverlay {
                      visible: card.selected
                      radius: root.radius
                      borderSpec: root.pickedBorder
                    }
                  }

                  Text {
                    anchors.top: frame.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: root.titleHeight
                    verticalAlignment: Text.AlignBottom
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: card.entry ? card.entry.title : ""
                    color: root.foreground
                    opacity: card.selected ? 1 : 0.75
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.goWindow(card.entry)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
