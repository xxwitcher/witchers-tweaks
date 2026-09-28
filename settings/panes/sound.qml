import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "../components"

// Output and input devices and their volume (PipeWire).
Column {
  id: pane
  spacing: 22

  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var sinks: nodes.filter(function(n) { return n && n.isSink && !n.isStream && n.audio })
  readonly property var sources: nodes.filter(function(n) {
    return n && !n.isSink && !n.isStream && n.audio && String(n.name).indexOf(".monitor") < 0
  })
  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var source: Pipewire.defaultAudioSource

  function nameOf(n) { return String(n.description || n.nickname || n.name) }

  PwObjectTracker { objects: pane.sinks.concat(pane.sources) }

  Group {
    title: "Output"
    SliderRow {
      label: "Output volume"
      from: 0
      to: 100
      step: 1
      value: pane.sink && pane.sink.audio ? Math.round(pane.sink.audio.volume * 100) : 0
      format: function(v) { return Math.round(v) + "%" }
      onMoved: function(v) { if (pane.sink && pane.sink.audio) pane.sink.audio.volume = v / 100 }
    }
    SwitchRow {
      label: "Mute"
      checked: pane.sink && pane.sink.audio ? pane.sink.audio.muted : false
      onToggled: function(wanted) { if (pane.sink && pane.sink.audio) pane.sink.audio.muted = wanted }
    }
    Repeater {
      model: pane.sinks
      SettingRow {
        id: out
        required property var modelData
        label: pane.nameOf(modelData)
        PillButton {
          text: out.modelData === pane.sink ? "In use" : "Use"
          prominent: out.modelData === pane.sink
          onClicked: Pipewire.preferredDefaultAudioSink = out.modelData
        }
      }
    }
  }

  Group {
    title: "Input"
    SliderRow {
      label: "Input volume"
      from: 0
      to: 100
      step: 1
      value: pane.source && pane.source.audio ? Math.round(pane.source.audio.volume * 100) : 0
      format: function(v) { return Math.round(v) + "%" }
      onMoved: function(v) { if (pane.source && pane.source.audio) pane.source.audio.volume = v / 100 }
    }
    SwitchRow {
      label: "Mute microphone"
      checked: pane.source && pane.source.audio ? pane.source.audio.muted : false
      onToggled: function(wanted) { if (pane.source && pane.source.audio) pane.source.audio.muted = wanted }
    }
    Repeater {
      model: pane.sources
      SettingRow {
        id: inp
        required property var modelData
        label: pane.nameOf(modelData)
        PillButton {
          text: inp.modelData === pane.source ? "In use" : "Use"
          prominent: inp.modelData === pane.source
          onClicked: Pipewire.preferredDefaultAudioSource = inp.modelData
        }
      }
    }
  }

  Group {
    ButtonRow {
      label: "Per-app volume and more"
      buttonText: "Open Mixer"
      onClicked: App.shDetached("omarchy-launch-or-focus-tui wiremix")
    }
    ButtonRow {
      label: "Audio not working?"
      buttonText: "Restart Audio"
      onClicked: App.terminal("omarchy-restart-audio")
    }
  }
}
