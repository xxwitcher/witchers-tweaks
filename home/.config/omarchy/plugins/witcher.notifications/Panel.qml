import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// A bell in the bar that opens every recent notification: the ones still on
// screen (read live from omarchy.notifications, or from the files Omarchy
// keeps for them on 4.0.3 and later, where a plugin can't reach that
// service) and the ones that already left it (kept by
// bin/notification-store, which copies them out of Omarchy's 10-entry
// history). Each card is Omarchy's own NotificationCard,
// so they look like the popups, with its hover ✕ to dismiss one and
// "Dismiss all" to clear the lot. Clicking a card runs its action, like
// clicking the popup would.
Panel {
  id: root
  moduleName: "witcher.notifications"
  ipcTarget: "witcher.notifications"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string storeCommand: pluginDir + "/bin/notification-store"
  readonly property string cardUrl: Util.fileUrl((Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy")
    + "/shell/plugins/notifications/components/NotificationCard.qml")

  readonly property var service: bar && bar.shell && typeof bar.shell.firstPartyServiceFor === "function"
    ? bar.shell.firstPartyServiceFor("omarchy.notifications") : null
  readonly property var popupModel: service ? service.popupModel : null

  // Toasts on screen right now, and everything the store kept.
  property var live: []
  property var stored: []

  // On-screen first; a toast that has also reached the store shows once.
  readonly property var entries: {
    var out = []
    var names = ({})
    for (var i = 0; i < live.length; i++) {
      out.push(live[i])
      names[live[i].name] = true
    }
    for (var j = 0; j < stored.length; j++)
      if (!names[stored[j].name]) out.push(stored[j])
    return out
  }

  function fileName(row) {
    return String(row.timestamp || 0) + "-" + String(row.originalId || row.id || 0) + ".json"
  }

  function refreshLive() {
    var out = []
    var model = root.popupModel
    for (var i = 0; model && i < model.count; i++) {
      var row = model.get(i)
      if (!row) continue
      out.push({
        live: true,
        name: fileName(row),
        app: String(row.app || ""),
        appIcon: String(row.appIcon || ""),
        summary: String(row.summary || ""),
        body: String(row.body || ""),
        image: String(row.image || ""),
        glyph: String(row.glyph || ""),
        urgency: Number(row.urgency),
        timestamp: Number(row.timestamp || 0)
      })
    }
    live = out
  }

  function liveIndex(name) {
    var model = root.popupModel
    for (var i = 0; model && i < model.count; i++) {
      var row = model.get(i)
      if (row && fileName(row) === name) return i
    }
    return -1
  }

  // ---------------------------------------------------------------- store
  // One store command at a time, in order: a dismiss has to be recorded
  // before the next sync, or the toast it archived would come straight back.

  property var storeQueue: []

  function runStore(args) {
    var queue = storeQueue.slice()
    var last = queue.length > 0 ? queue[queue.length - 1] : null
    if (args[0] === "sync" && last && last[0] === "sync") return
    queue.push(args)
    storeQueue = queue
    runNextStore()
  }

  function runNextStore() {
    if (storeProc.running || storeQueue.length === 0) return
    var queue = storeQueue.slice()
    var args = queue.shift()
    storeQueue = queue
    // Without the service, the store lists the toasts on screen too.
    storeProc.command = [root.storeCommand].concat(args, root.service ? [] : ["--live"])
    storeProc.running = true
  }

  function applyStore(text) {
    try {
      var parsed = JSON.parse(String(text || "[]"))
      if (!Array.isArray(parsed)) return
      for (var i = 0; i < parsed.length; i++) parsed[i].live = false
      stored = parsed
    } catch (e) {
      console.warn("witcher.notifications: bad store output", e)
    }
  }

  Process {
    id: storeProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStore(text)
    }
    onRunningChanged: if (!running) Qt.callLater(root.runNextStore)
  }

  // ---------------------------------------------------------------- actions

  function dismiss(entry) {
    if (!entry) return
    runStore(["dismiss", entry.name])
    if (entry.live) {
      var index = liveIndex(entry.name)
      if (index >= 0 && service) service.dismissPopup(index)
    } else if (entry.onScreen && entry.summary) {
      Quickshell.execDetached(["omarchy-shell", "-q", "notifications", "dismiss", String(entry.summary)])
    }
    stored = stored.filter(function(e) { return e.name !== entry.name })
  }

  function dismissAll() {
    var names = live.map(function(e) { return e.name })
    runStore(["clear"].concat(names))
    if (service) service.clearPopups()
    else Quickshell.execDetached(["omarchy-shell", "-q", "notifications", "dismissAll"])
    stored = []
  }

  function parseArgv(value) {
    try {
      var argv = JSON.parse(String(value || ""))
      if (!Array.isArray(argv) || argv.length === 0) return null
      for (var i = 0; i < argv.length; i++)
        if (typeof argv[i] !== "string" || argv[i] === "") return null
      return argv
    } catch (e) {
      return null
    }
  }

  // Clicking a card does what clicking the popup does: run its action and
  // take it away. One without an action stays put.
  function activate(entry) {
    if (!entry) return
    if (entry.live) {
      var index = liveIndex(entry.name)
      if (index < 0 || !service) return
      runStore(["dismiss", entry.name])
      service.invokePopupDefault(index)
      root.close()
      return
    }
    var argv = parseArgv(entry.execArgv)
    if (!argv) return
    Util.execArgv(argv)
    dismiss(entry)
    root.close()
  }

  // ---------------------------------------------------------------- refresh

  Connections {
    target: root.popupModel
    function onCountChanged() {
      root.refreshLive()
      // A toast leaving the screen is archived into Omarchy's history a
      // moment later; pick it up once it's there.
      syncSoon.restart()
    }
    function onDataChanged() { root.refreshLive() }
  }

  onPopupModelChanged: refreshLive()

  onOpenedChanged: if (opened) {
    refreshLive()
    runStore(["sync"])
  }

  Timer {
    id: syncSoon
    interval: 800
    onTriggered: root.runStore(["sync"])
  }

  // Notifications silenced by Do Not Disturb go straight to history without
  // touching the screen, so check for those now and then too (more often
  // without the service, when nothing says a toast came or went).
  Timer {
    interval: root.service ? 30000 : 5000
    repeat: true
    running: true
    onTriggered: root.runStore(["sync"])
  }

  Component.onCompleted: {
    refreshLive()
    runStore(["sync"])
  }

  // ---------------------------------------------------------------- bar

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Filled bell while there's something to read, outline when empty.
    text: root.entries.length > 0 ? "󰂚" : "󰂜"
    tooltipText: ""
    onPressed: function(buttonCode) { root.toggle() }
  }

  // ---------------------------------------------------------------- panel

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    readonly property real maxHeight: Math.round((panel.screen ? panel.screen.height : 800) * 0.7)
    contentHeight: panel.fittedContentHeight(
      header.height + separator.anchors.topMargin + separator.height + list.anchors.topMargin
        + (root.entries.length > 0 ? cards.implicitHeight : emptyText.implicitHeight),
      maxHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Math.max(title.implicitHeight, dismissAllButton.implicitHeight)

        Text {
          id: title
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.entries.length > 0 ? "Notifications  ·  " + root.entries.length : "Notifications"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Button {
          id: dismissAllButton
          visible: root.entries.length > 0
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: "Dismiss all"
          bordered: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          verticalPadding: Style.space(3)
          onClicked: root.dismissAll()
        }
      }

      PanelSeparator {
        id: separator
        anchors.top: header.bottom
        anchors.topMargin: Style.space(10)
        anchors.left: parent.left
        anchors.right: parent.right
        foreground: root.foreground
      }

      Flickable {
        id: list
        anchors.top: separator.bottom
        anchors.topMargin: Style.space(10)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        contentWidth: width
        contentHeight: cards.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: cards
          width: list.width
          spacing: Style.space(8)

          Repeater {
            model: root.entries

            Loader {
              id: card
              required property var modelData
              width: cards.width
              height: item ? item.implicitHeight : 0

              Component.onCompleted: setSource(root.cardUrl, {
                app: modelData.app || "",
                appIcon: modelData.appIcon || "",
                summary: modelData.summary || "",
                body: modelData.body || "",
                image: modelData.image || "",
                glyph: modelData.glyph || "",
                urgency: isFinite(Number(modelData.urgency)) ? Number(modelData.urgency) : 1,
                timestamp: Number(modelData.timestamp || 0),
                cornerRadius: Style.cornerRadius,
                fontFamily: root.fontFamily
              })

              onLoaded: item.width = Qt.binding(function() { return card.width })

              Connections {
                target: card.item
                ignoreUnknownSignals: true
                function onCloseRequested() { root.dismiss(card.modelData) }
                function onCardClicked() { root.activate(card.modelData) }
              }
            }
          }
        }
      }

      Text {
        id: emptyText
        visible: root.entries.length === 0
        anchors.top: separator.bottom
        anchors.topMargin: Style.space(10)
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: "No notifications"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
