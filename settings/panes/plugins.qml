import QtQuick
import Quickshell
import "../components"

// The Omarchy shell's plugins: turn them on and off, add and remove them.
Column {
  id: pane
  spacing: 22

  property var plugins: []
  function load() {
    App.run(["omarchy-shell", "shell", "listPlugins"], function(out) {
      try { pane.plugins = JSON.parse(out) } catch (e) {}
    })
  }
  Component.onCompleted: load()

  readonly property var builtIn: plugins.filter(function(p) { return p.firstParty })
  readonly property var added: plugins.filter(function(p) { return !p.firstParty })

  function kinds(p) {
    var k = (p.kinds || []).map(function(x) {
      return x === "bar-widget" ? "menu bar" : x === "bar" ? "bar" : x === "panel" ? "panel" : x === "overlay" ? "overlay" : x === "service" ? "service" : x
    })
    return k.join(", ")
  }
  function setEnabled(p, on) {
    App.run(["omarchy-shell", "shell", "setPluginEnabled", p.id, on ? "true" : "false"], function() { pane.load() })
  }

  Group {
    title: "Added"
    Repeater {
      model: pane.added
      SettingRow {
        id: ap
        required property var modelData
        label: modelData.name
        sublabel: modelData.id
        Row {
          spacing: 8
          Switch {
            visible: ap.modelData.id.indexOf("witcher.") !== 0 && ap.modelData.canDisable
            checked: ap.modelData.enabled
            onToggled: function(wanted) { pane.setEnabled(ap.modelData, wanted) }
          }
          PillButton {
            visible: ap.modelData.id.indexOf("witcher.") !== 0
            text: "Remove"
            danger: true
            onClicked: App.confirm({ title: "Remove " + ap.modelData.name + "?", text: "Its folder is deleted.", action: "Remove", danger: true,
              onAccept: function() { App.terminal("omarchy plugin remove " + ap.modelData.id) } })
          }
        }
      }
    }
    ButtonRow {
      label: "Add a plugin"
      buttonText: "Add…"
      onClicked: App.terminal("omarchy-plugin-add")
    }
    ButtonRow {
      label: "Update plugins"
      buttonText: "Update"
      onClicked: App.terminal("omarchy plugin update")
    }
  }

  Group {
    title: "Built in"
    Repeater {
      model: pane.builtIn
      SwitchRow {
        required property var modelData
        label: modelData.name
        checked: modelData.enabled
        switchEnabled: modelData.canDisable
        onToggled: function(wanted) { pane.setEnabled(modelData, wanted) }
      }
    }
  }
}
