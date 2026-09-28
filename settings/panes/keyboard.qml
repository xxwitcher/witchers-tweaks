import QtQuick
import Quickshell
import "../components"

// Keyboard layouts, special keys and repeat (saved to the app's settings and
// applied live), the key tweaks, every shortcut, and your own shortcuts.
Column {
  id: pane
  spacing: 22

  property var input: ({})
  property var xkb: ({ layouts: [], variants: [], options: [] })
  property var shortcuts: []

  function load() {
    App.helper(["input"], function(out) { try { pane.input = JSON.parse(out) } catch (e) {} })
    App.helper(["shortcuts"], function(out) { try { pane.shortcuts = JSON.parse(out) } catch (e) {} })
  }
  Component.onCompleted: {
    load()
    App.helper(["xkb"], function(out) { try { pane.xkb = JSON.parse(out) } catch (e) {} })
  }

  function setInput(key, value) {
    App.run([App.helperPath, "input-set", key, JSON.stringify(value)], function(out, code) {
      if (code !== 0) App.toast("Couldn't change " + key)
      App.helper(["input"], function(o) { try { pane.input = JSON.parse(o) } catch (e) {} })
    })
  }

  // ---------- layouts ----------
  readonly property var layouts: String(input.kb_layout || "us").split(",").map(function(s) { return s.trim() }).filter(function(s) { return s !== "" })
  readonly property var variants: {
    var v = String(input.kb_variant || "").split(",")
    return layouts.map(function(_, i) { return (v[i] || "").trim() })
  }
  function layoutName(code) {
    var l = xkb.layouts || []
    for (var i = 0; i < l.length; i++) if (l[i].code === code) return l[i].name
    return code
  }
  function saveLayouts(ls, vs) {
    App.run([App.helperPath, "input-set-many", JSON.stringify({ kb_layout: ls.join(","), kb_variant: vs.join(",") })], function(out, code) {
      if (code !== 0) App.toast("Couldn't change the layouts")
      App.helper(["input"], function(o) { try { pane.input = JSON.parse(o) } catch (e) {} })
    })
  }

  // ---------- options (kb_options) ----------
  // swap_lwin_lctl belongs to the swapkeys tweak, which adds it itself.
  readonly property var options: String(input.kb_options || "").split(",").map(function(s) { return s.trim() })
    .filter(function(s) { return s !== "" && s !== "ctrl:swap_lwin_lctl" })
  function optionIn(prefixes) {
    for (var i = 0; i < options.length; i++)
      for (var p = 0; p < prefixes.length; p++) if (options[i].indexOf(prefixes[p]) === 0) return options[i]
    return ""
  }
  function setOption(prefixes, value) {
    var rest = options.filter(function(o) {
      for (var p = 0; p < prefixes.length; p++) if (o.indexOf(prefixes[p]) === 0) return false
      return true
    })
    if (value !== "") rest.push(value)
    setInput("kb_options", rest.join(","))
  }

  // ---------- repeat ----------
  Group {
    SliderRow {
      label: "Key repeat rate"
      from: 10; to: 80; step: 5
      value: Number(pane.input.repeat_rate || 25)
      minLabel: "Slow"; maxLabel: "Fast"
      onChanged: function(v) { pane.setInput("repeat_rate", Math.round(v)) }
    }
    SliderRow {
      label: "Delay until repeat"
      from: 150; to: 1000; step: 50
      value: Number(pane.input.repeat_delay || 600)
      minLabel: "Short"; maxLabel: "Long"
      onChanged: function(v) { pane.setInput("repeat_delay", Math.round(v)) }
    }
    SwitchRow {
      label: "Num Lock on at start"
      checked: pane.input.numlock_by_default === true
      onToggled: function(wanted) { pane.setInput("numlock_by_default", wanted) }
    }
  }

  // ---------- layouts ----------
  Group {
    title: "Input sources"
    Repeater {
      model: pane.layouts
      SettingRow {
        id: layoutRow
        required property var modelData
        required property int index
        label: pane.layoutName(modelData)
        Row {
          spacing: 8
          Dropdown {
            buttonWidth: 200
            placeholder: "Standard"
            options: [{ value: "", label: "Standard" }].concat((pane.xkb.variants || []).filter(function(v) { return v.layout === layoutRow.modelData })
              .map(function(v) { return { value: v.code, label: v.name } }))
            current: pane.variants[layoutRow.index] || ""
            onChosen: function(v) {
              var vs = pane.variants.slice(); vs[layoutRow.index] = v
              pane.saveLayouts(pane.layouts, vs)
            }
          }
          PillButton {
            visible: pane.layouts.length > 1
            text: "Remove"
            onClicked: {
              var ls = pane.layouts.slice(), vs = pane.variants.slice()
              ls.splice(layoutRow.index, 1); vs.splice(layoutRow.index, 1)
              pane.saveLayouts(ls, vs)
            }
          }
        }
      }
    }
    ChoiceRow {
      label: "Add an input source"
      placeholder: "Choose…"
      searchable: true
      buttonWidth: 260
      options: (pane.xkb.layouts || []).filter(function(l) { return pane.layouts.indexOf(l.code) < 0 }).map(function(l) { return { value: l.code, label: l.name } })
      current: null
      onChosen: function(v) { pane.saveLayouts(pane.layouts.concat([v]), pane.variants.concat([""])) }
    }
    ChoiceRow {
      visible: pane.layouts.length > 1
      label: "Switch input sources with"
      options: [
        { value: "", label: "Nothing" },
        { value: "grp:alts_toggle", label: "Both Alt keys" },
        { value: "grp:alt_shift_toggle", label: "Alt + Shift" },
        { value: "grp:ctrl_shift_toggle", label: "Ctrl + Shift" },
        { value: "grp:win_space_toggle", label: "Super + Space" },
        { value: "grp:caps_toggle", label: "Caps Lock" }
      ]
      current: pane.optionIn(["grp:"])
      onChosen: function(v) { pane.setOption(["grp:"], v) }
    }
  }

  // ---------- special keys ----------
  Group {
    title: "Special keys"
    ChoiceRow {
      label: "Compose key"
      options: [
        { value: "", label: "None" },
        { value: "compose:caps", label: "Caps Lock" },
        { value: "compose:ralt", label: "Right Alt" },
        { value: "compose:rctrl", label: "Right Ctrl" },
        { value: "compose:menu", label: "Menu" },
        { value: "compose:rwin", label: "Right Super" }
      ]
      current: pane.optionIn(["compose:"])
      onChosen: function(v) { pane.setOption(["compose:"], v) }
    }
    ChoiceRow {
      label: "Caps Lock key"
      options: [
        { value: "", label: "Caps Lock" },
        { value: "ctrl:nocaps", label: "Control" },
        { value: "caps:escape", label: "Escape" },
        { value: "caps:swapescape", label: "Swap with Escape" },
        { value: "caps:none", label: "Nothing" }
      ]
      current: pane.optionIn(["ctrl:nocaps", "caps:"])
      onChosen: function(v) { pane.setOption(["ctrl:nocaps", "caps:"], v) }
    }
    TweakRow { tweak: "swapkeys"; label: "Swap left Ctrl and left Super" }
    ButtonRow {
      label: "Compose sequences"
      buttonText: "Edit…"
      onClicked: App.shDetached("omarchy-launch-config-editor ~/.XCompose && omarchy-restart-xcompose")
    }
  }

  // ---------- tweaks ----------
  Group {
    ButtonRow {
      label: "Keyboard shortcuts"
      buttonText: "View…"
      onClicked: App.detached(["omarchy-menu-keybindings"])
    }
  }

  Group {
    title: "Shortcut tweaks"
    TweakRow { tweak: "bindbrowser"; label: "SUPER+B opens the browser" }
    TweakRow { tweak: "bindagent"; label: "SUPER+A opens your agent" }
    TweakRow { tweak: "bindclose"; label: "CTRL+Q closes the window" }
  }

  // ---------- your shortcuts ----------
  Group {
    title: "Your shortcuts"
    Repeater {
      model: pane.shortcuts
      SettingRow {
        id: sc
        required property var modelData
        label: modelData.description || modelData.command
        sublabel: modelData.keys + "   ·   " + modelData.command
        PillButton {
          text: "Remove"
          danger: true
          onClicked: App.run([App.helperPath, "shortcut-remove", sc.modelData.keys], function() { pane.load() })
        }
      }
    }
    SettingRow {
      label: "New shortcut"
      Row {
        spacing: 8
        // Records a key combination.
        Rectangle {
          id: keysBox
          property string combo: ""
          width: 150; height: 28; radius: 7
          color: keysInput.activeFocus ? App.hover : App.control
          border.width: keysInput.activeFocus ? 1 : 0
          border.color: App.tint
          Text {
            anchors.centerIn: parent
            width: parent.width - 12
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            text: keysBox.combo !== "" ? keysBox.combo : (keysInput.activeFocus ? "Press keys…" : "Keys")
            color: keysBox.combo !== "" ? App.fg : App.faint
            font.family: App.font
            font.pixelSize: App.small + 1
          }
          Item {
            id: keysInput
            anchors.fill: parent
            focus: false
            Keys.onPressed: function(e) {
              var mods = []
              if (e.modifiers & Qt.MetaModifier) mods.push("SUPER")
              if (e.modifiers & Qt.ControlModifier) mods.push("CTRL")
              if (e.modifiers & Qt.AltModifier) mods.push("ALT")
              if (e.modifiers & Qt.ShiftModifier) mods.push("SHIFT")
              var modifierOnly = [Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R, Qt.Key_Control, Qt.Key_Alt, Qt.Key_Shift].indexOf(e.key) >= 0
              if (!modifierOnly) {
                var name = e.text && e.text.trim() !== "" && e.key < 0x01000000 ? String.fromCharCode(e.key) : ""
                if (name === "") {
                  var special = {}
                  special[Qt.Key_Return] = "RETURN"; special[Qt.Key_Space] = "SPACE"; special[Qt.Key_Tab] = "TAB"
                  special[Qt.Key_Escape] = "ESCAPE"; special[Qt.Key_Backspace] = "BACKSPACE"; special[Qt.Key_Delete] = "DELETE"
                  special[Qt.Key_Left] = "LEFT"; special[Qt.Key_Right] = "RIGHT"; special[Qt.Key_Up] = "UP"; special[Qt.Key_Down] = "DOWN"
                  special[Qt.Key_Home] = "HOME"; special[Qt.Key_End] = "END"; special[Qt.Key_PageUp] = "PAGE_UP"; special[Qt.Key_PageDown] = "PAGE_DOWN"
                  special[Qt.Key_Print] = "PRINT"
                  if (e.key >= Qt.Key_F1 && e.key <= Qt.Key_F24) name = "F" + (e.key - Qt.Key_F1 + 1)
                  else name = special[e.key] || ""
                }
                if (name !== "") keysBox.combo = mods.concat([name.toUpperCase()]).join(" + ")
              }
              e.accepted = true
            }
          }
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: keysInput.forceActiveFocus() }
        }
        Rectangle {
          width: 170; height: 28; radius: 7; color: App.control
          TextInput {
            id: commandInput
            x: 8; width: parent.width - 16
            anchors.verticalCenter: parent.verticalCenter
            color: App.fg; font.family: App.font; font.pixelSize: App.body; clip: true
            Text { visible: commandInput.text === ""; text: "Command to run"; color: App.faint; font: commandInput.font }
          }
        }
        PillButton {
          text: "Add"
          prominent: true
          enabled2: keysBox.combo !== "" && commandInput.text.trim() !== ""
          onClicked: App.run([App.helperPath, "shortcut-add", keysBox.combo, commandInput.text.trim(), commandInput.text.trim()], function(out, code) {
            if (code !== 0) App.toast("Couldn't add the shortcut")
            else App.toast(keysBox.combo + " added")
            keysBox.combo = ""
            commandInput.text = ""
            pane.load()
          })
        }
      }
    }
  }

}
