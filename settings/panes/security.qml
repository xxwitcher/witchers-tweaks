import QtQuick
import Quickshell
import "../components"

// Omarchy's security setups; each opens in a terminal, where it asks for
// your password.
Column {
  id: pane
  spacing: 22


  Group {
    title: "Sign in"
    ButtonRow { label: "Fingerprint"; buttonText: "Set Up…"; onClicked: App.terminal("omarchy-setup-security-fingerprint") }
    ButtonRow { label: "Security key (FIDO2)"; buttonText: "Set Up…"; onClicked: App.terminal("omarchy-setup-security-fido2") }
    ButtonRow { label: "Your password"; buttonText: "Change…"; onClicked: App.terminal("passwd") }
    ButtonRow { label: "Disk encryption password"; buttonText: "Change…"; onClicked: App.terminal("omarchy-drive-password") }
  }

  Group {
    title: "Access"
    ButtonRow { label: "Remote login (SSH)"; buttonText: "Set Up…"; onClicked: App.terminal("omarchy-setup-security-sshd") }
    ButtonRow { label: "sudo without a password"; buttonText: "Set Up…"; danger: true; onClicked: App.confirm({ title: "Use sudo without a password?", text: "Anything you run could change the system without asking. A terminal opens to set it up.", action: "Continue", danger: true, onAccept: function() { App.terminal("omarchy-sudo-passwordless") } }) }
    ButtonRow { label: "Docker without sudo"; buttonText: "Set Up…"; onClicked: App.terminal("omarchy-setup-security-sudoless-docker") }
  }

  Group {
    title: "Diagnostics"
    SwitchRow {
      label: "Capture crashes"
      checked: App.status.crashCaptureOff !== true
      onToggled: function(wanted) { if (wanted === (App.status.crashCaptureOff === true)) App.apply(["omarchy-toggle-crash-capture"]) }
    }
  }
}
