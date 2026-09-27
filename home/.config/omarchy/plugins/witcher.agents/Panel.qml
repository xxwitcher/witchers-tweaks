import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import QMLTermWidget
import qs.Commons
import qs.Ui

// Witcher's Tweaks take on omarchy.agents: a compact usage header (agent, plan, and
// the session/weekly limits side by side) over a real terminal running
// Omarchy's default agent the same way the agent console does
// (`omarchy-agent --inline`), so every agent and every command works. The
// terminal lives as long as the shell, so closing the popup keeps the
// session. Usage data comes from the stock Main.qml/Agent.qml. Needs the
// qmltermwidget package.
Panel {
  id: root
  moduleName: "witcher.agents"
  ipcTarget: "witcher.agents"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color surface: Color.popups.background
  readonly property color track: Style.selectedFillFor(foreground, Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // ---------------------------------------------------------------- agent
  // The header follows the agent actually running in the terminal: the
  // default agent (omarchy default agent <name>) as it was when the session
  // started. Changing the default doesn't kill a live session; the header
  // switches over on the next Start/Restart.
  readonly property string defaultAgentFile: Quickshell.env("HOME") + "/.config/omarchy/defaults/agent"
  property string defaultAgent: ""
  property string sessionAgent: ""
  readonly property string currentAgent: sessionAgent !== "" ? sessionAgent : defaultAgent

  // Agents whose usage Omarchy collects, keyed by agent id → usage record id.
  readonly property var agentUsageIds: ({ "claude": "claude", "codex": "codex" })
  readonly property var agentNames: ({
    "pi": "Pi", "omp": "Oh My Pi", "opencode": "OpenCode", "ori": "Ori",
    "claude": "Claude Code", "codex": "Codex", "crush": "Crush", "grok": "Grok",
    "agy": "Antigravity", "hermes": "Hermes", "copilot": "GitHub Copilot"
  })

  function agentUsageId(agent) {
    return agentUsageIds[agent] || ""
  }

  function agentName(agent) {
    return agentNames[agent] || (agent === "" ? "Agent" : agent)
  }

  onCurrentAgentChanged: selectedProviderId = agentUsageId(currentAgent)

  FileView {
    path: root.defaultAgentFile
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.defaultAgent = String(text() || "").trim()
    onLoadFailed: root.defaultAgent = ""
  }

  // A session started before the file was read (or while no default was
  // set and --pick asked for one) adopts the first agent that shows up.
  onDefaultAgentChanged: if (agentRunning && sessionAgent === "") sessionAgent = defaultAgent

  readonly property var providers: usage.enabledProviders
  // Follows the current agent; middle-click / `next` can still cycle through
  // the other providers until the agent changes.
  property string selectedProviderId: ""
  readonly property int providerIndex: {
    for (var i = 0; i < providers.length; i++)
      if (providers[i].providerId === selectedProviderId) return i
    return -1
  }
  // No usage for the current agent means no usage shown, rather than
  // falling back to another agent's numbers.
  readonly property var provider: providerIndex >= 0 ? providers[providerIndex] : null

  property double nowMs: Date.now()

  readonly property var limits: limitWindows(provider)
  readonly property var headline: bindingWindow(provider)
  readonly property bool alarming: !!headline && headline.percent >= 0.9

  // ---------------------------------------------------------------- terminal
  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
  property string colorSchemePath: ""
  property bool agentRunning: false

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

  function selectProvider(index) {
    if (providers.length === 0) return
    var wrapped = ((index % providers.length) + providers.length) % providers.length
    selectedProviderId = providers[wrapped].providerId
  }

  function refreshNow() {
    usage.refreshAll(true)
  }

  // Tear the terminal down and start a fresh agent session.
  function restartAgent() {
    terminalLoader.active = false
    terminalLoader.active = true
  }

  // ---------------------------------------------------------------- limits
  // Same normalization as the stock panel: Claude spells its windows out,
  // Codex abbreviates them; both land on one {title, percent, resetAt} record.

  function windowIsLong(text) {
    return text.indexOf("week") >= 0 || text.indexOf("7-day") >= 0 || text.indexOf("seven") >= 0
      || text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0
  }

  function windowSpanMs(label) {
    var text = String(label || "").toLowerCase()
    if (text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0) return 30 * 24 * 3600 * 1000
    if (windowIsLong(text)) return 7 * 24 * 3600 * 1000
    var hours = text.match(/(\d+)\s*-?\s*h(?:our)?\b/)
    if (hours) return Number(hours[1]) * 3600 * 1000
    var minutes = text.match(/(\d+)\s*-?\s*m(?:in(?:ute)?s?)?\b/)
    if (minutes) return Number(minutes[1]) * 60 * 1000
    return 0
  }

  function windowTitle(label) {
    var text = String(label || "").toLowerCase()
    if (text.indexOf("month") >= 0) return "Monthly"
    if (windowIsLong(text)) return "Weekly"
    if (text.indexOf("session") >= 0 || windowSpanMs(label) > 0) return "Session"
    var plain = String(label || "").replace(/\s*\(.*\)\s*/, "").trim()
    return plain === "" ? "Limit" : plain
  }

  function limitWindow(label, percent, resetAt, title) {
    return {
      title: String(title || "") !== "" ? String(title) : windowTitle(label),
      percent: Number(percent),
      resetAt: String(resetAt || "")
    }
  }

  function limitWindows(p) {
    if (!p) return []
    var out = []
    var list = p.limits || []
    for (var i = 0; i < list.length; i++) {
      var entry = list[i] || {}
      var percent = Number(entry.percent)
      if (percent >= 0) out.push(limitWindow(entry.label, percent, entry.resetsAt, entry.title))
    }
    return out
  }

  function bindingWindow(p) {
    var windows = limitWindows(p)
    var best = null
    for (var i = 0; i < windows.length; i++) {
      if (!best || windows[i].percent > best.percent) best = windows[i]
    }
    return best
  }

  function resetMsFor(w) {
    if (!w || w.resetAt === "") return -1
    var ms = new Date(w.resetAt).getTime()
    return isFinite(ms) ? ms - root.nowMs : -1
  }

  function formatDuration(ms) {
    if (!(ms > 0)) return "now"
    var minutes = Math.floor(ms / 60000)
    var hours = Math.floor(minutes / 60)
    var days = Math.floor(hours / 24)
    if (days > 0) return days + "d " + (hours % 24) + "h"
    if (hours > 0) return hours + "h " + (minutes % 60) + "m"
    return Math.max(1, minutes) + "m"
  }

  function planText(p) {
    if (!p) return ""
    if (String(p.usageStatusText || "") !== "") return p.usageStatusText
    var tier = String(p.tierLabel || "")
    return tier === "" ? "" : tier.charAt(0).toUpperCase() + tier.slice(1)
  }

  function iconFor(p) {
    return p ? Qt.resolvedUrl("assets/" + p.providerId + ".svg") : ""
  }

  // The agent works without any usage recorded, so the icon always shows
  // (unlike the stock widget, which hides until then).
  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    nowMs = Date.now()
    usage.refreshLimits()
    colorsProc.running = true
  }

  Main {
    id: usage
    settings: root.settings
  }

  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  // Terminal colors follow the current Omarchy theme.
  Process {
    id: colorsProc
    running: true
    command: [root.pluginDir + "/bin/terminal-colors"]
    stdout: SplitParser { onRead: function(line) { root.colorSchemePath = String(line || "").trim() } }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function restart(): void { root.restartAgent() }
    function refresh(): string { root.refreshNow(); return "ok" }
    function next(): string { root.selectProvider(root.providerIndex + 1); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󱚣"
    active: root.alarming
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) root.selectProvider(root.providerIndex + 1)
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: terminalLoader.item
    contentWidth: panel.fittedContentWidth(Style.space(560))
    // Sized to the screen rather than a fixed height: about two-thirds of it
    // including the header, so the popup never runs to the bottom edge.
    readonly property real fittedHeight: Math.round((panel.screen ? panel.screen.height : 800) * 0.55)
    contentHeight: panel.fittedContentHeight(fittedHeight, fittedHeight)

    // No PanelKeyCatcher: every key, Esc and Tab included, belongs to the
    // agent. Close the panel by clicking the bar icon or outside it.
    Item {
      anchors.fill: parent

      // ---------- Header: mark · agent · plan ············ restart ----------
      Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Math.max(headerName.implicitHeight, restartButton.implicitHeight)

        Image {
          id: headerMark
          visible: !!root.provider && status === Image.Ready
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: visible ? Style.font.title : 0
          height: Style.font.title
          source: root.iconFor(root.provider)
          sourceSize.width: Style.font.title * 2
          sourceSize.height: Style.font.title * 2
          fillMode: Image.PreserveAspectFit
        }

        Text {
          id: headerName
          textFormat: Text.PlainText
          anchors.left: headerMark.right
          anchors.leftMargin: headerMark.visible ? Style.spacing.md : 0
          anchors.right: restartButton.left
          anchors.rightMargin: Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideRight
          text: {
            if (!root.provider) {
              var agent = root.agentName(root.currentAgent)
              return root.currentAgent === "" ? agent : agent + "  ·  Usage not tracked"
            }
            var name = root.provider.providerName
            var plan = root.planText(root.provider)
            return plan === "" ? name : name + "  ·  " + plan
          }
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Button {
          id: restartButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: root.agentRunning ? "Restart" : "Start"
          bordered: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          verticalPadding: Style.space(3)
          onClicked: root.restartAgent()
        }
      }

      // ---------- Limits, side by side ----------
      Row {
        id: limitsRow
        visible: root.limits.length > 0
        anchors.top: header.bottom
        anchors.topMargin: visible ? Style.space(12) : 0
        anchors.left: parent.left
        anchors.right: parent.right
        height: visible ? implicitHeight : 0
        spacing: Style.space(16)

        Repeater {
          model: root.limits

          LimitCell {
            required property var modelData
            width: (limitsRow.width - limitsRow.spacing * (root.limits.length - 1)) / root.limits.length
            window: modelData
          }
        }
      }

      PanelSeparator {
        id: terminalSeparator
        anchors.top: limitsRow.bottom
        anchors.topMargin: Style.space(12)
        anchors.left: parent.left
        anchors.right: parent.right
        foreground: root.foreground
      }

      // ---------- The agent's own terminal interface ----------
      Loader {
        id: terminalLoader
        anchors.top: terminalSeparator.bottom
        anchors.topMargin: Style.space(10)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        active: true
        sourceComponent: terminalComponent
      }

      Text {
        visible: !root.agentRunning
        anchors.centerIn: terminalLoader
        width: terminalLoader.width * 0.8
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: "The agent exited. Press Start to open a new session."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  Component {
    id: terminalComponent

    QMLTermWidget {
      id: terminal
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      colorScheme: "Omarchy"
      blinkingCursor: true
      enableBold: true
      antialiasText: true
      smooth: true

      session: QMLTermSession {
        id: agentSession
        initialWorkingDirectory: Quickshell.env("HOME")
        shellProgram: "omarchy-agent"
        shellProgramArgs: ["--inline", "--pick"]
        onFinished: {
          root.agentRunning = false
          root.sessionAgent = ""
        }
      }

      Component.onCompleted: {
        root.sessionAgent = root.defaultAgent
        agentSession.startShellProgram()
        root.agentRunning = true
      }

      // The terminal renders scrollback itself; the wheel scrolls it.
      QMLTermScrollbar {
        terminal: terminal
        width: Style.space(6)
        Rectangle {
          anchors.fill: parent
          radius: width / 2
          color: root.foreground
          opacity: 0.35
        }
      }
    }
  }

  // A limit window squeezed into half the width: title and percentage on one
  // line, the meter, and the reset countdown under it.
  component LimitCell: Column {
    id: cell
    property var window: null
    readonly property bool alarming: window && window.percent >= 0.9
    spacing: Style.space(5)

    Item {
      width: parent.width
      implicitHeight: Math.max(cellTitle.implicitHeight, cellValue.implicitHeight)

      Text {
        id: cellTitle
        textFormat: Text.PlainText
        text: cell.window ? cell.window.title : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        anchors.left: parent.left
        anchors.right: cellValue.left
        anchors.rightMargin: Style.spacing.sm
      }

      Text {
        id: cellValue
        textFormat: Text.PlainText
        text: cell.window && cell.window.percent >= 0 ? Math.round(cell.window.percent * 100) + "%" : "—"
        color: cell.alarming ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        anchors.right: parent.right
      }
    }

    Meter {
      width: parent.width
      value: cell.window ? cell.window.percent : -1
      alarming: cell.alarming
    }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: {
        var remainingMs = root.resetMsFor(cell.window)
        return remainingMs > 0 ? "Resets in " + root.formatDuration(remainingMs) : ""
      }
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  component Meter: Item {
    id: meter
    property real value: -1
    property bool alarming: false
    implicitHeight: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))

    Rectangle {
      id: meterTrack
      anchors.fill: parent
      radius: height / 2
      color: root.track
    }

    Rectangle {
      anchors.left: meterTrack.left
      anchors.verticalCenter: meterTrack.verticalCenter
      height: meterTrack.height
      radius: meterTrack.radius
      width: meterTrack.width * root.clamp(meter.value, 0, 1)
      color: meter.alarming ? root.urgent : root.foreground
      Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }
  }
}
