import QtQuick
import Quickshell
import "../components"

// Every one of Witcher's Tweaks this machine can use, by category, with a
// way to its settings.
Column {
  id: pane
  spacing: 22

  readonly property var categories: {
    var seen = []
    for (var i = 0; i < App.tweakList.length; i++)
      if (seen.indexOf(App.tweakList[i].category) < 0) seen.push(App.tweakList[i].category)
    return seen
  }
  // Where each configurable setting lives in this app.
  readonly property var settingsPane: ({ borders: "appearance", corners: "appearance", dock: "dock", notifications: "notifications", suspend: "power", monitors: "displays" })


  Repeater {
    model: pane.categories
    Group {
      id: cat
      required property var modelData
      title: modelData
      Repeater {
        model: App.tweakList.filter(function(t) { return t.category === cat.modelData })
        SettingRow {
          id: tw
          required property var modelData
          label: modelData.description
          sublabel: modelData.state === "partial" ? "Partly installed" : ""
          Row {
            spacing: 10
            PillButton {
              visible: App.tweakOn(tw.modelData.name) && tw.modelData.configure.length > 0 && pane.settingsPane[tw.modelData.configure[0]] !== undefined
              text: "Settings"
              onClicked: shellRoot.select(pane.settingsPane[tw.modelData.configure[0]])
            }
            Switch {
              anchors.verticalCenter: parent.verticalCenter
              checked: App.tweakOn(tw.modelData.name)
              busy: App.tweakPending(tw.modelData.name)
              onToggled: function(wanted) { App.setTweak(tw.modelData.name, wanted) }
            }
          }
        }
      }
    }
  }

  Group {
    ButtonRow {
      label: "Run the installer"
      buttonText: "Open"
      onClicked: App.terminal(App.repo + "/install.sh")
    }
  }
}
