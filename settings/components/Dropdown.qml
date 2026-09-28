import QtQuick
import QtQuick.Controls

// A pop-up button: shows the current choice; opens a list to pick from (with
// a search field when `searchable`). options: [{ value, label }] or strings.
Item {
  id: dd
  property var options: []
  property var current: null
  property bool searchable: options.length > 12
  property string placeholder: "Choose…"
  property real buttonWidth: 220
  signal chosen(var value)

  function labelOf(o) { return typeof o === "object" && o !== null ? String(o.label) : String(o) }
  function valueOf(o) { return typeof o === "object" && o !== null ? o.value : o }
  readonly property string currentLabel: {
    for (var i = 0; i < options.length; i++) if (valueOf(options[i]) === current) return labelOf(options[i])
    return current === null || current === undefined || current === "" ? placeholder : String(current)
  }

  width: buttonWidth
  height: 28

  Rectangle {
    anchors.fill: parent
    radius: 7
    color: area.containsMouse ? App.hover : App.control
    Text {
      x: 10
      width: parent.width - 34
      anchors.verticalCenter: parent.verticalCenter
      text: dd.currentLabel
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: App.fg
      font.family: App.font
      font.pixelSize: App.body
    }
    Icon {
      anchors.right: parent.right
      anchors.rightMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      name: "pan-down-symbolic"
      size: 14
      color: App.subtle
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      search.text = ""
      popup.open()
      if (dd.searchable) search.forceActiveFocus()
      Qt.callLater(function() { list.positionViewAtIndex(Math.max(0, list.currentIndexOf()), ListView.Center) })
    }
  }

  Popup {
    id: popup
    y: dd.height + 4
    x: Math.min(0, dd.width - width)
    width: Math.max(dd.width, 240)
    height: Math.min(360, (dd.searchable ? 40 : 0) + list.contentHeight + 12)
    padding: 6
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    background: Rectangle {
      radius: 10
      color: App.bg
      border.width: 1
      border.color: App.line
    }

    contentItem: Column {
      spacing: 4
      Rectangle {
        visible: dd.searchable
        width: parent.width
        height: 32
        radius: 7
        color: App.control
        TextInput {
          id: search
          x: 10
          width: parent.width - 20
          anchors.verticalCenter: parent.verticalCenter
          color: App.fg
          font.family: App.font
          font.pixelSize: App.body
          clip: true
          Text {
            visible: search.text === ""
            text: "Search"
            color: App.faint
            font: search.font
          }
          Keys.onReturnPressed: if (list.count > 0) { dd.chosen(dd.valueOf(list.model[0])); popup.close() }
        }
      }
      ListView {
        id: list
        width: parent.width
        height: popup.height - popup.padding * 2 - (dd.searchable ? 36 : 0)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: {
          var q = search.text.trim().toLowerCase()
          if (q === "") return dd.options
          return dd.options.filter(function(o) {
            return dd.labelOf(o).toLowerCase().indexOf(q) >= 0 || String(dd.valueOf(o)).toLowerCase().indexOf(q) >= 0
          })
        }
        function currentIndexOf() {
          for (var i = 0; i < model.length; i++) if (dd.valueOf(model[i]) === dd.current) return i
          return 0
        }
        delegate: Rectangle {
          id: item
          required property var modelData
          width: ListView.view.width
          height: 30
          radius: 6
          color: itemArea.containsMouse ? App.tint : "transparent"
          readonly property bool isCurrent: dd.valueOf(modelData) === dd.current
          Text {
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            text: item.isCurrent ? "✓" : ""
            color: itemArea.containsMouse ? App.onTint : App.fg
            font.family: App.font
            font.pixelSize: App.body
          }
          Text {
            x: 26
            width: parent.width - 34
            anchors.verticalCenter: parent.verticalCenter
            text: dd.labelOf(item.modelData)
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: itemArea.containsMouse ? App.onTint : App.fg
            font.family: App.font
            font.pixelSize: App.body
          }
          MouseArea {
            id: itemArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { dd.chosen(dd.valueOf(item.modelData)); popup.close() }
          }
        }
      }
    }
  }
}
