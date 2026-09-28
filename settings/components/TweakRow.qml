import QtQuick

// A switch that adds or removes one of Witcher's Tweaks. Hidden when the
// tweak doesn't apply to this machine.
SwitchRow {
  id: row
  property string tweak: ""
  label: App.tweaks[tweak] ? App.tweaks[tweak].description : tweak
  visible: App.tweakAvailable(tweak)
  checked: App.tweakOn(tweak)
  busy: App.tweakPending(tweak)
  onToggled: function(wanted) { App.setTweak(row.tweak, wanted) }
}
