import QtQuick
import QtCore
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// A dock like the macOS one, on every screen.
//
// Left to right: the Apps icon (AppsPanel.qml: every app in rows of five
// with a search field; drag one onto the dock to keep it); the apps kept in the Dock (and, without recent apps, the
// other running apps); a divider and the running apps that aren't kept plus
// the last three closed ones (Show suggested and recent apps); a divider,
// minimized windows, Downloads and the Trash. A dot under an app means it's
// running; the focused app's dot is wider and in the border color.
//
// Click an app to open it or go to its window (a minimized one comes back);
// middle click opens a new window. Drag an app to move it; drag a running app
// among the kept ones to keep it; drag a kept app out of the dock or onto the
// Trash to remove it. Right click for its windows, Keep in Dock, Open at
// Login, Show All Windows, Hide and Quit. Downloads opens a list of the newest
// downloads; the Trash opens in Files and can be emptied from its menu.
// SUPER+M (the dock-minimize Hyprland tweak) minimizes the focused window.
//
// Settings live on this plugin's entry in ~/.config/omarchy/shell.json and
// install.sh --configure dock changes them (macOS's Desktop & Dock options):
//
//   { "id": "witcher.dock",
//     "size": 48,             icon size in px
//     "magnification": 0,     icon size under the pointer; 0 is off
//     "position": "bottom",   bottom, left or right
//     "minimize": false,      true: minimize windows into application icon
//     "hide": "auto",         auto: automatically hide and show the Dock;
//                             smart: hide only while a window is under it;
//                             never: always shown, windows tile around it
//     "animate": true,        animate opening applications (bounce)
//     "indicators": true,     show indicators for open applications
//     "recents": true,        show suggested and recent apps in Dock
//     "click": "cycle",       clicking the app you're in: cycle goes to its
//                             next window, focus stays on the last used one
//     "transparency": 0,      dock background transparency, 0-90 %
//     "appsTransparency": 0,  Apps panel background transparency, 0-90 %
//     "roundness": 60,        corner rounding, 0 (sharp) to 100 % (round ends)
//     "border": "windows",    windows (their gradient), custom, solid or none
//     "borderColors": ["#c4b5fd", "#a855f7", "#da70d6"],   for custom (3) and solid (1)
//     "pinned": ["chromium", "org.gnome.Nautilus"] }   desktop entry ids
Item {
  id: root
  visible: false

  property var shell: null
  property var manifest: null

  readonly property string pluginId: "witcher.dock"
  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string tool: pluginDir + "/bin/dock"
  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/witcher"
  readonly property string dataHome: Quickshell.env("XDG_DATA_HOME") || home + "/.local/share"
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || home + "/.config"
  readonly property string downloadsPath: String(StandardPaths.writableLocation(StandardPaths.DownloadLocation)).replace(/^file:\/\//, "")
  readonly property string minimizedName: "special:minimized"

  // --------------------------------------------------------------- settings

  readonly property var entry: {
    var plugins = shell && shell.shellConfig && Array.isArray(shell.shellConfig.plugins) ? shell.shellConfig.plugins : []
    for (var i = 0; i < plugins.length; i++)
      if (plugins[i] && plugins[i].id === pluginId) return plugins[i]
    return ({})
  }
  function choice(key, allowed) { return allowed.indexOf(entry[key]) >= 0 ? entry[key] : allowed[0] }
  function flag(key, fallback) { return typeof entry[key] === "boolean" ? entry[key] : fallback }
  function number(key, fallback, min, max) {
    var n = Number(entry[key])
    return typeof entry[key] === "number" && isFinite(n) ? Math.max(min, Math.min(max, n)) : fallback
  }

  readonly property string position: choice("position", ["bottom", "left", "right"])
  readonly property bool vertical: position !== "bottom"
  readonly property string hideMode: choice("hide", ["auto", "smart", "never"])
  readonly property string clickMode: choice("click", ["cycle", "focus"])
  readonly property bool animate: flag("animate", true)
  readonly property bool indicators: flag("indicators", true)
  readonly property bool recentsOn: flag("recents", true)
  readonly property bool minimizeToApp: flag("minimize", false)
  readonly property var pinned: Array.isArray(entry.pinned)
    ? entry.pinned.filter(function(id) { return typeof id === "string" && id.length > 0 }) : []
  readonly property bool overviewOn: {
    var plugins = shell && shell.shellConfig && Array.isArray(shell.shellConfig.plugins) ? shell.shellConfig.plugins : []
    return plugins.some(function(p) { return p && p.id === "witcher.overview" })
  }

  // --------------------------------------------------------------- look

  readonly property color foreground: Color.menu.text
  readonly property color background: Color.menu.background
  readonly property color accent: Color.accent
  readonly property color quiet: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.25)
  readonly property color hover: Color.menu.selectedBackground
  // The popup border: the theme's active-border gradient, which the border
  // tweak sets to your colors (a flat color on themes without one).
  readonly property var windowBorderSpec: Border.surfaceSpec("popups", "border", accent, Math.max(1, Style.space(2)))

  // The dock's own border ("border" setting): the windows' gradient, a
  // custom gradient ("borderColors": three colors, spread 3:3:2 like
  // Hyprland does), one solid color, or none.
  readonly property string borderMode: choice("border", ["windows", "custom", "solid", "none"])
  readonly property var borderColors: Array.isArray(entry.borderColors)
    ? entry.borderColors.filter(function(c) { return /^#?[0-9a-fA-F]{6}$/.test(String(c)) })
        .map(function(c) { return String(c).charAt(0) === "#" ? String(c) : "#" + c }) : []
  readonly property var borderSpec: {
    var width = Border.withWidth(windowBorderSpec, Math.max(1, Style.space(2))).widths
    if (borderMode === "none") return Border.none()
    if (borderMode === "solid")
      return { color: borderColors.length > 0 ? borderColors[0] : accent, widths: width, gradient: { colors: [], angle: 0, enabled: false } }
    if (borderMode === "custom" && borderColors.length >= 2) {
      var c = borderColors
      var stops = c.length >= 3 ? [c[0], c[0], c[0], c[1], c[1], c[1], c[2], c[2]] : c
      return { color: c[0], widths: width, gradient: { colors: stops, angle: 45, enabled: true } }
    }
    return windowBorderSpec
  }
  // The focused app's dot: the middle of the border's colors.
  readonly property color activeColor: borderSpec.gradient && borderSpec.gradient.enabled
    ? borderSpec.gradient.colors[Math.floor(borderSpec.gradient.colors.length / 2)]
    : borderMode === "solid" ? borderSpec.color : accent

  // Transparency of the dock and of the Apps panel, 0 (solid) to 90 %.
  readonly property real dockAlpha: 1 - number("transparency", 0, 0, 90) / 100
  readonly property real appsAlpha: 1 - number("appsTransparency", 0, 0, 90) / 100
  readonly property color dockBackground: Qt.rgba(background.r, background.g, background.b, background.a * dockAlpha)
  readonly property color appsBackground: Qt.rgba(background.r, background.g, background.b, background.a * appsAlpha)
  // install.sh --configure shows the dock (or the Apps panel) while a
  // setting is being changed, so the change can be seen.
  readonly property string peek: choice("peek", ["", "dock", "apps"])
  readonly property string fontFamily: Style.font.menuFamily

  readonly property int iconSize: Style.space(number("size", 48, 16, 128))
  readonly property int magnifiedSize: Math.max(iconSize, Style.space(number("magnification", 0, 0, 256)))
  readonly property int iconGap: Math.round(iconSize / 6)
  readonly property int padding: Math.round(iconSize / 6)
  readonly property int dotRoom: Style.space(6)
  readonly property int dotSize: Style.space(4)
  readonly property int edgeGap: Style.space(6)
  readonly property int thickness: iconSize + padding * 2 + dotRoom
  readonly property int dividerExtent: Style.space(1) + iconGap
  // Rounded whatever the theme's corner radius, like the macOS dock.
  // "roundness": 0 (sharp corners) to 100 % (fully round ends); 60 by
  // default. Everything the dock draws rounds by the same share.
  readonly property real roundness: number("roundness", 60, 0, 100) / 100
  readonly property int radius: Math.round(thickness / 2 * roundness)
  readonly property int smallRadius: Math.round(Style.space(16) * roundness)
  readonly property int popupWidth: Style.space(280)

  // --------------------------------------------------------------- window model

  // When each window last had focus, so an app's icon goes to the window
  // used last. Bumped on every focus change so the model re-sorts.
  property var lastFocus: ({})
  property int focusStamp: 0

  Connections {
    target: Hyprland
    function onActiveToplevelChanged() {
      var top = Hyprland.activeToplevel
      if (!top) return
      root.lastFocus[String(top.address)] = Date.now()
      root.focusStamp++
    }
  }

  function appIdOf(top) {
    var id = top && top.wayland ? String(top.wayland.appId || "") : ""
    if (id === "" && top && top.lastIpcObject) id = String(top.lastIpcObject.class || "")
    return id
  }

  function isMinimized(top) {
    return !!(top && top.workspace && top.workspace.name === minimizedName)
  }

  // The launcher of a window's app: by id, by StartupWMClass, a browser web
  // app (class chrome-<host>__-Default) by its URL, then Quickshell's guess
  // when it plausibly names the same app.
  function desktopFor(id, entries) {
    if (!id) return null
    var d = DesktopEntries.byId(id)
    if (d) return d
    var lower = id.toLowerCase()
    var web = lower.match(/^(?:chrome|chromium|google-chrome|brave|msedge|vivaldi)-(.+?)__/)
    var host = web ? web[1].split("_")[0] : ""
    var byUrl = null
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      if (e.startupClass && String(e.startupClass).toLowerCase() === lower) return e
      if (host && !byUrl && String(e.execString || "").indexOf(host) >= 0) byUrl = e
    }
    if (byUrl) return byUrl
    var guess = DesktopEntries.heuristicLookup(id)
    if (!guess) return null
    var last = lower.split(".").pop()
    var gid = String(guess.id).toLowerCase()
    return gid === lower || gid.split(".").pop() === last ? guess : null
  }

  function iconFor(desktop, id) {
    var names = []
    if (desktop && desktop.icon) names.push(desktop.icon)
    if (id) names.push(id, id.toLowerCase())
    if (desktop && desktop.command && desktop.command.length > 0) names.push(String(desktop.command[0]).split("/").pop())
    names.push("application-x-executable")
    for (var i = 0; i < names.length; i++) {
      var path = Quickshell.iconPath(names[i], true)
      if (path !== "") return path
    }
    return ""
  }

  function recency(top) {
    var stamp = lastFocus[String(top.address)]
    if (stamp) return stamp
    // Windows not focused since the shell started fall back to Hyprland's
    // own order (0 is the most recent).
    var history = top.lastIpcObject ? Number(top.lastIpcObject.focusHistoryID) : NaN
    return isFinite(history) ? -history - 1 : -1e9
  }

  // Everything in the dock, in order:
  //   { key, kind: "app", app }          app: { id, desktop, appId, name, icon,
  //                                      pinned, recent, windows, byRecency, active }
  //   { key, kind: "divider" }
  //   { key, kind: "minimized", window, app }
  //   { key, kind: "downloads" } / { key, kind: "trash" }
  // plus keptCount (how many apps lead the list as kept ones) and runningIds.
  readonly property var model: {
    var stamp = focusStamp // re-sort on focus changes
    var entries = DesktopEntries.applications ? DesktopEntries.applications.values : []
    var tops = Hyprland.toplevels ? Hyprland.toplevels.values : []
    var active = Hyprland.activeToplevel
    var byId = ({})
    var lookups = ({})
    var kept = [], running = [], recent = [], minimized = []

    function make(id, desktop, appId) {
      return {
        id: id, desktop: desktop, appId: appId,
        name: desktop && desktop.name ? String(desktop.name) : appId,
        icon: iconFor(desktop, appId),
        pinned: false, recent: false, windows: [], byRecency: [], active: false
      }
    }

    for (var p = 0; p < pinned.length; p++) {
      if (byId[pinned[p]]) continue
      var desktop = DesktopEntries.byId(pinned[p])
      if (!desktop) continue // uninstalled, or a launcher still being written
      var app = make(desktop.id, desktop, pinned[p])
      app.pinned = true
      byId[desktop.id] = app
      kept.push(app)
    }

    for (var t = 0; t < tops.length; t++) {
      var top = tops[t]
      if (!top || !top.workspace) continue
      var mini = isMinimized(top)
      if (top.workspace.id < 0 && !mini) continue // the scratchpad stays out
      var appId = appIdOf(top)
      if (appId === "") continue
      if (lookups[appId] === undefined) lookups[appId] = desktopFor(appId, entries)
      var d = lookups[appId]
      var id = d ? d.id : appId
      var owner = byId[id]
      if (!owner) {
        owner = make(id, d, appId)
        byId[id] = owner
        running.push(owner)
      }
      owner.windows.push(top)
      if (top === active) owner.active = true
      if (mini && !minimizeToApp) minimized.push({ key: "min:" + top.address, kind: "minimized", window: top, app: owner })
    }

    if (recentsOn) {
      for (var r = 0; r < recentIds.length && recent.length < 3; r++) {
        if (byId[recentIds[r]]) continue
        var rd = DesktopEntries.byId(recentIds[r])
        if (!rd) continue
        var ra = make(rd.id, rd, recentIds[r])
        ra.recent = true
        byId[rd.id] = ra
        recent.push(ra)
      }
    }

    var all = kept.concat(running, recent)
    for (var a = 0; a < all.length; a++)
      all[a].byRecency = all[a].windows.slice().sort(function(x, y) { return recency(y) - recency(x) })

    function items(list) {
      return list.map(function(app) { return { key: "app:" + app.id, kind: "app", app: app } })
    }
    // The Apps icon leads, like on macOS.
    var list = [{ key: "apps", kind: "apps" }].concat(items(recentsOn ? kept : kept.concat(running)))
    var second = recentsOn ? items(running.concat(recent)) : []
    if (second.length > 0) {
      if (list.length > 0) list.push({ key: "div:apps", kind: "divider" })
      list = list.concat(second)
    }
    list.push({ key: "div:stacks", kind: "divider" })
    list = list.concat(minimized, [{ key: "downloads", kind: "downloads" }, { key: "trash", kind: "trash" }])
    return {
      items: list,
      keptCount: kept.length,
      runningIds: kept.concat(running).filter(function(x) { return x.windows.length > 0 }).map(function(x) { return x.id })
    }
  }

  // The dock's model is just the keys, so an icon keeps its delegate (and
  // its hover and bounce) while windows and focus change.
  readonly property var itemKeys: model.items.map(function(item) { return item.key })
  readonly property var itemsByKey: {
    var map = ({})
    for (var i = 0; i < model.items.length; i++) map[model.items[i].key] = model.items[i]
    return map
  }

  // --------------------------------------------------------------- recent apps

  // Apps that were running and got closed, newest first (kept ones left out),
  // saved in ~/.local/state/witcher/dock-recent.json.
  property var recentIds: []
  property var previousRunning: []

  FileView {
    id: recentFile
    path: root.stateDir + "/dock-recent.json"
    printErrors: false
    onLoaded: {
      try {
        var list = JSON.parse(text())
        root.recentIds = Array.isArray(list) ? list.filter(function(id) { return typeof id === "string" }) : []
      } catch (e) {
        root.recentIds = []
      }
    }
  }

  Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", root.stateDir])

  function noteRecent(ids) {
    var next = ids.concat(recentIds.filter(function(id) { return ids.indexOf(id) < 0 }))
      .filter(function(id) { return root.pinned.indexOf(id) < 0 }).slice(0, 10)
    if (JSON.stringify(next) === JSON.stringify(recentIds)) return
    recentIds = next
    recentFile.setText(JSON.stringify(next) + "\n")
  }

  readonly property var runningIds: model.runningIds
  onRunningIdsChanged: {
    var now = runningIds
    var closed = previousRunning.filter(function(id) {
      return now.indexOf(id) < 0 && DesktopEntries.byId(id) !== null
    })
    previousRunning = now.slice()
    if (closed.length > 0) noteRecent(closed)
  }

  // --------------------------------------------------------------- folders

  FolderListModel {
    id: downloadsModel
    folder: "file://" + root.downloadsPath
    sortField: FolderListModel.Time
    showDirs: true
    showDirsFirst: false
    showDotAndDotDot: false
    showHidden: false
  }

  FolderListModel {
    id: trashModel
    folder: "file://" + root.dataHome + "/Trash/files"
    showDirs: true
    showDotAndDotDot: false
    showHidden: true
  }
  readonly property bool trashFull: trashModel.count > 0

  FolderListModel {
    id: autostartModel
    folder: "file://" + root.configHome + "/autostart"
    nameFilters: ["*.desktop"]
    showDirs: false
  }

  function opensAtLogin(id) {
    var n = autostartModel.count
    for (var i = 0; i < n; i++)
      if (autostartModel.get(i, "fileName") === id + ".desktop") return true
    return false
  }

  function firstIcon(names) {
    for (var i = 0; i < names.length; i++) {
      var path = Quickshell.iconPath(names[i], true)
      if (path !== "") return path
    }
    return ""
  }

  function fileIcon(name, isDir) {
    var ext = String(name).toLowerCase().split(".").pop()
    var names = isDir ? ["folder"]
      : /^(png|jpe?g|gif|webp|svg|bmp|heic|avif)$/.test(ext) ? ["image-x-generic"]
      : /^(mp4|mkv|webm|mov|avi)$/.test(ext) ? ["video-x-generic"]
      : /^(mp3|flac|ogg|wav|m4a|opus)$/.test(ext) ? ["audio-x-generic"]
      : ext === "pdf" ? ["application-pdf"]
      : /^(zip|tar|gz|xz|zst|bz2|7z|rar|deb|rpm)$/.test(ext) ? ["package-x-generic", "application-x-archive"]
      : []
    return firstIcon(names.concat(["text-x-generic"]))
  }

  function stackIcon(kind) {
    if (kind === "trash") return firstIcon(trashFull ? ["user-trash-full", "user-trash"] : ["user-trash"])
    return firstIcon(["folder-download", "folder-downloads", "folder"])
  }

  // --------------------------------------------------------------- actions

  function hexAddress(value) {
    var text = String(value || "").replace(/^0x/, "")
    return text === "" ? "" : "0x" + text
  }

  function focusWindow(top) {
    if (top) Quickshell.execDetached([tool, "focus", hexAddress(top.address)])
  }

  function minimizeWindows(tops) {
    var args = [tool, "minimize"]
    for (var i = 0; i < tops.length; i++) if (!isMinimized(tops[i])) args.push(hexAddress(tops[i].address))
    if (args.length > 2) Quickshell.execDetached(args)
  }

  function closeWindows(tops) {
    for (var i = 0; i < tops.length; i++)
      Quickshell.execDetached(["hyprctl", "dispatch",
        "hl.dsp.window.close({ window = \"address:" + hexAddress(tops[i].address) + "\" })"])
  }

  function openPath(path) {
    Quickshell.execDetached(["xdg-open", path])
  }

  // Apps that are opening, by id: they bounce until a new window shows up
  // (10 seconds at most).
  property var launching: ({})
  property int launchStamp: 0

  function launch(app) {
    if (app && app.desktop) launchEntry(app.desktop)
  }

  // Starts an app the way Omarchy's launcher does (shell.appLibrary), and
  // bounces its icon.
  function launchEntry(entry) {
    var library = shell && shell.appLibrary ? shell.appLibrary : null
    if (library && typeof library.launch === "function") library.launch(entry.id, String(entry.name))
    else Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", entry.id])
    if (animate) {
      var item = itemsByKey["app:" + entry.id]
      launching[entry.id] = { at: Date.now(), windows: item ? item.app.windows.length : 0 }
      launchStamp++
    }
  }

  Timer {
    interval: 300
    repeat: true
    running: root.launchStamp >= 0 && Object.keys(root.launching).length > 0
    onTriggered: {
      var changed = false
      for (var id in root.launching) {
        var item = root.itemsByKey["app:" + id]
        var started = root.launching[id]
        if (!item || item.app.windows.length > started.windows || Date.now() - started.at > 10000) {
          delete root.launching[id]
          changed = true
        }
      }
      if (changed) root.launchStamp++
    }
  }

  function activate(app) {
    if (!app) return
    if (app.windows.length === 0) {
      launch(app)
      return
    }
    if (clickMode === "cycle" && app.active && app.windows.length > 1) {
      // Hyprland's window list order is stable, so this walks every window.
      var visible = app.windows.filter(function(w) { return !isMinimized(w) })
      var list = visible.length > 1 ? visible : app.windows
      var at = list.indexOf(Hyprland.activeToplevel)
      focusWindow(list[(at + 1) % list.length])
    } else {
      focusWindow(app.byRecency[0])
    }
  }

  function writePinned(list) {
    if (!shell || typeof shell.mutateShellConfig !== "function") return
    shell.mutateShellConfig(function(config) {
      if (!Array.isArray(config.plugins)) config.plugins = []
      for (var i = 0; i < config.plugins.length; i++)
        if (config.plugins[i] && config.plugins[i].id === root.pluginId) config.plugins[i].pinned = list
    })
  }

  // The id an app is kept under: its launcher, or one written for it from
  // its window's command line when it has none (bin/dock pin-custom).
  function keepId(app) {
    if (app.desktop) return app.desktop.id
    var top = app.windows.length > 0 ? app.windows[0] : null
    var pid = top && top.lastIpcObject ? Number(top.lastIpcObject.pid) : 0
    if (!pid) return ""
    var name = app.appId.split(".").pop()
    name = name.charAt(0).toUpperCase() + name.slice(1)
    Quickshell.execDetached([tool, "pin-custom", app.appId, String(pid), name])
    return "witcher-dock-" + app.appId.replace(/[^A-Za-z0-9._-]/g, "-").replace(/-+$/, "")
  }

  // Keeps an app at a place among the kept ones (-1: at the end), or moves
  // it there when it's kept already.
  function keep(app, index) {
    keepAt(keepId(app), index)
  }

  function keepEntry(entry, index) {
    keepAt(entry.id, index)
  }

  function unkeepId(id) {
    writePinned(pinned.filter(function(p) { return p !== id }))
  }

  function keepAt(id, index) {
    if (id === "") return
    var list = pinned.filter(function(p) { return p !== id && DesktopEntries.byId(p) !== null })
    if (index < 0 || index > list.length) index = list.length
    list.splice(index, 0, id)
    writePinned(list)
    if (recentIds.indexOf(id) >= 0) {
      recentIds = recentIds.filter(function(r) { return r !== id })
      recentFile.setText(JSON.stringify(recentIds) + "\n")
    }
  }

  function unkeep(app) {
    writePinned(pinned.filter(function(p) { return p !== app.id }))
    if (app.id.indexOf("witcher-dock-") === 0 && app.windows.length === 0) {
      Quickshell.execDetached([tool, "autostart", "off", app.id])
      Quickshell.execDetached([tool, "unpin-custom", app.id])
    }
  }

  function setOpenAtLogin(app, on) {
    if (app.desktop) Quickshell.execDetached([tool, "autostart", on ? "on" : "off", app.desktop.id])
  }

  // --------------------------------------------------------------- windows

  // Keeps Hyprland's window positions fresh for the smart hide.
  Connections {
    target: Hyprland
    enabled: root.hideMode === "smart"
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      if (/^(openwindow|closewindow|movewindow|movewindowv2|changefloatingmode|fullscreen|workspace|workspacev2|activewindow|activewindowv2)$/.test(name))
        refreshTimer.restart()
    }
  }

  Timer {
    id: refreshTimer
    interval: 60
    onTriggered: Hyprland.refreshToplevels()
  }

  // Floating windows dragged or resized send no event; catch those too.
  Timer {
    interval: 1000
    repeat: true
    running: root.hideMode === "smart"
    onTriggered: Hyprland.refreshToplevels()
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: dockWindow
      required property var modelData
      screen: modelData

      readonly property var monitor: Hyprland.monitorFor(modelData)
      readonly property var workspace: monitor ? monitor.activeWorkspace : null
      readonly property bool fullscreen: workspace ? workspace.hasFullscreen : false

      // Length of the screen edge the dock sits on.
      readonly property real mainLength: root.vertical ? height : width

      // ---------- geometry ----------

      // A rectangle from dock coordinates: main runs along the edge, cross
      // away from it (0 is the screen edge).
      function place(main, cross, mainSize, crossSize) {
        if (root.position === "left") return { x: cross, y: main, width: crossSize, height: mainSize }
        if (root.position === "right") return { x: width - cross - crossSize, y: main, width: crossSize, height: mainSize }
        return { x: main, y: height - cross - crossSize, width: mainSize, height: crossSize }
      }

      // Dock coordinates of a point in the window.
      function toDock(p) {
        if (root.position === "left") return { main: p.y, cross: p.x }
        if (root.position === "right") return { main: p.y, cross: width - p.x }
        return { main: p.x, cross: height - p.y }
      }

      property real hideOffset: revealed ? 0 : -(root.thickness + root.edgeGap + Style.space(10))
      Behavior on hideOffset { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
      readonly property real bodyCross: root.edgeGap + hideOffset
      readonly property real iconCross: bodyCross + root.padding + root.dotRoom

      // ---------- pointer and drag ----------

      // Where the pointer is (point.position updates in place, so bind to it).
      readonly property var hoverPoint: toDock(stageHover.point.position)
      readonly property real hoverMain: hoverPoint.main
      readonly property real hoverCross: hoverPoint.cross
      // Over the dock itself (not an open popup or the room beyond it).
      // (The window only takes the pointer over the dock and an open popup.)
      readonly property bool hovering: stageHover.hovered && hoverCross <= root.edgeGap + root.thickness
      property bool held: false

      property string dragKey: ""
      // An app dragged in from the Apps panel that isn't in the dock yet.
      property var dragNewItem: null
      property bool dragFromApps: false
      property real dragMain: 0
      property real dragCross: 0
      readonly property bool dragging: dragKey !== "" || dragNewItem !== null
      readonly property var dragItem: dragKey !== "" ? root.itemsByKey[dragKey] || null : dragNewItem

      // The Apps panel (the Apps icon opens it).
      property bool appsOpen: false
      onAppsOpenChanged: {
        if (!appsOpen) return
        popup = null
        appsPanel.reset()
      }

      // The app waiting for "Remove?" to be answered (dropped on the Trash,
      // or Remove… in the Apps panel).
      property var confirmEntry: null
      onConfirmEntryChanged: if (confirmEntry) Qt.callLater(function() { confirmCard.forceActiveFocus() })

      function askRemove(entry) {
        if (!entry) return
        popup = null
        appsOpen = false
        confirmEntry = entry
      }

      function confirmRemove() {
        var e = confirmEntry
        confirmEntry = null
        if (!e) return
        root.unkeepId(e.id)
        var library = root.shell && root.shell.appLibrary ? root.shell.appLibrary : null
        if (library && typeof library.remove === "function") library.remove(e.id, String(e.name))
      }

      // The Apps panel and the Remove dialog take the keyboard.
      readonly property bool modal: appsOpen || confirmEntry !== null
      // The outside-click grab starts a moment after they open: taking the
      // keyboard re-commits the layer surface, and a grab started in the same
      // moment is cleared straight away (closing them again).
      property bool modalGrab: false
      Timer {
        id: modalGrabDelay
        interval: 80
        onTriggered: dockWindow.modalGrab = dockWindow.modal
      }
      onModalChanged: {
        modalGrab = false
        if (modal) modalGrabDelay.restart()
      }
      readonly property bool overTrash: {
        if (!dragging || !trashSpan) return false
        return dragCross < root.edgeGap + root.thickness && dragMain >= trashSpan.start && dragMain <= trashSpan.start + trashSpan.size
      }
      property var trashSpan: null
      // What dropping now would do, shown above the dragged icon.
      readonly property string dragHint: !dragItem ? ""
        : overTrash && dragItem.app.desktop ? "Uninstall"
        : removing ? "Remove from Dock" : ""
      // A kept app dragged well away from the dock (or onto the Trash) goes.
      readonly property bool removing: dragItem !== null && dragItem.app.pinned
        && (overTrash || dragCross > root.edgeGap + root.thickness + Style.space(48))

      // The layout along the main axis, in window coordinates:
      //   { slots: { key: { start, size } }, bodyStart, bodyEnd, hoverKey, keepIndex }
      // Magnification swells icons near the pointer (cosine falloff over three
      // icons), growing the dock evenly from its center. While dragging, the others make room where it would land.
      readonly property var layout: {
        var items = root.model.items
        var base = root.iconSize
        var gap = root.iconGap
        var order = items.slice()
        var keepIndex = -1
        function extentOf(item) { return item.kind === "divider" ? root.dividerExtent : base }

        if (dragging && dragItem) {
          var from = order.indexOf(dragItem)
          if (from >= 0) order.splice(from, 1)
          var keptLeft = root.model.keptCount - (dragItem.app.pinned ? 1 : 0)
          // Where it would drop among the kept apps, from the layout without it.
          // The kept apps come right after the Apps icon (when it's there).
          var lead = order.length > 0 && order[0].kind === "apps" ? 1 : 0
          var total0 = 0
          for (var i0 = 0; i0 < order.length; i0++) total0 += extentOf(order[i0]) + (i0 > 0 ? gap : 0)
          var at0 = (mainLength - total0) / 2
          for (var l = 0; l < lead; l++) at0 += extentOf(order[l]) + gap
          var index = 0
          for (var k = 0; k < keptLeft; k++) {
            if (dragMain > at0 + base / 2) index = k + 1
            at0 += base + gap
          }
          // at0 is now where the kept apps end.
          var inKept = dragMain < at0 + base / 2
          if (removing) {
            // Leaves no gap: the others close up.
          } else if (dragItem.app.pinned || inKept) {
            keepIndex = index
            order.splice(lead + index, 0, dragItem)
          } else if (from >= 0) {
            order.splice(from, 0, dragItem) // not kept: back where it was
          }
        }

        var extents = order.map(extentOf)
        var baseTotal = 0
        for (var e = 0; e < extents.length; e++) baseTotal += extents[e] + (e > 0 ? gap : 0)
        var baseStart = (mainLength - baseTotal) / 2

        var pointer = dragging ? dragMain : (hovering ? hoverMain : -1)
        var magnify = root.magnifiedSize > base && pointer >= 0
        var range = base * 3
        var sizes = []
        var total = 0
        var cursor = baseStart
        for (var s = 0; s < order.length; s++) {
          var size = extents[s]
          if (magnify && order[s].kind !== "divider" && !(dragging && order[s] === dragItem)) {
            var d = Math.abs(pointer - (cursor + extents[s] / 2))
            if (d < range) size = base + (root.magnifiedSize - base) * (Math.cos(Math.PI * d / range) + 1) / 2
          }
          sizes.push(size)
          total += size + (s > 0 ? gap : 0)
          cursor += extents[s] + gap
        }

        // The dock stays centered: magnification grows it evenly from the
        // middle, so its ends barely move while the pointer runs along it.
        var slots = ({})
        var at = (mainLength - total) / 2
        var hoverKey = ""
        for (var n = 0; n < order.length; n++) {
          slots[order[n].key] = { start: at, size: sizes[n] }
          if (!dragging && hovering && order[n].kind !== "divider" && hoverMain >= at && hoverMain <= at + sizes[n])
            hoverKey = order[n].key
          at += sizes[n] + gap
        }
        var first = order.length > 0 ? slots[order[0].key].start : mainLength / 2
        return {
          slots: slots,
          bodyStart: first - root.padding,
          bodyEnd: (order.length > 0 ? at - gap : first) + root.padding,
          hoverKey: hoverKey,
          keepIndex: keepIndex
        }
      }

      function startDrag(key, p) {
        var d = toDock(p)
        popup = null
        hideTimer.stop()
        held = true
        trashSpan = layout.slots["trash"] || null
        dragMain = d.main
        dragCross = d.cross
        dragKey = key
      }

      // Dragging an app out of the Apps panel: the dock makes room for it and
      // keeps it where it's dropped. An app already in the dock just moves.
      function startEntryDrag(entry, p) {
        var d = toDock(p)
        hideTimer.stop()
        held = true
        trashSpan = layout.slots["trash"] || null
        dragMain = d.main
        dragCross = d.cross
        dragFromApps = true
        var key = "app:" + entry.id
        if (root.itemsByKey[key]) {
          dragKey = key
          return
        }
        dragNewItem = { key: "new:" + entry.id, kind: "app", app: {
          id: entry.id, desktop: entry, appId: entry.id, name: String(entry.name),
          icon: root.iconFor(entry, entry.id), pinned: false, recent: false,
          windows: [], byRecency: [], active: false
        } }
      }

      function cancelDrag() {
        dragKey = ""
        dragNewItem = null
        dragFromApps = false
      }

      function moveDrag(p) {
        var d = toDock(p)
        dragMain = d.main
        dragCross = d.cross
      }

      function finishDrag() {
        held = true
        if (!pointerInside) hideTimer.restart()
        var item = dragItem
        var remove = removing
        var trash = overTrash
        var index = layout.keepIndex
        var fromApps = dragFromApps
        dragKey = ""
        dragNewItem = null
        dragFromApps = false
        if (fromApps) appsOpen = false
        if (!item) return
        // On the Trash: uninstall (after asking); an app without a launcher
        // can only leave the dock.
        if (trash && item.app.desktop) askRemove(item.app.desktop)
        else if (remove) root.unkeep(item.app)
        else if (index >= 0) root.keep(item.app, index)
      }

      // ---------- popups ----------

      // null, or { kind: "app" | "minimized" | "downloads" | "trash", key, main }
      property var popup: null
      readonly property bool popupOpen: popup !== null

      function togglePopup(kind, key, main) {
        if (popup && popup.key === key && popup.kind === kind) popup = null
        else popup = { kind: kind, key: key, main: main }
      }

      // ---------- showing and hiding ----------

      readonly property bool pointerInside: stageHover.hovered || edgeHover.hovered

      // Whether some window on this screen's workspace would sit under the
      // dock (smart hide).
      readonly property bool covered: {
        if (root.hideMode !== "smart" || !monitor || !workspace) return false
        var tops = Hyprland.toplevels ? Hyprland.toplevels.values : []
        var r = place(layout.bodyStart, 0, layout.bodyEnd - layout.bodyStart, root.edgeGap + root.thickness)
        var origin = root.position === "bottom" ? { x: 0, y: modelData.height - height }
          : root.position === "right" ? { x: modelData.width - width, y: 0 } : { x: 0, y: 0 }
        var left = monitor.x + origin.x + r.x, top = monitor.y + origin.y + r.y
        var right = left + r.width, bottom = top + r.height
        for (var i = 0; i < tops.length; i++) {
          var w = tops[i]
          if (!w || w.workspace !== workspace || !w.lastIpcObject) continue
          var at = w.lastIpcObject.at, size = w.lastIpcObject.size
          if (!at || !size) continue
          if (at[0] < right && at[0] + size[0] > left && at[1] < bottom && at[1] + size[1] > top) return true
        }
        return false
      }

      readonly property bool revealed: {
        if (popupOpen || modal || held || dragging || root.peek !== "") return true
        if (root.hideMode === "never") return true
        if (fullscreen) return false
        if (root.hideMode === "smart") return !covered
        return false
      }

      // A short grace period so the dock doesn't flicker away when the
      // pointer slips off it for a moment.
      // A drag holds it too: the drag's grab can hide the hover, and the dock
      // mustn't slip away the moment the icon is dropped.
      onPointerInsideChanged: {
        if (pointerInside || dragging) {
          hideTimer.stop()
          held = true
        } else {
          hideTimer.restart()
        }
      }

      Timer {
        id: hideTimer
        interval: 450
        onTriggered: dockWindow.held = false
      }

      // ---------- the window ----------

      // Room beyond the dock for magnified icons, labels, popups and drags.
      // Constant: resizing the window mid-drag or on a popup makes the whole
      // dock jump for a frame. The mask keeps the empty room click-through.
      // The whole screen across, so the Apps panel can sit centered between
      // the dock and the far edge.
      readonly property real crossExtent: root.vertical ? modelData.width : modelData.height

      anchors {
        bottom: true
        top: root.vertical
        left: root.position !== "right"
        right: root.position !== "left"
      }
      implicitHeight: root.vertical ? 0 : crossExtent
      implicitWidth: root.vertical ? crossExtent : 0
      color: "transparent"
      exclusionMode: root.hideMode === "never" ? ExclusionMode.Normal : ExclusionMode.Ignore
      exclusiveZone: root.hideMode === "never" ? root.thickness + root.edgeGap : 0
      WlrLayershell.namespace: "witcher-dock"
      WlrLayershell.layer: WlrLayer.Top
      // The Apps panel's search takes the keyboard while it's open.
      WlrLayershell.keyboardFocus: modal ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

      // Only the dock itself (and an open popup), or the screen edge while
      // it's hidden, takes the pointer; the rest of this window lets clicks
      // through.
      mask: Region { item: dockWindow.revealed ? hitBox : edge }

      // Everything the dock draws. Its hover handler sees the pointer over the
      // icons too (theirs would hide it from a sibling's).
      Item {
        id: stage
        anchors.fill: parent

        HoverHandler { id: stageHover }

        Item {
          id: hitBox
          readonly property var bodyRect: dockWindow.place(dockWindow.layout.bodyStart, 0,
            dockWindow.layout.bodyEnd - dockWindow.layout.bodyStart, Math.max(0, dockWindow.bodyCross) + root.thickness)
          readonly property var rect: {
            var r = bodyRect
            function union(a, b) {
              var x = Math.min(a.x, b.x), y = Math.min(a.y, b.y)
              return { x: x, y: y,
                width: Math.max(a.x + a.width, b.x + b.width) - x,
                height: Math.max(a.y + a.height, b.y + b.height) - y }
            }
            if (dockWindow.popupOpen) r = union(r, { x: popupCard.x, y: popupCard.y, width: popupCard.width, height: popupCard.height })
            if (dockWindow.appsOpen) r = union(r, { x: appsPanel.x, y: appsPanel.y, width: appsPanel.width, height: appsPanel.height })
            if (dockWindow.confirmEntry) r = union(r, { x: confirmCard.x, y: confirmCard.y, width: confirmCard.width, height: confirmCard.height })
            return r
          }
          x: rect.x
          y: rect.y
          width: rect.width
          height: rect.height
        }

        Item {
          id: edge
          readonly property var rect: dockWindow.place(0, 0, dockWindow.mainLength, 1)
          x: rect.x
          y: rect.y
          width: rect.width
          height: rect.height
          HoverHandler { id: edgeHover }
        }

        HyprlandFocusGrab {
          windows: [dockWindow]
          active: dockWindow.popupOpen || dockWindow.modalGrab
          onCleared: {
            dockWindow.popup = null
            dockWindow.confirmEntry = null
            if (!dockWindow.dragging) dockWindow.appsOpen = false
          }
        }

        // ---------- the dock ----------

        BorderSurface {
          id: body
          readonly property var rect: dockWindow.place(dockWindow.layout.bodyStart, dockWindow.bodyCross,
            dockWindow.layout.bodyEnd - dockWindow.layout.bodyStart, root.thickness)
          x: rect.x
          y: rect.y
          width: rect.width
          height: rect.height
          radius: root.radius
          color: root.dockBackground
          borderSpec: root.borderSpec
        }

        Repeater {
          model: ScriptModel { values: root.itemKeys }

          Item {
            id: slot
            required property var modelData
            readonly property var item: root.itemsByKey[modelData] || null
            readonly property string kind: item ? item.kind : "divider"
            readonly property var app: item && item.app ? item.app : null
            readonly property var slotLayout: dockWindow.layout.slots[modelData] || { start: 0, size: root.iconSize }
            readonly property bool dragged: dockWindow.dragKey === modelData
            readonly property bool hovered: dockWindow.layout.hoverKey === modelData
            readonly property bool isLaunching: root.launchStamp >= 0 && kind === "app" && app !== null
              && root.launching[app.id] !== undefined
            readonly property real size: dragged ? root.iconSize : slotLayout.size
            property real bounce: 0

            readonly property real mainPos: dragged ? dockWindow.dragMain - size / 2 : slotLayout.start
            readonly property real crossPos: dragged ? dockWindow.dragCross - size / 2
              : kind === "divider" ? dockWindow.bodyCross + root.padding
              : dockWindow.iconCross + bounce
            readonly property real crossSize: kind === "divider" ? root.thickness - root.padding * 2 : size
            readonly property var rect: dockWindow.place(mainPos, crossPos, size, crossSize)

            x: rect.x
            y: rect.y
            width: rect.width
            height: rect.height
            z: dragged ? 10 : 1
            opacity: dragged && dockWindow.removing ? 0.6 : 1

            // Neighbors glide aside while something is dragged.
            Behavior on x { enabled: dockWindow.dragging && !slot.dragged; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on y { enabled: dockWindow.dragging && !slot.dragged; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            SequentialAnimation on bounce {
              running: slot.isLaunching
              loops: Animation.Infinite
              alwaysRunToEnd: true
              NumberAnimation { to: root.iconSize * 0.45; duration: 260; easing.type: Easing.OutQuad }
              NumberAnimation { to: 0; duration: 300; easing.type: Easing.OutBounce }
              PauseAnimation { duration: 80 }
            }

            Rectangle {
              visible: slot.kind === "divider"
              anchors.centerIn: parent
              width: root.vertical ? parent.width : Math.max(1, Style.space(1))
              height: root.vertical ? Math.max(1, Style.space(1)) : parent.height
              color: root.quiet
            }

            Image {
              visible: slot.kind === "app" || slot.kind === "downloads" || slot.kind === "trash"
              anchors.fill: parent
              sourceSize.width: root.magnifiedSize * 2
              sourceSize.height: root.magnifiedSize * 2
              fillMode: Image.PreserveAspectFit
              smooth: true
              mipmap: true
              // The Trash opens up while an app is held over it.
              scale: slot.kind === "trash" && dockWindow.overTrash ? 1.25 : 1
              transformOrigin: root.position === "left" ? Item.Left : root.position === "right" ? Item.Right : Item.Bottom
              Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
              source: slot.kind === "app" && slot.app ? slot.app.icon
                : slot.kind === "downloads" || slot.kind === "trash" ? root.stackIcon(slot.kind) : ""
            }

            // The Apps icon: a tile with a 3 x 3 grid in the border's colors.
          Rectangle {
            visible: slot.kind === "apps"
            anchors.fill: parent
            anchors.margins: parent.width * 0.06
            radius: width * 0.4 * root.roundness
            color: Qt.lighter(root.background, 1.6)
            border.width: Math.max(1, Style.space(1))
            border.color: root.quiet

            Grid {
              anchors.centerIn: parent
              columns: 3
              spacing: parent.width * 0.08
              Repeater {
                model: 9
                Rectangle {
                  required property int index
                  readonly property var colors: root.borderSpec.gradient && root.borderSpec.gradient.enabled
                    ? root.borderSpec.gradient.colors : [root.accent]
                  width: parent.parent.width * 0.18
                  height: width
                  radius: width * 0.3
                  color: colors[Math.floor((index % 3 + Math.floor(index / 3)) / 4 * (colors.length - 1))]
                }
              }
            }
          }

          // A minimized window: its picture, with its app's icon in the corner.
            Item {
              visible: slot.kind === "minimized"
              anchors.fill: parent

              ScreencopyView {
                anchors.centerIn: parent
                readonly property real aspect: sourceSize.width > 0 && sourceSize.height > 0 ? sourceSize.width / sourceSize.height : 1.6
                width: aspect >= 1 ? parent.width : parent.height * aspect
                height: aspect >= 1 ? parent.width / aspect : parent.height
                captureSource: slot.kind === "minimized" && dockWindow.revealed && slot.item && slot.item.window
                  ? slot.item.window.wayland : null
                live: dockWindow.revealed
                constraintSize: Qt.size(root.magnifiedSize * 2, root.magnifiedSize * 2)
              }

              Image {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: parent.width * 0.4
                height: width
                sourceSize.width: width * 2
                sourceSize.height: height * 2
                fillMode: Image.PreserveAspectFit
                source: slot.kind === "minimized" && slot.item && slot.item.app ? slot.item.app.icon : ""
              }
            }

            // Running dot, between the icon and the screen edge.
            Rectangle {
              readonly property bool active: slot.app !== null && slot.app.active
              readonly property real along: active ? Style.space(12) : root.dotSize
              visible: root.indicators && !slot.dragged && slot.kind === "app" && slot.app !== null && slot.app.windows.length > 0
              width: root.vertical ? root.dotSize : along
              height: root.vertical ? along : root.dotSize
              radius: root.dotSize / 2
              color: active ? root.activeColor : root.foreground
              opacity: active ? 1 : 0.7
              x: root.position === "left" ? -(root.dotRoom + root.dotSize) / 2 - slot.bounce
                : root.position === "right" ? parent.width + (root.dotRoom - root.dotSize) / 2 + slot.bounce
                : (parent.width - width) / 2
              y: root.vertical ? (parent.height - height) / 2 : parent.height + (root.dotRoom - root.dotSize) / 2 + slot.bounce
            }

            MouseArea {
              id: mouse
              enabled: slot.kind !== "divider"
              anchors.fill: parent
              acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
              cursorShape: Qt.PointingHandCursor
              preventStealing: true
              property point pressAt: Qt.point(0, 0)
              property bool moved: false

              function windowPoint(m) { return mouse.mapToItem(dockWindow.contentItem, m.x, m.y) }

              onPressed: function(m) {
                pressAt = windowPoint(m)
                moved = false
              }
              onPositionChanged: function(m) {
                if (!(m.buttons & Qt.LeftButton) || slot.kind !== "app") return
                var p = windowPoint(m)
                if (!dockWindow.dragging) {
                  if (Math.hypot(p.x - pressAt.x, p.y - pressAt.y) < Style.space(8)) return
                  moved = true
                  dockWindow.startDrag(slot.modelData, p)
                } else if (dockWindow.dragKey === slot.modelData) {
                  dockWindow.moveDrag(p)
                }
              }
              onReleased: function(m) {
                if (dockWindow.dragKey === slot.modelData) dockWindow.finishDrag()
              }
              onCanceled: if (dockWindow.dragKey === slot.modelData) dockWindow.dragKey = ""
              onClicked: function(m) {
                if (moved) return
                var center = dockWindow.toDock(slot.mapToItem(dockWindow.contentItem, slot.width / 2, slot.height / 2)).main
                if ((m.button === Qt.RightButton && slot.kind !== "apps") || (slot.kind === "downloads" && m.button === Qt.LeftButton)) {
                  dockWindow.togglePopup(slot.kind, slot.modelData, center)
                  return
                }
                dockWindow.popup = null
                if (slot.kind !== "apps") dockWindow.appsOpen = false
                if (slot.kind === "apps") {
                if (m.button !== Qt.RightButton) dockWindow.appsOpen = !dockWindow.appsOpen
              } else if (slot.kind === "trash") {
                  Quickshell.execDetached([root.tool, "open-trash"])
                } else if (slot.kind === "minimized") {
                  root.focusWindow(slot.item.window)
                } else if (slot.kind === "app") {
                  if (m.button === Qt.MiddleButton) root.launch(slot.app)
                  else root.activate(slot.app)
                }
              }
            }

            // The name, beyond the icon on the far side from the edge.
            BorderSurface {
              readonly property string text: slot.kind === "app" && slot.app ? slot.app.name
                : slot.kind === "minimized" && slot.item ? String(slot.item.window.title || slot.item.app.name)
                : slot.kind === "downloads" ? "Downloads"
              : slot.kind === "apps" ? "Apps"
                : slot.kind === "trash" ? "Trash" : ""
              readonly property real gapOut: Style.space(10)
              visible: slot.hovered && !dockWindow.popupOpen && !dockWindow.dragging
              width: Math.min(Style.space(320), label.implicitWidth + Style.space(18))
              height: label.implicitHeight + Style.space(8)
              radius: root.smallRadius
              color: root.background
              borderSpec: root.borderSpec
              x: root.position === "left" ? parent.width + gapOut
                : root.position === "right" ? -width - gapOut
                : (parent.width - width) / 2
              y: root.vertical ? (parent.height - height) / 2 : -height - gapOut

              Text {
                id: label
                anchors.centerIn: parent
                width: Math.min(implicitWidth, Style.space(320) - Style.space(18))
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: parent.text
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }
          }
        }

        // ---------- the Apps panel ----------
        AppsPanel {
          id: appsPanel
          dock: root
          host: dockWindow
          readonly property real mainSize: root.vertical ? height : width
          readonly property real crossSize: root.vertical ? width : height
          // Centered between the top of the dock and the far screen edge.
          readonly property real dockTop: root.edgeGap + root.thickness
          readonly property var rect: dockWindow.place((dockWindow.mainLength - mainSize) / 2,
            dockTop + Math.max(Style.space(12), (dockWindow.crossExtent - dockTop - crossSize) / 2), mainSize, crossSize)
          x: rect.x
          y: rect.y
          z: 20
          readonly property bool shown: dockWindow.appsOpen || root.peek === "apps"
          visible: shown || fade.running
          // Fades out of the way while one of its apps is dragged to the dock.
          opacity: shown && !dockWindow.dragFromApps ? 1 : 0
          scale: shown ? 1 : 0.96
          Behavior on opacity { NumberAnimation { id: fade; duration: 160; easing.type: Easing.OutCubic } }
          Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
        }

        // An app dragged in from the Apps panel that isn't in the dock yet.
        Image {
          readonly property var rect: dockWindow.place(dockWindow.dragMain - root.iconSize / 2,
            dockWindow.dragCross - root.iconSize / 2, root.iconSize, root.iconSize)
          visible: dockWindow.dragNewItem !== null
          x: rect.x
          y: rect.y
          z: 30
          width: root.iconSize
          height: root.iconSize
          sourceSize.width: root.iconSize * 2
          sourceSize.height: root.iconSize * 2
          fillMode: Image.PreserveAspectFit
          source: dockWindow.dragNewItem ? dockWindow.dragNewItem.app.icon : ""
        }

        // What dropping the dragged app would do, beside the pointer.
        BorderSurface {
          readonly property real gapOut: Style.space(12)
          readonly property real mainSize: root.vertical ? height : width
          readonly property var rect: dockWindow.place(dockWindow.dragMain - mainSize / 2,
            dockWindow.dragCross + root.iconSize / 2 + gapOut, mainSize, root.vertical ? width : height)
          visible: dockWindow.dragging && dockWindow.dragHint !== ""
          x: rect.x
          y: rect.y
          z: 40
          width: hintText.implicitWidth + Style.space(18)
          height: hintText.implicitHeight + Style.space(8)
          radius: root.smallRadius
          color: root.background
          borderSpec: root.borderSpec

          Text {
            id: hintText
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: dockWindow.dragHint
            color: dockWindow.dragHint === "Uninstall" ? Color.urgent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
        }

        // ---------- "Remove?" ----------
        BorderSurface {
          id: confirmCard
          readonly property var entry: dockWindow.confirmEntry
          readonly property string exec: entry ? String(entry.execString || "") : ""
          readonly property string what: /omarchy-launch-webapp|omarchy-webapp-handler/.test(exec)
            ? "This removes the web app and its launcher."
            : /xdg-terminal-exec|\$TERMINAL/.test(exec) && / -e( |$)/.test(exec)
            ? "This removes the terminal app and its launcher."
            : "This uninstalls it from your computer. A terminal opens to confirm with your password when it's a package."
          visible: entry !== null
          x: (parent.width - width) / 2
          y: (parent.height - height) / 2
          z: 50
          width: Style.space(360)
          height: confirmColumn.implicitHeight + Style.space(40)
          radius: Math.round(Style.space(26) * root.roundness)
          color: root.background
          borderSpec: root.borderSpec
          focus: visible

          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) dockWindow.confirmEntry = null
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) dockWindow.confirmRemove()
            else return
            event.accepted = true
          }

          // Clicks on the card stay on it.
          MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton }

          Column {
            id: confirmColumn
            anchors.centerIn: parent
            width: parent.width - Style.space(40)
            spacing: Style.space(12)

            Image {
              anchors.horizontalCenter: parent.horizontalCenter
              width: Style.space(64)
              height: width
              sourceSize.width: width * 2
              sourceSize.height: height * 2
              fillMode: Image.PreserveAspectFit
              source: confirmCard.entry ? root.iconFor(confirmCard.entry, confirmCard.entry.id) : ""
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.Wrap
              textFormat: Text.PlainText
              text: confirmCard.entry ? "Remove “" + String(confirmCard.entry.name) + "”?" : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.Wrap
              textFormat: Text.PlainText
              text: confirmCard.what
              color: root.foreground
              opacity: 0.75
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(10)

              Repeater {
                model: [
                  { label: "Cancel", danger: false },
                  { label: "Remove", danger: true }
                ]

                Rectangle {
                  id: button
                  required property var modelData
                  width: Style.space(130)
                  height: buttonText.implicitHeight + Style.space(14)
                  radius: height / 2 * root.roundness
                  color: buttonMouse.containsMouse ? root.hover : "transparent"
                  border.width: Math.max(1, Style.space(1))
                  border.color: modelData.danger ? Color.urgent : root.quiet

                  Text {
                    id: buttonText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: button.modelData.label
                    color: button.modelData.danger ? Color.urgent : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  MouseArea {
                    id: buttonMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (button.modelData.danger) dockWindow.confirmRemove()
                      else dockWindow.confirmEntry = null
                    }
                  }
                }
              }
            }
          }
        }

        // ---------- popup: an app's menu, Downloads, the Trash ----------

        BorderSurface {
          id: popupCard
          readonly property var info: dockWindow.popup
          readonly property var item: info ? root.itemsByKey[info.key] || null : null
          readonly property real mainSize: root.vertical ? height : width
          readonly property real crossSize: root.vertical ? width : height
          readonly property real main: info ? Math.max(Style.space(8), Math.min(dockWindow.mainLength - mainSize - Style.space(8), info.main - mainSize / 2)) : 0
          readonly property var rect: dockWindow.place(main, dockWindow.bodyCross + root.thickness + Style.space(10), mainSize, crossSize)
          visible: info !== null && item !== null
          x: rect.x
          y: rect.y
          width: root.popupWidth
          height: rows.length > 0 ? column.implicitHeight + contentTopInset + contentBottomInset : 0
          radius: root.smallRadius
          color: root.background
          borderSpec: root.borderSpec
          padding: Style.space(4)

          // Every row: { label, action, icon?, checked?, current?, minimized?,
          // disabled? } or { separator: true }.
          readonly property var rows: {
            var it = item
            if (!it || !info) return []
            var list = []
            if (info.kind === "downloads") {
              var n = Math.min(downloadsModel.count, 10)
              for (var i = 0; i < n; i++) {
                (function(name, path, dir) {
                  list.push({ label: name, icon: root.fileIcon(name, dir), action: function() { root.openPath(path) } })
                })(downloadsModel.get(i, "fileName"), downloadsModel.get(i, "filePath"), downloadsModel.get(i, "fileIsDir"))
              }
              if (n === 0) list.push({ label: "No downloads", disabled: true })
              list.push({ separator: true })
              list.push({ label: "Open in Files", action: function() { root.openPath(root.downloadsPath) } })
              return list
            }
            if (info.kind === "trash") {
              list.push({ label: "Open", action: function() { Quickshell.execDetached([root.tool, "open-trash"]) } })
              if (root.trashFull) {
                list.push({ separator: true })
                list.push({ label: "Empty Trash", action: function() { Quickshell.execDetached([root.tool, "empty-trash"]) } })
              }
              return list
            }
            if (info.kind === "minimized") {
              var w = it.window
              list.push({ label: "Restore", action: function() { root.focusWindow(w) } })
              list.push({ label: "Close", action: function() { root.closeWindows([w]) } })
              return list
            }
            var a = it.app
            var tops = a.windows.slice(0, 8)
            for (var t = 0; t < tops.length; t++) {
              (function(top) {
                list.push({
                  label: String(top.title || a.name),
                  current: top === Hyprland.activeToplevel,
                  minimized: root.isMinimized(top),
                  action: function() { root.focusWindow(top) }
                })
              })(tops[t])
            }
            if (list.length > 0) list.push({ separator: true })
            list.push({ label: "Keep in Dock", checked: a.pinned,
              action: function() { if (a.pinned) root.unkeep(a); else root.keep(a, -1) } })
            if (a.desktop) {
              var atLogin = root.opensAtLogin(a.desktop.id)
              list.push({ label: "Open at Login", checked: atLogin, action: function() { root.setOpenAtLogin(a, !atLogin) } })
            }
            list.push({ separator: true })
            if (a.windows.length > 0 && root.overviewOn)
              list.push({ label: "Show All Windows", action: function() {
                Quickshell.execDetached(["omarchy-shell", "-q", "shell", "summon", "witcher.overview", "{}"])
              } })
            if (a.windows.length === 0) {
              if (a.desktop) list.push({ label: "Open", action: function() { root.launch(a) } })
            } else {
              if (a.desktop) list.push({ label: "New Window", action: function() { root.launch(a) } })
              list.push({ label: "Hide", action: function() { root.minimizeWindows(a.windows) } })
              list.push({ label: "Quit", action: function() { root.closeWindows(a.windows) } })
            }
            if (list.length > 0 && list[list.length - 1].separator) list.pop()
            return list
          }

          Column {
            id: column
            x: popupCard.contentLeftInset
            y: popupCard.contentTopInset
            width: popupCard.width - popupCard.contentLeftInset - popupCard.contentRightInset

            Repeater {
              model: popupCard.rows

              Item {
                id: row
                required property var modelData
                readonly property bool separator: modelData.separator === true
                width: column.width
                height: separator ? Style.space(9) : Math.max(rowText.implicitHeight, modelData.icon ? Style.space(22) : 0) + Style.space(10)

                Rectangle {
                  visible: row.separator
                  anchors.verticalCenter: parent.verticalCenter
                  x: Style.space(6)
                  width: parent.width - Style.space(12)
                  height: Math.max(1, Style.space(1))
                  color: root.quiet
                }

                Rectangle {
                  visible: !row.separator && !row.modelData.disabled && rowMouse.containsMouse
                  anchors.fill: parent
                  radius: Math.max(0, root.smallRadius - Style.space(4))
                  color: root.hover
                }

                // Check marks for the options, like macOS.
                Text {
                  visible: row.modelData.checked === true
                  anchors.verticalCenter: parent.verticalCenter
                  x: Style.space(8)
                  textFormat: Text.PlainText
                  text: "✓"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                Image {
                  visible: !!row.modelData.icon
                  anchors.verticalCenter: parent.verticalCenter
                  x: Style.space(8)
                  width: Style.space(22)
                  height: width
                  sourceSize.width: width * 2
                  sourceSize.height: height * 2
                  fillMode: Image.PreserveAspectFit
                  source: row.modelData.icon || ""
                }

                Text {
                  id: rowText
                  visible: !row.separator
                  anchors.verticalCenter: parent.verticalCenter
                  x: row.modelData.icon ? Style.space(38) : Style.space(26)
                  width: parent.width - x - Style.space(10)
                  elide: Text.ElideRight
                  textFormat: Text.PlainText
                  text: (row.modelData.minimized ? "◦ " : "") + (row.modelData.label || "")
                  // The focused window is in the border color.
                  color: row.modelData.current ? root.activeColor : root.foreground
                  opacity: row.modelData.disabled ? 0.5 : 1
                  font.family: root.fontFamily
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
                    dockWindow.popup = null
                    if (act) act()
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
