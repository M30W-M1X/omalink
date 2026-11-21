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
  property bool useTls: true
  property bool hasToken: false
  property string pairUrl: "https://127.0.0.1:7842"
  property string qrPath: ""
  property bool showQr: true
  property bool qrUserToggled: false
  property string defaultAgent: "agy"
  property int connectedClients: 0
  property int runningTasks: 0
  property string phoneName: ""
  property string phoneClientId: ""
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
  readonly property bool hasDevice: connectedClients > 0 || phoneBattery >= 0 || phoneName !== ""
  readonly property color batteryColor: {
    if (phoneBattery < 0) return dim
    if (phoneBattery <= 15) return "#f7768e"
    if (phoneBattery <= 30) return "#e0af68"
    return "#9ece6a"
  }

  readonly property string statusSubtitle: {
    if (!bridgeActive) return "BRIDGE OFFLINE"
    if (runningTasks > 0) return "CASTING SPELL (" + runningTasks + " RUNNING)"
    if (connectedClients > 0) return "CONNECTED · " + (useTls ? "TLS ENCRYPTED" : (connectedClients + (connectedClients === 1 ? " DEVICE" : " DEVICES")))
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
      useTls = parsed.tls !== false
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
      phoneClientId = parsed.phoneClientId ? String(parsed.phoneClientId) : ""
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

  function sendClipboard() {
    if (helperPath === "" || copyProc.running || root.phoneClientId === "") return
    copyProc.command = [
      "python3", helperPath, "--port", String(bridgePort),
      "--send-clip", "--target-client-id", root.phoneClientId,
      "--target-device", root.phoneName
    ]
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
          else if (res.action === "send_clip") root.showFlash(res.ok ? "Sent desktop clipboard to phone" : "Clipboard empty or no phone connected")
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

        // Dedicated Connected Device hero card (shown first whenever paired/connected)
        Column {
          visible: root.bridgeActive && root.hasDevice
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "CONNECTED DEVICE"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Rectangle {
            width: parent.width
            implicitHeight: deviceCardCol.implicitHeight + Style.space(22)
            radius: 10
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
            border.width: 1
            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)

            Column {
              id: deviceCardCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(11)
              spacing: Style.space(10)

              // Device header row: Smartphone glyph + Name/Battery bar + LINKED pill
              Item {
                width: parent.width
                implicitHeight: Math.max(phoneGlyphBox.height, deviceTitleCol.implicitHeight)

                Rectangle {
                  id: phoneGlyphBox
                  width: 38
                  height: 38
                  radius: 9
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                  border.width: 1
                  border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

                  Canvas {
                    id: phoneGlyphCanvas
                    anchors.fill: parent
                    antialiasing: true
                    property color strokeCol: root.foreground
                    onStrokeColChanged: requestPaint()
                    onPaint: {
                      var ctx = getContext("2d")
                      ctx.clearRect(0, 0, width, height)
                      ctx.strokeStyle = strokeCol
                      ctx.fillStyle = strokeCol
                      ctx.lineWidth = 1.7
                      ctx.lineJoin = "round"
                      ctx.lineCap = "round"

                      // Smartphone outer frame
                      var rx = 11
                      var ry = 6
                      var rw = 16
                      var rh = 26
                      var r = 3
                      ctx.beginPath()
                      ctx.moveTo(rx + r, ry)
                      ctx.lineTo(rx + rw - r, ry)
                      ctx.quadraticCurveTo(rx + rw, ry, rx + rw, ry + r)
                      ctx.lineTo(rx + rw, ry + rh - r)
                      ctx.quadraticCurveTo(rx + rw, ry + rh, rx + rw - r, ry + rh)
                      ctx.lineTo(rx + r, ry + rh)
                      ctx.quadraticCurveTo(rx, ry + rh, rx, ry + rh - r)
                      ctx.lineTo(rx, ry + r)
                      ctx.quadraticCurveTo(rx, ry, rx + r, ry)
                      ctx.closePath()
                      ctx.stroke()

                      // Top earpiece dot
                      ctx.beginPath()
                      ctx.moveTo(17, 9.5)
                      ctx.lineTo(21, 9.5)
                      ctx.stroke()

                      // Bottom gesture bar
                      ctx.beginPath()
                      ctx.moveTo(16, 28.5)
                      ctx.lineTo(22, 28.5)
                      ctx.stroke()
                    }
                  }

                  Rectangle {
                    width: 9
                    height: 9
                    radius: 4.5
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: -2
                    anchors.bottomMargin: -2
                    color: root.connectedClients > 0 ? "#9ece6a" : root.dim
                    border.width: 1.5
                    border.color: Commons.Color.popups.background
                  }
                }

                Rectangle {
                  id: linkedPill
                  anchors.right: parent.right
                  anchors.top: parent.top
                  height: 20
                  width: linkedLabel.implicitWidth + Style.space(12)
                  radius: 10
                  color: root.connectedClients > 0
                    ? Qt.rgba(0.62, 0.81, 0.42, 0.16)
                    : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                  border.width: 1
                  border.color: root.connectedClients > 0
                    ? Qt.rgba(0.62, 0.81, 0.42, 0.45)
                    : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

                  Text {
                    id: linkedLabel
                    anchors.centerIn: parent
                    text: root.connectedClients > 0 ? "● LINKED" : "● STANDBY"
                    textFormat: Text.PlainText
                    color: root.connectedClients > 0 ? "#9ece6a" : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Math.max(9, Style.font.caption - 1)
                    font.bold: true
                    font.letterSpacing: 0.6
                  }
                }

                Column {
                  id: deviceTitleCol
                  anchors.left: phoneGlyphBox.right
                  anchors.leftMargin: Style.space(10)
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(5)

                  Text {
                    text: (root.phoneName !== "" ? root.phoneName : "Phone")
                      + (root.connectedClients > 1 ? (" (+" + (root.connectedClients - 1) + " more)") : "")
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    elide: Text.ElideRight
                    width: parent.width - linkedPill.width - Style.space(6)
                  }

                  Row {
                    width: parent.width
                    spacing: Style.space(6)

                    // Segmented visual battery gauge
                    Row {
                      visible: root.phoneBattery >= 0
                      spacing: 1
                      anchors.verticalCenter: parent.verticalCenter

                      Rectangle {
                        width: 58
                        height: 11
                        radius: 3
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)

                        Row {
                          anchors.fill: parent
                          anchors.margins: 2
                          spacing: 1.5

                          Repeater {
                            model: 10
                            delegate: Rectangle {
                              required property int index
                              width: 4
                              height: 7
                              radius: 1
                              color: (root.phoneBattery >= (index + 1) * 10 || (index === 0 && root.phoneBattery > 0))
                                ? root.batteryColor
                                : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
                            }
                          }
                        }
                      }

                      Rectangle {
                        width: 2
                        height: 5
                        radius: 1
                        anchors.verticalCenter: parent.verticalCenter
                        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)
                      }
                    }

                    Text {
                      text: (root.phoneBattery >= 0
                          ? (root.phoneBattery + "%" + (root.phoneCharging ? " ⚡" : ""))
                          : "Ready")
                        + "  ·  " + (root.useTls ? "TLS" : "HTTP") + " · LAN"
                      textFormat: Text.PlainText
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }
                }
              }

              Rectangle {
                width: parent.width
                height: 1
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
              }

              // Quick device actions inside card
              Row {
                width: parent.width
                spacing: Style.space(8)

                Button {
                  width: (parent.width - Style.space(8)) / 2
                  text: "Ring Phone"
                  enabled: root.bridgeActive
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  bordered: true
                  onClicked: root.ringPhone()
                }

                Button {
                  width: (parent.width - Style.space(8)) / 2
                  text: "Send Clip"
                  enabled: root.bridgeActive && root.connectedClients === 1 && root.phoneName !== "" && root.phoneClientId !== ""
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  bordered: true
                  onClicked: root.sendClipboard()
                }
              }

              // Styled notification & quick-reply chat bubble inside the device card
              Rectangle {
                visible: root.replyable !== null && root.replyable !== undefined
                width: parent.width
                implicitHeight: replyBubbleCol.implicitHeight + Style.space(16)
                radius: 8
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
                border.width: 1
                border.color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.38)

                Column {
                  id: replyBubbleCol
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: Style.space(8)
                  spacing: Style.space(5)

                  Text {
                    text: root.replyable ? String(root.replyable.title || "Phone Notification") : ""
                    textFormat: Text.PlainText
                    color: Commons.Color.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    elide: Text.ElideRight
                    width: parent.width
                  }

                  Text {
                    text: root.replyable ? String(root.replyable.body || "") : ""
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    width: parent.width
                  }

                  Row {
                    width: parent.width
                    spacing: Style.space(6)

                    TextField {
                      id: replyField
                      width: parent.width - replyBtn.width - Style.space(6)
                      placeholderText: "Quick reply..."
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
                      text: "Send"
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
              }
            }
          }
        }

        PanelSeparator {
          visible: root.recentTasks.length > 0 && root.bridgeActive && root.hasDevice
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

        PanelSeparator {
          visible: (root.bridgeActive && root.hasDevice) || root.recentTasks.length > 0
          foreground: root.foreground
        }

        // Compact Bridge & Pairing section (demoted to bottom once a phone is connected)
        Column {
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: root.hasDevice ? "BRIDGE & PAIRING" : "PAIRING"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            text: root.pairUrl + (root.useTls ? " 🔒" : "") + "  ·  Agent: " + root.defaultAgent
            textFormat: Text.PlainText
            color: root.hasDevice ? root.dim : root.foreground
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
              text: "Copy Token"
              enabled: root.hasToken
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              onClicked: root.copyToken()
            }

            Button {
              text: root.showQr ? "Hide QR" : "Show QR"
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
      }
    }
  }
}
