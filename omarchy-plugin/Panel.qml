import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "wizard.panel"
  ipcTarget: "wizard.panel"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string pluginDir: decodeURIComponent(String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")).replace(/\/$/, "")

  property bool bridgeActive: false
  property bool hasToken: false
  property string pairUrl: "http://127.0.0.1:7842"
  property string defaultAgent: "agy"
  property int connectedClients: 0
  property int runningTasks: 0
  property var recentTasks: []
  property string flashText: ""
  property bool powerBusy: false

  readonly property int bridgePort: Math.max(1024, Math.min(65535, Number(setting("port", 7842))))
  readonly property int pollMs: Math.max(2000, Math.min(60000, Number(setting("refreshIntervalSec", 5)) * 1000))
  readonly property string helperPath: pluginDir !== "" ? pluginDir + "/status.py" : ""

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color barIconColor: bridgeActive ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string statusSubtitle: {
    if (!bridgeActive) return "BRIDGE OFFLINE"
    if (runningTasks > 0) return "CASTING SPELL (" + runningTasks + " RUNNING)"
    if (connectedClients > 0) return "CONNECTED · " + connectedClients + (connectedClients === 1 ? " DEVICE" : " DEVICES")
    return "ACTIVE · READY TO PAIR"
  }

  readonly property string barTooltip: {
    if (!bridgeActive) return "Omarchy Wizard · Bridge Offline"
    if (runningTasks > 0) return "Omarchy Wizard · Casting (" + runningTasks + " running)"
    if (connectedClients > 0) return "Omarchy Wizard · Connected (" + connectedClients + " device)"
    return "Omarchy Wizard · Bridge Active"
  }

  function applySnapshot(raw) {
    try {
      var parsed = JSON.parse(raw)
      if (!parsed || typeof parsed !== "object") return
      bridgeActive = parsed.active === true
      hasToken = parsed.hasToken === true
      if (parsed.pairUrl) pairUrl = String(parsed.pairUrl)
      if (parsed.defaultAgent) defaultAgent = String(parsed.defaultAgent)
      connectedClients = Number(parsed.connectedClients || 0)
      runningTasks = Number(parsed.runningTasks || 0)
      recentTasks = Array.isArray(parsed.recentTasks) ? parsed.recentTasks : []
    } catch (e) {}
  }

  function refresh() {
    if (helperPath === "" || statusProc.running) return
    statusProc.command = ["python3", helperPath, "--port", String(bridgePort)]
    statusProc.running = true
  }

  function toggleBridge() {
    if (helperPath === "" || toggleProc.running) return
    powerBusy = true
    var target = bridgeActive ? "off" : "on"
    toggleProc.command = ["python3", helperPath, "--port", String(bridgePort), "--toggle", target]
    toggleProc.running = true
  }

  function copyUrl() {
    if (helperPath === "" || copyProc.running) return
    copyProc.command = ["python3", helperPath, "--port", String(bridgePort), "--copy-url"]
    copyProc.running = true
  }

  function copyToken() {
    if (helperPath === "" || copyProc.running) return
    copyProc.command = ["python3", helperPath, "--port", String(bridgePort), "--copy-token"]
    copyProc.running = true
  }

  function showFlash(msg) {
    flashText = msg
    flashTimer.restart()
  }

  Component.onCompleted: Qt.callLater(refresh)
  onOpenedChanged: if (opened) refresh()

  Timer {
    id: pollTimer
    interval: root.pollMs
    repeat: true
    running: root.helperPath !== ""
    onTriggered: root.refresh()
  }

  Timer {
    id: flashTimer
    interval: 2200
    onTriggered: root.flashText = ""
  }

  Process {
    id: statusProc
    stdout: StdioCollector {
      onStreamFinished: root.applySnapshot(text)
    }
  }

  Process {
    id: toggleProc
    stdout: StdioCollector {
      onStreamFinished: {
        root.powerBusy = false
        root.applySnapshot(text)
      }
    }
    onExited: root.powerBusy = false
  }

  Process {
    id: copyProc
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var res = JSON.parse(text)
          if (res.copied === "url") root.showFlash("Copied Pair URL to clipboard")
          else if (res.copied === "token") root.showFlash("Copied Pairing Token to clipboard")
        } catch (e) {}
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.opened ? "" : root.barTooltip
    iconComponent: Component { Item {} }

    WizardIcon {
      x: (button.width - width) / 2
      y: (button.height - height) / 2
      iconSize: button.iconSize
      color: root.barIconColor
      active: root.bridgeActive
      connectedClients: root.connectedClients
      runningTasks: root.runningTasks
    }

    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleBridge()
      else if (b === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      id: keyCatcher
      implicitHeight: column.implicitHeight
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(12)

        // Hero header matching Bluetooth / Tailscale panels
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.height, heroLabels.implicitHeight, powerSwitch.implicitHeight)

          WizardIcon {
            id: heroIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            iconSize: Style.font.display
            color: root.foreground
            active: root.bridgeActive
            connectedClients: root.connectedClients
            runningTasks: root.runningTasks
            opacity: root.bridgeActive ? 1.0 : 0.5
          }

          ToggleSwitch {
            id: powerSwitch
            checked: root.bridgeActive
            busy: root.powerBusy
            foreground: root.foreground
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            onToggled: root.toggleBridge()
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(12)
            anchors.right: powerSwitch.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Omarchy Wizard"
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              text: root.statusSubtitle
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.0
              elide: Text.ElideRight
              width: parent.width
            }
          }
        }

        PanelSeparator {
          foreground: root.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "PAIRING"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            text: "Bridge URL: " + root.pairUrl
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
            width: parent.width
          }

          Text {
            text: "Default Agent: " + root.defaultAgent + "  ·  Clients: " + root.connectedClients
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Button {
              text: "Copy URL"
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              onClicked: root.copyUrl()
            }

            Button {
              text: "Copy Token"
              enabled: root.hasToken
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              onClicked: root.copyToken()
            }
          }

          Text {
            visible: root.flashText !== ""
            text: root.flashText
            textFormat: Text.PlainText
            color: Commons.Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            width: parent.width
          }
        }

        PanelSeparator {
          visible: root.recentTasks.length > 0
          foreground: root.foreground
        }

        Column {
          visible: root.recentTasks.length > 0
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "RECENT SPELLS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: root.recentTasks
            delegate: Column {
              required property var modelData
              width: parent.width
              spacing: Style.space(1)

              Text {
                text: String(modelData.prompt || "")
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                text: String(modelData.status || "") + " · " + String(modelData.agent || "")
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                width: parent.width
              }
            }
          }
        }
      }
    }
  }
}
