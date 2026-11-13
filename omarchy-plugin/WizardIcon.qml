import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Wizard hat badge with a KDE-Connect-style corner activity dot for the
// Omarchy top bar and popup header.
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
      var ox = (width - s) / 2
      var oy = (height - s) / 2
      function px(nx) { return ox + nx * s }
      function py(ny) { return oy + ny * s }

      ctx.strokeStyle = root.color
      ctx.fillStyle = root.color
      ctx.lineJoin = "round"
      ctx.lineCap = "round"

      // Slouchy pointed wizard hat crown leaning slightly right
      ctx.beginPath()
      ctx.moveTo(px(0.26), py(0.56))
      ctx.quadraticCurveTo(px(0.36), py(0.18), px(0.70), py(0.10))
      ctx.quadraticCurveTo(px(0.60), py(0.33), px(0.74), py(0.56))
      ctx.quadraticCurveTo(px(0.50), py(0.60), px(0.26), py(0.56))
      ctx.closePath()
      ctx.fill()

      // Wide swooping brim separated cleanly from crown to suggest a hat band
      ctx.beginPath()
      ctx.moveTo(px(0.06), py(0.73))
      ctx.quadraticCurveTo(px(0.18), py(0.66), px(0.26), py(0.64))
      ctx.quadraticCurveTo(px(0.50), py(0.69), px(0.74), py(0.64))
      ctx.quadraticCurveTo(px(0.82), py(0.66), px(0.94), py(0.73))
      ctx.quadraticCurveTo(px(0.50), py(0.88), px(0.06), py(0.73))
      ctx.closePath()
      ctx.fill()

      // Small 4-point star sparkle floating in upper-left balance space
      var sx = px(0.19)
      var sy = py(0.27)
      var sr = Math.max(1.8, s * 0.11)
      var ir = sr * 0.28
      ctx.beginPath()
      ctx.moveTo(sx, sy - sr)
      ctx.quadraticCurveTo(sx + ir, sy - ir, sx + sr, sy)
      ctx.quadraticCurveTo(sx + ir, sy + ir, sx, sy + sr)
      ctx.quadraticCurveTo(sx - ir, sy + ir, sx - sr, sy)
      ctx.quadraticCurveTo(sx - ir, sy - ir, sx, sy - sr)
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
