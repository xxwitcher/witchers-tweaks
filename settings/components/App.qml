pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// What every pane shares: the look (from the Omarchy theme and the dock's
// border colors), the machine's current state, and running commands.
Singleton {
  id: root

  // --------------------------------------------------------------- look

  readonly property color fg: Color.foreground
  readonly property color bg: Color.background
  readonly property color subtle: Qt.rgba(fg.r, fg.g, fg.b, 0.6)
  readonly property color faint: Qt.rgba(fg.r, fg.g, fg.b, 0.35)
  readonly property color line: Qt.rgba(fg.r, fg.g, fg.b, 0.1)
  readonly property color sidebar: Qt.rgba(fg.r, fg.g, fg.b, 0.035)
  readonly property color card: Qt.rgba(fg.r, fg.g, fg.b, 0.05)
  readonly property color hover: Qt.rgba(fg.r, fg.g, fg.b, 0.08)
  readonly property color control: Qt.rgba(fg.r, fg.g, fg.b, 0.14)
  readonly property color danger: Color.urgent
  readonly property var borderSpec: Border.surfaceSpec("popups", "border", Color.accent, 1)
  // The tint for switches, sliders and the selected section: the middle of
  // the border gradient (as the dock uses it), else the theme accent.
  readonly property color tint: borderSpec.gradient && borderSpec.gradient.enabled
    ? borderSpec.gradient.colors[Math.floor(borderSpec.gradient.colors.length / 2)] : Color.accent
  readonly property color onTint: (tint.r * 0.299 + tint.g * 0.587 + tint.b * 0.114) > 0.6 ? "#1b1b1f" : "#ffffff"
  readonly property string font: Style.font.menuFamily
  readonly property int body: Style.font.body + 1
  readonly property int small: Style.font.caption + 1
  readonly property int radius: 10

  // --------------------------------------------------------------- paths

  readonly property string home: Quickshell.env("HOME")
  readonly property string helperPath: String(Qt.resolvedUrl("../bin/settings-helper")).replace(/^file:\/\//, "")
  readonly property string repo: Quickshell.env("WITCHER_REPO") || ""

  // --------------------------------------------------------------- commands

  // Runs a command (an argument list) and hands its output and exit code to
  // the callback.
  function run(command, callback) {
    var p = processComponent.createObject(root, { command: command, callback: callback || null })
    p.running = true
  }

  function sh(script, callback) { run(["bash", "-c", script], callback) }
  function helper(args, callback) { run([helperPath].concat(args), callback) }
  function detached(command) { Quickshell.execDetached(command) }
  function shDetached(script) { Quickshell.execDetached(["bash", "-c", script]) }
  // For steps that need a password or show progress: Omarchy's floating
  // terminal, as its menu does.
  function terminal(script) {
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", script])
  }
  function editConfig(path) { Quickshell.execDetached(["omarchy-launch-config-editor", path]) }

  // Runs a command, then refreshes the state it may have changed.
  function apply(command, message) {
    run(command, function(out, code) {
      if (code !== 0 && out.trim() !== "") toast(out.trim().split("\n").pop())
      else if (message) toast(message)
      refresh()
    })
  }

  property Component processComponent: Component {
    Process {
      id: p
      property var callback: null
      property string output: ""
      property int code: -1
      property bool streamDone: false
      property bool exitDone: false
      function finish() {
        if (!streamDone || !exitDone) return
        if (callback) {
          try { callback(output, code) } catch (e) { console.warn("settings: " + e + " in " + JSON.stringify(command).slice(0, 120)) }
        }
        p.destroy()
      }
      stdout: StdioCollector {
        onStreamFinished: { p.output = text; p.streamDone = true; p.finish() }
      }
      onExited: function(exitCode) { p.code = exitCode; p.exitDone = true; p.finish() }
    }
  }

  // --------------------------------------------------------------- messages

  signal toastRequested(string text)
  signal confirmRequested(var options)
  function toast(text) { toastRequested(text) }
  // options: { title, text, action, danger, onAccept }
  function confirm(options) { confirmRequested(options) }

  // --------------------------------------------------------------- state

  // Most on/off states and current choices (settings-helper status).
  property var status: ({})
  // Witcher's Tweaks: { name: { category, description, state, configure } }.
  property var tweaks: ({})
  property var tweakList: []
  // Tweaks being added or removed.
  property var tweakBusy: ({})
  property int busyStamp: 0

  function refresh() {
    helper(["status"], function(out) {
      try { status = JSON.parse(out) } catch (e) {}
    })
  }

  function refreshTweaks() {
    helper(["tweaks"], function(out) {
      try {
        var list = JSON.parse(out)
        var map = ({})
        for (var i = 0; i < list.length; i++) map[list[i].name] = list[i]
        tweakList = list
        tweaks = map
      } catch (e) {}
    })
  }

  function tweakOn(name) { return !!tweaks[name] && tweaks[name].state !== "none" }
  function tweakAvailable(name) { return !!tweaks[name] }
  function tweakPending(name) { return busyStamp >= 0 && tweakBusy[name] === true }

  function setTweak(name, on, done) {
    if (tweakBusy[name]) return
    tweakBusy[name] = true
    busyStamp++
    helper(["tweak", on ? "add" : "remove", name], function(out, code) {
      delete tweakBusy[name]
      busyStamp++
      if (code !== 0) toast("Couldn't " + (on ? "add " : "remove ") + name)
      refreshTweaks()
      refresh()
      if (done) done(code === 0)
    })
  }

  // ~/.config/omarchy/shell.json: the bar, plugins and the dock's settings.
  property var shellConfig: ({})
  readonly property var dock: {
    var plugins = Array.isArray(shellConfig.plugins) ? shellConfig.plugins : []
    for (var i = 0; i < plugins.length; i++) if (plugins[i] && plugins[i].id === "witcher.dock") return plugins[i]
    return null
  }
  function pluginEntry(id) {
    var plugins = Array.isArray(shellConfig.plugins) ? shellConfig.plugins : []
    for (var i = 0; i < plugins.length; i++) if (plugins[i] && plugins[i].id === id) return plugins[i]
    return null
  }

  property FileView shellConfigFile: FileView {
    path: root.home + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.shellConfig = JSON.parse(text()) } catch (e) {}
    }
  }

  // Theme switches change the colors: reload them when the theme changes.
  property FileView themeName: FileView {
    path: root.home + "/.local/state/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onFileChanged: {
      reload()
      Color.colorsFile.reload()
      Color.shellFile.reload()
      root.refresh()
    }
  }

  Component.onCompleted: {
    refresh()
    refreshTweaks()
  }
}
