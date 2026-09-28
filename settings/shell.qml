//@ pragma AppId org.witcher.settings
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "components"

// Witcher's Tweaks Settings: one window, like macOS's System Settings, for
// everything Omarchy and Witcher's Tweaks let you change. A search field
// and the sections on the left, the chosen section's settings on the right.
// Each section is a file in panes/; they change things through Omarchy's own
// commands and settings-helper (bin/).
ShellRoot {
  id: shellRoot

  // Sections in sidebar order; `group` puts a gap between groups.
  readonly property var sections: [
    { id: "wifi", label: "Wi-Fi", icon: "network-wireless-symbolic", color: "#0a84ff", group: 0, keywords: "wireless network internet ssid password" },
    { id: "bluetooth", label: "Bluetooth", icon: "bluetooth-active-symbolic", color: "#0a84ff", group: 0, keywords: "devices headphones pair" },
    { id: "network", label: "Network", icon: "network-wired-symbolic", color: "#0a84ff", group: 0, keywords: "dns ethernet wired qr" },
    { id: "notifications", label: "Notifications", icon: "preferences-system-notifications-symbolic", color: "#ff453a", group: 1, keywords: "do not disturb dnd bell timeout" },
    { id: "sound", label: "Sound", icon: "audio-volume-high-symbolic", color: "#ff375f", group: 1, keywords: "audio volume output input microphone speakers" },
    { id: "general", label: "General", icon: "preferences-system-symbolic", color: "#8e8e93", group: 2, keywords: "about update version channel date time timezone reset firmware" },
    { id: "appearance", label: "Appearance", icon: "preferences-desktop-appearance-symbolic", color: "#5e5ce6", group: 2, keywords: "theme background wallpaper font text size windows corners rounding gaps border colors unlock screensaver overview mission control workspace layout columns fade swipe" },
    { id: "menubar", label: "Top Bar", icon: "open-menu-symbolic", color: "#636366", group: 2, keywords: "menu bar position transparent autohide clock battery bell agent" },
    { id: "dock", label: "Dock", icon: "view-app-grid-symbolic", color: "#1c1c1e", group: 2, keywords: "magnification size position hide recent apps transparency" },
    { id: "displays", label: "Displays", icon: "video-display-symbolic", color: "#0a84ff", group: 2, keywords: "monitor resolution scale rotation brightness night light" },
    { id: "power", label: "Power", icon: "battery-full-symbolic", color: "#30d158", group: 2, keywords: "battery suspend idle screensaver stay awake power profile hibernation" },
    { id: "security", label: "Security", icon: "system-lock-screen-symbolic", color: "#8e8e93", group: 3, keywords: "fingerprint fido2 ssh sudo docker password disk encryption crash" },
    { id: "keyboard", label: "Keyboard", icon: "input-keyboard-symbolic", color: "#8e8e93", group: 4, keywords: "layout repeat shortcuts keybindings compose caps swap ctrl super" },
    { id: "trackpad", label: "Mouse & Trackpad", icon: "input-touchpad-symbolic", color: "#8e8e93", group: 4, keywords: "touchpad natural scrolling tap click speed gestures swipe sensitivity" },
    { id: "apps", label: "Default Apps", icon: "preferences-desktop-apps-symbolic", color: "#ff9f0a", group: 5, keywords: "browser terminal editor agent" },
    { id: "plugins", label: "Shell Plugins", icon: "application-x-addon-symbolic", color: "#bf5af2", group: 5, keywords: "widgets bar plugins" },
    { id: "tweaks", label: "Witcher's Tweaks", icon: "applications-engineering-symbolic", color: "#a855f7", group: 5, keywords: "tweaks" },
    { id: "advanced", label: "Advanced", icon: "utilities-terminal-symbolic", color: "#636366", group: 5, keywords: "config files hyprland restart refresh maintenance xcompose" }
  ]

  property string current: "appearance"
  property string query: ""

  readonly property var shownSections: {
    var q = query.trim().toLowerCase()
    if (q === "") return sections
    return sections.filter(function(s) {
      return s.label.toLowerCase().indexOf(q) >= 0 || s.keywords.indexOf(q) >= 0
    })
  }

  function select(id) {
    for (var i = 0; i < sections.length; i++) {
      if (sections[i].id === id) {
        current = id
        scroller.scrollToTop()
        App.refresh()
        return
      }
    }
  }

  // witcher-settings <section> writes the section to open here.
  FileView {
    path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/witcher-settings/section"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var id = text().trim()
      if (id !== "") shellRoot.select(id)
    }
  }

  FloatingWindow {
    id: window
    title: "Settings"
    implicitWidth: 980
    implicitHeight: 680
    minimumSize: Qt.size(760, 480)
    color: App.bg

    // Closing the window ends the app.
    onVisibleChanged: if (!visible) Qt.quit()

    // ---------- sidebar ----------
    Rectangle {
      id: sidebar
      width: 200
      height: parent.height
      color: App.sidebar

      Rectangle {
        anchors.right: parent.right
        width: 1
        height: parent.height
        color: App.line
      }

      Rectangle {
        id: searchBox
        x: 14
        y: 16
        width: parent.width - 28
        height: 30
        radius: 8
        color: App.control
        Icon {
          x: 10
          anchors.verticalCenter: parent.verticalCenter
          name: "system-search-symbolic"
          size: 14
          color: App.subtle
        }
        TextInput {
          id: search
          x: 30
          width: parent.width - 40
          anchors.verticalCenter: parent.verticalCenter
          color: App.fg
          font.family: App.font
          font.pixelSize: App.body
          clip: true
          onTextEdited: shellRoot.query = text
          Keys.onReturnPressed: if (shellRoot.shownSections.length > 0) shellRoot.select(shellRoot.shownSections[0].id)
          Keys.onEscapePressed: { text = ""; shellRoot.query = "" }
          Text {
            visible: search.text === ""
            text: "Search"
            color: App.faint
            font: search.font
          }
        }
      }

      ListView {
        id: sectionList
        anchors.top: searchBox.bottom
        anchors.topMargin: 12
        anchors.bottom: parent.bottom
        width: parent.width
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: shellRoot.shownSections
        delegate: Item {
          id: entry
          required property var modelData
          required property int index
          readonly property bool gapAbove: index > 0 && shellRoot.query === ""
            && shellRoot.shownSections[index - 1].group !== modelData.group
          readonly property bool selected: shellRoot.current === modelData.id
          width: ListView.view.width
          height: 34 + (gapAbove ? 14 : 0)

          Rectangle {
            x: 10
            y: entry.gapAbove ? 14 : 0
            width: parent.width - 20
            height: 34
            radius: 8
            color: entry.selected ? App.tint : (entryArea.containsMouse ? App.hover : "transparent")

            Rectangle {
              x: 8
              anchors.verticalCenter: parent.verticalCenter
              width: 24
              height: 24
              radius: 6
              color: entry.modelData.color
              border.width: entry.selected ? 1 : 0
              border.color: Qt.rgba(1, 1, 1, 0.5)
              Icon {
                anchors.centerIn: parent
                name: entry.modelData.icon
                size: 15
                color: "#ffffff"
              }
            }
            Text {
              x: 42
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - 50
              text: entry.modelData.label
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: entry.selected ? App.onTint : App.fg
              font.family: App.font
              font.pixelSize: App.body
            }
            MouseArea {
              id: entryArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: shellRoot.select(entry.modelData.id)
            }
          }
        }
      }
    }

    // ---------- the section ----------
    Scroller {
      id: scroller
      anchors.left: sidebar.right
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      contentHeight: pane.height + 60

      Loader {
        id: pane
        x: Math.max(28, (scroller.width - width) / 2)
        y: 28
        width: Math.min(scroller.width - 56, 700)
        source: "panes/" + shellRoot.current + ".qml"
        onStatusChanged: if (status === Loader.Error) console.warn("settings: can't load pane " + shellRoot.current)
      }
    }

    // ---------- messages ----------
    Rectangle {
      id: toast
      property string text: ""
      anchors.horizontalCenter: scroller.horizontalCenter
      y: parent.height - height - 20
      width: Math.min(scroller.width - 60, toastText.implicitWidth + 32)
      height: toastText.implicitHeight + 16
      radius: 10
      color: Qt.rgba(App.fg.r, App.fg.g, App.fg.b, 0.9)
      opacity: 0
      visible: opacity > 0
      Behavior on opacity { NumberAnimation { duration: 180 } }
      Text {
        id: toastText
        anchors.centerIn: parent
        width: Math.min(implicitWidth, parent.width - 32)
        text: toast.text
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: App.bg
        font.family: App.font
        font.pixelSize: App.body
      }
      Timer { id: toastTimer; interval: 3200; onTriggered: toast.opacity = 0 }
      Connections {
        target: App
        function onToastRequested(text) {
          toast.text = text
          toast.opacity = 1
          toastTimer.restart()
        }
      }
    }

    // ---------- "Are you sure?" ----------
    Rectangle {
      id: dialog
      property var options: null
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.45)
      visible: options !== null
      z: 100

      MouseArea { anchors.fill: parent; onClicked: dialog.options = null }

      Rectangle {
        anchors.centerIn: parent
        width: 380
        height: dialogColumn.implicitHeight + 40
        radius: 14
        color: App.bg
        border.width: 1
        border.color: App.line
        MouseArea { anchors.fill: parent }

        Column {
          id: dialogColumn
          anchors.centerIn: parent
          width: parent.width - 40
          spacing: 12
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: dialog.options ? dialog.options.title || "" : ""
            color: App.fg
            font.family: App.font
            font.pixelSize: App.body + 3
            font.bold: true
          }
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: dialog.options ? dialog.options.text || "" : ""
            color: App.subtle
            font.family: App.font
            font.pixelSize: App.body
          }
          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10
            PillButton { text: "Cancel"; width: 130; onClicked: dialog.options = null }
            PillButton {
              text: dialog.options ? dialog.options.action || "OK" : "OK"
              width: 130
              prominent: true
              danger: dialog.options ? !!dialog.options.danger : false
              onClicked: {
                var o = dialog.options
                dialog.options = null
                if (o && o.onAccept) o.onAccept()
              }
            }
          }
        }
      }

      Connections {
        target: App
        function onConfirmRequested(options) { dialog.options = options }
      }
    }
  }
}
