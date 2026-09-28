import QtQuick
import Quickshell
import "../components"

// The dock's settings (witcher.dock in shell.json): macOS's Desktop & Dock
// options plus transparency, corners and its border.
Column {
  id: pane
  spacing: 22

  readonly property var d: App.dock || ({})
  function set(key, value) { App.apply([App.helperPath, "dock-set", key, JSON.stringify(value)]) }
  function get(key, fallback) { return d[key] === undefined || d[key] === null ? fallback : d[key] }
  readonly property var colors: Array.isArray(d.borderColors) && d.borderColors.length > 0 ? d.borderColors : ["#c4b5fd", "#a855f7", "#da70d6"]

  Group {
    TweakRow { tweak: "dock"; label: "Show the dock"; icon: "view-app-grid-symbolic"; iconColor: "#1c1c1e" }
  }

  Column {
    width: parent.width
    spacing: 22
    visible: App.tweakOn("dock") && App.dock !== null

    Group {
      SliderRow {
        label: "Size"
        from: 32; to: 80; step: 4
        value: pane.get("size", 48)
        minLabel: "Small"; maxLabel: "Large"
        onChanged: function(v) { pane.set("size", Math.round(v)) }
      }
      SwitchRow {
        label: "Magnification"
        checked: pane.get("magnification", 0) > 0
        onToggled: function(wanted) { pane.set("magnification", wanted ? Math.max(64, pane.get("size", 48) + 32) : 0) }
      }
      SliderRow {
        visible: pane.get("magnification", 0) > 0
        label: "Magnified size"
        from: 48; to: 128; step: 8
        value: pane.get("magnification", 80)
        minLabel: "Small"; maxLabel: "Large"
        onChanged: function(v) { pane.set("magnification", Math.round(v)) }
      }
      SegmentedRow {
        label: "Position on screen"
        options: [{ value: "left", label: "Left" }, { value: "bottom", label: "Bottom" }, { value: "right", label: "Right" }]
        current: pane.get("position", "bottom")
        onChosen: function(v) { pane.set("position", v) }
      }
      ChoiceRow {
        label: "Minimize windows using"
        options: [
          { value: "genie", label: "Genie effect" },
          { value: "scale", label: "Scale effect" },
          { value: "fade", label: "Fade" },
          { value: "slide", label: "Slide down" },
          { value: "none", label: "No animation" }
        ]
        current: pane.get("minimizeEffect", "genie")
        onChosen: function(v) { pane.set("minimizeEffect", v) }
      }
      SliderRow {
        visible: pane.get("minimizeEffect", "genie") !== "none"
        label: "Animation speed"
        from: 50; to: 200; step: 10
        value: pane.get("minimizeSpeed", 100)
        minLabel: "Slow"; maxLabel: "Fast"
        onChanged: function(v) { pane.set("minimizeSpeed", Math.round(v)) }
      }
      SwitchRow {
        label: "Minimize windows into application icon"
        checked: pane.get("minimize", false) === true
        onToggled: function(wanted) { pane.set("minimize", wanted) }
      }
      ChoiceRow {
        label: "Automatically hide and show the Dock"
        options: [
          { value: "auto", label: "Always" },
          { value: "smart", label: "When a window is under it" },
          { value: "never", label: "Never" }
        ]
        current: pane.get("hide", "auto")
        onChosen: function(v) { pane.set("hide", v) }
      }
      SwitchRow {
        label: "Animate opening applications"
        checked: pane.get("animate", true) === true
        onToggled: function(wanted) { pane.set("animate", wanted) }
      }
      SwitchRow {
        label: "Show indicators for open applications"
        checked: pane.get("indicators", true) === true
        onToggled: function(wanted) { pane.set("indicators", wanted) }
      }
      SwitchRow {
        label: "Show suggested and recent apps in Dock"
        checked: pane.get("recents", true) === true
        onToggled: function(wanted) { pane.set("recents", wanted) }
      }
      ChoiceRow {
        label: "Clicking the app you're in"
        options: [{ value: "cycle", label: "Goes to its next window" }, { value: "focus", label: "Stays on its last window" }]
        current: pane.get("click", "cycle")
        onChosen: function(v) { pane.set("click", v) }
      }
    }

    Group {
      title: "Look"
      SliderRow {
        label: "Dock transparency"
        from: 0; to: 90; step: 5
        value: pane.get("transparency", 0)
        format: function(v) { return Math.round(v) + "%" }
        onChanged: function(v) { pane.set("transparency", Math.round(v)) }
      }
      SliderRow {
        label: "App drawer transparency"
        from: 0; to: 90; step: 5
        value: pane.get("appsTransparency", 0)
        format: function(v) { return Math.round(v) + "%" }
        onChanged: function(v) { pane.set("appsTransparency", Math.round(v)) }
      }
      SliderRow {
        label: "Corner rounding"
        from: 0; to: 100; step: 5
        value: pane.get("roundness", 60)
        format: function(v) { return Math.round(v) + "%" }
        onChanged: function(v) { pane.set("roundness", Math.round(v)) }
      }
      ChoiceRow {
        label: "Border"
        options: [
          { value: "windows", label: "Same gradient as windows" },
          { value: "custom", label: "Custom gradient" },
          { value: "solid", label: "One solid color" },
          { value: "none", label: "No border" }
        ]
        current: pane.get("border", "windows")
        onChosen: function(v) {
          pane.set("border", v)
          if ((v === "custom" && pane.colors.length < 3) || (v === "solid" && pane.colors.length < 1))
            pane.set("borderColors", ["#c4b5fd", "#a855f7", "#da70d6"])
        }
      }
      ColorRow {
        visible: pane.get("border", "windows") === "custom" || pane.get("border", "windows") === "solid"
        label: pane.get("border", "windows") === "solid" ? "Border color" : "Gradient colors"
        colors: pane.get("border", "windows") === "solid" ? pane.colors.slice(0, 1)
          : [0, 1, 2].map(function(i) { return pane.colors[Math.min(i, pane.colors.length - 1)] })
        onColorPicked: function(i, hex) {
          var c = (pane.get("border", "windows") === "solid" ? pane.colors.slice(0, 1) : [0, 1, 2].map(function(k) { return pane.colors[Math.min(k, pane.colors.length - 1)] }))
          c[i] = hex
          pane.set("borderColors", c)
        }
      }
    }

    Group {
      title: "Keep in Dock"
      ButtonRow {
        label: "Forget recent apps"
        buttonText: "Clear"
        onClicked: App.sh("rm -f \"${XDG_STATE_HOME:-$HOME/.local/state}/witcher/dock-recent.json\"", function() { App.toast("Recent apps cleared (the dock updates on its next restart)") })
      }
    }
  }
}
