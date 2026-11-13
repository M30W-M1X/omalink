import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// KDE-Connect-inspired smartphone + arcane wizard spark badge with a corner
// activity dot for the Omarchy top bar.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Commons.Color.foreground
  property color badgeColor: "#9ece6a"
  property color castingColor: Commons.Color.accent
  property bool active: false
  property int connectedClients: 0
  property int runningTasks: 0

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  onColorChanged: glyphCanvas.requestPaint()
  onActiveChanged: glyphCanvas.requestPaint()
  onIconSizeChanged: glyphCanvas.requestPaint()

  Canvas {
    id: glyphCanvas
    anchors.fill: parent
    antialiasing: true

    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)

      var s = Math.min(width, height)
      var phoneW = s * 0.56
      var phoneH = s * 0.86
      var px = (width - phoneW) / 2
      var py = (height - phoneH) / 2
      var r = Math.max(1.8, s * 0.12)
      var strokeW = Math.max(1.4, s * 0.105)

      ctx.strokeStyle = root.color
      ctx.fillStyle = root.color
      ctx.lineWidth = strokeW
      ctx.lineJoin = "round"
      ctx.lineCap = "round"

      // Rounded smartphone body
      ctx.beginPath()
      ctx.moveTo(px + r, py)
      ctx.lineTo(px + phoneW - r, py)
      ctx.quadraticCurveTo(px + phoneW, py, px + phoneW, py + r)
      ctx.lineTo(px + phoneW, py + phoneH - r)
      ctx.quadraticCurveTo(px + phoneW, py + phoneH, px + phoneW - r, py + phoneH)
      ctx.lineTo(px + r, py + phoneH)
      ctx.quadraticCurveTo(px, py + phoneH, px, py + phoneH - r)
      ctx.lineTo(px, py + r)
      ctx.quadraticCurveTo(px, py, px + r, py)
      ctx.closePath()
      ctx.stroke()

      // Subtle bottom speaker/chin dot
      var cx = width / 2
      ctx.beginPath()
      ctx.arc(cx, py + phoneH - strokeW * 1.35, Math.max(0.8, s * 0.045), 0, Math.PI * 2)
      ctx.fill()

      // 4-point wizard sparkle centered inside phone screen
      var sy = py + phoneH * 0.44
      var sr = s * 0.165
      var ir = sr * 0.30
      ctx.beginPath()
      ctx.moveTo(cx, sy - sr)
      ctx.quadraticCurveTo(cx + ir * 0.4, sy - ir * 0.4, cx + sr, sy)
      ctx.quadraticCurveTo(cx + ir * 0.4, sy + ir * 0.4, cx, sy + sr)
      ctx.quadraticCurveTo(cx - ir * 0.4, sy + ir * 0.4, cx - sr, sy)
      ctx.quadraticCurveTo(cx - ir * 0.4, sy - ir * 0.4, cx, sy - sr)
      ctx.closePath()
      ctx.fill()
    }
  }

  // KDE-Connect-style bottom-right status dot when bridge is active
  BorderSurface {
    id: statusDot
    visible: root.active
    width: Math.max(6, parent.width * 0.38)
    height: width
    radius: width / 2
    color: root.runningTasks > 0
      ? root.castingColor
      : (root.connectedClients > 0 ? root.badgeColor : root.castingColor)
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.rightMargin: -width * 0.12
    anchors.bottomMargin: -height * 0.08
    borderSpec: Border.flat(Commons.Color.popups.background, 1.2)

    SequentialAnimation on opacity {
      running: root.active && root.runningTasks > 0
      loops: Animation.Infinite
      NumberAnimation { from: 1.0; to: 0.35; duration: Math.max(1, Style.duration(550)) }
      NumberAnimation { from: 0.35; to: 1.0; duration: Math.max(1, Style.duration(550)) }
    }
  }
}
