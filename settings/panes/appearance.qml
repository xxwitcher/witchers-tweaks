import QtQuick
import Quickshell
import "../components"

// Theme, background, font and text size (Omarchy's own commands), and the
// look tweaks: window corners, gaps and the gradient border.
Column {
  id: pane
  spacing: 22

  property var themes: []
  property var backgrounds: []
  property var fonts: []
  property var border: []          // light, main, accent, inactive as #rrggbb
  property string themeBusy: ""

  function load() {
    App.helper(["themes"], function(out) { try { pane.themes = JSON.parse(out) } catch (e) {} })
    App.helper(["backgrounds"], function(out) { try { pane.backgrounds = JSON.parse(out) } catch (e) {} })
    App.helper(["fonts"], function(out) { try { pane.fonts = JSON.parse(out) } catch (e) {} })
    App.helper(["border", "get"], function(out) {
      // (The pane may be gone by the time this answers.)
      try {
        var c = out.trim().split(/\s+/)
        if (c.length === 4) pane.border = c.map(function(x) { return "#" + x })
      } catch (e) {}
    })
  }
  Component.onCompleted: load()

  function pretty(id) {
    return String(id).split("-").map(function(w) { return w.charAt(0).toUpperCase() + w.slice(1) }).join(" ")
  }

  // Theme changes can take a few seconds; the list of backgrounds follows.
  function setTheme(id) {
    themeBusy = id
    App.run(["omarchy-theme-set", id], function() {
      pane.themeBusy = ""
      App.refresh()
      App.helper(["backgrounds"], function(out) { try { pane.backgrounds = JSON.parse(out) } catch (e) {} })
    })
  }

  function borderArgs(colors) { return colors.map(function(c) { return String(c).replace(/^#/, "") }) }

  // ---------- theme ----------
  Group {
    title: "Theme"
    // Two rows, scrolling sideways.
    Item {
      width: parent.width
      height: themeGrid.height + 24
      GridView {
        id: themeGrid
        x: 12
        y: 12
        width: parent.width - 24
        readonly property real cardWidth: (width - 24) / 3.4
        cellWidth: cardWidth + 12
        cellHeight: cardWidth * 0.62 + 34
        height: cellHeight * 2
        flow: GridView.FlowTopToBottom
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        model: pane.themes
        delegate: Item {
          id: themeCard
          required property var modelData
          readonly property bool current: App.status.theme === modelData.id
          width: themeGrid.cardWidth
          height: themeGrid.cellHeight - 8
          Rectangle {
            width: parent.width
            height: parent.width * 0.62
            radius: 8
            color: App.control
            border.width: themeCard.current ? 3 : (themeArea.containsMouse ? 1 : 0)
            border.color: themeCard.current ? App.tint : App.faint
            clip: true
            Image {
              anchors.fill: parent
              anchors.margins: themeCard.current ? 3 : 1
              source: themeCard.modelData.preview ? "file://" + themeCard.modelData.preview : ""
              sourceSize.width: 320
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
            }
            Rectangle {
              anchors.fill: parent
              radius: 8
              color: Qt.rgba(0, 0, 0, 0.45)
              visible: pane.themeBusy === themeCard.modelData.id
              Text { anchors.centerIn: parent; text: "Applying…"; color: "white"; font.family: App.font; font.pixelSize: App.body }
            }
          }
          Text {
            anchors.bottom: parent.bottom
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: pane.pretty(themeCard.modelData.id)
            color: themeCard.current ? App.fg : App.subtle
            font.family: App.font
            font.pixelSize: App.small + 1
          }
          MouseArea {
            id: themeArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: pane.themeBusy === ""
            onClicked: if (!themeCard.current) pane.setTheme(themeCard.modelData.id)
          }
        }
        // Two-finger sideways scrolling (it arrives through the page's
        // scroller): follows the fingers, then glides.
        property real sideVelocity: 0
        property double sideAt: 0
        Connections {
          target: scroller
          function onSideways(dx, at, phase) {
            var p = themeGrid.mapFromItem(null, at.x, at.y)
            var inside = p.x >= 0 && p.y >= 0 && p.x <= themeGrid.width && p.y <= themeGrid.height
            if (dx === 0) {
              if (phase === Qt.ScrollEnd && Math.abs(themeGrid.sideVelocity) > 60) themeGrid.flick(themeGrid.sideVelocity, 0)
              themeGrid.sideVelocity = 0
              return
            }
            if (!inside) return
            var now = Date.now()
            var dt = Math.max(4, now - themeGrid.sideAt)
            var v = dx * 1.4 * 1000 / dt
            themeGrid.sideVelocity = now - themeGrid.sideAt > 120 ? v : themeGrid.sideVelocity * 0.5 + v * 0.5
            themeGrid.sideAt = now
            themeGrid.cancelFlick()
            var max = Math.max(0, themeGrid.contentWidth - themeGrid.width)
            themeGrid.contentX = Math.max(themeGrid.originX, Math.min(themeGrid.originX + max, themeGrid.contentX - dx * 1.4))
          }
        }
        // Starts at the current theme.
        onCountChanged: Qt.callLater(function() {
          for (var i = 0; i < pane.themes.length; i++)
            if (pane.themes[i].id === App.status.theme) { themeGrid.positionViewAtIndex(i, GridView.Contain); break }
        })
      }
    }
    ButtonRow {
      label: "More themes"
      buttonText: "Update Themes"
      onClicked: App.terminal("omarchy-theme-update")
    }
  }

  // ---------- background ----------
  Group {
    title: "Background"
    Item {
      width: parent.width
      height: bgGrid.height + 24
      Grid {
        id: bgGrid
        x: 12
        y: 12
        columns: 4
        spacing: 10
        readonly property real cell: (parent.width - 24 - spacing * (columns - 1)) / columns
        Repeater {
          model: pane.backgrounds
          Rectangle {
            id: bg
            required property var modelData
            // By file name: the theme's backgrounds are copies of where the
            // current-background link points.
            readonly property bool current: String(App.status.background || "").split("/").pop() === String(modelData).split("/").pop()
            width: bgGrid.cell
            height: width * 0.62
            radius: 8
            color: App.control
            border.width: current ? 3 : 0
            border.color: App.tint
            clip: true
            Image {
              anchors.fill: parent
              anchors.margins: bg.current ? 3 : 0
              source: "file://" + bg.modelData
              sourceSize.width: 260
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: App.apply(["omarchy-theme-bg-set", bg.modelData])
            }
          }
        }
      }
    }
    ButtonRow {
      label: "All backgrounds"
      buttonText: "Choose…"
      onClicked: App.shDetached('background=$(omarchy-theme-bg-switcher); [[ -n $background ]] && omarchy-theme-bg-set "$background"')
    }
  }

  // ---------- text ----------
  Group {
    title: "Text"
    ChoiceRow {
      label: "Font"
      options: pane.fonts
      searchable: true
      buttonWidth: 260
      current: App.status.font || ""
      onChosen: function(v) { App.apply(["omarchy-font-set", v], "Font set to " + v) }
    }
    SliderRow {
      label: "Text size"
      from: 9
      to: 20
      step: 1
      value: Number(App.status.textSize || 12)
      format: function(v) { return Math.round(v) + " px" }
      onChanged: function(v) { App.apply(["omarchy-display-text-size", String(Math.round(v))]) }
    }
  }

  // ---------- windows ----------
  Group {
    title: "Windows"
    TweakRow { tweak: "rounding"; label: "Rounded window corners" }
    SliderRow {
      visible: App.tweakOn("rounding")
      label: "Corner rounding"
      from: 0
      to: 100
      step: 5
      value: Number(App.status.roundness || 0)
      format: function(v) { return Math.round(v) + "%" }
      onChanged: function(v) { App.apply([App.helperPath, "corners-set", String(Math.round(v))]) }
    }
    SwitchRow {
      label: "Gaps between windows"
      readonly property bool gapsTweak: App.tweakOn("gaps")
      checked: !App.status.noGaps && !gapsTweak
      busy: App.tweakPending("gaps")
      onToggled: function(wanted) {
        if (wanted) {
          if (gapsTweak) App.setTweak("gaps", false)
          if (App.status.noGaps) App.apply(["omarchy-hyprland-toggle", "window-no-gaps", "off"])
        } else {
          App.apply(["omarchy-hyprland-toggle", "window-no-gaps", "on"])
        }
      }
    }
    SwitchRow {
      label: "Square single windows"
      checked: App.status.squareRatio === true
      onToggled: function(wanted) { App.apply(["omarchy-hyprland-toggle", "single-window-aspect-ratio", wanted ? "on" : "off"]) }
    }
    ChoiceRow {
      label: "New windows open"
      options: [{ value: "tiled", label: "Tiled" }, { value: "floating", label: "Floating" }]
      current: App.status.windowMode || "tiled"
      onChosen: function(v) { App.apply([App.helperPath, "window-mode", v]) }
    }
    TweakRow { tweak: "titlebars"; label: "Window buttons and drag strip on floating windows" }
    TweakRow { tweak: "borderresize"; label: "Resize floating windows by their border" }
    TweakRow { tweak: "overview"; label: "Window overview" }
    TweakRow { tweak: "wsfade"; label: "Slide workspaces in with a fade" }
    TweakRow { tweak: "swipe"; label: "Swipe between workspaces with three fingers" }
    SwitchRow {
      label: "Scrolling layout on this workspace"
      checked: App.status.layout === "scrolling"
      onToggled: function(wanted) { App.apply(["omarchy-hyprland-workspace-layout-toggle"]) }
    }
    TweakRow { tweak: "columns"; label: "One column per screen in the scrolling layout" }
  }

  // ---------- border ----------
  Group {
    title: "Window border"
    TweakRow { tweak: "border"; label: "Animated gradient border" }
    ColorRow {
      visible: App.tweakOn("border") && pane.border.length === 4
      label: "Gradient colors"
      colors: pane.border.slice(0, 3)
      onColorPreviewed: function(i, hex) {
        var c = pane.border.slice(); c[i] = hex
        App.run([App.helperPath, "border", "preview"].concat(pane.borderArgs(c)))
      }
      onColorPicked: function(i, hex) {
        var c = pane.border.slice(); c[i] = hex
        pane.border = c
        App.apply([App.helperPath, "border", "set"].concat(pane.borderArgs(c)), "Border colors saved")
      }
      onCancelled: App.run([App.helperPath, "border", "revert"])
    }
    ColorRow {
      visible: App.tweakOn("border") && pane.border.length === 4
      label: "Inactive windows"
      colors: pane.border.slice(3, 4)
      onColorPreviewed: function(i, hex) {
        var c = pane.border.slice(); c[3] = hex
        App.run([App.helperPath, "border", "preview"].concat(pane.borderArgs(c)))
      }
      onColorPicked: function(i, hex) {
        var c = pane.border.slice(); c[3] = hex
        pane.border = c
        App.apply([App.helperPath, "border", "set"].concat(pane.borderArgs(c)), "Border colors saved")
      }
      onCancelled: App.run([App.helperPath, "border", "revert"])
    }
    ButtonRow {
      visible: App.tweakOn("border")
      label: "Default colors"
      buttonText: "Reset"
      onClicked: App.run([App.helperPath, "border", "reset"], function() { pane.load(); App.toast("Border colors reset") })
    }
  }

  // ---------- screens ----------
  Group {
    title: "Lock and start screens"
    ButtonRow {
      label: "Unlock screen"
      buttonText: "Choose…"
      onClicked: App.shDetached('unlock=$(omarchy-plymouth-switcher); if [[ $unlock == default ]]; then omarchy-launch-floating-terminal-with-presentation omarchy-plymouth-reset; elif [[ -n $unlock ]]; then omarchy-launch-floating-terminal-with-presentation "omarchy-plymouth-set-by-theme $(printf %q "$unlock")"; fi')
    }
    SettingRow {
      label: "Screensaver"
      Row {
        spacing: 8
        PillButton { text: "Text…"; onClicked: App.detached(["omarchy-branding-screensaver", "text"]) }
        PillButton { text: "Image…"; onClicked: App.detached(["omarchy-branding-screensaver", "image"]) }
        PillButton { text: "Default"; onClicked: App.detached(["omarchy-branding-screensaver", "reset"]) }
      }
    }
    SettingRow {
      label: "About screen"
      Row {
        spacing: 8
        PillButton { text: "Text…"; onClicked: App.detached(["omarchy-branding-about", "text"]) }
        PillButton { text: "Image…"; onClicked: App.detached(["omarchy-branding-about", "image"]) }
        PillButton { text: "Default"; onClicked: App.detached(["omarchy-branding-about", "reset"]) }
      }
    }
  }
}
