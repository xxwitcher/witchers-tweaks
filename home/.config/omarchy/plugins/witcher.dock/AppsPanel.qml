import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// The dock's Apps panel, like the Apps view on macOS: a search field on top
// and every app below in rows of five, scrolling when they don't fit. It
// opens beside the dock (above it at the bottom of the screen).
//
// Type to search; arrows move, Enter opens the picked app, Esc clears the
// search and then closes. Click an app to open it, drag it onto the dock to
// keep it there, or right click it for Open, Keep in Dock, Open at Login and
// Remove (uninstall, after a confirmation).
//
// The list, search order, icons, launching and removal are Omarchy's own
// (shell.appLibrary), so apps hidden from Omarchy's launcher stay hidden.
BorderSurface {
  id: panel

  // The dock service (Dock.qml's root) and the dock window (host) it opens in.
  required property var dock
  required property var host

  readonly property var library: dock.shell && dock.shell.appLibrary ? dock.shell.appLibrary : null
  readonly property int columns: 5
  readonly property int iconSize: Style.space(64)
  readonly property int cellWidth: Style.space(128)
  readonly property int cellHeight: iconSize + Style.font.body * 2 + Style.space(30)
  readonly property int visibleRows: 4
  readonly property int searchHeight: Style.font.title + Style.space(18)
  readonly property int inset: Style.space(18)

  property string query: ""
  property int selected: 0
  // { entry, x, y } while an app's menu is open.
  property var menu: null

  width: cellWidth * columns + inset * 2
  height: inset * 2 + searchHeight + Style.space(18) + cellHeight * visibleRows
  radius: Math.round(Style.space(30) * dock.roundness)
  color: dock.appsBackground
  borderSpec: dock.borderSpec

  function reset() {
    query = ""
    selected = 0
    menu = null
    grid.positionViewAtBeginning()
    if (library && typeof library.refreshIcons === "function") library.refreshIcons()
    Qt.callLater(function() { search.forceActiveFocus() })
  }

  // --------------------------------------------------------------- apps

  readonly property var apps: {
    var stamp = DesktopEntries.applications ? DesktopEntries.applications.values.length : 0
    // Omarchy's search returns ranked rows ({ entry, score, ... }).
    if (library && typeof library.sortedEntries === "function")
      return library.sortedEntries(query).map(function(row) { return row && row.entry ? row.entry : row })
    // Without Omarchy's library: by name, filtered on the name.
    var q = query.trim().toLowerCase()
    return (DesktopEntries.applications ? DesktopEntries.applications.values : [])
      .filter(function(e) { return e && !e.noDisplay && (q === "" || String(e.name).toLowerCase().indexOf(q) >= 0) })
      .sort(function(a, b) { return String(a.name).localeCompare(String(b.name)) })
  }
  onAppsChanged: selected = 0
  // Typing breaks a text binding, so clearing the query clears the field here.
  onQueryChanged: if (search.text !== query) search.text = query

  function nameOf(entry) {
    return library && typeof library.entryName === "function" ? library.entryName(entry) : String(entry.name)
  }

  function iconOf(entry) {
    if (library && typeof library.iconSource === "function") return library.iconSource(entry.icon)
    var path = entry.icon ? Quickshell.iconPath(entry.icon, true) : ""
    return path !== "" ? path : Quickshell.iconPath("application-x-executable", true)
  }

  function launch(entry) {
    if (!entry) return
    host.appsOpen = false
    dock.launchEntry(entry)
  }

  // Asks first (the dock's Remove dialog), then uninstalls.
  function remove(entry) {
    host.askRemove(entry)
  }

  function move(delta) {
    if (apps.length === 0) return
    selected = Math.max(0, Math.min(apps.length - 1, selected + delta))
    grid.positionViewAtIndex(selected, GridView.Contain)
  }

  // Clicks on the panel stay on it (and close an open app menu).
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: panel.menu = null
  }

  // ---------- search ----------
  BorderSurface {
    id: searchBox
    anchors.horizontalCenter: parent.horizontalCenter
    y: panel.inset
    width: Style.space(300)
    height: panel.searchHeight
    radius: height / 2 * dock.roundness
    color: Qt.lighter(dock.background, 1.3)
    borderSpec: Border.flat(dock.quiet, Math.max(1, Style.space(1)))

    Text {
      anchors.verticalCenter: parent.verticalCenter
      x: Style.space(14)
      textFormat: Text.PlainText
      text: "⌕"
      color: dock.foreground
      opacity: 0.6
      font.family: dock.fontFamily
      font.pixelSize: Style.font.title
    }

    TextInput {
      id: search
      anchors.verticalCenter: parent.verticalCenter
      x: Style.space(34)
      width: parent.width - x - Style.space(14)
      clip: true
      color: dock.foreground
      selectionColor: dock.accent
      font.family: dock.fontFamily
      font.pixelSize: Style.font.body
      onTextEdited: panel.query = text

      Text {
        visible: search.text === ""
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "Search"
        color: dock.foreground
        opacity: 0.45
        font: search.font
      }

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          if (panel.menu) panel.menu = null
          else if (panel.query !== "") panel.query = ""
          else host.appsOpen = false
        }
        else if (event.key === Qt.Key_Left) panel.move(-1)
        else if (event.key === Qt.Key_Right) panel.move(1)
        else if (event.key === Qt.Key_Up) panel.move(-panel.columns)
        else if (event.key === Qt.Key_Down) panel.move(panel.columns)
        else if (event.key === Qt.Key_Tab) panel.move(1)
        else if (event.key === Qt.Key_Backtab) panel.move(-1)
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) panel.launch(panel.apps[panel.selected])
        else return
        event.accepted = true
      }
    }
  }

  // ---------- the apps ----------
  GridView {
    id: grid
    x: panel.inset
    y: searchBox.y + searchBox.height + Style.space(18)
    width: panel.cellWidth * panel.columns
    height: panel.cellHeight * panel.visibleRows
    cellWidth: panel.cellWidth
    cellHeight: panel.cellHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    model: panel.apps
    // Scrolling is done by hand below (the grid's own wheel scrolling has no
    // momentum here), and a mouse drag on an app carries it to the dock.
    interactive: false

    delegate: Item {
      id: cell
      required property var modelData
      required property int index
      readonly property bool picked: panel.selected === index
      width: panel.cellWidth
      height: panel.cellHeight

      Rectangle {
        anchors.fill: parent
        anchors.margins: Style.space(5)
        radius: dock.smallRadius
        color: dock.hover
        visible: cell.picked
      }

      Image {
        id: icon
        anchors.horizontalCenter: parent.horizontalCenter
        y: Style.space(12)
        width: panel.iconSize
        height: panel.iconSize
        sourceSize.width: panel.iconSize * 2
        sourceSize.height: panel.iconSize * 2
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        source: panel.iconOf(cell.modelData)
        scale: cellMouse.pressed && !host.dragging ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: 90 } }
      }

      Text {
        anchors.top: icon.bottom
        anchors.topMargin: Style.space(8)
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - Style.space(14)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: panel.nameOf(cell.modelData)
        color: dock.foreground
        font.family: dock.fontFamily
        font.pixelSize: Style.font.body
      }

      MouseArea {
        id: cellMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        property point pressAt: Qt.point(0, 0)
        property bool moved: false

        function windowPoint(m) { return cellMouse.mapToItem(host.contentItem, m.x, m.y) }

        onEntered: if (!panel.menu) panel.selected = cell.index
        onPressed: function(m) {
          pressAt = windowPoint(m)
          moved = false
        }
        // Dragging an app out of the panel carries it to the dock.
        onPositionChanged: function(m) {
          if (!(m.buttons & Qt.LeftButton)) return
          var p = windowPoint(m)
          if (!host.dragging) {
            if (Math.hypot(p.x - pressAt.x, p.y - pressAt.y) < Style.space(10)) return
            moved = true
            panel.menu = null
            host.startEntryDrag(cell.modelData, p)
          } else {
            host.moveDrag(p)
          }
        }
        onReleased: function(m) {
          if (moved && host.dragging) host.finishDrag()
        }
        onCanceled: if (moved) host.cancelDrag()
        onClicked: function(m) {
          if (moved) return
          if (m.button === Qt.RightButton) {
            var p = cell.mapToItem(panel, m.x, m.y)
            panel.selected = cell.index
            panel.menu = { entry: cell.modelData, x: p.x, y: p.y }
          } else if (panel.menu) {
            panel.menu = null
          } else {
            panel.launch(cell.modelData)
          }
        }
      }
    }
  }

  // ---------- smooth scrolling ----------
  // A touchpad moves the grid with the fingers, then it glides on and slows
  // down when they lift (the compositor sends no momentum of its own). A
  // mouse wheel notch pushes it into the same glide.
  QtObject {
    id: scroller
    property real velocity: 0          // px/s, positive scrolls down
    property double lastAt: 0
    readonly property real friction: 3.4  // how fast a glide slows (1/s)
    readonly property real speed: 1.4     // touchpad distance multiplier

    function maxY() { return grid.originY + Math.max(0, grid.contentHeight - grid.height) }
    function moveBy(dy) {
      var y = Math.max(grid.originY, Math.min(maxY(), grid.contentY + dy))
      var stuck = y === grid.contentY
      grid.contentY = y
      return !stuck
    }
  }

  // Takes only scroll events (clicks, hover and drags pass through to the
  // apps below).
  MouseArea {
    x: grid.x
    y: grid.y
    width: grid.width
    height: grid.height
    z: 5
    acceptedButtons: Qt.NoButton
    enabled: panel.menu === null && !host.dragging
    onWheel: function(event) {
      var now = Date.now()
      // The touchpad marks a scroll's start and end (phases 1 and 3) with
      // events that move nothing; the end one means the fingers lifted.
      if (event.pixelDelta.y === 0 && event.angleDelta.y === 0) {
        if (event.phase === Qt.ScrollEnd) {
          liftTimer.stop()
          glide.running = Math.abs(scroller.velocity) > 60
        } else if (event.phase === Qt.ScrollBegin) {
          glide.running = false
          scroller.velocity = 0
        }
        return
      }
      var fine = event.pixelDelta.y !== 0 || event.angleDelta.y % 120 !== 0
      if (fine) {
        // Fingers on the touchpad: follow them, and track their speed.
        var dy = (event.pixelDelta.y !== 0 ? -event.pixelDelta.y : -event.angleDelta.y / 120 * Style.space(40)) * scroller.speed
        var dt = Math.max(4, now - scroller.lastAt)
        var speed = dy * 1000 / dt
        scroller.velocity = now - scroller.lastAt > 120 ? speed : scroller.velocity * 0.5 + speed * 0.5
        scroller.lastAt = now
        glide.running = false
        scroller.moveBy(dy)
        liftTimer.restart()
      } else {
        // A mouse wheel notch: a push into the glide, adding up when spun.
        var push = -event.angleDelta.y / 120 * Style.space(1400)
        scroller.velocity = Math.sign(push) === Math.sign(scroller.velocity) && glide.running ? scroller.velocity + push : push
        liftTimer.stop()
        glide.running = true
      }
    }
  }

  // The fingers lifted (no events for a moment): glide.
  Timer {
    id: liftTimer
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

  Text {
    visible: panel.apps.length === 0
    anchors.centerIn: grid
    textFormat: Text.PlainText
    text: "No results for “" + panel.query + "”"
    color: dock.foreground
    opacity: 0.7
    font.family: dock.fontFamily
    font.pixelSize: Style.font.title
  }

  // ---------- right-click menu ----------
  BorderSurface {
    id: menuCard
    readonly property var info: panel.menu
    readonly property var entry: info ? info.entry : null
    readonly property bool kept: entry !== null && dock.pinned.indexOf(entry.id) >= 0
    visible: info !== null
    x: info ? Math.max(Style.space(8), Math.min(panel.width - width - Style.space(8), info.x)) : 0
    y: info ? Math.max(Style.space(8), Math.min(panel.height - height - Style.space(8), info.y)) : 0
    z: 10
    width: Style.space(220)
    height: menuColumn.implicitHeight + contentTopInset + contentBottomInset
    radius: dock.smallRadius
    color: dock.background
    borderSpec: dock.borderSpec
    padding: Style.space(4)

    readonly property var rows: {
      var e = entry
      if (!e) return []
      var atLogin = dock.opensAtLogin(e.id)
      var list = [
        { label: "Open", action: function() { panel.launch(e) } },
        { separator: true },
        { label: "Keep in Dock", checked: kept, action: function() {
          if (menuCard.kept) dock.unkeepId(e.id)
          else dock.keepEntry(e, -1)
        } },
        { label: "Open at Login", checked: atLogin, action: function() {
          Quickshell.execDetached([dock.tool, "autostart", atLogin ? "off" : "on", e.id])
        } }
      ]
      if (panel.library && typeof panel.library.remove === "function") {
        list.push({ separator: true })
        list.push({ label: "Remove…", danger: true, action: function() { panel.remove(e) } })
      }
      return list
    }

    MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton }

    Column {
      id: menuColumn
      x: menuCard.contentLeftInset
      y: menuCard.contentTopInset
      width: menuCard.width - menuCard.contentLeftInset - menuCard.contentRightInset

      Repeater {
        model: menuCard.rows

        Item {
          id: row
          required property var modelData
          readonly property bool separator: modelData.separator === true
          width: menuColumn.width
          height: separator ? Style.space(9) : rowText.implicitHeight + Style.space(10)

          Rectangle {
            visible: row.separator
            anchors.verticalCenter: parent.verticalCenter
            x: Style.space(6)
            width: parent.width - Style.space(12)
            height: Math.max(1, Style.space(1))
            color: dock.quiet
          }

          Rectangle {
            anchors.fill: parent
            radius: Math.max(0, dock.smallRadius - Style.space(4))
            color: dock.hover
            visible: !row.separator && !row.modelData.disabled && rowMouse.containsMouse
          }

          Text {
            visible: row.modelData.checked === true
            anchors.verticalCenter: parent.verticalCenter
            x: Style.space(8)
            textFormat: Text.PlainText
            text: "✓"
            color: dock.foreground
            font.family: dock.fontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            id: rowText
            visible: !row.separator
            anchors.verticalCenter: parent.verticalCenter
            x: Style.space(26)
            width: parent.width - x - Style.space(8)
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: row.modelData.label || ""
            color: row.modelData.danger ? Color.urgent : dock.foreground
            opacity: row.modelData.disabled ? 0.6 : 1
            font.family: dock.fontFamily
            font.pixelSize: Style.font.body
          }

          MouseArea {
            id: rowMouse
            enabled: !row.separator && !row.modelData.disabled
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              var act = row.modelData.action
              if (!row.modelData.keepOpen) panel.menu = null
              if (act) act()
            }
          }
        }
      }
    }
  }
}
