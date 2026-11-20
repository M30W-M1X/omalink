import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "omalink.panel"
  ipcTarget: "omalink.panel"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string pluginDir: decodeURIComponent(String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")).replace(/\/$/, "")

  property bool bridgeActive: false
  property bool hasToken: false
  property string pairUrl: "http://127.0.0.1:7842"
  property string qrPath: ""
  property bool showQr: true
  property bool qrUserToggled: false
  property string defaultAgent: "agy"
  property int connectedClients: 0
  property int runningTasks: 0
  property string phoneName: ""
  property int phoneBattery: -1
  property bool phoneCharging: false
  property var replyable: null
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
    if (!bridgeActive) return "OmaLink · Bridge Offline"
    var bat = phoneBattery >= 0 ? (" · Phone " + phoneBattery + "%" + (phoneCharging ? " ⚡" : "")) : ""
    if (runningTasks > 0) return "OmaLink · Casting (" + runningTasks + " running)" + bat
    if (connectedClients > 0) return "OmaLink · Connected (" + connectedClients + " device)" + bat
    return "OmaLink · Bridge Active" + bat
  }

  function applySnapshot(raw) {
    try {
      var parsed = JSON.parse(raw)
      if (!parsed || typeof parsed !== "object") return
      bridgeActive = parsed.active === true
      hasToken = parsed.hasToken === true
      if (parsed.pairUrl) pairUrl = String(parsed.pairUrl)
      qrPath = parsed.qrPath ? String(parsed.qrPath) : ""
      if (parsed.defaultAgent) defaultAgent = String(parsed.defaultAgent)
      connectedClients = Number(parsed.connectedClients || 0)
      if (!qrUserToggled) {
        showQr = (connectedClients === 0)
      }
      runningTasks = Number(parsed.runningTasks || 0)
      phoneName = parsed.phoneName ? String(parsed.phoneName) : ""
      phoneBattery = (parsed.phoneBattery !== null && parsed.phoneBattery !== undefined) ? Number(parsed.phoneBattery) : -1
      phoneCharging = parsed.phoneCharging === true
      replyable = parsed.replyable || null
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

  function ringPhone() {
    if (helperPath === "" || copyProc.running) return
    copyProc.command = ["python3", helperPath, "--port", String(bridgePort), "--ring"]
    copyProc.running = true
  }

  function sendQuickReply(replyText) {
    if (helperPath === "" || !replyable || !replyable.reply_id || replyText.trim() === "") return
    if (copyProc.running) return
    copyProc.command = [
      "python3", helperPath, "--port", String(bridgePort),
      "--reply-id", String(replyable.reply_id),
      "--reply-text", replyText.trim()
    ]
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
          else if (res.action === "ring") root.showFlash(res.ok ? "Ringing connected phone..." : "No phone connected")
          else if (res.action === "reply") root.showFlash(res.ok ? "Reply sent to phone" : "Reply failed")
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
              text: "OmaLink"
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

          Button {
            visible: !root.bridgeActive
            text: root.powerBusy ? "Starting OmaLink Bridge..." : "Install & Start OmaLink Bridge"
            enabled: !root.powerBusy
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            width: parent.width
            onClicked: root.toggleBridge()
          }

          Row {
            visible: root.bridgeActive
            width: parent.width
            spacing: Style.space(6)

            Button {
              text: "Copy URL"
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              onClicked: root.copyUrl()
            }

            Button {
              text: "Token"
              enabled: root.hasToken
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              onClicked: root.copyToken()
            }

            Button {
              text: root.showQr ? "Hide QR" : "QR"
              enabled: root.qrPath !== ""
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              onClicked: {
                root.qrUserToggled = true
                root.showQr = !root.showQr
              }
            }
          }

          Rectangle {
            visible: root.showQr && root.qrPath !== ""
            width: 164
            height: 164
            radius: 10
            color: "#FFFFFF"
            anchors.horizontalCenter: parent.horizontalCenter

            Image {
              anchors.centerIn: parent
              width: 150
              height: 150
              source: root.qrPath !== "" ? ("file://" + root.qrPath) : ""
              cache: false
              smooth: false
            }
          }

          Row {
            visible: root.phoneBattery >= 0 || root.connectedClients > 0
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: (root.phoneName !== "" ? root.phoneName : "Phone")
                + (root.phoneBattery >= 0 ? (" · " + root.phoneBattery + "%" + (root.phoneCharging ? " ⚡" : "")) : "")
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              anchors.verticalCenter: parent.verticalCenter
            }

            Button {
              text: "Ring Phone"
              enabled: root.bridgeActive
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              onClicked: root.ringPhone()
            }
          }

          Column {
            visible: root.replyable !== null && root.replyable !== undefined
            width: parent.width
            spacing: Style.space(4)

            Text {
              text: root.replyable ? (String(root.replyable.title || "Message") + ": " + String(root.replyable.body || "")) : ""
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: parent.width
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              TextField {
                id: replyField
                width: parent.width - replyBtn.width - Style.space(6)
                placeholderText: "Quick reply to phone..."
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                onAccepted: {
                  root.sendQuickReply(text)
                  text = ""
                }
              }

              Button {
                id: replyBtn
                text: "Reply"
                foreground: root.foreground
                fontFamily: root.fontFamily
                bordered: true
                onClicked: {
                  root.sendQuickReply(replyField.text)
                  replyField.text = ""
                }
              }
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
