import QtQuick
import Quickshell
import "../components"

// Pointer and touchpad settings (saved to the app's settings and applied
// live), gestures and the touch devices.
Column {
  id: pane
  spacing: 22

  property var input: ({})
  function load() { App.helper(["input"], function(out) { try { pane.input = JSON.parse(out) } catch (e) {} }) }
  Component.onCompleted: load()
  function set(key, value) {
    App.run([App.helperPath, "input-set", key, JSON.stringify(value)], function(out, code) {
      if (code !== 0) App.toast("Couldn't change " + key)
      pane.load()
    })
  }

  Group {
    title: "Pointer"
    SliderRow {
      label: "Tracking speed"
      from: -1; to: 1; step: 0.05
      value: Number(pane.input.sensitivity || 0)
      minLabel: "Slow"; maxLabel: "Fast"
      onChanged: function(v) { pane.set("sensitivity", Number(v.toFixed(2))) }
    }
    SwitchRow {
      label: "Pointer acceleration"
      checked: pane.input.accel_profile !== "flat"
      onToggled: function(wanted) { pane.set("accel_profile", wanted ? "adaptive" : "flat") }
    }
  }

  Group {
    title: "Trackpad"
    SwitchRow {
      visible: App.status.laptop === true
      label: "Trackpad"
      checked: App.status.touchpadOff !== true
      onToggled: function(wanted) { App.apply(["omarchy-toggle-touchpad", wanted ? "on" : "off"]) }
    }
    SwitchRow {
      label: "Natural scrolling"
      checked: pane.input["touchpad:natural_scroll"] === true
      onToggled: function(wanted) { pane.set("touchpad:natural_scroll", wanted) }
    }
    SwitchRow {
      label: "Tap to click"
      checked: pane.input["touchpad:tap-to-click"] === true
      onToggled: function(wanted) { pane.set("touchpad:tap-to-click", wanted) }
    }
    SwitchRow {
      label: "Click with two fingers to right-click"
      checked: pane.input["touchpad:clickfinger_behavior"] === true
      onToggled: function(wanted) { pane.set("touchpad:clickfinger_behavior", wanted) }
    }
    SliderRow {
      label: "Scrolling speed"
      from: 0.1; to: 2; step: 0.05
      value: Number(pane.input["touchpad:scroll_factor"] || 1)
      minLabel: "Slow"; maxLabel: "Fast"
      onChanged: function(v) { pane.set("touchpad:scroll_factor", Number(v.toFixed(2))) }
    }
    SwitchRow {
      label: "Ignore the trackpad while typing"
      checked: pane.input["touchpad:disable_while_typing"] === true
      onToggled: function(wanted) { pane.set("touchpad:disable_while_typing", wanted) }
    }
    SwitchRow {
      label: "Three-finger drag"
      checked: Number(pane.input["touchpad:drag_3fg"] || 0) > 0
      onToggled: function(wanted) { pane.set("touchpad:drag_3fg", wanted ? 1 : 0) }
    }
    ChoiceRow {
      visible: App.status.haptics === true
      label: "Click feel"
      options: [{ value: "low", label: "Light" }, { value: "mid", label: "Medium" }, { value: "high", label: "Firm" }]
      current: null
      placeholder: "Choose…"
      onChosen: function(v) { App.apply(["dell-xps-touchpad-haptics", "set", v]) }
    }
  }


  Group {
    visible: App.status.touchscreen === true
    title: "Touchscreen"
    SwitchRow {
      label: "Touchscreen"
      checked: App.status.touchscreenOff !== true
      onToggled: function(wanted) { App.apply(["omarchy-toggle-touchscreen", wanted ? "on" : "off"]) }
    }
  }

  Group {
    ButtonRow { label: "Trackpad acting up?"; buttonText: "Restart Trackpad"; onClicked: App.terminal("omarchy-restart-trackpad") }
  }
}
